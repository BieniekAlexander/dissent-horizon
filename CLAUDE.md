# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Dissent Horizon is a Godot 4.5 RTS game written in GDScript. Isometric perspective, 3D world with 2D sprites on `CharacterBody3D` nodes. The game has fog of war, a build/train economy, multiple unit types, and an AI opponent. The main scene is `scenes/scenarios/s1.tscn`. Physics runs at 30 ticks/second.

Current state: playable prototype. Terrain uses a `HeightMapShape3D`-backed heightmap with a custom in-editor height-pin editing workflow. Unit/Structure class hierarchy was recently collapsed into a single `Commandable` class using component children (see §Entity hierarchy below).

---

## Running and testing

No CLI build script. Open the project in Godot 4.5 by pointing the editor at `project.godot`.

Tests use the [GUT](https://github.com/bitwes/Gut) addon. Run all tests headlessly:
```
godot --headless -s addons/gut/gut_cmdln.gd
```

Run a single test file:
```
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HexUtils.gd
```

Tests live in `tests/` and extend `GutTest`.

---

## Tech stack

- **Godot 4.5**, GDScript only
- **Addons**: `gut` (testing), `csv-data-importer` (terrain grid CSVs), `godot-improved-json` (JSON serialization), `heightmap_editor` (HeightPin gizmo plugin)
- Collision layers are centralised in `scripts/collision_layers.gd` (`CollisionLayers.Layer.*`)

---

## Folder / file structure

```
scripts/
  scenario.gd                     — root node for a game session
  entities/
	entity.gd                     — base class (CharacterBody3D)
	commandable.gd                 — entity that accepts commands (units + structures)
	command_receiver.gd            — manages the command queue (RefCounted)
	hit_box.gd
	components/                   — optional node-children bolted onto entities
	  defense.gd                  — hp, hp_max, armor
	  loadout.gd                — holds Weapon children
	  movement.gd                 — wraps NavigationAgent3D
	  obstruction.gd              — declares footprint dimensions for structures
	  ore_extractor.gd
	  ownership.gd                — commander relationship + team tint signal
	  production.gd               — training queue + rally; also has producible_types
	  resource_provider.gd        — population contribution
	  selectable.gd
	  dominion_generator.gd
	  command_line_indicator.gd
	structures/
	  structure_spec.gd           — per-type placement checker + StructureSpec.structure_type_spec_map
	  lab.gd, mine.gd, footprint_visualizer.gd
	units/
	  vanguard.gd
	tools/
	  tool.gd                     — Tool class + Tool.command_tool_map (static)
	  weapon.gd                   — Weapon node; AttackRange child = ranged, null = melee
	  projectile.gd
	items/
	  star.gd
  interface/
	rts_controller.gd             — CanvasLayer: selection, input, HUD, build preview
	command_context_parser.gd     — maps entity predicates → available command names
	command_message.gd            — context bundle passed to commands
	commands/                     — one file per command type
	  command.gd                  — base class; static meets_precondition/requires_position/tool_applies_to
	  attack.gd, attack_move.gd, build.gd, capture.gd, collect.gd
	  defend.gd, drop_off.gd, launch.gd, pick_up.gd, repair.gd, stop.gd, train.gd
	commander/
	  commander.gd                — tracks ore/population/dominion + technology_mapping
	  bot.gd                      — AI subclass of Commander
	  cost_spec.gd
	hud/
	  button_spec.gd, command_grid.gd, static_grid_button.gd, static_grid_container.gd
	rts_camera_3d.gd
	waypoint_indicator.gd
  maps/
	map.gd                        — @tool; owns terrain, navmesh, cell_grid, coordinate helpers
	fog.gd                        — MeshInstance3D fog-of-war shader driver
	terrain/
	  terrain_grid.gd             — tracks cell occupancy + slope-steepness
	  nav_manager.gd              — builds NavigationMesh from passable cells
	  heightmap_mesh_generator.gd — @tool; generates ArrayMesh from HeightMapShape3D
	  height_pin.gd               — @tool; Sprite3D pin per heightmap corner
  utils/
	vector_utils.gd               — VU alias (VectorUtils)
	array_utils.gd                — AU alias (ArrayUtils)
	space_utils.gd                — SU alias (SpaceUtils)
	collision_utils.gd
	evaluator.gd
	function_utils.gd
	node_utils.gd
	set.gd
  rendering/
	priority.gd                   — RenderPriority constants (FOG_PRIORITY etc.)
	shaders/fog.gdshader
  collision_layers.gd
  nav_grid.gd
scenes/
  scenarios/s1.tscn               — main scene
  player.tscn                     — Commander id=1 with RTSController + Camera
  commandable.tscn                — base scene inherited by unit.tscn / structure.tscn
  units/technician.tscn, sentry.tscn, vanguard.tscn
  structures/outpost.tscn, dwelling.tscn, mine.tscn, lab.tscn, compound.tscn, armory.tscn, turret.tscn, mountain.tscn
  projectiles/projectile.tscn, radiation.tscn
  items/star.tscn
  map/terrain.tscn
configs/
  scenarios/scenario1/, scenario2/
	init.json    — per-commander starting entities (scene path + grid location)
	events.json  — timed spawn waves
tests/
addons/
assets/
```

---

## High-level architecture

### Session root: `Scenario`

`Scenario` (`scripts/scenario.gd`) is the scene root. It creates three `Commander` nodes (id 0 = neutral/world, id 1 = human player loaded from `scenes/player.tscn`, id 2 = `Bot`). Entities live as children of their commander in the scene tree; reparenting happens automatically via the `Ownership.commander_changed` signal.

### Entity hierarchy (flat, component-based)

```
Entity (CharacterBody3D)           — type enum, @export default_commander_id, auto-init from scene
  @onready ownership: Ownership    — commander ref; emits commander_changed
  @onready defense: Defense        — hp, hp_max, armor (get_node_or_null)
  @onready movement: Movement      — wraps NavigationAgent3D (get_node_or_null; null = stationary)
  @onready weapon_inventory: Loadout   — holds Weapon children (get_node_or_null; null = unarmed)
  @onready vision_range_shape: CollisionShape3D
  @onready aggro_range_shape: CollisionShape3D

  └── Commandable (Entity)         — command queue, HP bar, aggro logic, _physics_process
		@onready command_receiver: CommandReceiver   (RefCounted, not a Node)
		@onready selectable: Selectable
		@onready production: Production    (get_node_or_null; null = can't train)
        @onready resource_provider: ResourceProvider
        @onready ore_extractor: OreExtractor
        @onready dominion_generator: DominionGenerator
```

**Units** and **Structures** are no longer separate classes. `unit.tscn` / `structure.tscn` are inherited base scenes that add groups:
- `"unit"` — added in `unit.tscn`; gates movement/aggro logic
- `"structure"` — added in `structure.tscn`; gates grid registration/teardown
- `"commandable"` — added on all; used by fog.gd, scenario iteration

Use `entity.is_in_group("unit")` / `is_in_group("structure")` rather than `is Unit` / `is Structure` (those classes don't exist anymore).

### `Entity.Type` enum

Hex-encoded values in `entity.gd`:
- Hundreds digit: `1` = unit, `2` = structure (confusingly the comment says "Type {0: entity, 1: unit, 2: structure}" but the actual values show `1100`=unit, `1200`=structure)
- Examples: `UNIT_TECHNICIAN=0x1100`, `STRUCTURE_OUTPOST=0x1200`
- Commander id `0` = neutral/world-owned

### Component attachment pattern

All optional components are node-children resolved with `get_node_or_null` in `@onready` vars. The pattern throughout the codebase:
```gdscript
@onready var movement: Movement = get_node_or_null("Movement") as Movement
# then: if movement != null: ...
```
Required nodes use `$NodeName` directly or assert. See `get_node_or_null_audit.md` for the full audit of which are legitimately optional vs. likely bugs.

---

## Command system

Commands are the primary game-action abstraction. Each command is a `RefCounted`-subclass instance. The per-tick lifecycle (driven by `CommandReceiver._update_state()` → `Commandable._process_commands()`):

1. `get_updated_state(actor)` — may reactively swap to a new command (e.g., interrupt with attack)
2. `can_act(actor)` — checks if the action is ready (in range, timer elapsed, etc.)
3. `fulfill_action(actor)` — performs the action, returns a follow-up command or `null`
4. If not acting and `should_move()`: navigate toward `message.position` via `Movement`

**`CommandMessage`** is the context bundle passed everywhere:
- `target: Entity` — the entity under the cursor (may be null)
- `tool: Tool` — for Build/Train commands
- `world_position: Vector3` — raw raycast hit
- `map: Map`
- `xz_position: Vector2` — computed from world_position
- Reference-counted: `retain()` / `release()` in Command `_init` / `_notification(PREDELETE)`. `deep_copy()` when snapshotting for waypoint indicators.

**`CommandReceiver`** owns the queue (`_command: Command` + `_command_queue: Array[Command]`). Key method: `update_commands(a_commands, add_to_queue, prepend)` — accepts a `Command`, an `Array[Command]`, or `null` (clears queue).

**`CommandContextParser`** (static class) is the single source of truth for which command names are available to a given entity or selection:
- `commands_for(entity)` — predicate table → list of command name strings
- `commands_for_selection(entities)` — union across selection
- `train_tools_for(entity)` — reads `Production.producible_types`
- `build_tools_for(entity)` — reads `Build.tool_applies_to()`

**Command preconditions** — every command subclass implements:
```gdscript
static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause
static func requires_position() -> bool
static func tool_applies_to(command_tool_name: String, entity_type: Entity.Type) -> bool
```
`PreconditionFailureCause.COMMAND_PENDING_TOOL` is not a failure — it means "armed but waiting on tool selection."

**Structure-flavored routing**: `Commandable._process_commands()` intercepts `Train` and base `Command` (rally) before they reach `CommandReceiver._process_commands()`, routing them into the `Production` component.

---

## Input and HUD (`RTSController`)

`RTSController` is a `CanvasLayer` in `scenes/player.tscn`. It owns:
- **Selection**: box-select (drag) or click; selection stored as `Array[Node]` (Commandable instances)
- **`pending_command_name`**: arms a sub-mode (e.g., `"command_attack_move"` → next right-click resolves to `AttackMove`/`Attack`)
- **`_available_commands`**: recomputed via `CommandContextParser.commands_for_selection()` on every selection change; HUD button visibility and hotkey gate read from this
- **Build preview ghost**: a translucent `Sprite3D` duplicated from `Commander.get_build_preview_instance(tool)`; snapped to grid cell each frame
- **Waypoint indicators**: pooled `WaypointIndicator` nodes under Map; shown for active `CommandMessage` snapshots in selected units' command chains

`_resolve_command_class()` (static) is the central command resolution function — replaces the old `CommandContext` + `Pattern` machinery.

Key input actions (defined in `project.godot`):
- `isometric_camera_select` (LMB), `move` (RMB)
- `command_attack_move` (A), `command_stop` (S), `command_launch` (F), `command_ability` (technician Build)
- `command_tool_well`, `command_tool_dwelling`, `command_tool_outpost`, `command_tool_mine`, `command_tool_lab`, `command_tool_compound`, `command_tool_armory`
- `debug_hide_fog` / `debug_info` (Space)

---

## Map, terrain, and navmesh

### `Map` (`@tool`, `scripts/maps/map.gd`)

The scene node that owns terrain and navigation. Key exports:
- `@export var height_map: HeightMapShape3D` — **single source of truth** for terrain extent and corner heights
- `const CELL_SIZE: float = 2.0` — world-space side of one terrain cell; encoded as Map's own scale in the scene

Key methods:
- `grid_to_world(cell: Vector2i) -> Vector3` — bilinearly samples corner heights for Y
- `world_to_grid(world_xz: Vector2) -> Vector2i` — exact inverse
- `terrain_height_at(world_xz: Vector2) -> float` — bilinear interpolation for continuous height

`Map` maintains `cell_grid: Array` (2D, indexed by grid coords, null = unoccupied, non-null = Commandable) for O(1) structure lookups, and `structure_cell_map: Dictionary` (Commandable → Array[Vector2i]).

### `TerrainGrid` (`scripts/maps/terrain/terrain_grid.gd`)

Derives the navigable cell grid from the heightmap. A `HeightMapShape3D` with `map_width` W and `map_depth` D yields **(W−1) × (D−1) navigable cells** (one quad per adjacent corner pair). Tracks:
- `_building_cells: Dictionary` (Vector2i → Object) — O(1) occupancy lookup
- `_building_footprints: Dictionary` (Object → Array[Vector2i]) — per-structure footprint
- `_steep_cells: Dictionary` — precomputed at startup; cells where corner height spread > `MAX_SLOPE_DIFF = 0.5` are impassable

Emits `cells_changed(cells: Array)` whenever buildings are placed/removed.

### `NavManager` (`scripts/maps/terrain/nav_manager.gd`)

Builds the `NavigationMesh` directly from `HeightMapShape3D` data (not from baked 3D geometry). One quad per passable cell; shared vertices across adjacent cells. Rebuilds are debounced with `call_deferred`. The navmesh excludes building-occupied cells and steep cells automatically.

**Do not change the navmesh building approach** — it avoids Godot's slow geometry-bake path and correctly encodes terrain heights.

### HeightmapMeshGenerator + HeightPin (editor tools)

`HeightmapMeshGenerator` (`@tool`) generates an `ArrayMesh` from `HeightMapShape3D`; lives as a child of `NavigationRegion/Body`. `HeightPin` (`@tool`, `Sprite3D`) — one pin per heightmap corner under `Map/HeightPins`. Moving a pin in the editor writes back to `height_map.map_data` and triggers a mesh rebuild. The pin system is editor-only; pins `queue_free()` themselves at runtime.

To spawn pins: select the Map node in the editor and toggle `generate_height_pins` in the inspector.

---

## Fog of war (`scripts/maps/fog.gd`)

`MeshInstance3D` with a shader that samples a grayscale `ImageTexture` (FORMAT_L8). Each physics frame:
1. Copies `_explored_bytes` → `_fog_bytes`
2. For each player-owned commandable with a `VisionRange` CollisionShape3D, clears pixels within radius (disc pre-cached by radius)
3. Marks cleared pixels as explored (EXPLORED_ALPHA = 127) in `_explored_bytes`
4. Uploads updated image to shader
5. Hides enemy commandables whose pixel value is non-zero

`POINTS_PER_UNIT = 1.0 / Map.CELL_SIZE` (set in `_initialize`). The fog plane is scaled to cover the terrain plus one cell margin.

Hide fog for debugging: hold Space (`debug_info` action).

---

## Commander and economy

`Commander` (`@tool`) tracks:
- `ore: int`, `population_used / population_max`, `dominion: int`
- `technology_mapping: Dictionary[Entity.Type → TechnologySpec]` — costs + `availability_evaluator` callable
- `structure_type_map: Dictionary[Entity.Type → Set]` — all owned structures of each type

`proc_technology()` must be called whenever structures are added or removed (handled automatically via `add_structure` / `remove_structure`).

`TechnologySpec.get_unmet_need(commander)` returns the first blocking reason (NOT_ENOUGH_ORE, MISSING_STRUCTURE, etc.). `Command.unmet_need_to_precondition` maps those to `PreconditionFailureCause` values.

**Build preview instances**: `Commander.get_build_preview_instance(tool)` returns a cached, out-of-tree entity instance used for placement-preview art. These are **never added to the SceneTree** — they never trigger `_ready`, physics, fog visibility, or auto-init. They're freed in `Commander._notification(PREDELETE)`.

---

## `Tool` and `StructureSpec` / `Entity.Type` wiring

`Tool` (`scripts/entities/tools/tool.gd`): a plain value object with `type: Variant` (an `Entity.Type`) and `packed_scene: PackedScene`. `Tool.command_tool_map` is a static Dictionary keyed by input-action name string:
```gdscript
"command_tool_outpost" → Tool(STRUCTURE_OUTPOST, outpost.tscn)
"command_tool_technician" → Tool(UNIT_TECHNICIAN, technician.tscn)
```

`StructureSpec` (`scripts/entities/structures/structure_spec.gd`): per-type placement checker callable. `StructureSpec.structure_type_spec_map` is the static lookup used by `Build.meets_precondition`.

`Obstruction` (`scripts/entities/components/obstruction.gd`): a node-child on structures that declares `dimensions: Vector2i` — the footprint in grid cells. `Map.add_structure` reads this to register all occupied cells.

---

## Key conventions and patterns

### `@onready` and optional components

- Required nodes: use `$NodeName` directly or `assert()`. Don't silently accept null for nodes that must exist.
- Optional components: `get_node_or_null("NodeName") as TypeName` stored in `@onready` var; all callers gate on `!= null`.
- Out-of-tree instances (build previews): `@onready` never resolves; use `get_node_or_null` inline instead of relying on `@onready` fields.

### Component pattern for entity behavior

Behavior is composed by adding component nodes as children, not by subclassing. To check if an entity has a capability:
```gdscript
entity.has_node("Production")     # can train
entity.has_node("Movement")       # can navigate
entity.movement != null           # same but typed
entity.is_in_group("unit")        # unit-flavored (not "is Unit")
```

### Coordinate system

- Grid indices: `Vector2i(x, z)` — origin at top-left (min-x/min-z corner)
- World space: Y is terrain height; XZ is the horizontal plane
- `VU.inXZ(v3)` → `Vector2(v3.x, v3.z)`, `VU.fromXZ(v2)` → `Vector3(v2.x, 0, v2.y)`

### Utility aliases

- `VU` = `VectorUtils` — `inXZ`, `fromXZ`, `onXZ` for Vector3↔Vector2
- `AU` = `ArrayUtils` — sort/filter helpers
- `SU` = `SpaceUtils` — collision/placement helpers, `linf_distance`, `unit_is_close_to_structure`

### Structure placement flow

1. Player selects Build, picks tool → `command_message.tool` set
2. `RTSController._resolve_command_class()` returns `Build`
3. `Build.meets_precondition()` checks: resources, tech prereqs, `StructureSpec.placement_checker(msg, dims)` (all cells in `Obstruction.dimensions` footprint are in-bounds and unoccupied)
4. On right-click: `Build.fulfill_action()` → `map.add_entity()` → `map.add_structure()` → `TerrainGrid.place_building()` → `cells_changed` → `NavManager` rebuilds navmesh

### Terrain height snapping for units

Units snap to terrain Y every physics tick in two places:
1. `Commandable._on_velocity_computed()` — after `move_and_slide()`, snaps to `map.terrain_height_at(xz)`
2. `Commandable._physics_process()` — unconditional snap at the end of each tick

Velocity sent to `NavigationAgent3D` is XZ-only (Y zeroed) to keep RVO avoidance stable. Terrain tracking is handled separately.

---

## Things NOT to break

**Navmesh cell-exclusion approach**: `NavManager._build_mesh()` iterates `terrain_grid.get_all_passable_cells()`. The passability check (`TerrainGrid.is_passable()`) gates on `is_in_bounds AND NOT is_building_at AND NOT is_too_steep`. Do not replace this with Godot's geometry-bake path — it's too slow and doesn't encode terrain heights correctly.

**`Map.CELL_SIZE` const**: fog, NavManager, and coordinate helpers all derive from this. It's `2.0` and encoded as Map's scale. Don't add a separate `cell_size` export that could diverge.

**`get_node_or_null` for optional components**: the `@onready` optional-component pattern is intentional. Don't change optional components to hard `$` references without checking all call sites gate on null. See `get_node_or_null_audit.md` for verdicts on each occurrence.

**`Commandable._process_commands()` routing**: structures intercept `Train` and base `Command` (rally) here before they reach `CommandReceiver._process_commands()`. Calling `command_receiver._process_commands()` directly (bypassing `Commandable._process_commands()`) breaks structure training and rally points.

**Commander_id = 0 is neutral/world**: fog hides enemies (id != player_id), aggro checks gate on `commander_id > 0 and != self.commander_id`. Don't conflate "unowned" with "player-owned."

**`Commander.get_build_preview_instances`**: these out-of-tree entity instances must never be added to the SceneTree. They skip `_ready`, physics, and auto-init intentionally.

**`Entity._auto_initialize`**: scene-placed entities (not spawned by Scenario) call this deferred to find their `Map` and `Commander`. It then calls `map.add_structure()` with a centroid-offset correction. If you add new structures to the scene in the editor, they rely on this path.

---

## Recent architectural decisions

**Unit/Structure class collapse** (Stage D): `Unit` and `Structure` GDScript classes were deleted. Both are now `Commandable` instances distinguished by group membership (`"unit"` / `"structure"`) set in the `.tscn` base scenes. Existing checks like `is Unit` / `is Structure` in old code were replaced with `is_in_group(...)`.

**`Obstruction` component** (replaces inline `width`/`length` fields): structures declare their footprint size via an `Obstruction` child node with `dimensions: Vector2i`. `Map.add_structure` and `Build.meets_precondition` read this instead of hard-coded values. This is how multi-cell structures work.

**`Loadout` / `Weapon` refactor**: weapons are `Weapon` node-children of a `Loadout` node (`entity.weapon_inventory`). Previously weapons were mixed into entity stats. `Loadout.weapon_for_target(entity)` selects the correct weapon; `Weapon.fire()` handles both projectile and instant-damage modes. Melee vs. ranged is determined by presence of an `AttackRange` CollisionShape3D child on the `Weapon`.

**`HeightmapMeshGenerator` + `HeightPin` editor tools**: terrain heights are edited by moving `HeightPin` Sprite3D gizmos in the Godot editor; each pin writes back to `height_map.map_data` and triggers a mesh rebuild. Pins are deleted at runtime (`queue_free()` in `HeightPin._ready()` when not in editor).

**Terrain height snapping for units**: units snap Y to terrain each physics tick; navmesh velocity is XZ-only. This split was introduced when verticality was added back after a brief removal.

**`CommandContextParser`** replaces `CommandContext` + `CommandContextRegistry` + `CommandContextProvider`: a flat predicate table (static array of `[Callable, command_name_string]`) is the single source of truth for what commands are available to an entity. The old per-type pre-built context objects and the `Pattern`-based evaluation chain are gone.

**`RTSController._resolve_command_class()`** replaces the old `CommandContext.evaluate_command` / `state_maping` sub-context machinery. Command sub-modes (e.g., attack-move) are now a single `pending_command_name: String` on the controller; next right-click resolves it.

**Multi-cell structures design**: see `multi-cell-structures.md` for a full design doc. Current code has partial infrastructure (`Obstruction.dimensions`, `Map.add_structure` iterating the rectangle, `TerrainGrid` accepting arbitrary footprint arrays). Known open issue: visual centering for scene-placed structures and `get_grid_coordinates` returning `Vector2` (should be `Vector2i`).
