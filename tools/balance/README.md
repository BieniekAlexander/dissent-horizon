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
| `speed` | unit scene `Movement` node |
| weapon `split_time`/`reload_time`/`clip_size`/`melee_*`/`hits` | weapon node under `Loadout` (`hits`→`target_mask`) |
| weapon `reach` | the weapon's `AttackRange` → `SubResource` shape `radius` |
| projectile `base_damage`/`damage_type`/`speed` | projectile scene root |
| status-effect `damage_per_tick`/`tick_rate`/`duration_ticks`/`damage_type` | the `DamageOverTimeStatusEffect` node |
| `ore`/`population`/`dominion` | `manifest.json` |
| `damage_table.yaml` cells | source CSVs `resources/damage/damage_vs_{armour,attribute}.csv` (targeted cell; blank = default multiplier) |
| structural (`name`, `kind`, `weapons`, `attributes`, `layer`, `requires`) | reported, edited by hand |

## Concepts

| Concept | Definition |
|---|---|
| **DPS(A→T)** | best sustained damage A lands on T, after armour/attribute multipliers; **0 if A can't hit T's layer** (air/ground). |
| **TTK(A→T)** | `T.hp / DPS(A→T)` (∞ if A can't hurt T). |
| **exchange_cost(R,T)** | `cost(R) · TTK(R→T) / TTK(T→R)` — resources of R spent to kill one T in a duel. **Lower = better answer.** |
| **favorable response** | `exchange_cost(R,T) < cost(T)`. The Costed-Response bar: every threat should have one. |
| **tech tier** | longest `requires` chain depth in the faction's tech DAG. |

Cost is **ore-only in v1** (see `TODO(weighted-scalar)` in `model.py:Cost.scalar`).
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
