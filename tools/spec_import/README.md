# Spec importer: gdd docs → Godot

The Obsidian docs in `gdd/` are the **governing source** for game-piece data.
A markdown file is a spec **if and only if its YAML frontmatter has an `id`
key**; the importer applies it to the Godot project — one-way (the old
Godot→YAML export direction is retired). Doc **location is purely
organizational**: nothing but the `id` key decides spec-hood, so a spec doc can
live in **any** folder under `gdd/` and be moved freely — faction membership is
data, never directory structure. (`kind` is then required *content* of a spec;
it selects how the spec is processed.)

## Running

```bash
# CLI (headless):
godot --headless -s res://tools/spec_import/import.gd                       # full mode
godot --headless -s res://tools/spec_import/import.gd -- --mode=incremental

# In-editor: the "Spec Import" toolbar menu (addons/spec_import) runs the same
# pipeline and rescans the filesystem afterwards.
```

Pipeline: **scan → validate → sync scenes → generate**. Validation is total
and loud: any unknown reference, duplicate id, bad enum name, or missing scene
file aborts the run **before anything is written** (no fuzzy matching — you
reconcile ids by hand, by design).

## Modes

Scalar keys present in a doc always overwrite; **omitted keys never touch the
scene** (that's how visuals/VFX stay hand-authored). The modes only differ on
collection-valued keys (`weapons`, `status_effects`, `trains`, `builds`,
`starts_with`, `ordnances`):

- **full** — the spec list is authoritative: matched items updated, spec-only
  items created, scene-only items **removed**.
- **incremental** — update/create only; scene-only items are preserved.

A second full-mode run immediately after a first is always a zero-diff no-op
(change detection is semantic, against the live component values).

## What gets generated

| artifact | contents |
| --- | --- |
| `scripts/generated/entity_ids.gd` | `EntityIds` — one StringName const per piece, alphabetical |
| `scripts/generated/status_effect_ids.gd` | `StatusEffectIds` consts |
| `resources/generated/technology.json` | cost / build-time / requires per piece (Commander loads at startup) |
| `resources/generated/tools.json` | build/train tool registry (Tool loads at startup; command names are `command_tool_<id>`) |

`Entity.id` (a StringName) replaced the old `Entity.Type` enum; hand-written
code references pieces via the generated `EntityIds` consts.

## Doc schema

Two keys are common to every kind:

- **`id`** (required — it's what makes the doc a spec) — a **generic**,
  snake_case identifier. It is the stable game-side key; keep it flavor-neutral
  (e.g. `anarchical`, not `baladians`), because renaming it ripples through
  generated code and cross-references.
- **`title`** — the user-facing display name (flavor text). Named `title`, not
  `name`, because `name` is reserved on Godot nodes. For a **faction** the title
  is written to the scene's `faction_name`; for other kinds it is carried as
  display metadata (e.g. the balance tool's roster name).
- **`editor_description`** (optional) — copied verbatim into the scene root
  node's Godot-native `editor_description` (the in-editor tooltip). Multi-line
  values are fine.

Wikilinks are accepted anywhere an id is expected (`"[[warlord]]"`,
`"[[dir/warlord#Stats|alias]]"` → `warlord`). Times are **seconds** (converted
to 30 tps ticks on import). Enum names come from the engine enums
(`Defense.ArmourType`, `Defense.FrameType`, `Damage.Type`, `Movement.Mode`,
`Projectile.Trajectory`).

### kind: unit | structure

```yaml
kind: unit                     # or structure
id: warlord                    # required (generic, snake_case) — makes this a spec
title: Warlord                 # user-facing display name (flavor text)
editor_description: Veterancy-scaling rocket infantry.   # optional -> Godot editor_description
scene: res://scenes/entities/units/an/warlord.tscn   # ABSENT => skeleton scene auto-created
cost: {ore: 250, vigor: 0, dominion: 0}
build_time: 20                 # seconds
requires: [stronghold]         # structure ids; ALL must be built to unlock
hp: 160                        # Defense.hp_max
armour: MEDIUM                 # Defense.ArmourType
frame: BIOLOGICAL              # Defense.FrameType
vision: 6                      # VisionRange cylinder radius
aggro: 5                       # AggroRange cylinder radius
movement: {mode: GROUNDED_DIRECT, speed: 1.2, turn_rate: 1080}
weapons:                       # matched by name (the sync key)
  - name: Rocket
    projectile: warlord_rocket # projectile id; omit for a melee weapon:
    # melee_damage: 10
    # melee_damage_type: LEAD
    split_time: 1.5            # seconds between attacks
    reload_time: 1.5
    clip_size: 1
    reach: {ground: 4, air: 10}   # or a single number
    hits: [ground, air]
ui: {label: Warlord, grid: [1, 2], factions: [anarchists]}
# structure-only:
footprint: [3, 3]              # Structure.dimensions (grid cells)
trains: [warlord, irregular]   # Production.producible_types
builds: [stronghold]           # Builds.buildable_types (builder units use this too)
vigor: {capacity: 40, upkeep: 0}   # vigor_provided / vigor_required
```

- `ui:` makes the piece buildable/trainable (it becomes a Tool registry entry).
  `ui.factions` is **button-grid layout metadata** for the collision review,
  not a gameplay gate — availability is always technology (structures owned).
- A doc **without** `scene:` gets a skeleton scene created (inheriting
  `unit.tscn` / `abstract_structure.tscn`, placeholder art from the base), and
  the new path is written back into the doc's frontmatter. Scene placement maps
  `gdd/factions/anarchical/` → `an/`, `colonial/` → `cl/`.

### kind: projectile

```yaml
kind: projectile
id: warlord_rocket
scene: res://scenes/entities/projectiles/an/warlord_rocket.tscn
damage: 25                     # base_damage
damage_type: EXPLOSIVE
speed: 0.175
trajectory: BALLISTIC
hitscan: false
status_effects: [lazer_burn]   # status-effect ids -> instanced scenes under EffectApplicator
```

### kind: status_effect

```yaml
kind: status_effect
id: lazer_burn
scene: res://scenes/entities/status_effects/lazer_burn.tscn
```

Registration only: the effect's mechanics stay authored in its scene/script;
the doc just makes the id referenceable from projectiles (and enumerated in
`StatusEffectIds`).

### kind: faction

```yaml
kind: faction
id: anarchical                 # generic ideology id
title: Anarchists              # user-facing name -> scene faction_name
scene: res://scenes/factions/anarchical.tscn
starts_with: [stronghold, warlord, irregular, irregular, irregular]   # exactly 1 structure (the HQ)
ordnances: [ambush, irradiate, dignify, informant]
```

`ordnances` is **name-only matching** this pass: each identifier must match an
existing `OrdnanceUnlock` in the faction scene (snake_cased `ordnance_name`);
the list controls membership + order, while dominion costs, prerequisites, and
event scenes stay authored in the scene.

> **TODO (future pass):** extend the spec process so ordnances, events, and
> triggers are their own doc kinds (costs, prerequisites, targeting, event
> scene refs) instead of name-only matching.

## Downstream: balance analysis

`tools/balance/gdd_to_balance.py` derives the `dh_balance` YAML catalogs from
the same docs (no engine run needed):

```bash
python3 tools/balance/gdd_to_balance.py
cd tools/balance && PYTHONPATH=. .venv/bin/python -m dh_balance list
```

## Files

- `frontmatter.gd` — YAML-subset frontmatter parser (wikilink-aware)
- `tscn_doc.gd` — text-level .tscn editor (byte-identical round-trip; never
  `PackedScene.pack()`, which would flatten scene inheritance)
- `spec_registry.gd` — scan + validate
- `generators.gd` — EntityIds / StatusEffectIds / technology.json / tools.json
- `scene_sync.gd` — doc→scene application, skeletons, faction rewrite
- `import_pipeline.gd` — the shared pipeline; `import.gd` — CLI entry
- `addons/spec_import/` — the editor toolbar menu

Tests: `tests/test_Frontmatter.gd`, `tests/test_TscnDoc.gd`,
`tests/test_SpecRegistry.gd`, `tests/test_Tool.gd`, `tests/test_FactionRosters.gd`.
