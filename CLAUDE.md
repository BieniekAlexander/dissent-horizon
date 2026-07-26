# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Terminology

**Garrison (verb / noun)** — the mechanic by which a GROUNDED_DIRECT unit enters a Commandable that has a `Garrison` component. The `Garrison` component is the host; `Occupy` is the command issued by the entering unit.

**Shelter (noun)** — a specific game structure with resource significance (distinct from the generic garrison mechanic). Do not use "shelter" as a synonym for a garrison host.

---

## Project overview

Dissent Horizon is a Godot 4.7 RTS game written in GDScript. Isometric perspective, 3D world with 2D sprites on `CharacterBody3D` nodes. The game has fog of war, a build/train economy, multiple unit types, and an AI opponent. The main scene is `scenes/scenarios/s1.tscn`. Physics runs at 30 ticks/second.

Current state: playable prototype. Terrain is a tile-type model: a single `TerrainData` resource holds per-corner heights + a per-cell tile-type layer (see `terrain-tile-types.md`), authored in-editor with the `terrain_brush` plugin (paint tile types; raise/lower/smooth/set height). Unit/Structure class hierarchy was recently collapsed into a single `Commandable` class using component children (see §Entity hierarchy below).

---

## Running and testing

No CLI build script. Open the project in Godot 4.7 by pointing the editor at `project.godot`.

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

- **Godot 4.7**, GDScript only
- **Addons**: `gut` (testing), `csv-data-importer` (terrain grid CSVs), `godot-improved-json` (JSON serialization), `terrain_brush` (in-editor terrain painting/sculpting), `terrain_snap` (drag-snap entities to the grid/height), `editor_camera_angle`, `scene_visibility_tools`
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
	  production.gd               — training queue; also has producible_types
	  garrison.gd                 — holds occupants; Occupy enters, Evacuate releases
	  resource_provider.gd        — population contribution
	  selectable.gd
	  dominion_generator.gd
	  command_line_indicator.gd
	structures/
	  lab.gd, mine.gd, footprint_visualizer.gd
	units/
	  vanguard.gd
	tools/
	  tool.gd                     — Tool class; command_tool_map loads from resources/generated/tools.json
	  weapon.gd                   — Weapon node; AttackRange child = ranged, null = melee
	  projectile.gd
	items/
	  star.gd
  interface/
	rts_controller.gd             — CanvasLayer: selection, input, HUD, build preview
	command_context_parser.gd     — maps entity predicates → available command names
	command_message.gd            — context bundle passed to commands
	commands/                     — one file per command type
	  move_command.gd              — base class; static meets_precondition/requires_position/tool_applies_to
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
	  terrain_data.gd             — @tool Resource; the authored source: heights + per-cell tile_types + catalog
	  tile_type.gd                — @tool Resource; one tile type (passable / buildable / …)
	  terrain_tile_catalog.gd     — @tool Resource; the tile-type palette (byte index → TileType)
	  terrain_grid.gd             — tracks per-cell passability (steep / building / blocked bitmask)
	  nav_manager.gd              — builds NavigationMesh from passable cells
	  heightmap_mesh_generator.gd — @tool; generates ArrayMesh from the derived HeightMapShape3D
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
  map/terrain.tscn
  entities/                       — all game entities, grouped by category then faction
    commandable.tscn              — base scene inherited by unit.tscn / abstract_structure.tscn
    units/                        — unit.tscn (base) at root; per-faction subfolders below
      tc/vanguard.tscn
      an/technician.tscn, b_irregular.tscn, warlord.tscn, b_kamikaze.tscn
      cl/h_recruit.tscn, h_badger.tscn
    structures/                   — abstract_structure.tscn (base) at root
      nt/n_building.tscn, n_mine.tscn, n_shelter.tscn, mountain.tscn
      tc/dwelling.tscn, lab.tscn, compound.tscn, armory.tscn
      an/b_redoubt.tscn, deposit.tscn
      cl/h_sam.tscn, h_cannon.tscn
    projectiles/                  — projectile.tscn, bullet.tscn, lazer.tscn, radiation.tscn (base/generic) at root
      an/irregular_bullet.tscn, warlord_rocket.tscn, b_kamikaze_bomb.tscn
      cl/h_badger_rocket.tscn, h_cannon_shell.tscn, h_recruit_bullet.tscn, h_sam_missile.tscn
  # faction-code dirs are organizational only: nt=neutral, tc=technocracy, an=anarchists/baladians, cl=collective/colonials
