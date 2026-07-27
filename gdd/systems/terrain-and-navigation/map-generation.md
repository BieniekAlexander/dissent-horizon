---
title: Map generation
type: system-note
---

# Map generation

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**Passes 1–6 are built**: the pure core is `scripts/maps/generation/` (`MapGenerator`);
`GeneratedMapWriter` (`tools/map_generation/`) turns a result into a skirmish scene; and maps are
generated from the editor's Map Generator dock (§Interface). **TODO: pass 7**, visual facets.
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
   starts, not from geometry.
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
`k × value_per_alliance`, `k` the alliance count:

- **energy** — `value_per_alliance` is a parameter. Ponds are drawn until they reach
  `pond_value_fraction` of it, and the rest is extraction sites, grouped into site clusters
  (§Extraction sites).
- **shelters** — the count is drawn directly: `round(k × (1 + 1.5 × randf()))`, i.e. 1 … 2.5 per
  alliance. See §Shelters for the ones tied to starts.
- **buildings** — the budget is an **occupancy**: `building_occupancy`, the fraction of the play
  area's cells covered by building footprints (3% by default), shared evenly between alliances.
  Clusters are drawn until it is spent, the last one cut short at the budget. It is set by map
  area, not player count — it replaced a per-player calibration — and an occupancy rather than a
  count because it stays meaningful as the pool gains footprints of other sizes.

  **High occupancies fail loudly; they do not crash or hang.** Measured on default 2-player maps
  with today's pieces: 5% and 10% generate; from about 12% up, a building cluster finds no valid
  position and the generation fails with `no valid position for BUILDING_CLUSTER i of n`. The
  ceiling is room, not time — about 90–140 4×4 buildings fit on a 75–120 map once sites, ponds,
  shelters, start squares and cluster separation have taken theirs, whatever the budget asks.
  Every run finished in under a second.

**Pond sizing and charge.** A pond's size and charge are drawn before it is placed, because the
charge is its value:

- **size** — a cell count from a right-skewed normal, clamped to `[pond_cells_min, pond_cells_max]`;
- **richness** — one of `pond_richness_factors` (`[50, 75, 90, 100]`). Richer categories are rarer,
  and they grow rarer still as the pond gets bigger;
- **charge** — `cell_count × richness_factor`.

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

**Buildings go down as clusters** — a cluster centre plus a scatter — never as an even spread; a
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

PLANNED, decided 2026-09-28. **Every start is guaranteed a shelter inside a distance band** —
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

TODO: the count can fall short of the guarantee. It is drawn per alliance, so a 1v1 map has two
shelters about one time in six — each then assigned, leaving none to rebalance and making the
opponent's band certain — and a team map can hold fewer shelters than starts. Whether the count
should be floored at the start count (or that plus one) is open.

TODO: the band's bounds are not tuned.

#### Buildings

`nt_building` is one piece today; generation must not assume that. Buildings will be drawn from a
**pool of neutral pieces with differing footprints**, so a cluster is packed from footprints, not
from a count, and the pool is a generation parameter.

**Cluster size is heavy-tailed**: `1 + NegativeBinomial(cluster_size_successes,
cluster_size_success_chance)`, capped at `cluster_size_max`. At 2 and 0.4 (mean 4), clusters of
1–3 are about half of all clusters, 4–7 about a third, 8–10 about one per two players, and 11–16
about one per three matches. Uniform sizes in a narrow band — what this superseded — made every
cluster the same landmark, and a map had only one or two of them.

TODO: balancing constraints on buildings are not designed — guaranteeing some number of clusters
of given sizes, and positioning clusters relative to the starts (ideally as the same kind of
fairness constraint the other currencies use). Today a cluster is aimed at a favor target like any
feature, and nothing constrains which sizes a map gets.

**Clusters keep apart.** No building of one cluster may be within `building_cluster_separation_cells`
(L1, between their nearest cells) of a building of another, so two clusters never read as one.
Centre spacing alone could not promise that: two large clusters whose centres are far apart can
still sprawl into each other.

A cluster's scatter radius is derived
from its members' footprints (gap included) at `cluster_packing_density`, so a cluster of eight
spreads wider than a cluster of three. A building's value is its footprint cell
count — an approximation, and the reason a 3×3 is worth more than a 2×2 without anyone pricing
garrison slots.

#### Collocation

**Pairwise affinity.** Each ordered pair (kind being placed, kind already placed) carries an
`affinity` in `[−1, 1]` and a `radius`. A candidate's score is its favor error minus
`collocation_weight × Σ affinity` over already-placed features within that pair's radius — so a
positive affinity pulls a candidate toward those features and a negative one pushes it away. A
shelter beside a building cluster and a shelter alone are then one table entry apart.

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

