---
title: Map generation
type: system-note
---

# Map generation

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**Passes 1–7 are built**: the pure core is `scripts/maps/generation/` (`MapGenerator`);
`GeneratedMapWriter` (`tools/map_generation/`) turns a result into a skirmish scene; and maps are
generated from the editor's Map Generator dock (§Interface). Pass 7, visual facets, is a
proof of concept with its own note.
It supersedes the sketch in [tile-types.md](tile-types.md) §Stage 2, and it assumes the feature
and water models in [map-composition.md](map-composition.md) — a generator can only place things
that note defines.

---

## What a generator produces

**One `TerrainData`, plus a placement list.** `TerrainData` already carries the authored layers and
derives everything else; a generator that emits one is done with the terrain. Entity placements —
starts, extraction sites, ponds, buildings, shelters — come out beside it as a separate list,
because they are scene content rather than terrain. Water bodies come out as a third thing: a level
and a charge per basin.

Today's generators emit none of it: `HeightmapGenerator.generate()` returns bare corner heights and
`BlockMaskGenerator.generate()` returns a boolean mask. Both are subsumed.

**The generator knows the alliance count and its own parameters, and nothing else.** It never sees
which factions are playing, nor how many players an alliance holds. A resource whose worth depends
on faction (the shelter) is balanced in its own currency so that no exchange rate — which would be
faction knowledge — is ever needed (§Currencies).

---

## Precedent: how the games that solved this actually solved it

The question was whether to generate symmetrically or generate freely and repair. **The answer from
the precedents is neither — nobody mirrors the map, and the only near-symmetric thing on it is where
the players stand.**

| Game | How fairness is guaranteed | How symmetric |
|---|---|---|
| **AoE2** (random map scripting) | `set_place_for_every_player` places one copy of an object per *player land*; `min_distance_to_players` / `max_distance_to_players` constrain the radius it may land at. Counts and range are equal; position is free | player lands sit on a **circle** at equal spacing (`base_size`, `circle_radius`). Nothing else is mirrored |
| **AoE3** | `rmPlacePlayersCircular` with explicit min/max radius and an **angle variation** knob — players equidistant, or deliberately slightly closer/farther | same: a jittered ring, and nothing more |
| **AoE4** | same per-player quota, plus a `contested` fraction (0…1) positioning a resource along the player-to-player axis — 0.45–0.55 puts it midway, near 0 puts it in someone's base. Each player is guaranteed one node of each type in Town Centre range, as an un-raidable early source | approximately rotational, and **fought for patch by patch** — central lakes, neutral markets and starting territory each needed their own symmetry fix |
| **Tooth and Tail** | almost nothing. Only *counts* are pinned (7–9 gristmills; 40–50 tiles square). Uneven expansion access and uneven proximity to the enemy are deliberate | none |

**What is taken, and what is not.**

1. **No mirroring.** Comparable access comes from how resources are placed relative to the
   starts, not from geometry. The one exception is a TRAINING control, never a shipped map:
   §Symmetric maps.
2. **AoE4's `contested` fraction, generalised.** Every resource — not only the ones meant for the
   middle — is placed against a *target favor* (§Favor). AoE4's un-raidable guaranteed node is
   **not** taken: there is no default "natural expansion", and no ENERGY feature is placed near
   a start unconditionally. **Shelters are the exception** (reversed 2026-09-28): every start is
   guaranteed a shelter inside a distance band (§3 Shelters), because spawn points are hidden and
   that band is what the players reason about.
3. **AoE4's patch history is the cost of free placement.** A generator that places first and checks
   later needs a separate fairness fix per feature, forever. So favor is an *input* each placement
   is aimed at, not a measurement a finished map is judged by.
4. **Start variance nearer Tooth and Tail than AoE3.** AoE3's jitter is small; the ring here is
   jittered harder. Tooth and Tail's *resource* unfairness is not taken — it is paid for by
   ten-minute matches, and here an early deficit compounds through tech and production.

---

## Currencies, value and favor

### Currencies

Every placed feature has a **value** in one **currency**, and each currency is balanced on its own.

| Currency | Features | Value of one feature |
|---|---|---|
| site energy | extraction site cluster | income over `value_horizon_seconds` (below) |
| pond energy | lithium pond | income over `value_horizon_seconds` (below) |
| shelter | shelter | 1 |
| buildings (a pseudo-resource) | neutral buildings | its footprint cell count |

Balancing per currency is what keeps the generator faction-blind: how much a shelter is worth
depends on who is playing, so it is never converted into energy.

**Sites and ponds are balanced apart, though both pay energy.** Balanced together, one alliance
could be handed the ponds and the other the sites at equal energy value — and since a pond is
fast and finite while a site is slow and endless, that split rewards whoever holds the ponds for
rushing. Balancing each alone gives every alliance comparable access to both kinds of income.
The energy BUDGET is still one number: ponds take `pond_value_fraction` of it and sites the
rest.

**Energy value.** A site is infinite at the extractor's rate `r`; a pond pays
`POND_RATE_MULTIPLIER × r` until its charge `E` runs out (and admits one extractor —
[water-bodies.md](water-bodies.md)). Which is worth more depends on how long you look, so value is
measured over a fixed window `H = value_horizon_seconds`:

- site: `r × H`
- pond: `min(E, POND_RATE_MULTIPLIER × r × H)`

The site is the unit the rest is compared against: it is the most stable piece in the economy.

### Favor

Alliances `1…k` each hold one or more starts. For a point `p`, `d_a(p)` is the straight-line distance
to the nearest start of alliance `a`. A feature at `p` gives each alliance an **access share**

    w_a(p) = (1 / d_a(p)) / Σ_b (1 / d_b(p))

which sums to 1 over alliances. For two alliances this is one signed number, the **favor**
`f = w_1 − w_2 = (d_2 − d_1) / (d_1 + d_2)`, in `[−1, 1]`: `0` is equal access, `±1` is standing on a
start. That two-alliance case is the priority; the share vector is how it generalises.

An alliance's **accessible value** in a currency is `V_a = Σ value(r) × w_a(r)` over that currency's
features. **A map is fair in a currency when every `V_a` is close to the same target**,
`value_per_alliance[currency]`. Favor is relative — a feature equidistant from everyone at the far
edge of the map favors nobody — and that is intended: absolute distance is what the terrain pass
and the players decide, not the balance sum.

TODO: favor SPREAD and BOUNDS are not designed. With no bound, a site on one start's doorstep is
cancelled by a pond on another's, and that is allowed for now. Whether to cap any single feature's
favor, or the spread of favors in a currency, is open — and a cap is what would rule out a
natural expansion rather than merely not defaulting to one.

---

## The pipeline

Seven passes. Each states an invariant it must not break — that is what makes a failed generation
*diagnosable* rather than merely ugly, and validation on a generated map is loud and total
(`~/.claude/CLAUDE.md` §10).

**`last_pass` stops the generator after any pass**, leaving the map as that pass left it,
so each pass can be inspected alone. Passes run in order and none can be skipped; balance is
validated whenever pass 3 ran, against the distances the last pass left — straight-line after
pass 3, walking after pass 4. The dock warns while it is below the last pass.

### 1. Extent

`play_size` (in diamonds, `(s, t)`) fixes the corner grid: always square with side `s + t`,
derived, never authored (see [map-and-terrain-grid.md](map-and-terrain-grid.md)). Cells outside the
play rectangle render as nothing, so every later pass works in play-area coordinates and the four
dead corners are simply not addressable.

*Invariant:* every placement is inside the play rectangle.

### 2. Start positions — the ring

Starts are placed at equal angular spacing about the play-area centre, jittered by
`start_angle_jitter`. **Along each start's bearing its distance is drawn freely** between a floor
and the edge margin: at least `start_min_center` (a fraction of the side length it is measured
along) from the centre, and at least `start_edge_margin` cells from every edge. Both are measured
on an ellipse with the play rectangle's own aspect, since a circle sized to the shorter side
cannot separate two starts on a long map. A start is therefore never near the middle, and how far
out it sits varies — nearer Tooth and Tail than AoE3's fixed-radius ring.

This superseded a ring at a fixed fraction of the half-extents with a small radial jitter: that
fixed a start's distance from the centre where a floor was what was wanted, and the fraction in
use put starts inside a quarter-side of the centre.

`PlayArea` carries a centre and two perpendicular axes, so the ring is expressed in play-area local
coordinates and stays inside the rotated rectangle rather than its bounding box.

**This pass is entirely upstream of resource placement.** Pass 3 reads a list of starts, each
labelled with its alliance, and nothing about how they were chosen — so the ring can be replaced
without touching anything downstream.

*Invariant:* each start has a flat, empty box of L∞ radius `start_clear_radius_cells` around it
(twice that on a side, wholly in play) — base-building room nothing is placed in and no pass
shapes. The placement grid reserves it, and a later terrain pass must leave it level too. Each
start also sits at
least `start_edge_margin` from the play-area boundary, at least `start_min_center` from the
centre (less up to 0.02 of the half-extents for snapping its square to whole cells), and at least
`start_separation` from every other start.

TODO: alliance ordering. Same-alliance starts should be adjacent on the ring (AoE2's
`grouped_by_team`), which is a choice of ordering around the circle, not a new mechanism. Not
designed.

A start is allowed to have no energy feature near it. Starting income no longer comes from the
map or the start loader: the starting extractors are removed, and a slot will drop its command
centre and two extractors itself (PLANNED —
[starting-formations.md](../scenario-scripting/starting-formations.md) §Deferred deployment).
Those extractors bring their own sites and stay out of the favor sum.

The clear box (default 12×12) holds the largest starting structure (8×8) while the structure
still spawns on the start. Room to drop a command centre elsewhere is a matter of tuning the
generator so open ground is generally ample, not a reserved box.

### 3. Resource placement — aimed at a favor

**Order.** Energy first, then shelters, then buildings. Each currency's PARAMETERS are independent
of the others'; only buildings' PLACEMENT depends on what came before (§Collocation).

**Budget.** For each currency, the generator places features until the total value reaches
`k × value_per_alliance`, `k` the alliance count (energy is the exception: per player, below):

