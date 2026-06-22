# Godot → YAML balance exporter (Phase 2)

Extracts the **resolved** combat stats of game scenes into the YAML catalogs the
`dh_balance` Python tool consumes — the export half of the two-way bridge.

It instantiates each scene **without adding it to the tree** (so `_ready` /
`_auto_initialize` never fire) and reads the live component values: `Defense`
(hp, armour), `Weapon` (cadence, reach, target layers, melee vs projectile),
`Projectile` (base damage, type, speed), and `DamageOverTimeStatusEffect`. This
is why it's reliable where parsing `.tscn` by hand is not — inherited base
scenes, projectile-borne damage, and DoT effects all resolve correctly.

## Run

```bash
# from the repo root
godot --headless -s res://tools/balance_export/godot_export.gd
```

Output lands in `tools/balance/data/../data_exported/` (a separate dir, so you can
diff against the hand-authored `data/` before promoting). Then analyze it:

```bash
cd tools/balance
PYTHONPATH=. .venv/bin/python -m dh_balance --data-dir data_exported list
PYTHONPATH=. .venv/bin/python -m dh_balance --data-dir data_exported obsolete prototype
```

## `manifest.json`

The exporter fills **stats** from scenes, but **cost**, **tech `requires`**, and
**faction grouping** are not reliably on the scenes yet (there's one shared
`technology_mapping` and the new scenes have unset/placeholder `type`s). So those
live in `manifest.json` — edit it to organize the roster into real factions and
set economy/tech. Each buildable is `{id, scene, cost, requires}`; everything
else is read from the scene.

## What gets normalized

- **Projectiles** are deduped by scene filename stem (`irregular_bullet.tscn` →
  `irregular_bullet`), so a projectile shared by two weapons becomes one catalog
  entry referenced twice — mirroring Godot's own `PackedScene` sharing.
- **Weapons** are emitted per-buildable (`<buildable>_<weapon>`); Godot weapons
  are scene-embedded nodes, not shared resources.
- **Status effects** hang off their projectile (`<projectile>_dot`).
- **Damage table** is regenerated from `resources/damage/*.csv`.

## Known gaps / notes

- Output is **generated** (git-ignored). Promote by copying into `data/`.
- Pareto "obsolete" is **combat-only**: a builder like the technician shows up as
  dominated because the model doesn't yet know about non-combat roles. Expected.
- Headless logs some pre-existing project noise (`DamageTable` autoload,
  `implicit_initializer` warnings). Harmless to the export — the stats still extract.
- Phase 3 (YAML → Godot importer) is the reverse direction and not built yet.
