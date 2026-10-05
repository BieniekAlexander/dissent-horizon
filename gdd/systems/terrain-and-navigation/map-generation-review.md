---
title: Map generation — review, 2026-10-02
type: review
---

# Map generation review

*A review of [map-generation.md](map-generation.md)'s implementation — `scripts/maps/generation/`,
`tools/map_generation/` and `addons/map_generator/` — against three questions: speed, the design
of the passes, and how they are parameterised. Branch `refactor/map-generation`.*

**TODO: every proposal below is unapproved.** What was built is §1's "Done" list, all of it
local and output-preserving. Everything else changes a public shape, spans modules, or changes
what a seed generates, so it is a decision for Alex (`~/.claude/CLAUDE.md` §8, §9). This note is
a work list: delete each item when it is built or rejected, and the note when it is empty.

---

## 1. Performance

### Where the time went

Default 1v1 parameters, 100–120 play size, per-step timing averaged over seeds 2000–2002:

| step | seconds | |
|---|---|---|
| pass 6, first relabel | 11.5 | one call: grade, settle zones, grade again |
| pass 6, ramps for routes | 11.1 | each ramp built or plateau re-levelled relabels the whole map |
| pass 4, obstacle regions | 2.2 | two-thirds of it the open-gap trim |
| pass 7, decoration | 1.4 | |
| everything else | < 0.5 each | |

**Grading was nine-tenths of a generation.** `MapElevation._sweep_grade` walked every cell of
the grid on 24 sweeps (12 rounds, forward and back), skipping all but the few thousand near a
height change, and for each of those called `TerrainData.is_cell_in_play` — five calls deep, on
the staggered grid — for each of nine neighbours. Seed 2002 relabelled often enough to take 53 s.

### Done on this branch