- **energy** — the budget is **per player**: `energy_value_per_player × start count`, so a team
  game gives every player as much as a duel (Alex, 2026-10-01; it was per alliance, which halved
  each player's share in a 2v2). Placement still balances access per alliance. Ponds are drawn
  until they reach `pond_value_fraction` of it, and the rest is extraction sites, grouped into
  site clusters (§Extraction sites).
- **shelters** — the count is drawn directly: `round(1 + n × (1 + randf()))` for `n` players
  (`shelters_base`, `shelters_per_player_min`, `shelters_per_player_extra`), so a 1v1 map has 3 to
  5, and never fewer than one per start (Alex, 2026-10-05; it was `round(k × (1 + 1.5 × randf()))`,
  1 … 2.5 per alliance). See §Shelters for the ones tied to starts.
- **buildings** — the budget is **garrison capacity per player**:
  `building_capacity_per_player × start count` (Alex, 2026-10-01; it was a footprint share of
  the play area, 3%, which gave about 19 clusters per player). Clusters are drawn until it is
  spent, the last one cut short at the budget. At 75, a 1v1 map gets about 7.5 clusters and 16
  buildings per player.

  **High budgets fail loudly; they do not crash or hang.** Measured on default 1v1 maps with
  the neutral-building pool: 225 per player generates 13 seeds in 15, 250 nine, 275 two, and
  300 none — `no valid position for BUILDING_CLUSTER i of n`. The dock warns from 250
  (`BUILDING_CAPACITY_FAILURE`). The ceiling is room, mostly the 20-cell cluster separation.

**Pond sizing and charge.** A pond's charge is drawn first, because how long it lasts is the
design target (Alex, 2026-10-01: about 3 minutes for a small pond and 8 for a large one, with one
extractor):

- **charge** — a right-skewed normal over `[pond_charge_min, pond_charge_max]` (2700 … 7200: 3
  to 8 minutes at 15/s). Small ponds are common;
- **richness** — one of `pond_richness_factors` (poor 60, standard 90, rich 120), drawn by
  `pond_richness_weights` among the categories whose own size bounds
  (`pond_richness_cells_min` / `_max`: poor 45–80, standard 30–70, rich 30–60) can hold that
  charge;
- **size** — `charge / richness`, clamped to the category's bounds. The stored charge is then
  `cell_count × richness_factor`, capped at `pond_charge_max`: filling the pan's holes at
  placement can add a few cells past the planned size.

**Richness sets size, and size sets how hard a pond is to hold.** A rich pond is compact, so a few
pieces cover it; a poor one sprawls. The per-category bounds are what cap a rich pond's size.

The charge is a balance knob of the generator. Hand-authored ponds keep their flat authored charge
(`WaterBody.NOMINAL_ENERGY`); this rule is for generated ponds only.

**Targets.** Each feature draws a random share vector (a Dirichlet draw; for two alliances, a
random favor) and is aimed at what the currency still owes every alliance **plus** that draw's
lean, scaled by its **freedom** — the share of the currency's value still to come after it. The
last feature has no freedom and aims exactly where balance needs it; early ones may lean hard,
because later ones can make up for it. Without that scaling a currency of three shelters misses
its tolerance whenever the last one draws a lean. Placement never has to discover a fair layout;
it is handed one.

**Placement is best-candidate, not guess-and-check.** For each feature, sample a fixed number of
candidate points (`placement_candidates`) that satisfy the hard constraints — inside the play area,
footprint clear, `feature_spacing` from other features, outside every start's clearance square — and
take the one whose `w(p)` is nearest the target. That is Mitchell's best-candidate scheme: the work
is bounded by `candidates × features`, so it cannot spin. A realised favor that misses its target is
carried forward into the next feature's recentring rather than rejected.

**Buildings go down as clusters** — groupings of buildings grown from a seed cell (§Building layout) — never as an even spread; a
lone neutral building is a rounding error, a block of them is a landmark. A cluster is placed as one
feature against one target, and its buildings are drawn from `building_pool` (§Buildings).

*Invariant:* for every currency, each alliance's accessible value is within `favor_tolerance` of
`value_per_alliance`.

#### Extraction sites

**Sites come in clusters of one to three, edge to edge.** The site count is split by a
stochastic restricted integer partition: per map, `site_triple_fraction` and
`site_pair_fraction` are drawn from their ranges, and in expectation that share of the sites
stands in threes and in twos, the rest alone. Each cluster count is rounded STOCHASTICALLY —
1.4 threes is one three plus a second with chance 0.4 — because a map holds only a handful of
sites, and flooring rounded every cluster away (the first build gave five maps of lone sites).
Threes are taken first and capped by what is left, so the parts always sum to the site count.

A site cluster is one feature, valued as its sites together and aimed at one favor target.
Its sites stand flush: each one after the first is placed against a random side of a random
member already placed. Two site clusters keep `site_cluster_separation_cells` (L1, nearest
sites) apart — 50 by default, far enough that a cluster is a destination rather than part of a
spread.

#### Shelters

Decided 2026-09-28, built 2026-10-05. **Every start is guaranteed a shelter inside a distance band** —
between `shelter_start_band_min_cells` and `_max_cells` of it, not too near, not too far. These
assigned shelters are placed first in the shelter pass, their candidates restricted to the band,
best-candidate still choosing the one nearest its favor target. The remaining shelters are aimed
as usual, and their freedom-scaled targets absorb whatever imbalance the assigned ones left. The
distribution need not space shelters evenly — no shelter has to be equidistant — so long as no
side is favored.

Why a band: spawn points are hidden from every player, but shelter positions are shown, fogged,
from match start. A player then knows the opponent started in a band around one of the shelters
not near them, and the band's width is how sharp that guess is. Its distance also sets how much
a player gives up by dropping the command centre near their shelter rather than elsewhere.

Pass 4 may move an assigned shelter while correcting favor, and that is accepted: the correction
radius is small against the band, and the favor correction already keeps access comparable.

How it is built: the first shelter plan per start carries that start (`FeaturePlan.band_start`),
and its candidates are drawn uniformly over the annulus, centre to centre, then filtered by the
band — the filter is the rule, since rounding to a cell moves a centre. Best-candidate still
aims each one at a fair access split, and inside the band that is its far edge: at 15–35, 29 of
the first 30 starts measured had their shelter at 29–35 cells. The band was narrowed to 25–35
(Alex, 2026-10-05) rather than dropping the steering; 35 of seeds 3000–3039 generate at 25–35
against 36 at 15–35, and no rejection is the band's. Pass 4 re-places a feature
with the same plan, so a moved shelter stays in its band (a band candidate inside pass 4's small
window is found by filtering rather than drawing). `_validate_shelter_bands` refuses a map where
any start lacks one, which happens only when a band has no free footprint at all.

The count no longer falls short: it is at least one per start plus, at the shipped knobs, one
more to rebalance with (`round(1 + n × (1 + randf()))`, floored at the start count). Before
2026-10-05 a 1v1 map had two shelters about one time in six, both assigned, and the opponent's
band was then certain.

TODO: the band's bounds are not tuned.

#### Buildings

The neutral buildings are a family (`nt_building_square`, `_long`, `_shack`, `_large`) of differing
footprints, and generation must not assume a square. Buildings are drawn from a **pool of neutral
pieces**, the whole `neutral_building` family at uniform weights, so a cluster is packed from
footprints, not from a count, and the pool is a generation parameter.

**A cluster is sized by garrison capacity, not building count** (Alex, 2026-10-01), because the
buildings differ: a shack holds 3 and a large building 10. Each piece's capacity is read from its
scene's `Garrison`, like its footprint. A cluster draws a capacity, then buildings until it is
reached:

- **capacity** — a band by `cluster_capacity_band_weights`, then uniformly within it
  (`cluster_capacity_band_edges` 3–10–15–20–25, weights 0.55, 0.36, 0.07, 0.02): up to 10 is
  about half of all clusters, 10–15 about a third, and the two upper bands are the rare
  landmarks. Banded rather than a skew-normal or gamma, which could not hold the 20–25 tail
  without inflating the bands below it;
- **buildings** — drawn from the pool, each only if it lands the cluster at most
  `cluster_capacity_overshoot` past its capacity. The pool's weights are scaled by
  `capacity^(cluster_large_building_bias × t)`, `t` the cluster's capacity across the bands, so a
  small cluster draws as the pool is weighted and a large one leans toward large buildings.

A cluster's balance value is its capacity. Two earlier forms are superseded: uniform sizes in a
narrow band made every cluster the same landmark, and a building-count draw
(`1 + NegativeBinomial(2, 0.4)`) stopped meaning a cluster's size once buildings held 3 to 10.

With the budget at 75 per player, a 60-seed sample of 1v1 maps gave per player 4.4 clusters up
to 10, 2.2 at 10–15 and 0.64 at 15–20, and 0.4 clusters of 20–25 per match.

TODO: balancing constraints on buildings are not designed — guaranteeing some number of clusters
of given sizes, and positioning clusters relative to the starts (ideally as the same kind of
fairness constraint the other currencies use). Today a cluster is aimed at a favor target like any
feature, and nothing constrains which sizes a map gets.

**Clusters keep apart.** No building of one cluster may be within `building_cluster_separation_cells`
(L1, between their nearest cells) of a building of another, so two clusters never read as one.
Centre spacing alone could not promise that: two large clusters whose centres are far apart can
still sprawl into each other.

#### Building layout

Decided 2026-10-09 (Alex). **A cluster is a set of groupings**: one to three buildings standing a
TIGHT gap (1 cell) apart, like a row of houses, with groupings an OPEN gap (3–5 cells) from each
other. Every gap is the Chebyshev gap between footprints — clear cells along the axis they are
furthest apart on — because that is what a square-eroded navmesh lets through: a tight gap passes
only the narrowest size class, an open one the wider ones.

- **No more than three buildings are tightly packed.** More than that walls the cluster off.
  Grouping sizes are drawn by `grouping_size_weights`, whose length is the largest grouping.
- **A grouping looks built, not scattered.** Each member after the first stands a tight gap off
  a side of a member already placed, with one pair of their side edges in line (flush). Within
  one grouping, members not joined directly may stand at any gap — a row of three shacks puts 4
  cells between its ends, behind the middle one — but never touch.
- **Between groupings, no gap is narrower than 3**, so no tight gap joins two groupings, and each
  grouping stands within 5 of a grouping already placed, so the cluster grows from its first
  grouping as one connected place.
- **A cluster fills out toward square.** A new grouping is placed across the SHORTER axis of the
  cluster's bounds so far, staying within the longer axis's span (give or take
  `cluster_span_slack_cells`, or the grouping's own excess when it is longer than the span); once
  the axes are equal, any side. Without this, groupings trail off in a line.
- **A grouping's long walls run parallel.** Each grouping draws an axis, and every non-square
  building in it is turned a quarter (Fixture.quarter_turns, written as the piece's yaw) so its
  long side lies along it; square ones are never turned. Groupings of one cluster may differ.
- **Never adjacent**, edge or corner.

A cluster is grown from a random seed cell; its feature centre is the mean of its buildings'
centres. `tools/map_generation/cluster_review.sh` renders a review set and checks these rules.

Superseded: a random scatter in a disc sized by `cluster_packing_density`, each building only kept
`footprint_gap_cells` from the others — it produced staggered neighbours, arbitrary packing and
gaps of every width.

#### Shelters and clusters

Decided 2026-10-09 (Alex). **A shelter is either in one building cluster or clear of all of them**,
and for `n` players at least `n − 1` stand each way, with no cluster holding more than one.

- **In a cluster, a shelter is one of its groupings.** The cluster is grown around it — its first
  grouping stands the open gap (§Building layout) from the shelter, and every grouping keeps that
  gap from it — but the shelter is not one of the cluster's buildings: it adds nothing to the
  garrison capacity a cluster is sized by, nor to the building budget.
- **Apart, a shelter keeps `shelter_cluster_clearance_cells`** (Chebyshev gap) from every building
  of every cluster, so it never reads as some cluster's next grouping.
- **How many host.** Shelters are placed before buildings, so once they stand the generator draws
  how many will host, uniformly between `n − 1` and all but `n − 1` of them (capped by the cluster
  count), picks those shelters and that many clusters at random, and every cluster built around a
  shelter is placed against it. The rest are apart.
- **Impossible parameters refuse the map.** Fewer than `2(n − 1)` shelters or `n − 1` clusters
  is an error, as is a finished map where any shelter is half-in a cluster, two shelters share one,
  or either count falls short — checked from the geometry, after pass 4 and the mirror.
  `MapGenerationParams.warnings()` flags a shelter count that can never reach `2(n − 1)`. A map
  with no building pool can no longer be valid.
- **Pass 4 never moves a hosting shelter**, since its cluster would not follow; it may re-grow
  the cluster around it.
- **Hosted clusters are placed before free ones.** One pinned to its shelter, placed after free
  clusters, often found one already within `building_cluster_separation_cells` and had nowhere to
  go: on the topology tests' crowded map that alone took valid seeds from 25 of 25 to 17.
- **The shelter's footprint is read from its scene**, like every piece's, and every rule here is a
  gap between footprint edges, so a larger shelter (planned) needs no change here;
  `test_a_larger_shelter_still_stands_in_one_cluster_or_apart` holds that.

This replaced a collocation affinity pulling clusters toward shelters (1.0 within 14 cells), which
made nearness likely rather than decided and could not keep a shelter apart.

TODO: hosting still costs a little room on crowded maps: the topology tests' 80–90-cell map with 20
single-building clusters is valid on 23 of 25 seeds against 25 before. Not tuned.

#### Collocation

**Pairwise affinity.** Each ordered pair (kind being placed, kind already placed) carries an
`affinity` in `[−1, 1]` and a `radius`. A candidate's score is its favor error minus
`collocation_weight × Σ affinity` over already-placed features within that pair's radius — so a
positive affinity pulls a candidate toward those features and a negative one pushes it away. Whether
a shelter stands in a cluster is not collocation but a rule (§Shelters and clusters).

Because placement runs energy → shelters → buildings, an affinity can only name a kind placed
EARLIER — which is exactly how buildings depend on energy and shelters. Collocation is weighted by
the same freedom as the favor lean: a feature nothing after it can rebalance places for balance. The table is
`collocation_affinity`, and a pair it does not name has affinity 0.

TODO: revisit. Composite features — a named group such as "settlement: a shelter with a building
cluster", placed as one feature against one target — were the other candidate and were deferred
for this simpler form, not rejected.

### 4. Topology — obstruct, carve, correct

Its input is the point set from passes 2–3; its output is a set of *decisions* — which cells are
barriers, which are carved open — and possibly moved features. Nothing here sets heights.
`MapTopology` holds them.

**The feature graph.** Nodes are the starts and the placed features. Edges come from a Delaunay
triangulation of the node positions (`FeatureGraph`) — the *only* cartesian step, and it exists
solely to decide which features are plausibly neighbours.

**Obstruction is chosen as edge cuts.** A barrier is an *edge of the graph to sever*, not a blob
dropped on the ground: `cut_fraction` of the edges are cut, at random. A cut is drawn on the
Voronoi boundary between its two nodes — every cell whose two nearest nodes are that pair and
which lies within `barrier_width_cells` of equidistant. **A barrier never takes a cell next to
anything reserved** (a start's box, a footprint or its gap, a pond or its rim): pass 5 moves a
barrier cell's corners, which its neighbours share, and those must stay level. So a barrier is
clipped short wherever it would cross a feature's ground.

Consequence, visible on every map: barriers come out as short walls between near neighbours
rather than as lines dividing the map, and they seldom enclose anything, so carving rarely
triggers. That is what the construction gives with features as dense as the defaults.

**Connectivity is restored by carving, not by rejecting.** This is AoE2's `CONNECTION_GENERATION`:
rather than testing a cut and discarding it, apply the cuts and then *carve* passages until every
required connection exists. A carve opens a band across the barrier along its graph edge, its
walkable width drawn from `MIN_CHOKE_WIDTH × (1 + randf())` — 10 to 20 cells (two wider as drawn,
since a barrier's border cells are steep). Carving terminates; attempt-then-reject can spin. Required connections are:

1. the walkable ground is one connected component;
2. every start reaches every feature;
3. every start keeps at least `min_routes` vertex-disjoint routes to every OTHER START over the
   graph's open edges (uncut, or cut and carved).

Test (3) is what stops a base being reachable through one choke. It is decided on the graph
first — a carve is kept only if it raises the deficient pair's route count — and (1)–(2) are then
checked on the cells, carving the barrier nearest any stranded ground until none is left.

TODO: test (3)'s subject — routes between STARTS — is the rule most likely to change. The earlier
wording ("routes to the features nearest equal favor") was too vague to build; Alex chose starts
(2026-09-19) and expects to revisit it.

**No gap between two obstacles is narrower than `open_gap_cells` (20).** A gap is the walkable
ground between two separate obstacles — barriers, each with its steep border, and the edge of
the play area. After carving, any barrier that leaves a narrower one is trimmed back (the
smaller of two barriers gives way; a barrier gives way to the edge unless its mass touches it),
and fragments under four cells are dropped. Trimming only removes barrier, so connectivity and routes survive it. So two
masses either merge into one or stand a field apart; see §Openness for why the trim width is
not the choke floor. Chokes made by resource footprints — buildings, shelters, sites — are not
held to the rule, and ponds are walkable.

**The deliberate chokes are carves and ramps**, and those are drawn from `MIN_CHOKE_WIDTH`
(10 cells) up to twice that. The floor is a constant, not a knob: it keeps a unit column moving
through every choke on every map. Width above the floor is still the strongest balance lever on
the map — narrow is the StarCraft ramp that makes melee viable, wide is the open field that
makes it worthless.

TODO: a narrow bay inside ONE bent obstacle is not measured, only gaps between separate
obstacles. Grown masses bend, so these now appear: a C-shaped mountain with a 7–10-cell mouth,
about one map in three (§Openness). Filling a bay whose mouth is narrower than the open gap
would close them.

**Favor correction.** Pass 3 aimed at straight-line favor; barriers make some features farther by
foot than by line. Once cuts and carves are fixed, every feature's share is re-measured by
WALKING distance (`PathField`: octile shortest paths over the walkable cells, one field per
alliance), and:

- a feature that drifted more than `favor_tolerance` from its target is re-placed by the same
  best-candidate search, within `correction_radius_cells` of where it stood, scored by walking
  share — kept only if it lands nearer its target;
- a currency still out of tolerance is then rebalanced: its features, largest first, are re-aimed
  at the share that would even it out given the rest, keeping each move that shrinks the
  imbalance, for up to three rounds.

Everything else holds its ground while a feature moves — starts, other features, barriers and
carved passages — and the graph is not re-triangulated: it only chose the cuts, and the cuts are
fixed.

The invariant is per CURRENCY, not per feature. The first build failed any single feature that
could not be moved back, which rejected most maps: features are aimed at deliberately leaning
targets, and one stubborn feature matters only if it leaves its currency unfair.

*Invariant:* (1)–(3) hold, and every currency is within `favor_tolerance` by walking distance
(checked by the balance validation at the end).

### 5. Terrain realisation

Only now does anything become heights and water levels. **Open ground stays flat at
`ground_height`**: a cell is buildable only when its four corners are equal, so any rolling would
make ground unbuildable, and height has no gameplay effect yet (Alex, 2026-09-19).

- **Ponds** are sunk as flat pans exactly `MAX_SLOPE_DIFF` below the ground, water just above the floor, so
  their cells are shallow and the rim is passable-but-unbuildable
  (see [map-composition.md](map-composition.md) §The basin). **A map with a pond units cannot walk into is
  rejected**: the rim sits at exactly the walkable limit, so rounding, or a limit moved under a
  saved map, seals it silently.
- **Each cut** is a ridge or a flooded chasm, drawn at random by `flooded_cut_fraction`:
  - a **ridge** raises its cells' corners `ridge_height`, every other corner a further
    `RIDGE_ROUGHNESS` — so the crest is as steep as the sides, not a plateau nothing can reach;
  - a **chasm** sinks its cells' corners and floods each connected stretch with uncharged water
    halfway up: deep over the floor. A *dry* chasm would be walkable, so a chasm cut is always
    flooded. A carved chasm leaves a land bridge.
    - **One body per level, at that level's own ground.** Water fills everything connected below
      its surface, so a chasm lifted across a cliff by pass 6 pours into every level beneath it:
      three of five review maps came out 55–88% flooded. Each stretch sitting at one level holds
      its own water instead.
    - **The chasm stops two cells short of a level boundary, and that gap stays dry**, or the
      water would run down the chasm into the level below. The gap spans the step, so it is
      cliff — impassable, and the barrier still divides. Two cells, because the row touching the
      water shares its sunk corners and floods with it. This is where a waterfall goes when one
      is built.
    - **A body that will not stay in its chasm is not placed, and that stretch is raised as a
      ridge.** A chasm beside a cliff stands above the ground below it, and a cliff cell is steep
      but not TALL: its middle can sit under the water, so the fill walks over it. Predicting
      that from rim heights means re-deriving the fill, so the fill itself is the test.
    - **A dry chasm is not left sunk.** Its floor is flat, so anything over two cells across is
      walkable ground in a pit ringed by a one-cell cliff — pass 4 counted it as obstruction, the
      finished map did not, and the ring drew thin enclosures across the map (seed 2003 of
      `test_MapElevation` had 17 such cells before 2026-10-02). Raising one stretch lifts a corner
      it shares with a diagonal neighbour, which can strand that neighbour's seed or cut part of
      it off from its water, so the fill is settled: re-tested from a seed still on its floor,
      until no chasm cell is left walkable and dry — lips and cells beside a ridge included.
    - The water is seeded per **4-connected** stretch, because that is how a basin fills: an arm
      joined only across a corner would take no water and stay walkable chasm.
- Every cell bordering a barrier shares a moved corner, so it is steep too.
- Where a chasm meets a ridge, the chasm cells sharing the ridge's corners stand too high to
  flood; they are steep instead, and still impassable.

*Invariant:* at least `flat_fraction` of in-play walkable cells are buildable. Slopes eat the
player's ability to build, and this is the number that stops a generator quietly making an
unplayable map.

Note what is deliberately **not** an invariant: connectivity of every passable cell. A ridge top
or chasm floor is unreachable ground, and that is allowed (see
[map-composition.md](map-composition.md)). Tests (1)-(3) in pass 4 are about walkable ground
and the feature graph.

Pass 6 then lifts this flat ground onto discrete levels; within a level it stays flat.

> **REJECTED — gently rolled relief** (the original sketch): ground that rolls is unbuildable
> wherever it rolls. Pass 6's discrete levels joined by ramps are what replaced it.

### 6. Elevation — terraces and cliffs

The ground is lifted off the flat. **Levels come from the feature graph**, not from a free
heightmap (Alex, 2026-09-19): every start and feature is a node, and each node gets a terrace
level, `elevation_step` apart, at or under `MAX_SLOPE_DIFF` — walked over, so only the cells on
a step lose their buildability.

**A cliff may stand only where a barrier does** (Alex, 2026-09-19). Elevation marks divisions the
topology already decided; it adds none of its own. Pass 6 used to draw a full step at every
boundary between differing regions, which cliffed about three-quarters of them on nothing, and
halved the map's widest corridor — gen_02 went from 17 cells to 9, below `MIN_CHOKE_WIDTH`.

> **REJECTED — a second ladder of cliff TIERS** (built 2026-09-19, retired 2026-10-02). A tier
> changed only across a cut but was crossed elsewhere on graded ground, and under the tan 30°
> walkable limit a tier's drop graded over about twelve cells: the long ramps Alex did not want,
> and wide bands that squeezed reserved zones into slivers and narrowed the map. Its drop also
> hid inside the ridge it stood behind, so no generated map showed a cliff.

- **Where levels come from.** Coherent noise sampled at each node, `elevation_scale_cells`
  across, stretched so the whole ladder gets used — raw noise bunches near its middle. Each
  group asks for that level and is given the nearest the rules below allow, solved as difference
  constraints over the groups (`LevelConstraints`), so assignment never paints itself into a
  corner.
  > **REJECTED — ranking the noise** instead of stretching it. Ranking spreads the groups evenly
  > over the ladder, which puts neighbouring regions at opposite ends; the one-step limit below
  > then squashes them back together and whole maps came out at a single height.
  > **REJECTED — smoothing the levels** toward neighbours' commonest: with the one-step limit
  > already holding them together it dragged whole maps onto the starts' level, leaving three of
  > six seeds with no relief at all.
- **Regions a walker can cross between differ by at most one terrace** (Alex, 2026-10-02), so
  no slope is longer than a terrace graded. That is every open graph edge, and every pair whose
  ground touches where no barrier stands — a cut whose barrier was clipped or trimmed short is
  crossed there all the same. **Across a barrier there is no limit** (Alex, 2026-09-30): a
  height difference that divides the two sides only agrees with the topology. The one exception
  is a cliff's ends (§Cliffs). **Every re-level holds it again** — a repair that copies one
  region's height onto a stranded group reruns a relaxation, holding the starts, the moved
  groups and the region they were levelled to. A pair still more than a terrace apart at the end
  rejects the map. Seed 2004 of `test_MapElevation` shipped exactly that once: a routes re-level
  lifted two groups two terraces clear of their open neighbours, and nothing looked again.
- **What must share a height.** Reserved zones within a couple of cells of each other are one
  group, and so are the two sides of a carved cut. A closer pair on different heights would
  leave a sliver of ground walled in, and a carve is an opening a cliff would close again.
- **Starts all share one height**: a terrace from `start_level_fraction_min … _max`, high but
  not always the top (Alex). Height has no gameplay effect yet, and when it has, no start should
  begin below another.
- **Each cell takes its region's height**: reserved ground (footprints, pond rims, start boxes)
  outranks barrier cells, which outrank free ground. A corner shared by cells of different
  heights takes the highest-ranked cell's. **So a step never falls inside a footprint.**

**Grading is what keeps a height change from becoming a wall.** The free ground between two
regions of different height is pulled to within `_GRADE_PER_CELL` of its neighbours, sweep by
sweep like a distance transform, until the drop is spread over a band a walker climbs. Two
things are held out of it:

- **A barrier is where a drop may land whole.** Its cells are excluded, so they neither grade nor
  drag the ground either side toward them — a step across a barrier lands on the barrier, and on
  a cliff that is its face. Ground out of play is held out for the same reason.
- **A reserved zone is held flat**, then settled onto the graded ground: every cell of a zone
  takes the mean height of the free ground around it — one height, so the footprint stays
  buildable — and the grade is swept again to meet it. Per zone, not per group: a group can hold
  zones far apart.

A **cliff** is then simply a cell whose corners span more than `MAX_SLOPE_DIFF`, and it is
impassable like a barrier. After grading, nearly all of them stand against a barrier.

**Ramps** survive as the repair tool, not the main mechanism: a slope cut across a cliff, as long
as the rise needs at the walkable gradient and `MIN_CHOKE_WIDTH × (1 + randf())` wide. A ramp
follows its two sides: if they come to match, it goes. **Every ramp must carry a corridor at
least `MIN_CHOKE_WIDTH` wide from foot to head** — a feature, a barrier or a second cliff can cut
across one and leave a sliver nothing fits through. The width is measured slice by slice as the
longest unbroken walkable run, so a slice split in two counts as two narrow corridors rather than
one wide one. A ramp that fails is widened once; if it still fails it is dropped and its two
sides brought level.

The rest of the pass is unchanged, and checks the same three things:

1. **Every pair of starts keeps `min_routes` disjoint routes** over the edges still open, where
   an edge between heights is open only if a walker can cross it. First a ramp that raises the
   count, then one that extends a path, then a node re-levelled to match its neighbour.
2. **Walkable ground is one piece.** A stranded stretch first gets a ramp on a cliff beside it,
   then the groups owning it are re-levelled, then the stretch itself. A stretch under 25 cells
   is left unreachable, like a ridge top: no ramp fits one, and chasing them piles up ramps.
3. **The choke floor holds**, with cliffs as fixed obstacles: a barrier within
   `MIN_CHOKE_WIDTH` of a cliff is trimmed. Only the floor, not the open gap pass 4 keeps
   between barriers — a cliff follows a barrier rather than standing as a mass of its own, and
   held to the open gap it trimmed a third of a map's barriers away after pass 4 had met its
   share. Trimming frees cells and a new ramp adds walls, so the floor and test 2 alternate
   for a few rounds until neither changes anything. Test 1 is judged last, on the settled map.

A feature that ends on a cliff or a ramp, or too near another feature, is **moved and rebalanced
per currency** exactly as in pass 4, against walking distance on the levelled ground. Pass 5's
shaping is then re-run on top of the offsets: a pond or a chasm floods at its own level, and the
`flat_fraction` invariant is checked again.

A generation costs **5–11 seconds** at the defaults (22 seeds at 100–120, 7 s mean, 2026-10-02),
about two-fifths of it pass 6, a quarter pass 4 and a fifth pass 7. It was 16–53 s before the
grading sweep stopped visiting cells that cannot move and testing play and barriers per
neighbour — grading was nine-tenths of a generation, run twice per relabel and once per ramp
tried.

*Invariants:* tests 1–3 above, pass 4's balance, and **elevation does not narrow the map** — the
widest corridor from one side to the other is no smaller than it was on the flat map. **A map
that cannot meet them is rejected, not patched.**

- A barrier's own shape can cancel a cliff's step: a ridge on a lower level can top out exactly
  at the upper one. That cell is then only upper ground beside the barrier, and cannot join two
  levels, because neighbouring cells share their edge corners.
- TODO: a few dozen cells per map still cliff with no barrier behind them — mostly where a
  reserved zone sits in a strong grade and its flat footprint leaves a step at one edge, a
  building platform cut into a hillside. They are slivers and do not narrow the map, so they are
  left; removing them means letting a footprint tilt, or grading more gently around features.
- TODO: when a start pair cannot keep its routes, the map is rejected rather than having the
  heights between them flattened. Flattening would always succeed but erase the relief exactly
  where the starts meet; whether that trade is wanted is Alex's call.

#### Cliffs — a way of realising a barrier

Decided and built 2026-10-02 (Alex). **Topology decides where ground is untraversable; elevation
decides how.** A cliff is one way pass 6 realises an untraversable cut: its two sides stand
several terraces apart and the band between them is the face, where a ridge or a river would
otherwise stand between ground at one height. Before this, a drop hid inside the ridge it stood
behind, and of seeds 2000–2011 four had no visible drop at all.

- **Which cuts.** A thin cut — ungrown, uncarved — between two groups whose ground touches round
  the barrier's ends along at most a fifth of the barrier's length. Pass 4's barriers are short
  walls, so a cut's sides usually touch somewhere; where they touch a lot, the slope round the
  wall would be the long ramp the one-terrace rule exists to prevent.
- **Pass 6 chooses, deliberately.** `cliff_cut_fraction` of the candidate group pairs is drawn,
  each held a drop apart in the level constraints, the side whose noise asks higher on top. A
  thin cut's kind — ridge, river or cliff — is decided here; a grown region keeps the kind pass 4
  gave it, because the lake share steers growth.
- **Drop: 2 to 4 terraces** (`cliff_drop_terraces_min` / `_max`, 1.0 to 2.0), drawn per cliff and
  tried smaller when the way round cannot climb it: every open route round a cut climbs at most
  a terrace per region it crosses, and on most cuts the shortest is two or three regions.
- **Ends are graded** (Alex, 2026-10-02): where the two sides touch, the drop is spread over a
  slope — about four cells for two terraces, eight for four. The one exception to the
  one-terrace rule.
- **Shape: a face, talus and a crest.** Each band cell stands at its own side's level, so the step
  falls on the band's midline. Below the face the band keeps the cells the drop hides from the
  lowest camera pitch, so the only ground a cliff hides is its own; above it, a one-cell crest;
  the rest of the band becomes ground of its own side. The kept cells are low rubble, spiked
  `TALUS_ROUGHNESS` on alternate corners — enough to stand on none of them, far under a ridge.
- **A chosen cliff the levels cannot hold**, or that a repair's re-level flattens, is drawn as the
  cut's ridge or river and counted in the report.
- **At `last_pass = TERRAIN`** a cliff cut shows as a ridge: stopping early is a debugging
  convenience, not a map anyone plays.
- **Reported, not enforced**: the report gives each map's cliffs, their band cells and the ones
  that stayed ridges or rivers. 1–5 cliffs per map on seeds 2000–2011.
- **No trees on a cliff** (pass 7): a tall prop stands only on steep ground well above the
  walkable ground near it — a mountain's flank, never a face, talus, ridge foot or rim.

- TODO: **a cliff still reads as a rocky strip rather than a face.** At one height sample per
  cell a 1.0–1.5 drop is barely taller than the talus spikes beside it, and pass 7 scatters
  boulders over the band where trees were. Candidates: smoother talus (the least roughness that
  stays impassable), fewer rocks on cliff bands, the planned rock-face meshes
  ([visual-facets](visual-facets.md) §Shortlist 1), or a taller minimum drop (fewer cliffs).
  Alex judged it fine for now (2026-10-02).
- TODO: **the face of a grown mass is not built.** Alex's answer included a mountain or lake's
  face where it borders a level change; only thin cuts become cliffs.
- TODO: **two `test_MapElevation` seeds are pending.** Since cliffs replaced tiers, seed 2003
  narrows the map by one cell (11 against 12 flat) and seed 2004 leaves one barrier cell
  walkable — a corner the talus, the occlusion cap and a neighbouring barrier share.
- PLANNED: incremental relabel ([map-generation-review](map-generation-review.md) P1), approved
  and waiting on this rewrite.
- A cliff need not show its whole face to the camera, but must not hide units (§Seeing the
  ground, below).

#### Seeing the ground

Decided 2026-10-02 (Alex): **a walkable slope must be wholly visible to the camera, and terrain
should not hide units behind it** — at the default view, with no rotation needed. The camera's
free yaw is the player's option, never a requirement, so the rules hold from every side. An
untraversable face need not be seen whole.

The camera is orthographic, pitched between 30° and 45° below the horizontal, with free yaw.
Comparable titles: Warcraft III about 56°, Age of Empires II's 2:1 tiles about 30°.

- **Walkable slopes against the pitch.** Alex set the camera below 45° (40° on 2026-10-02) and
  expects it to stay between 30° and 45°. A slope steeper than the pitch, facing away, is hidden
  outright, and one equal to it is seen edge-on, so the walkable limit is derived from the 30°
  floor (§Parameters), and `test_ViewPitchFloor` keeps the camera above it. Before, the limit
  was 45° and about 3% of a generated map's walkable cells — pond rims, the steepest graded
  ground, terrace steps — stood steeper than a 40° camera; now none do.
- **An obstacle's height is capped by its distance from walkable ground** (Alex, 2026-10-02). At pitch θ an obstacle h above the ground hides the h / tan θ cells behind it;
  a mountain's edge stands about 4 above its foot (ridge 3 plus roughness 1.1), hiding up to
  about 7 cells at 30°. So a cell of an obstacle may stand no higher above the nearest walkable ground
  than its distance from it × tan θ, plus `occlusion_allowance` (0.5, the part of a unit at the
  foot it may hide): masses rise toward their middle, not at their edge. θ is the lowest camera
  pitch, `MIN_VIEW_PITCH_DEGREES`, so the cap holds wherever the camera sits. Where the cap
  leaves no room for the roughness above, an alternate corner stands below instead, so a capped
  cell stays impassable. For a cliff it means the apron is
  at least `drop / tan θ` wide, so the only ground a cliff hides is its own impassable apron.
  Units are drawn as silhouettes through terrain today, which softens a miss; the heights are
  the fix.
---

## Obstacle regions: mountains and lakes

Decided 2026-10-01 (Alex), and built (`ObstacleRegions`, in pass 4; shaped in pass 5). It folds
in the water-as-a-feature plan of 2026-09-19.

**Why.** Before regions, a generated 1v1 map was about 90% traversable (88–92% over five seeds:
ridges and cliffs 6.2%, water barriers 2.2%, footprints 1.4%). The open ground was not
gathered into large voids: a typical open cell was about 5 cells from something. The whole map
was simply mostly open. Wider cuts were measured and do not fix this: at 6 cells wide instead
of 3, obstruction went from 9% to 14%, but open ground stayed as close to things as before,
because cuts are clipped short around features and fill ground that was already near
something.

**Target: 85% ± 2.5% of the play area traversable** (`target_traversable_fraction`,
`traversable_tolerance`; Alex, 2026-10-02 — it was 80% ± 5%, and the masses that took grew
large enough to make ground units walk a long way round, handing the map to air). A traversable cell is in play, not steep, not under deep water and not
a footprint, so a lake's shallow shelf counts and its deep core does not. The finished terrain is
measured, and **a map outside the band is rejected**. Unbuildable ground is tracked as well
(the report states both shares). It is bounded only by `flat_fraction`, as a share of walkable
ground.

**There is no separate cap on water** (Alex, 2026-10-01). Ground left unbuildable by a slope
and ground left unbuildable by shallow water play the same, because elevation has no combat
effect and none is planned. So one bound covers both, `flat_fraction`. This supersedes the
`water_fraction` cap of the 2026-09-19 plan.

### A region is an aggregation of cuts

Alex's framing: a set of cuts that isolates a piece of the navmesh, with that piece then made
impassable entirely. Ridges and regions both make ground untraversable; their shapes differ,
and so does what they do to the ground around them. So regions are **grown from pass 4's
cuts**, not placed as free blobs:

- **A cut grows by widening its Voronoi band.** A plain cut is the cells whose two nearest nodes
  are its pair, within `barrier_width_cells` of equidistant. A grown cut keeps the same cells out
  to a gap drawn in `region_width_min_cells … _max_cells`, ragged by coherent noise
  (`region_edge_noise`, `region_noise_scale_cells`). Widening thickens the cut and lengthens it
  toward the Voronoi vertices, where neighbouring grown cuts meet.
- **Ground the growth closes off is filled**, when it holds no start, feature footprint or pond
  and lies outside every start's buffer. A growth that would close off any of those is undone.
  This is the "isolated piece made impassable".
- **A cell whose nearest pair is an OPEN edge is never taken**, so the corridors the graph's
  routes run through stay open. Only uncarved cuts grow: a carved cut is one the routes need.
- **The growth happens in pass 4**, after carving and before the connectivity repair and the
  choke floor, so those cover regions exactly as they cover cuts. Cuts grow, then the trim to
  the open gap, for up to six rounds, until the share is reached. Once every uncarved cut has
  grown, the grown ones grow again, each round reaching further: the trim gave back what a cut
  lost to its neighbours, and only room away from every other obstacle survives the next trim.
- **A growth that would strand a feature or a start is retried shorter**, twice, before it is
  dropped. Undoing it whole threw away most regrowth, which reaches far enough to close pockets.
- **Regions keep out of a start's clear box plus `feature_spacing`**. A cut's own thin band,
  drawn before any growth, follows the plain barrier rule and may come closer.
- **No gap is narrower than `open_gap_cells`**, regions included; a mass near the play edge is
  closed onto it instead, and no mass spans more than `max_obstacle_span_fraction` of either
  side (§Openness).

**`cut_fraction` is 0.45, the top of its bracket.** Only uncarved cuts grow, and at 0.3 growing
every one of them still left 81–88% of a 1v1 map traversable, short of the old 80% target.
TODO: not re-measured at the 85% target, where fewer cuts may do.

### Mountains and lakes

- **A grown ridge is a mountain**: a rough massif, raised and steep everywhere like a ridge, and
  `mountain_rise_per_cell` taller for each cell from its edge, up to `mountain_rise_max`. Not a
  plateau with an unreachable flat top.
- **A grown chasm is a lake**: its cells are the deep core, sunk like a chasm. Free ground within
  `lake_shelf_cells` of it is sunk to a pond's pan, and the water stands at a pond's level, so the
  shelf is shallow and wadeable but unbuildable. Deep is impassable
  (see [water-bodies.md](water-bodies.md)). Where no shelf fits, a lake is deep to its edge.
- **An ungrown flooded cut stays a river**, its water halfway up its chasm as before.
- **A thin cut may instead be a cliff**, chosen in pass 6 (§6, Cliffs).
- **Which kind grows next** is the kind further below its share of the cells grown so far,
  `region_lake_fraction` of them lakes.
- **A body never spans levels.** A lake follows the chasm rule of pass 5: the stretch on one
  level holds water, and a stretch whose water would run out of its lake is raised as a
  mountain instead.
- **Waterfalls are deferred**: later, an upper line and a lower line are joined by decoration.

Carried over unchanged from the 2026-09-19 water plan: a chasm and a river are the same thing,
a cut shaped as a trench that may or may not hold water. The gameplay difference is thin (a dry
crossing is buildable, a shallow one is not) and does not earn a second mechanism. A ford is a
shallow crossing cut into deep water, the way pass 4 carves a gap in a ridge.

### Obstruction is a cost balanced per alliance

How much impassable ground lies near a player matters to that player, so it falls about evenly
between alliances: mountains, lakes, ridges and cliffs together. Each impassable cell is split
between alliances by the same access share the resources use (`MapFavor.access_share`). The
next cut to grow is the one leaning most toward the alliance with the least so far, drawn from
the best three so neighbouring seeds differ — or simply the best, once the split leans past a
third of the tolerance. **A map whose worst alliance is more than `obstruction_tolerance` (15%)
from even is rejected.**

- **A cut's lean is the mean share of the cells it can grow into**, not of its graph edge's
  midpoint: the Voronoi boundary a cut grows along can sit far from that midpoint, and steering
  by it made balancing worse.
- **The tally is recounted after every trim**, over everything blocked (a barrier and its steep
  ring). A running sum of what growth added kept counting what the trim had taken away.
- **Then a balancing phase**, because masses are large and the split can still lean hard when
  the target is met: below the target the next move grows toward the light side, through an
  uncut graph edge if no cut is left there (kept only if every pair of starts keeps its
  routes); at or above it, the move un-grows the grown cut leaning hardest toward the heavy
  side. Each move is kept only if it evens the split and leaves the blocked share within half
  the traversable tolerance of its target, at most twelve moves.

TODO: the check for closed-off ground is local. Each piece of ground beside a growth is flooded
up to 5000 cells, and a piece that large counts as open, so a growth that split the open ground
into two such halves is not caught there. The connectivity repair then carves it open, possibly
through the region. None has been seen.

TODO: pass 6 rejected about one seed in five on routes between the starts; at the defaults of
2026-10-02 it rejected one of seeds 2000–2021 (2016, on routes and terraces), and 2004 now
generates. Whether `cut_fraction` 0.45 moves that rate is unmeasured.

TODO: map-size parameters are still being calibrated. Keep the current `play_size` bounds for
now. The parameterization will need reworking once resource and pseudo-resource allocation,
the distances between spawns, and the share of openly traversable ground are settled together.

### Openness

Decided 2026-10-02 (Alex): obstruction should leave **large, open, connected fields**, with
narrow passages rare. Occasional narrow chokes are fine; a map threaded with them is not.

**How it is measured** (`MapOpenness`, on the finished terrain, footprints counted as walkable
because their chokes are not held to the rule):

- **Clearance** — per walkable cell, the distance to the nearest cell a unit cannot stand on.
  A passage `k` cells wide has clearance `(k + 1) / 2` down its middle.
- **Open share at radius r** — the walkable cells inside some clear disc of radius `r`: what is
  left after a morphological opening. The report gives it at 12, a field 25 cells across.
- **Chokes** — found as BWEM finds them for StarCraft. Cells are grown into areas from the most
  clear down, a watershed on clearance. Where two areas meet, the meeting cell's clearance is
  the half-width of the narrowest passage between them. It is a choke when both areas are open
  ground (clearance at least 8, i.e. 15 cells across) and the passage is at most 0.7 of the
  smaller one's clearance; otherwise it is a waist in one field, or the mouth of an alcove.

**What was wrong.** Pass 4 trimmed every gap between two obstacles to exactly the 10-cell
floor, so the floor became the commonest passage width. And obstruction came as 15–25 separate
walls, one per cut, so the gaps between them were many. Measured on 16 default 1v1 seeds
before the change: 8.3 chokes per map under 16 cells (1.7 under 10), and 75% of walkable
ground in a 25-cell field. A third of the narrow chokes were obstacle-to-edge, a third
obstacle-to-obstacle; chokes beside footprints were left out, by the rule above.

**The rule now: a gap is closed or open.** Two obstacles either merge into one mass or keep
`open_gap_cells` (20) apart. The narrow passages left are the deliberate ones — carves and
ramps, 10–20 cells. Holding the share with fewer, wider gaps means fewer, larger masses:
regions reach further (8–22 cells), regrow, and retry shorter rather than give up (§A region is
an aggregation of cuts). Consolidating masses made the obstruction split lumpier, which is why
balancing grew a second phase (§Obstruction is a cost balanced per alliance).

**The play edge follows the same rule** (Alex, 2026-10-02). A mass within `open_gap_cells` of
the edge is closed onto it: the ground between, walked straight out along the play area's own
axis, becomes part of it, with any pocket that encloses. A band of open ground round the whole
perimeter tells a player the edge is always a way through, and that should not always hold. A
mass whose fill would take a reserved cell (a footprint, a start's buffer, a carve) or strand a
feature is trimmed back from the edge instead. A mass touches the edge when no walkable cell is
left between them (`MapTopology.EDGE_TOUCH_GAP`): a cell out of play is reserved, so a barrier
can stand no nearer than the second row, and its steep border covers the first.

**No mass is too large to walk round** (Alex, 2026-10-02). A mass's bounding box, in the play
area's own axes — the diagonals of the engine's grid — may span at most
`max_obstacle_span_fraction` (30%) of either side. After every growth, a larger mass is broken
by one of two moves:

- **delete one of its cuts** — "of two mountains and a lake, delete a mountain". That cut's
  graph edge is marked carved, so nothing grows it again and pass 6 treats it as open;
- **cut a passage** `open_gap_cells` wide across its longer side, through the median of its
  cells, so it splits in two of about equal size. The passage is carved ground; across a lake,
  the lake shelf rule gives it shallow margins.

**The cheaper move wins**: of those that bring every piece under the cap, the one losing fewest
cells; failing that, the one leaving the largest piece smallest. Deletion first, as built at
first, threw away whole mountains — a third of a small map's obstruction on the last round,
with nothing left to grow it back (two of 16 seeds at 100–120 came out at 88% traversable).

Measured on the same 16 seeds after both rounds: 0.4 chokes per map under 16 cells (against
8.3 before any of it), 92% of walkable ground in a 25-cell field (75%), traversable 83–87%, the
widest mass at most 30% of a side, and 3–9 masses per map on the edge. 15 of 16 seeds generate,
as before; the failure is pass 4's routes.

At the 100–120 play size (2026-10-02), the same 16 seeds: 15 generate (the failure is pass 6's
routes), traversable 83–87% around a mean of 85%, 0.2 chokes per map under 16 cells, 90% of
walkable ground in a 25-cell field, 10–11 masses per map with 3–7 on the edge.

TODO: openness is reported, not enforced (`GeneratedMapWriter.report` lists every choke's
width) — whether a map with too many narrow chokes is rejected, and at what width and count, is
open; see [tasks](../../tasks.md) T-055. What remains narrow is mostly the bay inside one
bent mass (§4, the TODO under the choke rule).

TODO: the thresholds — the open gap, the open-area clearance, the 0.7 ratio — are first
guesses, not tuned against play.

Elsewhere, regions need:
- the minimap to draw impassable terrain ([ui/hud-layout](../ux/ui/hud-layout.md) §The minimap);
- an answer to whether terrain blocks shots or sight; it is open, and today it blocks neither
  ([combat/target-acquisition](../combat/target-acquisition.md) §Line of fire);
- a decoration slot kind per obstacle kind ([ux](../ux/README.md) §World).

---

### 7. Visual facets

Cosmetic only, and derived: the same planner runs here and at every map load, so nothing it makes
is written into the map scene. Ground paint, trails between settlements, doodads, and the sites
of later dressing (cliff faces, ramps, mountains, shores, waterfalls) →
[visual-facets.md](visual-facets.md), which also holds the shortlist of what is worth building.

*Invariant:* none on the map — it cannot fail a generation.

## Symmetric maps — a training control

The generator's `symmetric` parameter, off by default, makes the finished map point-symmetric
about its centre: every corner height, tile, void cell, feature, water body and start point has
an exact image under `(x, z) -> (-x, -z)` (Alex, 2026-10-09).

### Why it exists, and why it is not a map rule

The game is not meant to be played on symmetric maps, and §Precedent stands: fairness comes
from placement, not geometry. The mode is for the self-play harness. A bot parameter search
scores vectors by mirror matches, and on an authored map the side a vector draws can decide
the match outright — on `skirmish.tscn` with the personality jitter pinned, the second start
point won 12 of 12 ([world-model/lattice-and-topology](../ai/world-model/lattice-and-topology.md)
§Measured). Swapping start points cancels that in expectation but not in variance: a close
pairing reads one to one whatever the vectors are. A symmetric map makes every match carry
vector signal, and it is the only ground on which a residual side effect is a BOT bug — which is
how the September control copy exposed the grid-anchoring bias
([ai/selfplay-results-2026-09-06](../ai/selfplay-results-2026-09-06.md) §The symmetric copy).
That copy was made by rewriting a scene by hand and is no longer in the tree; this mode replaces
it with something any seed can produce.

Training should still mix symmetric and authored maps — a roster scored only on symmetric ground
has never been scored on the situation a human puts it in. That is the trainer's business
([ai/selfplay-harness](../ai/selfplay-harness.md)), not the generator's.

### The operation

Generate freely, then overwrite one half with the image of the other — Alex's framing. One
step, `MapSymmetry.apply` on the `GeneratedMap`, with no randomness: a symmetric map is a
deterministic function of the free one.

**Point reflection, not a line.** The play area is a rectangle in diamond coordinates
`s = x + z`, `t = x - z`; a reflection in x alone swaps `s` and `t`, so it maps the rectangle onto
itself only when it is square. A 180° rotation maps it onto itself at any size, is exact on the
corner grid (`(i, j) <-> (W-1-i, W-1-j)`) and on the cell grid, and is what `Map.mirror_map`'s
secondary-axis setting and the September copy both declare. The dividing line is `s = 0`, and
**the reference half is whichever side of it holds the first start** — a fixed half would sit the
first start on overwritten ground half the time.

**Two starts, one per alliance.** A point reflection pairs exactly two starts. The mode refuses
(a generation error before any pass, so `is_valid()` is false) unless there are two alliances of
one start each — two starts of ONE alliance would pair nothing. The first start is kept and the
second becomes its image; it lies on the same ring at the opposite bearing, so §2's separation
and edge rules hold by construction. **A first start whose clear box, with the ring pass 6 keeps
on its level, reaches the axis is refused**: the mirror would rewrite part of its ground.

**Where in the pipeline.** After pass 6 has shaped the heights and before the end-of-generation
validation, so the route, pond, obstruction and balance checks run on the mirrored map rather
than the free one — reflecting the terrain changes the routes between the starts, which §6
already rejects about one seed in five, and a seed the mirrored map fails is retried like any
other. Pass 7 derives decoration afterwards and needs no change. Not a numbered pass: a flag-gated
step in `MapGenerator._run`, so the dock's pass list and `last_pass` are untouched, and a map
inspected at `last_pass = 6` with the flag on is already mirrored.

**The rules on the axis**, which is where a naive copy produces overlaps:

| what | rule |
|---|---|
| corner heights, void cells, tile types | copy the reference half onto the other; the centre corner (odd grids) is its own image |
| a feature entirely in the reference half | kept, and its image added — every placement's origin reflected (`origin' = grid - origin - dims`), the plan shared |
| a feature with any footprint cell whose CORNER lies on or past the line | **dropped** before reflection (so is a pond whose cells or rim do: the rim's heights hold its water). A kept footprint's ground is then never rewritten, and no kept feature can overlap an image |
| a feature entirely in the other half | dropped |
| a flooded chasm (`chasm_waters`, a seed cell and a level) | the reference half's seeds are kept and reflected at the same level; a reflected seed whose basin, refilled on the mirrored heights, already contains a kept seed's cell is dropped — one stretch of water, one body |
| the balance and obstruction reports | re-measured by the existing validation (`accessible_value`, `obstructed`, traversable and buildable fractions, openness). A kept feature's share is re-measured by walking distance over the mirrored ground; its image takes that share with the alliances swapped, so balance passes by construction. The swap is deliberate: a start stands on a grid corner, and seeding a distance field at the cell below it is a one-cell bias the image would not share |
| `topology` and `elevation` | left as the free map's records — they describe how the reference half was made, and nothing downstream reads them for play |

**Determinism.** No draw: the same free map always mirrors to the same symmetric map, so a seed
still names one map and a replay re-derives it.

### Interface

- `MapGenerationParams.symmetric: bool = false`, in the "Passes" group with a `DESCRIPTIONS`
  entry (`test_MapGeneratorDock` requires both).
- The self-play harness: `map_symmetric: true` beside `map_seed` in a match config, read in
  `run_match.gd._apply_generated_map` and recorded in the result beside `map_seed`.
- The dock exposes it like any other parameter; nothing else in the editor changes.

### Measured, 2026-10-09

- **A seed is rejected more often.** With the default 1v1 parameters, 8 of seeds 1–24 make a
  valid symmetric map against 20 free: mirroring moves the traversable share off its ±2% target,
  and a first start near the axis is refused. The harness's 20 seeds still find one all but
  always (0.67^20 ≈ 0.03% miss), at about 5 s per rejected seed.
- **The written map is exact.** `verify_symmetry.py` on a symmetric map scene: residual 0.000
  under the point reflection for heights, start points and all 50 placed entities.
- **The start point still decides.** A 12-match MEDIUM Colonial mirror on one symmetric map
  (`map_seed: 1`, played at seed 3), `personality_spread` and `decision_temperature` pinned to
  0, one match seed each, start points swapped on half: **the FIRST start point won 11 of 12**,
  from either slot. On authored `skirmish.tscn` the second point won 12 of 12. The ground is
  identical for both sides, so the edge was the bot's — three world-anchored reads in its
  opening, found with this mode and fixed the same day
  ([bot-architecture](../ai/bot-architecture.md) §The start-position bias: found).

---

---

## Interface

### What a map IS

**A map is a `Map` node and everything under it** — terrain, resources, water and start points
— and it saves as a scene of its own, rooted at that node (Alex, 2026-09-20). A scenario plays
one by holding it as its `Map` child, which is how every scenario has always read its map
(`Scenario.map` is `$Map`), so a generated map scene instances straight in.

What a map does NOT carry is everything the SCENARIO decides: **player slots**, lighting,
triggers, objectives. One map serves a two-player skirmish and a four-player one.

- **Start points live in the map**, because where a match can start is a fact about the ground.
- **A scenario may have no more slots than its map has start points.** Fewer is the normal case:
  slots take the first N points by sorted name, and the map's remaining starts go unplayed.

### The dock

**The Map Generator dock** (`addons/map_generator`, in the editor's right dock): an alliance
count, a seed, and a form of every generation parameter, grouped.

- **Generate builds into the Scenario you have open** — the new map becomes its `Map` child,
  selected, with the scene left unsaved for you to keep or discard. With no Scenario open it
  does nothing and says so: a map only means something inside one.
- **A Scenario that already has a map is warned first.** Generating replaces that map, and an
  unsaved one is gone — save it as a map scene if it is worth keeping.
- **Re-roll** draws a new seed and generates again, the same way.
- **Save map as scene…** packs the open scenario's map — hand edits included — as a `.tscn`
  with its terrain resource beside it, defaulting to `scenes/map/`. That file is the reusable
  asset; instance it under any scenario.
- **The form is built from `MapGenerationParams`' own properties**, sectioned by its
  `PROPERTY_GROUPS`, so a new knob appears in the dock with no edit to the dock. A knob nobody
  filed lands under "Other" rather than vanishing. Piece facts — footprints, the extractor's
  income, the building pool — are not offered at all: `GeneratedMapWriter.apply_piece_facts`
  reads them from the piece scenes, so there is one source for each.
- **Changing the alliance count resets the form** to that count's defaults, because some
  defaults (the play-size range) depend on it.
- **A failed generation changes nothing**: the report lists the broken invariants, the open
  scenario keeps the map it had, and Save stays disabled.
- **Known-bad values are warned about as they are typed**: `MapGenerationParams.warnings()`
  names each one, and the dock shows them under its buttons — a building capacity at or above
  `BUILDING_CAPACITY_FAILURE` (250 per player), a terrace step steeper than `MAX_SLOPE_DIFF`, an energy
  budget of zero (refused by pass 3: a map with no ponds or sites is not a map), and a
  `last_pass` short of the last pass, which the warning names.
- **The form resets when `MapGenerationParams` changes on disk.** The editor hot-reloads the
  script into the dock's live instance, and a knob the new script added or renamed reads as
  null there rather than as its default — which once generated maps with no resources at all,
  after the energy budget was renamed. Generate rebuilds the form from the new defaults first,
  and the report says so.

`tools/map_generation/generate_maps.tscn` is the batch form of the same pipeline: five
two-player MAP scenes from fixed seeds, plus `report.md`, for reviewing the defaults. They land
in the gitignored `scenes/scenarios/generated/`; a map you save from the dock is ordinary
tracked content.

---

## Parameters and reasonable bounds

TODO: **none of these are tuned.** They are starting brackets with a stated reason, to be moved once
maps are generated and played. The point of writing them down is that a generator refusing to
produce a map outside them is a better failure than one that produces a bad map silently.

**The walkable slope limit comes from the camera; the heights are authored** (Alex, 2026-10-02).
`TerrainGrid.MAX_SLOPE_DIFF` is the tangent of the lowest pitch the camera may take
(`MIN_VIEW_PITCH_DEGREES`, 30°), rounded down to a value float32 holds exactly, so that no
walkable slope can face away from the camera and hide (§6, Seeing the ground). What derives from
the limit follows it — a pond's sink, a crest's roughness, the grade per cell, a ramp's run.
What is authored does not: relief was doubled earlier that day because a 0.4 terrace read as flat
under the camera, and it kept that height when the limit fell from 1.0, taking more and gentler
steps instead (six terraces of 0.5, where five of 0.8 had been). So a terrace or a graded slope
covers more cells than it did, and a seed's layout changed with the limit. Ridges and mountains
(`ridge_height`, `mountain_rise_*`) are impassable whatever their height and keep their old
values: doubled, they towered over the play.

The limit is exact in float32 because a pond's rim is sunk by exactly the limit to be walkable
but unbuildable; at tan 30° unrounded, the stored heights rounded a hair past it, and every
pond and lake shelf rim silently turned impassable (about two points of traversable ground).

TODO: hand-authored and saved terrains (`s1`, `blue_hole`, `skirmish_map`, `generated_639364842`,
the `mesh_*` test terrains) are not regenerated. When the limit doubled (1.0), some of their
cliffs became walkable — Alex accepted losing them; when it fell to tan 30°, 1.4–2.8% of their
walkable cells (none on the flat, disc and plateau meshes) turned steep. **Every pond on a map
generated before the fall is sealed** — its rim was sunk 1.0, now past the limit — so units
cannot enter it; `skirmish.tscn` as saved on 2026-10-02 had all eleven sealed. A narrow ramp may
no longer join its levels either. Regenerate or rescale before reuse. Also undecided:
`chasm_depth` is still 4; halving it needs `WADE_DEPTH` moved too.

| Parameter | Bracket | Why the bracket |
|---|---|---|
| `play_size_min` / `_max` | `Vector2i` (s, t) bounds, each axis drawn in its own range, by start count; 100 … 120 diamonds at 2 starts (Alex, 2026-10-02; it was 120 … 150, widened 2026-10-01 to hold the per-player economy, and 75 … 120 before that) | the corner grid is square with side `s + t`, so 120 + 120 is a 241² grid; unequal axes give a long map. TODO: only the 2-start range exists, and the per-player budgets were not shrunk with it |
| `start_count` | 2 … 8 | |
| `start_min_center` | ≥ 0.25 × the side length | a start near the middle has no rear and meets the enemy too early |
| `start_angle_jitter` | 0 … 0.5 × the equal-spacing angle | wide on purpose; `start_separation` is what stops two starts crowding |
| `start_clear_radius_cells` | 6 (L∞; a 12×12 box) | holds the largest starting structure (8×8) while it still spawns on the start; the starting-site row it once also held is gone |
| `start_edge_margin` | ≥ 10 cells | a base backed onto the void has no rear |
| `start_separation` | ≥ 0.25 × play diagonal at 2 starts, scaled by `√(2/start_count)` | keeps early aggression a decision rather than a default. 0.35 was unsatisfiable: a ring inside the margin cannot put two starts that far apart |
| `value_horizon_seconds` | 480 | the window over which a pond is priced against a site; the largest pond's drain time, so every pond is valued at its charge |
| `energy_value_per_player` | 37000 | how much energy every player can reach: about 25000 in 5–6 ponds and about five generated sites (2400 each), beside the two home sites |
| `shelters_base` / `shelters_per_player_min` / `_extra` | 1 / 1 / 1: `round(1 + n × (1 + randf()))`, at least one per start | 3 … 5 on a 1v1 map: one per start plus at least one to rebalance with (§Shelters) |
| `shelter_start_band_min_cells` / `_max_cells` | 25 / 35, centre to centre (was 15 / 35); TODO untuned | the band every start's own shelter lies in (§Shelters) |
| `pond_value_fraction` | 0.676 | ponds are finite, so they are the prize; they are also the early engine, because a site pays little on purpose ([pacing/resource-allotment](../macroeconomics/pacing/resource-allotment.md) §Second pass, 2026-10-01) |
| `pond_charge_min` / `pond_charge_max` | 2700 / 7200 | 3 to 8 minutes for one extractor at 15/s |
| pond charge location, scale, skew | 3500, 2000, 4 | right-skewed: small ponds common, large ones rare |
| `pond_cells_min` / `pond_cells_max` | 30 / 80 | the union of the category bounds; below ~30 a basin has little floor left once the rim is taken |
| `pond_richness_factors` | `[60, 90, 120]` | poor, standard, rich: charge per cell |
| `pond_richness_cells_min` / `_max` | `[45, 30, 30]` / `[80, 70, 60]` | each category's size bounds; they cap a rich pond's size |
| `pond_richness_weights` | `[0.35, 0.45, 0.2]` | drawn among the categories that can hold the charge; rich is rarest |
| `placement_candidates` | 16 … 64 per feature | the best-candidate budget; bounds the pass's work |
| `feature_spacing` | ≥ 6 cells | two features closer than this read as one |
| `favor_tolerance` | | how far an alliance's accessible value may sit from its target |
| `correction_radius` | | how far pass 4 may move a feature to restore its favor |
| `building_pool` | neutral pieces + weights | footprints vary; see §Buildings |
| `building_capacity_per_player` | 75; warned at 250, fails from ~225–300 | about 7.5 clusters and 16 buildings per player on a 1v1 map, which is what the capacity bands' stated frequencies assume; see §3 for the ceiling |
| `building_cluster_separation_cells` | 20 (was 10; Alex, 2026-10-01) | L1 between the nearest buildings of two clusters; below this they read as one |
| `site_triple_fraction` / `site_pair_fraction` | 0.2 … 0.4 each, drawn per map | share of sites in threes and in twos; the rest stand alone |
| `site_cluster_separation_cells` | 50 | L1 between the nearest sites of two site clusters |
| `shelter_cluster_clearance_cells` | 10; TODO untuned | the gap a shelter no cluster is built around keeps from every cluster (§Shelters and clusters) |
| `collocation_affinity` | per ordered kind pair: `[−1, 1]` + radius | only kinds placed earlier can be named |
| `collocation_weight` | | how much affinity may cost in favor error |
| `cluster_capacity_band_edges` / `_weights` | 3–10–15–20–25 / 0.55, 0.36, 0.07, 0.02 | garrison capacity per cluster; small clusters common, a large one a rarity rather than a fixture |
| `cluster_capacity_overshoot` | 2 | how far a cluster's last building may carry it past its drawn capacity |
| `cluster_large_building_bias` | 0.5 | at the top band a 10-capacity building is drawn about 1.8× as often, relative to a 3, as the pool weights it |
| `grouping_size_weights` | 0.3, 0.4, 0.3 | groupings of one, two, three buildings; the length is the cap (Alex: three). TODO: the weights are not tuned |
| `grouping_gap_cells_min` / `_max` | 1 / 1 | the tight gap inside a grouping (Alex, 2026-10-09; briefly 1–2) |
| `cluster_open_gap_cells_min` / `_max` | 3 / 5 | the open gap between groupings (Alex, 2026-10-09; briefly 5–8) |
| `cluster_span_slack_cells` | 2 | how far a grouping may stretch a cluster's longer axis. TODO: not tuned |
| `last_pass` | a named pass: extent, starts, resources, topology, terrain, elevation, visuals | stop after that pass to inspect it. A `Pass` enum, numbered as this doc numbers them, so the dock offers the names and a report reads the same as §The pipeline |
| `ground_height` | 8.0 | high enough that a chasm sunk `chasm_depth` stays above 0 |
| `cut_fraction` | 0.15 … 0.45 of graph edges; 0.45 | 0 is a featureless field; above ~0.5 the map is an SC2 partition, which this game explicitly is not. At the top because only uncarved cuts grow into regions (§Obstacle regions) |
| `target_traversable_fraction` / `traversable_tolerance` | 0.85 / 0.025 | Alex, 2026-10-02 (was 0.8 / 0.05: masses large enough to favour air); a finished map outside the band is rejected |
| `open_gap_cells` | 20 | the least gap pass 4 leaves between two obstacles, or an obstacle and the edge it does not touch; at 10 the floor was the commonest passage width (§Openness) |
| `max_obstacle_span_fraction` | 0.3 | Alex, 2026-10-02: the widest a mass's bounding box may run along either play-area axis, as a share of that side |
| `region_width_min_cells` / `_max_cells` | 8 / 22 (was 5 / 14) | a grown cut's reach from equidistant; widened with the open gap, which trims more away, so fewer, larger masses make up the share |
| `region_edge_noise` / `region_noise_scale_cells` | 0.35 / 12 | ragged edges rather than the straight Voronoi boundary |
| `region_lake_fraction` | 0.5 | share of grown cells that are lakes |
| `lake_shelf_cells` | 2 | the wadeable shelf around a lake's core |
| `mountain_rise_per_cell` / `mountain_rise_max` | 0.5 / 2.0 | a mountain is taller toward its core |
| `obstruction_tolerance` | 0.15 | "somewhat fairly" (Alex); measured 6–8% |
| `flooded_cut_fraction` | 0 … 1; 0.5 | share of cuts that are chasms rather than ridges |
| `barrier_width_cells` | 2 … 5; 3 | roughly a barrier's thickness |
| `MIN_CHOKE_WIDTH` (const) | 10 | no passage is narrower; carves and ramps are 10–20, and a barrier keeps this from a cliff |
| `min_routes` | ≥ 2 | one route between two starts is a funnel |
| `correction_radius_cells` | 12 | how far pass 4 may move a feature to restore its favor |
| `ridge_height` / `chasm_depth` | 3.0 / 4.0 | anything above `MAX_SLOPE_DIFF` blocks; these read as terrain |
| `flat_fraction` | ≥ 0.55 of in-play walkable cells | structures need flat ground and slopes cost it |
| `elevation_levels` | 1 … 6; 6 | terrace levels, the map's whole relief; 1 leaves the ground level. Seven or more failed the one-terrace rule on a quarter of seeds while tiers stood (2026-10-02); not re-measured since |
| `elevation_step` | ≤ `MAX_SLOPE_DIFF`; 0.5 | a terrace step is walked over. Above the limit every boundary cliffs, and elevation starts dividing ground pass 4 left open — the dock warns |
| `cliff_cut_fraction` | 0 … 1; 0.5 | share of candidate cuts drawn as cliffs (§Cliffs) |
| `cliff_drop_terraces_min` / `_max` | 2 / 4 | a cliff's drop: at least two or it is walked over; at most what the apron hides from the lowest camera — the dock warns past either |
| `occlusion_allowance` | 0.5 | the part of a unit at an obstacle's foot the obstacle may hide (§Seeing the ground) |
| `elevation_scale_cells` | 40 … 90; 60 | the noise's feature size; smaller breaks the map into more plateaus and needs more ramps |
| `start_level_fraction_min` / `_max` | 0.5 / 0.75 | starts on high ground, not always the highest (Alex) |

---

## What this retires

| Today | Fate |
|---|---|
| `BlockMaskGenerator` | superseded — passability is depth and steepness now, not a painted mask. Its connectivity guard is the wrong half to keep; carving replaces rejecting |
| `HeightmapGeneratorTool` | repointed at `TerrainData` output instead of writing a `HeightMapShape3D` |
| `GraphPlateauHeightmapGenerator` | retuned for large, infrequent features or retired outright — its dense plateau-and-ramp partition is the topology this design rejects |
| `HeightmapGenerator` subclasses | survive as the *height pass* inside the larger generator |
| the impassable tile types (`Water`, `Forest`, `Cliff`, `NoGo`) | deleted — superseded by depth and steepness. `TileType` loses `passable` / `buildable` / `renders_surface` and the catalog becomes ground materials; impassability is always sculpted, never painted |
| the heightmap workbench / gallery tools (`tools/terrain/`) | repointed, or replaced by a generation workbench that renders the full pipeline |
