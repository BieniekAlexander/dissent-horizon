# dh-balance — Costed Response Analysis

A design-time framework for balancing Dissent Horizon's asymmetric factions.
You author factions as data, and it answers questions like *"does this faction
have an obsolete unit?"* and *"what can faction A field that faction B can't
afford to answer?"* — the **Costed Response Analysis** method, where every major
threat should have at least one *economically favorable* response.

This is a **design tool that runs ahead of the game**: factions can be modelled
and balanced here before they're built in Godot.

## Quickstart

```bash
cd tools/balance
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'   # or: pip install networkx pyyaml pytest
PYTHONPATH=. .venv/bin/python -m dh_balance list

# the three core queries
PYTHONPATH=. .venv/bin/python -m dh_balance obsolete   <faction>
PYTHONPATH=. .venv/bin/python -m dh_balance unanswered <attacker> <defender>
PYTHONPATH=. .venv/bin/python -m dh_balance tier-gap   <low_faction> <low_tier> <high_faction> <high_tier>

PYTHONPATH=. .venv/bin/python -m pytest -q
```

## Round-trip with Godot (the two-way bridge)

```bash
# 1. EXPORT current game stats -> data_exported/  (read-only)
godot --headless -s res://tools/balance_export/godot_export.gd

# 2. tune numbers in an edited copy
cp -r data_exported data_edited && $EDITOR data_edited/...

# 3. IMPORT: preview, then write back
PYTHONPATH=. .venv/bin/python -m dh_balance import --current data_exported --desired data_edited
PYTHONPATH=. .venv/bin/python -m dh_balance import --current data_exported --desired data_edited --apply
```

Import is a **surgical `.tscn` text-edit**: it replaces only the value of a
property that's *already* in the scene, preserving inheritance, node order, and
`ext_resource`s. Stats whose value equals the base-scene default (not overridden
in the child) are reported **UNWRITABLE** — "not created" — so you add them once
in the editor rather than risk a malformed override. Cost/tech changes route to
`tools/balance_export/manifest.json`. **Dry-run is the default**; `--apply` writes
(commit/stash first — changes are git-reversible). Routing per field:

| Field | Target |
|---|---|
| `hp`, `armour` | unit scene `Defense` node (`hp_max`, `armour_type`) |
| `speed` | unit scene `Locomotion` node |
| weapon `split_time`/`reload_time` (scene: `*_ticks`)/`clip_size`/`melee_*`/`hits` | weapon node under `Loadout` (`hits`→`target_mask`) |
| weapon `reach` | the weapon's `AttackRange` → `SubResource` shape `radius` |
| projectile `base_damage`/`damage_type` | the emission scene's `Payload` node |
| projectile `speed` | emission scene root — TODO: stale since speed moved onto the `EmissionPhase` children |
| status-effect `damage_per_tick`/`tick_rate`/`duration_ticks`/`damage_type` | the `DamageOverTimeStatusEffect` node |
| `energy`/`population`/`dominion` | `manifest.json` — TODO: `population` is a leftover name; `gdd_to_balance.py` fills it from `infrastructure`, and the tool's model, loader and importer should call it that |
| `damage_table.yaml` cells | source CSVs `resources/damage/damage_vs_{armour,attribute}.tsv` (targeted cell; blank = default multiplier) |
| structural (`name`, `kind`, `weapons`, `attributes`, `layer`, `requires`) | reported, edited by hand |

### Damage types are mirrored twice, and both mirrors are pinned

`Damage.Type` (`scripts/entities/tools/damage.gd`) has two Python counterparts:
`gdd_to_balance.DAMAGE_TYPES` (matched by ORDINAL — a projectile scene stores
`damage_type` as the enum's integer) and `dh_balance.model.DamageType` (matched
by NAME — the catalogs are YAML keyed by name). The first is now PARSED out of
`damage.gd` rather than hand-written; the second is still written out, for
greppability, and `tests/test_damage_types.py` fails if either disagrees with
the engine.

That test exists because both had drifted three members behind
(INCENDIARY, HIGH_EXPLOSIVE, CRYO). The failure modes are quiet in different
ways: a missing NAME drops that type's whole row from `damage_table.yaml` behind
a one-line WARN, and the first projectile doc to use it then raises
`ValueError: '<TYPE>' is not a valid DamageType` out of `load_projectiles` —
which takes down every command including `mermaid`, so a stale enum reads as
"the tech-tree diagram is broken".

### Validating the `Entity.Type` ↔ scene mapping

The export joins enums to scenes, so it's only as reliable as the scenes'
`type` values. This auditor catches drift between the `Entity.Type` enum and the
scenes that are supposed to declare each value:

```bash
godot --headless -s res://tools/balance_export/validation.gd
```

