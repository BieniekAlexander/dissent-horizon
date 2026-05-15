# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Dissent Horizon is a Godot 4.5 RTS game written in GDScript. The main scene is `scenes/scenarios/s1.tscn`. Physics runs at 30 ticks/second.

## Running and testing

There is no CLI build script. Open the project in Godot 4.5 by pointing the editor at `project.godot`.

Tests use the [GUT](https://github.com/bitwes/Gut) addon. Run all tests headlessly:
```
godot --headless -s addons/gut/gut_cmdln.gd
```

Run a single test file:
```
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HexUtils.gd
```

Tests live in `tests/` and extend `GutTest`.

## Architecture

### Top-level structure

`Scenario` (`scripts/scenario.gd`) is the root node for a game session. It owns the `Map` and instantiates `Commander` nodes — commander ID `1` is the human player (loaded from `scenes/player.tscn`), all others are AI `Commander` instances.

Scenario data (initial entity placement and timed events) is defined in `configs/scenarios/<name>/`:
- `init.json` — per-commander starting entities with grid locations and scene paths
- `events.json` — timed waves/spawns with `time_specs` (mean arrival time in seconds)
- `grid.csv` — terrain layout imported via the `csv-data-importer` addon

### Entity hierarchy

```
Entity (CharacterBody3D)           — type enum, stats (hp, armor, movement), commander assignment
  └── Commandable (Entity)         — command queue via CommandReceiver, HP bar, aggro logic
        ├── Unit (Commandable)     — NavigationAgent3D movement, sprite flip/animation
        └── Structure (Commandable)— grid placement, training queue, population/resource contribution
```

`Entity.Type` uses hex-encoded values: the hundreds digit is `1` = unit or `2` = structure; e.g., `UNIT_TECHNICIAN = 0x1100`, `STRUCTURE_OUTPOST = 0x1200`. Commander ID `0` is neutral/world-owned.

### Command system

Commands are the primary game action abstraction. The lifecycle on each physics tick (driven by `CommandReceiver._update_state()`):
1. `get_updated_state()` — may swap to a new command reactively (e.g., interrupt with attack)
2. `can_act()` — checks if the action is ready (in range, timer elapsed, etc.)
3. `fulfill_action()` — performs the action, returns a follow-up command or `null`
4. If not acting: navigate toward `message.position` via `NavigationAgent3D`

`CommandMessage` is the context bundle passed to commands: `target` (Entity), `tool` (Tool), `world_position` (Vector3), and `map`.

`CommandContext` + `Pattern` handle intent resolution: a `CommandContext` holds an ordered list of `Pattern` objects that pair a condition callable with a `Command` subclass. `evaluate_command(actor, message)` returns the first matching command type. Contexts can nest via `state_maping` (keyed by input action name) for multi-step command entry (e.g., pressing `A` enters the attack-move context).

### Input and HUD (`RTSController`)

`RTSController` (a `CanvasLayer` in the player scene) handles all input: unit selection (box select or click), command issuance (right-click `move`, hotkeys), and HUD button visibility. It resolves the active `CommandContext` from the union of contexts of all selected units.

Key input actions (defined in `project.godot`): `isometric_camera_select` (LMB), `move` (RMB), `command_attack_move` (A), `command_stop` (S), `command_launch` (F), `tool_well` (W), `tool_dwelling` (R), `tool_outpost` (Q), `debug_hide_fog` (Space).

### Commander and technology tree

`Commander` tracks resources (`ore`, `population`, `dominion`) and a `technology_mapping` dictionary keyed by `Entity.Type`. Each `TechnologySpec` has costs and an `availability_evaluator` callable that checks prerequisite structures. `proc_technology()` must be called whenever structures are added/removed.

### Map and spatial queries

`Map` wraps a `HeightMapShape3D`-based terrain (a `StaticBody3D` + `CollisionShape3D`) and a `NavigationRegion3D`. It exposes `@export var terrain_body: StaticBody3D`, `@export var terrain_collision: CollisionShape3D`, and `@export var cell_size: float` — all wired in the scene inspector.

`TerrainGrid` (`scripts/maps/terrain/terrain_grid.gd`) derives the navigable cell grid from the shape: a HeightMapShape3D with `map_width` W and `map_depth` D yields (W−1)×(D−1) cells. It tracks building footprints and emits `cells_changed` when they change.

`NavManager` (`scripts/maps/terrain/nav_manager.gd`) listens to `cells_changed` and rebuilds the `NavigationMesh` by sampling `HeightMapShape3D.map_data` for actual corner heights, converting via `terrain_body.global_transform` → `NavigationRegion3D.global_transform.affine_inverse()`. Rebuilds are debounced with `call_deferred`.

`Map` maintains a flat `cell_grid` array (indexed by grid coordinates) for O(1) structure lookups. `grid_to_world(cell)` / `world_to_grid(xz)` convert between grid indices and world space using `cell_size`. Entity proximity queries use `PhysicsShapeQueryParameters3D` against the `UNITS` collision layer.

## Utility aliases

Short-form class aliases used throughout the codebase:
- `VU` = `VectorUtils` — `inXZ`, `fromXZ`, `onXZ` for Vector3↔Vector2 conversions
- `AU` = `ArrayUtils` — sorting and filtering helpers  
- `SU` = `SpaceUtils` — collision and placement helpers
- `HU` = `HexUtils` — hex grid coordinate conversions (evenq, cube, axial)