scenes/entities/status_effects/       — standalone status-effect scenes (instanced under projectile EffectApplicators)
scripts/generated/                    — AUTO-GENERATED EntityIds / StatusEffectIds (spec importer)
resources/generated/                  — AUTO-GENERATED technology.json / tools.json (spec importer)
tools/spec_import/                    — the gdd-doc importer (see its README)
gdd/                                  — design docs; a file is an importable spec iff its frontmatter has an `id` key (location is free)
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

### Piece ids (`Entity.id` — the old `Entity.Type` enum is gone)

Every game piece is identified by a snake_case StringName `Entity.id` (e.g. `&"warlord"`), which is the id of its spec doc in `gdd/` (see §Spec importer). Hand-written code references ids through the GENERATED `EntityIds` constants (`EntityIds.WARLORD`) — never raw strings. An empty id marks an abstract inheritance-base scene (`Entity.is_abstract()`). Unit-vs-structure is group membership / the `Structure` component, never the id.
- Commander id `0` = neutral/world-owned (unchanged)

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
- Reference-counted: `retain()` / `release()` in MoveCommand `_init` / `_notification(PREDELETE)`. `deep_copy()` when snapshotting for waypoint indicators.

**`CommandReceiver`** owns the queue (`_command: MoveCommand` + `_command_queue: Array[MoveCommand]`). Key method: `update_commands(a_commands, add_to_queue, prepend)` — accepts a `MoveCommand`, an `Array[MoveCommand]`, or `null` (clears queue).

**`CommandContextParser`** (static class) is the single source of truth for which command names are available to a given entity or selection:
- `commands_for(entity)` — predicate table → list of command name strings
- `commands_for_selection(entities)` — union across selection
- `tools_for(entity, context)` — tool command names available in a `Tool.ControlContext` (BUILD/TRAIN); gates BUILD tools via `Build.tool_applies_to()`, TRAIN tools via `Production.producible_types`. The controller's `current_context()` supplies the context.

**Command preconditions** — every command subclass implements:
```gdscript
static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause
static func requires_position() -> bool
static func tool_applies_to(command_tool_name: String, entity_type: Entity.Type) -> bool
```
`PreconditionFailureCause.COMMAND_PENDING_TOOL` is not a failure — it means "armed but waiting on tool selection."

**Structure-flavored routing**: `Commandable._process_commands()` intercepts `Train`, routing it into the `Production` component, and (for any stationary `can_rally()` commandable — one with a `Production` or `Garrison` component) a base `MoveCommand`, storing it as `rally_point` instead of moving. Both are intercepted before reaching `CommandReceiver._process_commands()`.

**Rally / release destinations** (`Commandable.can_rally()` / `rally_point` / `rally_destination()`): any commandable that trains units (`Production`) or holds occupants (`Garrison`) can rally. A stationary one (no `Movement`) holds `rally_point`, set by intercepting a bare `MoveCommand` as above; a mobile one (e.g. a transport) instead hands off its own active movement command. `rally_destination()` returns whichever applies, or `null` for "no forced destination." `Production._spawn_unit` gives newly-trained units this as their first command; `Garrison.evacuate()` chains it on after each evacuee's immediate exit-point move, so e.g. a destroyed transport's passengers continue in the direction it was heading, and units released from a structure walk on toward its rally point.

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
- `command_tool_well`, `command_tool_dwelling`, `command_tool_mine`, `command_tool_lab`, `command_tool_compound`, `command_tool_armory`
- `debug_hide_fog` / `debug_info` (Space)

---

## Map, terrain, and navmesh

### `Map` (`@tool`, `scripts/maps/map.gd`)

The scene node that owns terrain and navigation. Key exports:
- `@export var terrain_data: TerrainData` — **single source of truth**: per-corner `heights` + a per-cell `tile_types` layer (byte indices into a `TerrainTileCatalog`). See `terrain-tile-types.md`.
- `@export var height_map: HeightMapShape3D` — **derived** from `terrain_data` (`TerrainData.to_height_shape()`) at load; read by `TerrainGrid` / `NavManager` / the mesh generator and used as the cursor-picking collider. `_validate_property` keeps the derived value out of the saved scene. (Un-migrated maps may still assign it directly instead of `terrain_data`.)
- `const CELL_SIZE: float = 1.0` — world-space side of one terrain cell; encoded as Map's own scale in the scene

Key methods:
- `grid_to_world(cell: Vector2i) -> Vector3` — bilinearly samples corner heights for Y
- `world_to_grid(world_xz: Vector2) -> Vector2i` — exact inverse
- `terrain_height_at(world_xz: Vector2) -> float` — bilinear interpolation for continuous height