Both changes keep every output identical: seeds 2000–2005 fingerprinted (hash of the corner
heights and of every feature's kind and centre) before and after, and all twelve hashes match.

1. **The grading sweep visits only the cells that can move**, as an index list in the order the
   grid walk visited them, and reads "fixed" and "ignored as a neighbour" from two masks built
   once per sweep from the topology's memoised in-play mask. The frontier scan compares each
   neighbouring pair once instead of twice. The relabel's cliff scan reads the same mask and
   computes a cell's corner spread inline. **159 s → 50 s for the six seeds.**
2. **The open-gap trim buckets cells by obstacle** (`MapTopology.too_narrow_cells`), so a cell
   skips its own obstacle's cells — most of any bucket — without visiting them, and stops at its
   first offending neighbour. **50 s → 38 s.**
3. **The end-of-generation checks run before pass 7**, so a rejected map is not decorated
   (`MapGenerator._run`). Saves pass 7's ~1.3 s on each rejection; changes nothing on a valid map.

**Result: 159 s → 38 s for seeds 2000–2005 (4.1×); 4.8–10.7 s per map over seeds 2000–2021,
7.1 s mean.** One of those 22 seeds is rejected (2016: pass 6 routes and terraces), so at the
defaults the retry cost is small.

Remaining split, per map: pass 6 about 2.7 s (relabel 0.9, ramps 1.0), pass 4 about 1.7 s
(regions 1.1, favor correction 0.4), pass 7 1.3 s, pass 3 0.3 s, validation 0.3 s.

### Further levers, not built

**PLANNED P1 — make a relabel incremental.** Approved 2026-10-02; cliffs, which rewrote how
pass 6 assigns heights, are built, so this is next ([map-generation](map-generation.md) §6). A ramp or a re-level changes heights in one
neighbourhood, but `_relabel` re-labels, re-grades and re-scans the whole grid, and
`_ramp_for_routes` calls it for every ramp it builds and every plateau it re-levels. Re-grading only the plateaus whose height changed
would take most of pass 6's remaining 2 s. **It changes what seeds generate**: the grade's
"squeezed" case averages two neighbours, so its result depends on visit order, and a regional
re-grade visits in a different order. Cost: every seed's map changes once; the A/B has to be
statistical (traversable share, chokes, rejection rate), not a hash.

**TODO P2 — one cell layer for barriers, not a Dictionary.** `MapTopology.barrier_of`
(`Vector2i` → cut) is the structure every pass-4 step reads, and the packed views of it are
rebuilt from scratch on demand: `passable_mask()` scans every barrier cell and its eight
neighbours, and `ObstacleRegions` asks for it three or four times per growth (`_grow_cut`,
`_enclosed_pockets`, `_blocked_cells`, `_retally`); `MapTopology.obstacles()` floods the
Dictionary with 25 lookups a cell, and runs once per trim round, per fragment drop, per edge
closure and per `masses()` call. A `PackedInt32Array` cut-per-cell (−1 for none), kept as the
source with the Dictionary dropped or derived, makes each of these a linear scan of packed
memory. Spans `MapTopology`, `ObstacleRegions`, `MapElevation` and `MapGenerator`: approval
needed. Output-preserving if iteration orders are kept, which the Dictionary's insertion order
makes fiddly — budget for a statistical A/B anyway.

**TODO P3 — profile pass 7 separately.** 1.3 s here, and [visual-facets.md](visual-facets.md)
runs the same planner at every map LOAD, so it is also load time. Its grid build calls
`is_cell_in_play` and `cell_height_spread` per cell, and it runs four full distance transforms.
Not reviewed in depth: out of the generator's scope.

**Not worth doing now:** a pond candidate grows by picking the least-scored frontier cell by
linear scan (`FeaturePlacer._nearest_frontier`), quadratic in pond size, but all of pass 3 is
0.3 s. `PlacementGrid.rect_cells(cell, Vector2i(2, 2))` allocates an array to name a cell's four
corners at eight call sites, some in per-cell loops — a corner-index helper on `TerrainData`
would read better and cost less, and goes naturally with P2.

---

## 2. The design of the process

**What holds up well.** A pure core that runs in a bare test. Invariants stated per pass, so a
failure names its cause. Best-candidate placement whose work is bounded. Carving rather than
rejecting. `last_pass` for inspecting one pass. Each rule written down with what it superseded.
The review below is about where the structure has drifted from that picture, not about the
picture.

**TODO D1 — `MapGenerator` is the orchestrator AND three passes' worth of work.** 1,240 lines:
pass 3's plan drawing, pass 4's favor correction, all of pass 5 (pond pans, ridges, mountain
rise, lake shelves, chasm flooding and its settle loop), pass 6's rebalance, and both
validations. Passes 4 and 6 have their own classes (`MapTopology`, `MapElevation`); 3 and 5 do
not, so the file reads as orchestration interleaved with terrain shaping. A split along the
doc's own lines:

- `FeaturePlanner` — `_pond_plans`, `_site_plans`, `_shelter_plans`, `_building_plans` and their
  statics (~240 lines);
- `TerrainShaper` — pass 5, `_shape_terrain` through `_chasm_stretch` (~330 lines), a pure
  function of (topology, offsets, features) → heights and waters, called by passes 5 and 6;
- `FavorCorrection` — `_correct_favor`, `_rebalance_currency`, `_replace_feature`,
  `_alliance_fields`, `_walking_share`, `_currency_deviation`, used by passes 4 and 6;

leaving `MapGenerator` at about 250 lines of sequencing and validation.

**TODO D2 — the passes are not sequential, and the doc says they are.** Pass 6 re-runs pass 5
on its offsets (fine, and documented), but it also **mutates pass 4's output**: it trims
`topology.barrier_of` against cliffs, narrows each cliff cut's band to its face, and moves
features the topology's graph was built from. Pass 5 turns a
chasm stretch that cannot hold water into a ridge, while `topology.flooded` still says chasm.
Three consequences:

1. After generation, `GeneratedMap.topology` is not the decision pass 4 made, nor quite a
   description of the finished map.
2. `last_pass = TERRAIN` shows ground that pass 6 will partly redo.
3. **Obstruction is steered on a proxy and judged on the real thing.** `ObstacleRegions` aims the
   traversable share and the per-alliance split using "barrier plus its one-cell ring"; pass 5
   adds lake shelves and raises dry chasms, pass 6 adds cliffs, and `_validate_obstruction`
   measures the finished terrain at the very end. A miss there is a rejection, never a
   correction.

Options: (a) document the real dataflow — which pass writes which structure — in
map-generation.md's pipeline section, and stop there; (b) make `TerrainShaper` (D1) the only
writer of heights, and have pass 6 return trims and moves for the generator to apply, so each
structure has one writer; (c) feed the shaped terrain's own blocked cells back into the
regions' tally. (a) is cheap; (b) is the refactor that makes (c) possible.

**TODO D3 — one random stream for every pass.** A single `RandomNumberGenerator` is threaded
through all seven passes, so anything that changes how many numbers an early pass draws moves
everything after it. Raise `building_capacity_per_player` and the mountains move; add one
`randf()` in a refactor and every seed's map changes. That makes tuning comparisons noisy (a
knob's effect is confounded with a reshuffle) and makes "output-preserving" refactors brittle.
Option: one stream per pass, seeded from (seed, pass) — and per currency in pass 3. Cost: every
seed's map changes once.

**TODO D4 — the topology's cut state is four parallel arrays edited from outside.** `cuts`,
`flooded`, `carved`, `grown` are kept in step by hand: `ObstacleRegions._recruit` appends to all
four and pops all four on failure, and `_try_balancing_move` snapshots seven fields of
`MapTopology` field by field to roll a move back. A field added to `MapTopology` is silently not
rolled back. Option: a `Cut` record (edge, flooded, carved, grown) in one array, and
`MapTopology.snapshot()` / `restore()` owned by the topology.

**TODO D5 — the same derivation in several places.**

- The start's clear box: `MapGenerator._clearance_origin` / `_clearance_dims`, re-derived in
  `ObstacleRegions._index` with a comment saying it must match.
- The ridge corner height (ground + ridge + alternating roughness): `_shape_terrain` and
  `_raise_dry_stretch`.
- Flood fill four times (`_chasm_stretch`, `MapElevation._stretch`, `ObstacleRegions._flood`,
  `MapTopology.obstacles`), plus `PathField` used as a reachability test; union-find three
  times (`MapElevation`, `MapOpenness`, `MapDecorationPlanner`); a Fisher–Yates shuffle twice;
  an eight-neighbour constant in four files.

A small cell-grid utility over packed masks (neighbours, flood, components) would carry most
of the third bullet, and is the same work as P2.

**TODO D6 — fix-ups accumulate in the settle loops.** Pass 4's settle is close-to-edge → trim →
break oversized → trim, run inside up to six growth rounds and again after each of up to twelve
balancing moves; pass 6's settle alternates the cliff trim with connectivity repair, twice, and
once more in `reown`. Every loop is bounded, which is right. But each new rule (open gap, edge
closure, span cap) arrived as one more post-hoc fix-up, and map-generation.md already records
fix-ups undoing each other — ramps and trims, mass deletion and regrowth. Not a code change:
a suggestion that the next rule be tried first as a **constraint on growth** (a cell
`_growth_cells` declines) rather than a trim afterwards. The open gap and the span cap are both
candidates.

**Small findings.**

- `_place_currency` steers by the PLAN's value (`remaining -= plan.value`) but tallies the
  realised share by the FEATURE's value, and a pond's feature value differs from its plan's
  (holes filled, then capped). The comment above the line says the pond is re-priced; the line
  does not use the re-priced value. The end validation uses feature values, so this only blurs
  the steering a little. TODO: decide which is meant.
- map-generation.md §2's TODO says alliance ordering on the ring is not designed, but
  `_draw_ring` already puts same-alliance starts adjacent (`i / starts_per_alliance`), and its
  comment says so. TODO: doc drift, one way or the other.
- Ramp building is unexercised at the defaults (the TODO on `_widen_narrow_ramps` says so); pass
  6's "ramps" step mostly re-levels plateaus.
- **Removed:** `GenerationRandom.negative_binomial` and its test (the building-count draw it
  served was superseded by capacity bands); `ObstacleRegions._midpoint`, never called.

---

## 3. Parameterisation

**What holds up well.** One object holds every knob; the dock's form is built from it, grouped
and described, so a new knob appears with no dock edit. Piece facts are read from the piece
scenes, never typed. Budgets are per player. `warnings()` catches known-bad values as they are
typed.

**TODO K1 — spatial knobs are absolute while the map's size is drawn.** Each play-size axis is
drawn in 100–120, so area varies by up to 1.44× between draws of one parameter set, while every
budget is per player (energy, building capacity) and every spacing is in cells (50-cell site
separation, 20-cell open gap and cluster separation, 8–22-cell region widths, 60-cell elevation
noise). The smallest map one parameter set produces is therefore 44% more crowded than the
largest — the same features in two-thirds of the room. map-generation.md §3's measured ceiling
on building capacity ("the ceiling is room") is this effect, and its own TODO says the size
parameterisation needs reworking. Options:

1. Draw the play size FROM the budgets: an area-per-player knob, size derived — density fixed,
   size varies with the economy.
2. Budgets as densities (per thousand cells), counts derived from the drawn size.
3. Keep both and scale the spatial knobs by one derived length (e.g. √(area / players)).

**TODO K2 — knobs that are derivable** (`~/.claude/CLAUDE.md` §2.2: express a factor once,
derived):

- `value_horizon_seconds` (480) is, by its own description, "the largest pond's drain time" —
  `pond_charge_max / (site_energy_per_second × pond_rate_multiplier)`, 7200 / 15 = 480. Typed, it
  goes stale the day the charge cap or the extractor rate moves.
- `pond_cells_min` / `_max` are "the union of the per-category bounds"; as knobs they can
  disagree with the categories, and `_pond_plan` clamps to both.
- REJECTED — **heights authored in slope steps**, so they would scale with `MAX_SLOPE_DIFF`:
  when the limit moved to tan 30°, Alex chose to keep the authored heights and retune the
  terraces instead (map-generation.md §Parameters).
- `site_energy_per_second` and `pond_rate_multiplier` are piece facts on the params object:
  overwritten by `apply_piece_facts`, hidden from the form by the dock's own list, yet still
  filed under "Value" in `PROPERTY_GROUPS`.

**TODO K3 — a knob is named in four places.** The `var`, `PROPERTY_GROUPS`, `DESCRIPTIONS`, and —
for a hidden one — the dock's skip list. A `Resource` with `@export`, `@export_group`,
`@export_range` and `##` doc comments (which the inspector shows as tooltips) says all of it at
the declaration: grouping, the bounds the doc table lists (enforced, where today only five are
warned about), and the hover text. Per-start-count presets become saved `.tres` files instead of
`PLAY_SIZE_RANGE_BY_START_COUNT`. Two cautions: a resource-valued `@export` on a `Resource`
crashes the inspector, so `building_pool`, the piece slots and `collocation_rules` stay
unexported (they are shell-injected anyway); and the form's own build-from-properties code
would be replaced by an `EditorInspector`, which is a dock rewrite.

**TODO K4 — parallel arrays nothing checks.** `pond_richness_factors` / `_weights` /
`_cells_min` / `_cells_max` must be one length, and `cluster_capacity_band_edges` one longer than
`_weights`. A mismatch is an index error mid-generation. The cheap fix is a `warnings()` entry
each; the thorough one is a record per category.

**Small findings.**

- map-generation.md's table said the shelter count is "not a parameter", but it is. Resolved
  2026-10-05: the table now names `shelters_base` / `shelters_per_player_min` / `_extra`.
- `last_pass` is a run control filed among the map's parameters, so it travels with them.
- `alliance_count` is the most consequential knob and sits last, in a group of its own; and
  `default_params(start_count)` treats start count as alliance count, so `starts_per_alliance`
  above 1 has no play-size row.
- Tuning-relevant numbers also live as constants — `ObstacleRegions`' round, reach and attempt
  budgets, `MapElevation._GRADE_PER_CELL`, `MapOpenness`' choke thresholds (which
  map-generation.md calls "first guesses"). Most are algorithm budgets, rightly constants; the
  openness thresholds are measurement knobs and could join the params when openness becomes an
  invariant ([deferred](../../deferred.md) 1.64).

---

## Also found, outside the generator

Commit `4e947991` ("removing extraneous files") deleted `.gitignore`'s `!.godot/imported/` line
and the imported files with it — the `.blend` scenes and s3tc textures CLAUDE.md §Running and
testing says a clone needs, "or ~800 tests fail". This session's probes logged missing `.blend`
and `.svg` imports from it. The generator's core is unaffected (no pieces load), but the suite
and the game are. TODO: intended?