It walks `scenes/entities/units` + `scenes/entities/structures` (recursing into faction subfolders), instantiates each scene
out-of-tree, reads the root's `type`, and reports:

- **[1] Unused enums** — `Entity.Type` values that **no** scanned scene
  instantiates with (an enum with no scene behind it, or a scene that forgot to
  set its `type`).
- **[2] Name/scene mismatches** — the enum's name-stem (the text after the last
  `_`, e.g. `AN_STRUCTURE_REDOUBT` → `REDOUBT`) is not a case-insensitive
  substring of a declaring scene's filename (e.g. type `…COMPOUND` living in
  `n_building.tscn`).
- **(note)** scenes whose root resolved to `UNDEFINED` (no `type` set).

It hardcodes no enum members, so it still runs — and pinpoints the cause — when
the rest of the project doesn't compile. Scope is the two scanned dirs; an enum
whose scene lives elsewhere shows as unused (the report prints the dirs it
scanned).

## Concepts

| Concept | Definition |
|---|---|
| **DPS(A→T)** | best sustained damage A lands on T, after armour/attribute multipliers; **0 if A can't hit T's layer** (air/ground). |
| **TTK(A→T)** | `T.hp / DPS(A→T)` (∞ if A can't hurt T). |
| **exchange_cost(R,T)** | `cost(R) · TTK(R→T) / TTK(T→R)` — resources of R spent to kill one T in a duel. **Lower = better answer.** |
| **favorable response** | `exchange_cost(R,T) < cost(T)`. The Costed-Response bar: every threat should have one. |
| **tech tier** | longest `requires` chain depth in the faction's tech DAG. |

Cost is **energy-only in v1** (see `TODO(weighted-scalar)` in `model.py:Cost.scalar`).
Counter values are **computed from stats**, with an optional per-matchup
`overrides:` block (see `schema/SCHEMA.md`).

### What the model deliberately ignores (v1)

This is a **surface-level DPS approximation**, intended as coarse triage ("does a
favorable answer exist?") — **not** a fight predictor. It treats every matchup as
a single-target 1v1 DPS race and ignores factors that can flip real outcomes:

- **Area-of-effect** — one-at-a-time vs all-at-once give opposite results.
- **Range & movement** — out-ranging + kiting; `reach`/`speed` are stored but unused in the math.
- **Compounding interactions** — support units, buffs, terrain, combined arms.
- **Micromanagement** — focus fire, retreats, ability timing.

When one of these dominates a matchup, capture the real value with an
`overrides:` entry instead of complicating the formula. Closing these gaps
properly is the job of the later analytic-Lanchester / in-engine simulator.

## Layout

```
data/damage_table.yaml      # rock-paper-scissors table, synced from the game CSVs
data/status_effects.yaml    # catalog: id -> effect
data/projectiles.yaml       # catalog: id -> projectile  (refs status_effects)
data/weapons.yaml           # catalog: id -> weapon       (refs a projectile)
data/factions/*.yaml        # one file per faction; buildables ref weapons by id
dh_balance/model.py         # typed, resolved model (mirrors Godot components)
dh_balance/loader.py        # YAML catalogs -> resolved graph (two-pass, by-id refs)
dh_balance/combat.py        # DPS / TTK / exchange_cost  (pure, no I/O)
dh_balance/graph.py         # NetworkX tech DAG + counter graph (+ override merge)
dh_balance/queries.py       # obsolete_units / unanswered_threats / tech_tier_gap
dh_balance/cli.py           # `python -m dh_balance ...`
```

### Data model: catalogs + by-id references

Game data is a **graph** (a unit *has* weapons, a weapon *references* a
projectile, a projectile *carries* status effects, any of which can be shared).
It's stored normalized — one catalog file per shareable type, cross-referenced
by **bare id inside a typed field** (`projectile: shell_explosive_50` resolves
against `projectiles.yaml`). Ids are global within their catalog, so one
projectile is referenceable from any weapon in any file. The loader resolves
bottom-up (effects → projectiles → weapons → factions) and **fails hard on
duplicate ids or dangling refs**. This mirrors Godot's own `uid`/`ext_resource`
sharing — full details in `schema/SCHEMA.md`.

### The baked tech graph: three relations, three devices, one arrow meaning

`python -m dh_balance mermaid <faction>` renders the tech DAG for a faction note
(`gdd/factions/<f>/<f>.md`, refreshed by that note's "Refresh tech tree" button).
The rosters have exactly three relations to show, and **only one of them is an
arrow** — an all-arrow diagram was unreadable long before a faction was finished:

| Relation | Drawn as | Why not an arrow |
|---|---|---|
| structure **trains** unit | the unit sits INSIDE the structure's subgraph | a production line is a group, and a group of 4 is 4 arrows saying one thing |
| unit **requires** a structure it isn't trained by | the gate and the units it gates share a colour class | the arrow crossed the whole diagram, and collided with the production lines on the way |
| structure **requires** structure | a solid arrow | it *is* the backbone; nothing else competes for the reading |

So an arrow means "tech backbone" and nothing else, and the dashed arrow is
retired — it existed to separate `requires` from `trains`, and neither of those
is an edge any more.

**The backbone is declared in an order chosen to keep its edges from crossing**, not in
id order. Mermaid lays flowcharts out with dagre, a Sugiyama pipeline whose within-rank
ORDERING step is a heuristic seeded by declaration order — so on a graph where the
heuristic gets stuck, the seed decides the picture, and a seed derived from spelling has
nothing to do with the shape of the tree. `_declaration_order` does one forward barycenter
sweep instead: each node goes at the mean position of its parents in the rank above, ties
broken by id so re-runs stay byte-identical.

Measured by driving **dagre itself** (`npm i dagre`, feed it the emitted graph, read the
ranks back out of the laid-out geometry and count crossings) rather than by eyeballing
renders: the Colonials went 2 crossings → 0, every other faction stayed at 0. It is a
heuristic, not a solver, so a future roster could still need a hand — but it cannot do
worse than the id-order seed on a tree, where the sweep is exact.

**Inside a producer, units are listed in the order its doc's `trains:` names
them** — not sorted. That list is authored and already load-bearing elsewhere: the
command grid takes a train button's COLUMN from the unit's index in it (CLAUDE.md
§Structure buttons are laid out by ROLE), so it is the same left-to-right order
the player reads off the HUD, and it is usually written as a progression (cheap to
expensive, basic to specialist). Sorting it made the chart disagree with the game
about the shape of its own roster. The order of the CLUSTERS, and every other list
in the emitter, is still by id — only within a production line does authoring win.

A **tech gate** is a structure named in a unit's `requires` that does *not* also
train it. The self-naming case (`an_airField` in the requires of the transport it
builds) is a production line stated twice; colouring it would announce a tech
step the faction has not got.

Colours are `_TECH_PALETTE` in `cli.py`: saturated fills carrying white text,
because one literal has to read on **both** Obsidian themes — a border-only
treatment is swallowed by the dark theme's own node border, and a pale fill loses
its text on it. Producer clusters use a translucent grey for the same reason (it
resolves light on the light theme, dark on the dark one). Mermaid's untouched
cluster default is a pale yellow that reads as a highlight, not a container.

Three mermaid facts the emitter is built around, all found by rendering rather
than by reading docs:

- `class` on a subgraph reaches only its LABEL, so a cluster takes its colour
  through `style`.
- A node may be declared in exactly one subgraph, so a unit named by two
  producers is drawn inside the first by id (the cluster order is the id-sorted
  one; the units within a cluster are not — see above).
- Siblings render in DECLARATION order, which is what makes the `trains:` order
  above reach the picture at all.
- **A subgraph's own `direction` is ignored whenever it is linked to anything
  outside it** — which every producer here is. So the units lay out along the
  PARENT's flow axis, and the chart is `TB` purely to stack them in a column;
  a horizontal backbone and columnar production lines cannot be had at once.
  Both workarounds fail: a nested inner subgraph with its own `direction TB` is
  ignored just the same *and* reserves dead space, and an invisible anchor
  fanning `~~~` links to force one rank leaves the units in a row.

Spacing is `_LAYOUT_DIRECTIVE`. In a TB chart `rankSpacing` is the gap between
the stacked units inside a producer, so it is the knob for how tight a production
line reads, and it runs well under mermaid's default 50.

## Roadmap

- **Phase 1 (done):** framework + schema + the three queries, on demo data.
- **Phase 2 (done):** Godot→YAML exporter — `tools/balance_export/godot_export.gd`
  instantiates each scene and reads resolved Defense/Weapon/Projectile/effect
  stats into `data_exported/`. Run it, then analyze with `--data-dir data_exported`.
  See `tools/balance_export/README.md`. *(`data/factions/*.yaml` remain demo;
  `data_exported/` is the real, git-ignored export.)*
- **Phase 3 (done):** YAML→Godot importer — `python -m dh_balance import` diffs an
  edited YAML dir against a fresh export and writes the numbers back by **surgical
  `.tscn` text-edit** (replaces only existing property values; never creates an
  override, so inherited scenes stay intact). Cost routes to `manifest.json`.
  **Dry-run by default; `--apply` mutates files** (commit/stash first). See below.
- **Later:** fastest tech-up timing; army-vs-army outcome estimation (analytic
  Lanchester first, then optional in-engine Godot simulation).