`Map` maintains `cell_grid: Array` (2D, indexed by grid coords, null = unoccupied, non-null = Commandable) for O(1) structure lookups, and `structure_cell_map: Dictionary` (Commandable → Array[Vector2i]).

### `TerrainGrid` (`scripts/maps/terrain/terrain_grid.gd`)

Derives the navigable cell grid from the heightmap. A `HeightMapShape3D` with `map_width` W and `map_depth` D yields **(W−1) × (D−1) navigable cells** (one quad per adjacent corner pair). Passability is one `_cell_state: PackedByteArray` (a per-cell bitmask of impassability *reasons*); a cell is passable iff its byte is `0`, so the check is a single byte read. Each source flips only its own bit:
- `_STEEP` — corner-height spread > `MAX_SLOPE_DIFF = 0.5` (the cliff layer; precomputed at startup)
- `_BUILDING` — a structure occupies the cell (`place_building` / `remove_building`; `_building_footprints` maps each structure → its cells)
- `_BLOCKED` — the cell's tile TYPE is impassable (water/forest/no-go), fed from `terrain_data.blocked_mask()` via `Map.set_blocked_mask`

Emits `cells_changed(cells: Array)` whenever passability changes.

### `NavManager` (`scripts/maps/terrain/nav_manager.gd`)

Builds the `NavigationMesh` directly from `HeightMapShape3D` data (not from baked 3D geometry). One quad per passable cell; shared vertices across adjacent cells. Rebuilds are debounced with `call_deferred`. The navmesh excludes building-occupied, steep, and impassable-typed cells automatically.

**Do not change the navmesh building approach** — it avoids Godot's slow geometry-bake path and correctly encodes terrain heights.

### Terrain visuals + in-editor editing (the `terrain_brush` plugin)

`HeightmapMeshGenerator` (`@tool`, under `NavigationRegion/Body`) generates the visual terrain `ArrayMesh` from the derived `HeightMapShape3D`. It **omits impassable cells** (steep or impassable-typed), leaving literal geometry holes — so blocking a cell / raising a cliff punches a hole with no transparency tricks.

Terrain is authored in-editor with the **`terrain_brush`** plugin (`addons/terrain_brush`): select a Map, toggle "Terrain Brush" in the spatial-editor toolbar, pick a mode, then left-click-drag over the terrain. Modes:
- **Paint** — sets the hovered cells' tile type (Open/Water/Forest/Cliff/NoGo) in `terrain_data.tile_types`.
- **Raise / Lower / Smooth / Set** — sculpt `terrain_data.heights` per corner (radial falloff; Set flattens to a target). All height edits are clamped to `[0, 5]` and snapped to `0.5`.

Edits write straight to `terrain_data` (persist with **Save All** / saving the resource) and are one undo action per stroke. The former `HeightPin` / `BlockPin` gizmos, the `heightmap_editor` addon, `Map.generate_editor_pins`, and `Map.blocked_cells` were all removed. `Map._mirror_*` (the mirror authoring tool) operates directly on `terrain_data` (heights + tile types).

---

## Fog of war (`scripts/maps/fog.gd`)