**No choke is narrower than `MIN_CHOKE_WIDTH` (10 cells).** A choke is the walkable gap between
two separate obstacles — barriers, each with its steep border, and the edge of the play area.
After carving, any barrier that leaves a narrower gap is trimmed back (the smaller of two
barriers gives way; a barrier gives way to the edge), and fragments under four cells are
dropped. Trimming only removes barrier, so connectivity and routes survive it. Chokes made by
resource footprints — buildings, shelters, sites — are not held to the rule, and ponds are
walkable.

It is a constant, not a knob: the floor keeps a unit column moving through every choke on every
map, and carve widths are sampled from it. Width above the floor is still the strongest balance
lever on the map — narrow is the StarCraft ramp that makes melee viable, wide is the open field
that makes it worthless.

TODO: a narrow bay inside ONE bent barrier is not measured, only gaps between separate
obstacles. Barriers are near-straight today, so none has been seen.

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

- **Ponds** are sunk as flat pans one 0.5 step below the ground, water just above the floor, so
  their cells are shallow and the rim is passable-but-unbuildable
  (see [map-composition.md](map-composition.md) §The basin).
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
    - **A body that will not stay in its chasm is not placed, and that chasm is left dry.** A
      chasm beside a cliff stands above the ground below it, and a cliff cell is steep but not
      TALL: its middle can sit under the water, so the fill walks over it. Predicting that from
      rim heights means re-deriving the fill, so the fill itself is the test. A dry chasm is a
      barrier like any other — see §Water as a feature kind, where dry and wet are one thing.
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

### 6. Elevation — tiers, terraces and cliffs

The ground is lifted off the flat. **Levels come from the feature graph**, not from a free
heightmap (Alex, 2026-09-19): every start and feature is a node, and each node gets a height.

A height is two ladders, because a step means two different things:

| | step | what it is |
|---|---|---|
| **terrace** | `elevation_step`, at or under `MAX_SLOPE_DIFF` | walked over. The map's relief; only the cells on the step lose their buildability |
| **tier** | `cliff_step`, well above it | a cliff |

**A cliff may stand only where a barrier does** (Alex, 2026-09-19). Elevation marks divisions the
topology already decided; it adds none of its own. Pass 6 used to draw a full step at every
boundary between differing regions, which cliffed about three-quarters of them on nothing, and
halved the map's widest corridor — gen_02 went from 17 cells to 9, below `MIN_CHOKE_WIDTH`.

- **Where levels come from.** Coherent noise sampled at each node, `elevation_scale_cells`
  across, stretched so the whole ladder gets used — raw noise bunches near its middle. TIERS are
  then smoothed: a group matching none of its neighbours takes their commonest tier, so tiers
  form broad plateaus rather than one-group islands. **Terraces are not smoothed** — the
  one-step limit below already holds them together, and smoothing on top of it dragged whole
  maps onto the starts' terrace, leaving three of six seeds with no relief at all.
  > **REJECTED — ranking the noise** instead of stretching it. Ranking spreads the groups evenly
  > over the ladder, which puts neighbouring regions at opposite ends; the one-step limit below
  > then squashes them back together and whole maps came out at a single height.
- **Neighbouring regions differ by at most one terrace**, since a terrace is meant to be walked
  over. A relaxation pulls violators together, holding the starts.
- **What must share a height.** Reserved zones within a couple of cells of each other are one
  group, and so are the two sides of a carved cut. A closer pair on different heights would
  leave a sliver of ground walled in, and a carve is an opening a cliff would close again.
- **Starts all share one height**: the middle tier, and a terrace from
  `start_level_fraction_min … _max` — high ground, but not always the top (Alex). Height has no
  gameplay effect yet, and when it has, no start should begin below another.
- **Each cell takes its region's height**: reserved ground (footprints, pond rims, start boxes)
  outranks barrier cells, which outrank free ground. A corner shared by cells of different
  heights takes the highest-ranked cell's. **So a step never falls inside a footprint.**

**Grading is what keeps a height change from becoming a wall.** The free ground between two
regions of different height is pulled to within `_GRADE_PER_CELL` of its neighbours, sweep by
sweep like a distance transform, until the drop is spread over a band a walker climbs. Two
things are held out of it:

- **A barrier is where a drop may land whole.** Its cells are excluded, so they neither grade nor
  drag the ground either side toward them — the tier step lands across the barrier, and that is
  the cliff. Ground out of play is held out for the same reason.
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
3. **The choke floor holds**, with cliffs as fixed obstacles: a barrier too near a cliff is
   trimmed. Trimming frees cells and a new ramp adds walls, so the floor and test 2 alternate
   for a few rounds until neither changes anything. Test 1 is judged last, on the settled map.

A feature that ends on a cliff or a ramp, or too near another feature, is **moved and rebalanced
per currency** exactly as in pass 4, against walking distance on the levelled ground. Pass 5's
shaping is then re-run on top of the offsets: a pond or a chasm floods at its own level, and the
`flat_fraction` invariant is checked again.

A generation costs **6–18 seconds** at the defaults, most of it grading; it was 40 before the
grading sweeps were restricted to the cells near a height change.

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

---

## Water as a feature kind — PLANNED

Decided 2026-09-19 (Alex), not built. Today water arrives only as a flooded pass-4 cut, plus
the lithium ponds of pass 3.

**A chasm and a river are the same thing**: a cut shaped as a trench, which may or may not hold
water. The gameplay difference is thin — forded with dry land a crossing is buildable, forded
with shallow water it is not — and it does not earn a second mechanism. So pass 4 keeps deciding
where a cut goes, and hands its shape to the water system.

- **Water is its own feature kind**, placed like a resource, and **balanced as a COST**: each
  alliance should carry about the same water near it, because water is buildable ground taken
  away rather than a prize. Same favor machinery, read with the opposite sign.
- **Placement sits with the passes that shape navigation** — a lake changes walking distances
  the way a ridge does, while its balance effect is small.
- **Every body is a basin: a deep core with a shallow margin.** Size decides whether there is a
  deep core at all, so small bodies come out entirely shallow. Shallow is walkable and
  unbuildable, deep is neither (see [water-bodies.md](water-bodies.md)) — so shallow water is
  the cheap kind of cost and deep water is a barrier.
- **Shapes: lines, regions, and fords.** Lines are rivers and channels, regions are lakes and
  marshes, and a ford is a shallow crossing cut into a deep line, the way pass 4 carves a gap in
  a ridge.
- **The total is capped as a share of the play area** (`water_fraction`), shallow and deep
  together, checked like `flat_fraction`: most walkable ground must stay buildable.
- **A body never spans levels.** Where one would, it breaks into a body per level at its own
  height — the rule pass 5 already follows for chasms.
- **Waterfalls are deferred**: later, an upper line and a lower line are joined by decoration.
  Nothing about the water model waits on them.

---

### 7. Visual facets

TODO: not built, and out of scope for now (Alex, 2026-09-19) — doodads, ground materials, water
surface appearance, river flow, mountain models laid over impassable cells as decoration.

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
  names each one, and the dock shows them under its buttons — a building occupancy at or above
  `BUILDING_OCCUPANCY_FAILURE` (10%), a terrace step steeper than `MAX_SLOPE_DIFF`, and a
  `last_pass` short of the last pass, which the warning names.

`tools/map_generation/generate_maps.tscn` is the batch form of the same pipeline: five
two-player MAP scenes from fixed seeds, plus `report.md`, for reviewing the defaults. They land
in the gitignored `scenes/scenarios/generated/`; a map you save from the dock is ordinary
tracked content.

---

## Parameters and reasonable bounds

TODO: **none of these are tuned.** They are starting brackets with a stated reason, to be moved once
maps are generated and played. The point of writing them down is that a generator refusing to
produce a map outside them is a better failure than one that produces a bad map silently.

| Parameter | Bracket | Why the bracket |
|---|---|---|
| `play_size` per axis | drawn per map from a range by start count; 75 … 120 diamonds at 2 starts | the corner grid is square with side `s + t`, so 120 + 120 is a 241² grid. TODO: only the 2-start range exists, and it may be revisited |
| `start_count` | 2 … 8 | |
| `start_min_center` | ≥ 0.25 × the side length | a start near the middle has no rear and meets the enemy too early |
| `start_angle_jitter` | 0 … 0.5 × the equal-spacing angle | wide on purpose; `start_separation` is what stops two starts crowding |
| `start_clear_radius_cells` | 6 (L∞; a 12×12 box) | holds the largest starting structure (8×8) while it still spawns on the start; the starting-site row it once also held is gone |
| `start_edge_margin` | ≥ 10 cells | a base backed onto the void has no rear |
| `start_separation` | ≥ 0.25 × play diagonal at 2 starts, scaled by `√(2/start_count)` | keeps early aggression a decision rather than a default. 0.35 was unsatisfiable: a ring inside the margin cannot put two starts that far apart |
| `value_horizon_seconds` | | the window over which a pond is priced against a site |
| `value_per_alliance` (energy) | | how much energy every alliance can reach; shelters and buildings draw theirs (below) |
| shelter count | `round(k × (1 + 1.5 × randf()))` | 1 … 2.5 per alliance; not a parameter. TODO: may fall short of one per start (§Shelters) |
| `shelter_start_band_min_cells` / `_max_cells` | PLANNED; untuned | the band every start's own shelter lies in (§Shelters) |
| `pond_value_fraction` | 0 … 0.5 of energy value | ponds are finite, so they are the prize, not the baseline income |
| `pond_cells_min` / `pond_cells_max` | 30 / 75 | below ~30 a basin has little floor left once the rim is taken |
| pond size skew, location, scale | | right-skewed: small ponds common, large ones rare |
| `pond_richness_factors` | `[50, 75, 90, 100]` | charge = cells × factor; 1 500 … 7 500 across the bounds |
| richness category weights | | richer is rarer, and rarer still in larger ponds |
| `placement_candidates` | 16 … 64 per feature | the best-candidate budget; bounds the pass's work |
| `feature_spacing` | ≥ 6 cells | two features closer than this read as one |
| `favor_tolerance` | | how far an alliance's accessible value may sit from its target |
| `correction_radius` | | how far pass 4 may move a feature to restore its favor |
| `building_pool` | neutral pieces + weights | footprints vary; see §Buildings |
| `building_occupancy` | 0.03 of play-area cells; warned at 0.10, fails from ~0.10–0.12 | about 12–20 of today's 4×4 buildings per player on a 2-player map; see §3 for the ceiling |
| `building_cluster_separation_cells` | 10 | L1 between the nearest buildings of two clusters; below this they read as one |
| `site_triple_fraction` / `site_pair_fraction` | 0.2 … 0.4 each, drawn per map | share of sites in threes and in twos; the rest stand alone |
| `site_cluster_separation_cells` | 50 | L1 between the nearest sites of two site clusters |
| building-cells skew, location, scale | | |
| `collocation_affinity` | per ordered kind pair: `[−1, 1]` + radius | only kinds placed earlier can be named |
| `collocation_weight` | | how much affinity may cost in favor error |
| `cluster_size` | 1 + NegBin(2, 0.4), capped at 16 | small clusters common, a large one a rarity rather than a fixture |
| `cluster_packing_density` | 0.3 … 0.5 | denser packings fail to fit often enough to reject whole seeds |
| `last_pass` | a named pass: extent, starts, resources, topology, terrain, elevation | stop after that pass to inspect it. A `Pass` enum, numbered as this doc numbers them, so the dock offers the names and a report reads the same as §The pipeline |
| `ground_height` | 4.0 | high enough that a chasm sunk `chasm_depth` stays above 0 |
| `cut_fraction` | 0.15 … 0.45 of graph edges; 0.3 | 0 is a featureless field; above ~0.5 the map is an SC2 partition, which this game explicitly is not |
| `flooded_cut_fraction` | 0 … 1; 0.5 | share of cuts that are chasms rather than ridges |
| `barrier_width_cells` | 2 … 5; 3 | roughly a barrier's thickness |
| `MIN_CHOKE_WIDTH` (const) | 10 | no passage between barriers, or a barrier and the edge, is narrower; carves are 10–20 |
| `min_routes` | ≥ 2 | one route between two starts is a funnel |
| `correction_radius_cells` | 12 | how far pass 4 may move a feature to restore its favor |
| `ridge_height` / `chasm_depth` | 3.0 / 2.0 | anything above `MAX_SLOPE_DIFF` blocks; these read as terrain |
| `flat_fraction` | ≥ 0.55 of in-play walkable cells | structures need flat ground and slopes cost it |
| `elevation_levels` | 1 … 6; 5 | terrace levels; 1 leaves the ground level within a tier |
| `elevation_step` | ≤ `MAX_SLOPE_DIFF`; 0.4 | a terrace step is walked over. Above the limit every boundary cliffs, and elevation starts dividing ground pass 4 left open — the dock warns |
| `cliff_levels` | 1 … 4; 3 | tiers, each a cliff apart. A map whose cuts divide it into fewer regions simply uses fewer |
| `cliff_step` | 1.5 | three `MAX_SLOPE_DIFF`s: a tier step is a cliff and reads as one. Keep it above `chasm_depth / 2` |
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