`MeshInstance3D` with a shader that samples a grayscale `ImageTexture` (FORMAT_L8). Each physics frame:
1. Copies `_explored_bytes` → `_fog_bytes`
2. For each player-owned entity in the **`"los"` group** (every `Entity` with a `VisionRange` CollisionShape3D — added in `Entity._ready`, independent of `"commandable"`), clears the pixels its vision shape covers in the XZ plane. `_vision_offsets()` generalizes over shape type: Cylinder/Sphere/Capsule reveal a circle (ellipse under non-uniform scale), Box a rectangle, and any other shape falls back to its XZ bounding box. Shapes are assumed axis-aligned; footprints are cached by signature (`kind:hx:hz`).
3. Marks cleared pixels as explored (EXPLORED_ALPHA = 127) in `_explored_bytes`
4. Uploads updated image to shader
5. Hides enemy commandables whose pixel value is non-zero (this step still iterates `"commandable"`, since it's about entity visibility, not vision sources)

A non-Commandable recon entity (e.g. `Scout`) reveals fog purely by having a `VisionRange` — it lands in `"los"` automatically. Do NOT assume the vision shape is a cylinder: `_vision_offsets()` must stay shape-agnostic.

`POINTS_PER_UNIT = 1.0 / Map.CELL_SIZE` (set in `_initialize`). The fog plane is scaled to cover the terrain plus one cell margin.

Hide fog for debugging: hold Space (`debug_info` action).

---

## Commander and economy

`Commander` (`@tool`) tracks:
- `ore: int`, vigor (capacity/upkeep), `dominion: int`
- `technology_mapping: Dictionary[StringName piece id → TechnologySpec]` — LOADED at startup from the generated `resources/generated/technology.json` (edit the gdd docs + re-run the spec importer, not the code). Ability gates ride in the same map under int `Ability.Type` keys.
- `structure_type_map: Dictionary[StringName piece id → Set]` — all owned structures of each id; entries appear lazily (use `has_built_structure` / `_structures_of`)

`proc_technology()` must be called whenever structures are added or removed (handled automatically via `add_structure` / `remove_structure`).

`TechnologySpec.get_unmet_need(commander)` returns the first blocking reason (NOT_ENOUGH_ORE, MISSING_STRUCTURE, etc.). `MoveCommand.unmet_need_to_precondition` maps those to `PreconditionFailureCause` values.

**Build preview instances**: `Commander.get_build_preview_instance(tool)` returns a cached, out-of-tree entity instance used for placement-preview art. These are **never added to the SceneTree** — they never trigger `_ready`, physics, fog visibility, or auto-init. They're freed in `Commander._notification(PREDELETE)`.

---

## `Tool` wiring and the spec importer

`Tool` (`scripts/entities/tools/tool.gd`): a ControlBinding with `type: StringName` (a piece id) and `packed_scene`. `Tool.command_tool_map` is BUILT FROM GENERATED DATA at startup (`resources/generated/tools.json`, derived from each piece doc's `ui:` frontmatter). Command names follow `command_tool_<id>`. To add a buildable/trainable piece: give its gdd doc a `ui:` key and re-run the importer — no code edit. `Tool.Faction` masks are button-grid layout metadata (collision review), never gameplay gating.

**Spec importer** (`tools/spec_import/`, full docs in its README): the gdd docs govern numeric/economy data one-way. `godot --headless -s res://tools/spec_import/import.gd` (or the "Spec Import" editor toolbar menu) validates every doc (loud, total, no fuzzy matching), syncs scenes via text-level .tscn edits (never `PackedScene.pack()` — it flattens inheritance), creates skeleton scenes for docs without `scene:`, and regenerates `scripts/generated/{entity_ids,status_effect_ids}.gd` + `resources/generated/{technology,tools}.json`. Full mode deletes scene-only collection items; incremental preserves them. Balance analysis derives from the same docs via `tools/balance/gdd_to_balance.py`.

Every spec carries a generic `id` (the stable game-side key — flavor-neutral, e.g. `anarchical` not `baladians`), a user-facing `title` (display flavor text; `name` is reserved on Godot nodes, so `title` — a faction's title syncs to its scene `faction_name`), and an optional `editor_description` (copied to the scene root node's Godot-native `editor_description`).

`Structure` (`scripts/entities/components/structure.gd`): the node-child that marks an entity as a structure and declares `dimensions: Vector2i` — the footprint in grid cells (doc key `footprint`). `Map.add_structure` reads this to register all occupied cells.

---

## Key conventions and patterns

### Variable typing

- Prefer specifying variable types rather than impling them, e.g. `var i: int = 0` rather than `var i := 0`

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
3. `Build.meets_precondition()` checks: resources, tech prereqs, `Structure.valid_placement(msg, dims)` (all cells in the `Structure.dimensions` footprint are in-bounds and unoccupied)
4. On right-click: `Build.fulfill_action()` → `map.add_entity()` → `map.add_structure()` → `TerrainGrid.place_building()` → `cells_changed` → `NavManager` rebuilds navmesh

### Terrain height snapping for units

Units snap to terrain Y every physics tick in two places:
1. `Commandable._on_velocity_computed()` — after `move_and_slide()`, snaps to `map.terrain_height_at(xz)`
2. `Commandable._physics_process()` — unconditional snap at the end of each tick

Velocity sent to `NavigationAgent3D` is XZ-only (Y zeroed) to keep RVO avoidance stable. Terrain tracking is handled separately.

---

## Things NOT to break

**Navmesh cell-exclusion approach**: `NavManager._build_mesh()` iterates `terrain_grid.get_all_passable_cells()`. The passability check (`TerrainGrid.is_passable()`) gates on `is_in_bounds AND NOT is_building_at AND NOT is_too_steep`. Do not replace this with Godot's geometry-bake path — it's too slow and doesn't encode terrain heights correctly.

**`Map.CELL_SIZE` const**: fog, NavManager, and coordinate helpers all derive from this. It's `1.0` and encoded as Map's scale. Don't add a separate `cell_size` export that could diverge.

**`get_node_or_null` for optional components**: the `@onready` optional-component pattern is intentional. Don't change optional components to hard `$` references without checking all call sites gate on null. See `get_node_or_null_audit.md` for verdicts on each occurrence.

**`Commandable._process_commands()` routing**: structures intercept `Train`, and stationary `can_rally()` commandables intercept base `MoveCommand` (rally), here before they reach `CommandReceiver._process_commands()`. Calling `command_receiver._process_commands()` directly (bypassing `Commandable._process_commands()`) breaks structure training and rally points.

**Commander_id = 0 is neutral/world**: fog hides enemies (id != player_id), aggro checks gate on `commander_id > 0 and != self.commander_id`. Don't conflate "unowned" with "player-owned."

**`Commander.get_build_preview_instances`**: these out-of-tree entity instances must never be added to the SceneTree. They skip `_ready`, physics, and auto-init intentionally.

**`Entity._auto_initialize`**: scene-placed entities (not spawned by Scenario) call this deferred to find their `Map` and `Commander`. It then calls `map.add_structure()` with a centroid-offset correction. If you add new structures to the scene in the editor, they rely on this path.

---

## Recent architectural decisions

**Unit/Structure class collapse** (Stage D): `Unit` and `Structure` GDScript classes were deleted. Both are now `Commandable` instances distinguished by group membership (`"unit"` / `"structure"`) set in the `.tscn` base scenes. Existing checks like `is Unit` / `is Structure` in old code were replaced with `is_in_group(...)`.

**`Obstruction` component** (replaces inline `width`/`length` fields): structures declare their footprint size via an `Obstruction` child node with `dimensions: Vector2i`. `Map.add_structure` and `Build.meets_precondition` read this instead of hard-coded values. This is how multi-cell structures work.

**`Loadout` / `Weapon` refactor**: weapons are `Weapon` node-children of a `Loadout` node (`entity.weapon_inventory`). Previously weapons were mixed into entity stats. `Loadout.weapon_for_target(entity)` selects the correct weapon; `Weapon.fire()` handles both projectile and instant-damage modes. Every `Weapon` has an `AttackRange` CollisionShape3D child defining its reach (queried via `SU.is_in_attack_range`); short-reach "melee" weapons just use an `AttackRange` only slightly larger than the wielder's body shape rather than a separate distance fallback.

**Tile-type terrain (`TerrainData`)**: terrain moved from a directly-authored `HeightMapShape3D` + a separate `blocked_cells` overlay to a single `TerrainData` resource (per-corner heights + per-cell tile types + a `TerrainTileCatalog`). `Map` derives the `HeightMapShape3D`, the visual mesh, the navmesh, and `TerrainGrid`'s blocked mask from it. Authoring is the `terrain_brush` plugin; the old `HeightPin`/`BlockPin` gizmos were deleted. Full design + migration notes in `terrain-tile-types.md`.

**Terrain height snapping for units**: units snap Y to terrain each physics tick; navmesh velocity is XZ-only. This split was introduced when verticality was added back after a brief removal.

**`CommandContextParser`** replaces `CommandContext` + `CommandContextRegistry` + `CommandContextProvider`: a flat predicate table (static array of `[Callable, command_name_string]`) is the single source of truth for what commands are available to an entity. The old per-type pre-built context objects and the `Pattern`-based evaluation chain are gone.

**`RTSController._resolve_command_class()`** replaces the old `CommandContext.evaluate_command` / `state_maping` sub-context machinery. Command sub-modes (e.g., attack-move) are now a single `pending_command_name: String` on the controller; next right-click resolves it.

**GDD spec pipeline + string ids (2026-07)**: game-piece data is governed by Obsidian docs in `gdd/` (YAML frontmatter) and imported one-way into scenes/generated data by `tools/spec_import` (see §Tool wiring). `Entity.Type` was deleted in favor of `Entity.id: StringName` + generated `EntityIds` consts; `Commander.technology_mapping` and `Tool.command_tool_map` load from generated JSON. The old `tools/balance_export` Godot→YAML exporter was retired (`tools/balance/gdd_to_balance.py` derives dh_balance data from the docs instead).

**Multi-cell structures design**: see `multi-cell-structures.md` for a full design doc. Current code has partial infrastructure (`Obstruction.dimensions`, `Map.add_structure` iterating the rectangle, `TerrainGrid` accepting arbitrary footprint arrays). Known open issue: visual centering for scene-placed structures and `get_grid_coordinates` returning `Vector2` (should be `Vector2i`).
