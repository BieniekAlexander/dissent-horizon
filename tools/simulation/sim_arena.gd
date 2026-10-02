class_name SimArena
extends SimulationScenario

## A [SimulationScenario] built from a parsed [SimSpec] rather than authored in the editor.
##
## THE ARENA IS BUILT AT RUNTIME. Nothing is generated to disk, so there is no derived
## artifact that can drift out of step with the spec that produced it
## (`~/.claude/CLAUDE.md` §10). Construction happens through `build()` BEFORE the node enters
## the tree, because `Scenario._ready` needs `player_slots` and a `$Map` child already in
## place — the same order `tools/generate_test_scenarios.gd` works in.
##
## The grammar it realises is gdd/systems/scenario-scripting/simulation-tests.md.

#region Constants
## Anchors sit this fraction of the way from the arena's centre to its edge. Short of 1.0 so
## a group placed at `west` has ground behind it to be pushed onto, and so a relative offset
## authored from an anchor usually still lands inside.
const ANCHOR_INSET: float = 0.75

## How far short of a group's own extent a `near:` order stops, in world units. Enough that a
## unit halts beside the group rather than inside it, which is the whole difference between
## `near:` and `target:`.
const APPROACH_STANDOFF: float = 1.0

## Centre-to-centre spacing between neighbouring members of a formation, in world units.
## Wide enough that units do not begin the run shoving each other apart through avoidance,
## which would move them before any order did.
const FORMATION_SPACING: float = 1.5

## Physics ticks allowed beyond the authored window before the backstop fires. Covers the
## tail of a run whose last check is still settling.
const WINDOW_SLACK_TICKS: int = 60

## The stand-in ground's colour. Muted and low-contrast on purpose: it is a backdrop for
## reading unit positions, not something to look at.
const GROUND_COLOUR: Color = Color(0.30, 0.32, 0.28)

## Spectator-camera orthographic size as a fraction of the arena's width. Under 1.0 because a
## 45° view covers more ground than its ortho size, and the groups sit inside ANCHOR_INSET.
const CAMERA_FIT_FRACTION: float = 0.8
#endregion

#region State
var spec: SimSpec = null
var roster := SimGroupRoster.new()
## Group reference -> the world position its formation is centred on. Resolved once, at
## build time, because a relative placement means "from where that group STARTS".
var _group_origins: Dictionary = {}
## Group reference -> Array[Vector2] of per-member offsets from that origin.
var _group_offsets: Dictionary = {}
## Problems found while building — a spec that parsed but could not be realised (a position
## outside the arena, a piece whose scene will not load). Reported like a parse error.
var build_errors: Array[String] = []
#endregion


#region Construction
## Build a runnable arena from a validated spec. The caller adds the returned node to the
## tree; everything that must exist before `_ready` is already on it.
##
## `a_seed` is THIS RUN's seed. The spec carries one only as an authored default; choosing
## and recording it is the runner's job, because repetition is (see the note, §One spec is
## one run).
static func build(a_spec: SimSpec, a_seed: int) -> SimArena:
	var arena := SimArena.new()
	arena.name = "SimArena_%s" % a_spec.id
	arena.spec = a_spec
	arena.rng_seed = a_seed
	arena.run_ticks = int(round(a_spec.run_seconds * Engine.physics_ticks_per_second))
	arena.max_ticks = arena.run_ticks + WINDOW_SLACK_TICKS
	arena._build_slots()
	arena.add_child(SimArena.flat_map(a_spec.arena_size_cells))
	arena._resolve_group_layout()
	arena._spawn_groups()
	return arena


## A flat Map of `a_cells` × `a_cells` navigable cells, in the node layout Map expects
## ($NavigationRegion/Body/Shape) over an all-zero heightmap.
##
## Static and public because `tools/generate_test_scenarios.gd` builds the same thing for the
## editor-authored scenarios; one arena, two callers, rather than two arenas that drift.
static func flat_map(a_cells: int) -> Map:
	var corners: int = a_cells + 1
	var heights := HeightMapShape3D.new()
	heights.map_width = corners
	heights.map_depth = corners
	var data := PackedFloat32Array()
	data.resize(corners * corners)
	heights.map_data = data

	var map := Map.new()
	map.name = "Map"

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	region.add_to_group("navigation_mesh_source_group", true)
	region.navigation_mesh = NavigationMesh.new()

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.Mask.TERRAIN
	body.collision_mask = 0
	region.add_child(body)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = heights
	body.add_child(shape)

	map.add_child(region)

	var pins := Node3D.new()
	pins.name = "HeightPins"
	map.add_child(pins)

	map.add_child(SimArena._ground_plane(a_cells))

	map.height_map = heights
	return map


## A flat, unshaded quad at y = 0, purely so a watched run has ground under it.
##
## A STAND-IN, not terrain: the real visual surface is a baked `ArrayMesh` driven by a
## `TerrainData` + tile catalog (see terrain-and-navigation/mesh-baked-terrain.md), and an
## arena has neither. Nothing reads this — passability comes from the heightmap and
## `TerrainGrid` — so it is safe to leave out, and without it a headless run is unaffected
## while a watched one shows units floating in the void.
##
## Deliberately NOT in `navigation_mesh_source_group`: the navmesh is built from passable
## CELLS (`NavManager._build_chunk`), never from geometry, and adding a source here would
## invite someone to assume otherwise.
static func _ground_plane(a_cells: int) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	var extent: float = a_cells * Map.CELL_SIZE
	plane.size = Vector2(extent, extent)

	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOUR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var instance := MeshInstance3D.new()
	instance.name = "GroundPlane"
	instance.mesh = plane
	instance.material_override = material
	# Just below zero so a unit snapped to terrain height sits ON it rather than z-fighting.
	instance.position = Vector3(0.0, -0.01, 0.0)
	return instance


## One PlayerSlot per commander slot, in the spec's declaration order, which is what fixes
## commander ids (slot 1 is the first `given` key).
func _build_slots() -> void:
	var slots: Array[PlayerSlot] = []
	var commander_id: int = 1
	for slot_name: String in spec.commanders:
		var settings: SimSpec.CommanderSettings = spec.commanders[slot_name]
		var slot := PlayerSlot.new()
		slot.is_bot = true
		slot.faction = _faction_scene(settings)
		slot.difficulty = PlayerSlot.Difficulty[settings.difficulty]
		# A controlled measurement starts from a known stockpile, and nothing in a spec buys
		# anything: the pieces are placed, not produced.
		slot.starting_energy = 0
		slot.starting_dominion = 0
		slots.append(slot)
		roster.register_slot(slot_name, commander_id)
		commander_id += 1
	player_slots = slots


## A slot's faction scene. Base `Scenario` never spawns a faction's opening force (only
## `Skirmish` does), so this only decides which sanctions and tints the commander carries —
## but `PlayerSlot.faction` is required, so a spec that names none still needs one.
func _faction_scene(a_settings: SimSpec.CommanderSettings) -> PackedScene:
	var path: String = a_settings.faction
	if path == "":
		path = "res://scenes/factions/colonial.tscn"
	var scene: PackedScene = load(path)
	if scene == null:
		build_errors.append("cannot load faction scene '%s'" % path)
	return scene


#endregion


#region Watching
## Widen the spectator camera so the whole arena is in frame.
##
## `Scenario` gives any session with no human rig a spectator camera, which is every spec by
## construction — a slot is always a bot. Its authored orthographic size is 15 world units,
## sized for a player's opening view of a real map, and an arena is routinely wider than that,
## so a watched run would otherwise open with its units off the edge of the screen.
##
## Cosmetic only: the camera is what a WATCHER sees, and a headless run has none.
func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_silence_unthinking_brains()
	var camera: Camera3D = get_node_or_null("SpectatorCamera") as Camera3D
	if camera == null:
		return
	# The view is tilted 45°, so the ground it covers is deeper than the ortho size; the
	# margin is what keeps a group placed at an anchor clear of the edge.
	camera.size = spec.arena_size_cells * Map.CELL_SIZE * CAMERA_FIT_FRACTION


#endregion


#region Brains
## Make every slot's BotBrain inert unless the spec asked it to think.
##
## **`Scenario` attaches a thinking BotBrain to every bot slot, and `PASSIVE` does NOT make it
## inert.** The tier means "minimally active, and never attacks" — a passive bot still builds,
## trains, defends itself and RE-TASKS its idle units. `BotBrain.active` is the flag that
## genuinely freezes a commander, and its own doc says it survives "for a scenario that
## genuinely wants a frozen commander". A spec is exactly that scenario.
##
## Without this a spec has TWO agents issuing orders to the same units, and the brain wins:
## the stock truck given `move` at an enemy had its order cleared on the first think pass,
## two seconds in, and stood still while it was shot to death. The spec looked wrong and was
## not — nothing in it could be read to explain a unit that simply stopped.
##
## So in a SPEC, `PASSIVE` means INERT. That is a deliberate narrowing of the engine's tier,
## because a controlled measurement cannot have a second decision-maker in it; any other tier
## gets the real brain, for a spec that wants to measure the bot itself.
func _silence_unthinking_brains() -> void:
	for slot_name: String in spec.commanders:
		var settings: SimSpec.CommanderSettings = spec.commanders[slot_name]
		if settings.difficulty != "PASSIVE":
			continue
		var commander: Variant = commanders[roster.commander_id(slot_name)]
		if not is_instance_valid(commander):
			continue
		var brain: BotBrain = (commander as Node).get_node_or_null("BotBrain") as BotBrain
		if brain != null:
			brain.active = false


#endregion


#region Layout
## Half the arena's width in world units. `Map.CELL_SIZE` is the one place cell size is
## stated, and the heightmap is centred on the Map's origin, so the playable square runs
## from -half to +half on both axes.
func _half_extent() -> float:
	return spec.arena_size_cells * Map.CELL_SIZE * 0.5


## Resolve every group's origin and per-member offsets. Origins first, in dependency order,
## because a relative placement reads the position of the group it names.
func _resolve_group_layout() -> void:
	for reference: String in spec.groups:
		_resolve_origin(reference, [] as Array[String])
	for reference: String in spec.groups:
		var group: SimSpec.Group = spec.groups[reference]
		_group_offsets[reference] = _formation_offsets(group)


## The world XZ a group's formation is centred on. Recursive through relative placements;
## the cycle guard is a belt over the parser's own check, not a substitute for it.
func _resolve_origin(a_reference: String, a_seen: Array[String]) -> Vector2:
	if _group_origins.has(a_reference):
		return _group_origins[a_reference]
	if a_seen.has(a_reference):
		build_errors.append("placement cycle reaching %s" % a_reference)
		return Vector2.ZERO
	var group: SimSpec.Group = spec.groups[a_reference]
	# `a_seen + [...]` would produce an UNTYPED array, which Godot then refuses at the
	# typed parameter below. Duplicate-and-append keeps the element type.
	var seen_here: Array[String] = a_seen.duplicate()
	seen_here.append(a_reference)
	var origin: Vector2 = _resolve_placement(group.placement, seen_here)
	if absf(origin.x) > _half_extent() or absf(origin.y) > _half_extent():
		build_errors.append(
			(
				"group %s resolves to %v, outside a %d-cell arena — widen `setting.size`"
				% [a_reference, origin, spec.arena_size_cells]
			)
		)
	_group_origins[a_reference] = origin
	return origin


func _resolve_placement(a_placement: SimSpec.Placement, a_seen: Array[String]) -> Vector2:
	if a_placement == null:
		return Vector2.ZERO
	if a_placement.anchor != "":
		return _anchor_position(a_placement.anchor)
	var base: Vector2
	if SimSpec.ANCHOR_DIRECTIONS.has(a_placement.from_ref):
		base = _anchor_position(a_placement.from_ref)
	else:
		base = _resolve_origin(a_placement.from_ref, a_seen)
	if a_placement.bearing == "":
		return base
	var direction: Vector2 = SimSpec.ANCHOR_DIRECTIONS[a_placement.bearing]
	return base + direction * a_placement.distance_units


func _anchor_position(a_anchor: String) -> Vector2:
	var direction: Vector2 = SimSpec.ANCHOR_DIRECTIONS[a_anchor]
	return direction * _half_extent() * ANCHOR_INSET


## Per-member offsets from the group's origin.
##
## DELIBERATELY DETERMINISTIC GEOMETRY, not the game's own scatter
## (`SU.get_nonoverlapping_points`): that probes the live physics world and needs a Map that
## is in the tree, which does not exist at build time — and an experiment wants the same
## starting layout every run rather than a seeded shuffle of it.
func _formation_offsets(a_group: SimSpec.Group) -> Array[Vector2]:
	var count: int = a_group.total_count()
	var offsets: Array[Vector2] = []
	if count <= 1:
		offsets.append(Vector2.ZERO)
		return offsets
	match a_group.formation:
		"ring":
			for index: int in count:
				var angle: float = TAU * float(index) / float(count)
				# Radius that keeps neighbours FORMATION_SPACING apart around the circle.
				var radius: float = FORMATION_SPACING / (2.0 * sin(PI / float(count)))
				offsets.append(Vector2(cos(angle), sin(angle)) * radius)
		"cluster":
			# A square block, filled row-major — the tightest legible packing.
			var side: int = int(ceil(sqrt(float(count))))
			for index: int in count:
				var column: int = index % side
				var row: int = index / side
				offsets.append(
					(
						Vector2(float(column), float(row)) * FORMATION_SPACING
						- Vector2(float(side - 1), float(side - 1)) * FORMATION_SPACING * 0.5
					)
				)
		_:
			# "line" and the default: a rank centred on the origin, running north-south so a
			# group facing east presents a front rather than a column.
			for index: int in count:
				var along: float = (float(index) - float(count - 1) * 0.5) * FORMATION_SPACING
				offsets.append(Vector2(0.0, along))
	return offsets


#endregion


#region Spawning
func _spawn_groups() -> void:
	for reference: String in spec.groups:
		var group: SimSpec.Group = spec.groups[reference]
		var origin: Vector2 = _group_origins.get(reference, Vector2.ZERO)
		var offsets: Array[Vector2] = _group_offsets.get(reference, [] as Array[Vector2])
		var index: int = 0
		for composition: SimSpec.Composition in group.composition:
			for _n: int in composition.count:
				var offset: Vector2 = offsets[index] if index < offsets.size() else Vector2.ZERO
				_spawn_one(group, composition.piece, origin + offset)
				index += 1


func _spawn_one(a_group: SimSpec.Group, a_piece: String, a_at: Vector2) -> void:
	var path: String = SimPieceCatalog.scene_path(a_piece)
	var packed: PackedScene = load(path) if path != "" else null
	if packed == null:
		build_errors.append("cannot load scene for piece '%s' (%s)" % [a_piece, path])
		return
	var entity := packed.instantiate() as Commandable
	if entity == null:
		build_errors.append("piece '%s' is not a Commandable" % a_piece)
		return
	entity.default_commander_id = roster.commander_id(a_group.slot)
	add_child(entity)
	entity.position = Vector3(a_at.x, 0.0, a_at.y)
	roster.add(a_group.qualified_name(), entity, a_piece)


#endregion


#region Orders
## Issue every group's opening orders. Called with a navigable world, which matters: a
## destination is snapped to the navmesh, and a unit ordered before the first sync would be
## pathing over nothing.
func _on_armed() -> void:
	for reference: String in spec.groups:
		var group: SimSpec.Group = spec.groups[reference]
		if group.orders.is_empty():
			continue
		var members: Array = roster.living(reference)
		var offsets: Array[Vector2] = _group_offsets.get(reference, [] as Array[Vector2])
		for index: int in members.size():
			var unit: Commandable = members[index]
			var offset: Vector2 = offsets[index] if index < offsets.size() else Vector2.ZERO
			var chain: Array[MoveCommand] = _chain_for(group, offset)
			if chain.is_empty():
				continue
			unit.update_commands(chain)
			# Prime the nav target explicitly: NavigationAgent3D defaults target_position to
			# the origin, so a destination AT the origin is otherwise read as "already
			# arrived" and silently dropped (the same trap EventIssueCommand documents).
			unit.load_destination(chain[0])


## One unit's command queue.
##
## An order against a GROUP expands to one command per member of that group, in declaration
## order — so every unit given this chain works the same list in the same order, which is what
## makes focus fire the default. That holds for a POSITIONAL command too: `move: { target: G }`
## is "drive at each of them in turn".
##
## **A `target:` that names a group carries the ENTITY, not a copy of where it stood.**
## `CommandMessage.position` reads `target.global_position` whenever a target is set, so the
## destination tracks the unit for free and a target that walks away is still the thing being
## driven at. Snapshotting it — which this did until 2026-09-12 — sent the truck to a patch of
## empty ground the infantry had already left.
##
## `near:` is the other half of that: it names a PLACE, so it resolves once, at issue time.
func _chain_for(a_group: SimSpec.Group, a_offset: Vector2) -> Array[MoveCommand]:
	var chain: Array[MoveCommand] = []
	for order: SimSpec.Order in a_group.orders:
		if order.target != null:
			_append_entity_commands(chain, order, _targets_of(order.target))
			continue
		var named: String = _group_named_outright(order.position)
		if named != "" and not order.approaches:
			_append_entity_commands(chain, order, roster.living(named))
			continue
		var positional: MoveCommand = _make_command(
			order.command, null, _destination_of(order, a_offset)
		)
		if positional != null:
			chain.append(positional)
	return chain


## One command per entity, each holding that entity. Every command owns its OWN
## CommandMessage: they are ref-counted and must never be shared.
func _append_entity_commands(
	a_chain: Array[MoveCommand], a_order: SimSpec.Order, a_targets: Array
) -> void:
	for target: Commandable in a_targets:
		var command: MoveCommand = _make_command(a_order.command, target, target.global_position)
		if command != null:
			a_chain.append(command)


## The group a placement names OUTRIGHT — a bare `B.armyB` with no offset applied — or "".
##
## An offset (`{ from: B.armyB, distance: 4, bearing: east }`) describes a PLACE derived from a
## group, not the group, so it resolves once like any other place. Only the bare form is the
## thing itself.
func _group_named_outright(a_placement: SimSpec.Placement) -> String:
	if a_placement == null or a_placement.anchor != "":
		return ""
	if a_placement.bearing != "" or a_placement.distance_units != 0.0:
		return ""
	return a_placement.from_ref if roster.has_group(a_placement.from_ref) else ""


## The entities an order's `target:` names, in declaration order. With a `pick` it is at most
## one; without, it is the whole (optionally piece-filtered) living set.
func _targets_of(a_target: SimSpec.TargetRef) -> Array:
	var candidates: Array = roster.living(a_target.group_ref, a_target.piece)
	if not a_target.picks_one() or candidates.is_empty():
		return candidates
	match a_target.pick:
		"first":
			return [candidates[0]]
		"furthest":
			return [_extreme(candidates, false)]
		_:
			return [_extreme(candidates, true)]


## The nearest or furthest candidate from the arena centre. Measuring from the CENTRE rather
## than from the ordering unit keeps a group's members on one shared target — the alternative
## fans a group out over several, which is the spread-fire case a spec expresses by splitting
## the defenders into groups instead.
func _extreme(a_candidates: Array, a_nearest: bool) -> Commandable:
	var best: Commandable = a_candidates[0]
	var best_distance: float = VU.inXZ(best.global_position).length()
	for index: int in range(1, a_candidates.size()):
		var candidate: Commandable = a_candidates[index]
		var distance: float = VU.inXZ(candidate.global_position).length()
		if (distance < best_distance) == a_nearest:
			best = candidate
			best_distance = distance
	return best


## Where a positional order sends one unit: the resolved point plus that unit's own formation
## offset, snapped to the navmesh. Carrying the offset keeps a group's shape as it advances
## instead of every member converging on one post and swirling there.
##
## `near:` (a_order.approaches) pulls the point back to the referenced group's EDGE — its
## own radius plus a standoff — so the order stops beside the group. `target:` drives at the
## point itself, which is what running something over requires.
func _destination_of(a_order: SimSpec.Order, a_offset: Vector2) -> Vector3:
	var target: Vector2 = _resolve_placement(a_order.position, [] as Array[String]) + a_offset
	if a_order.approaches:
		target = _pulled_back_to_edge(a_order.position, target)
	var world := Vector3(target.x, 0.0, target.y)
	if map == null or map.nav_region == null:
		return world
	return NavigationServer3D.map_get_closest_point(map.nav_region.get_navigation_map(), world)


## Pull `a_point` back toward the arena centre by the referenced group's radius, so a `near:`
## order halts at its edge. An `at:`-style reference that names an ANCHOR rather than a group
## has no extent to stand off from, so it is left alone — `near: west` is `target: west`.
func _pulled_back_to_edge(a_placement: SimSpec.Placement, a_point: Vector2) -> Vector2:
	if a_placement == null:
		return a_point
	var reference: String = a_placement.anchor if a_placement.anchor != "" else a_placement.from_ref
	if not roster.has_group(reference):
		return a_point
	var centre: Variant = roster.centroid(reference)
	if centre == null:
		return a_point
	var radius: float = 0.0
	for member: Commandable in roster.living(reference):
		radius = maxf(radius, VU.inXZ(member.global_position - (centre as Vector3)).length())
	var inward: Vector2 = Vector2.ZERO - a_point
	if inward.length() < 0.001:
		return a_point
	return a_point + inward.normalized() * (radius + APPROACH_STANDOFF)


func _make_command(a_name: String, a_target: Commandable, a_position: Vector3) -> MoveCommand:
	var message := CommandMessage.new(map, a_target, null, a_position)
	match a_name:
		"attack":
			return Attack.new(message)
		"attack_move":
			return AttackMove.new(message)
		"defend":
			return Defend.new(message)
		"stop":
			return Stop.new(message)
		_:
			return MoveCommand.new(message)


#endregion


#region Checks
## Compile the spec's expectation tree: one [SimulationCheck] per leaf, plus a resolver that
## folds the tree over their settled verdicts ONCE, at the end of the run.
func _compile_checks() -> Array[SimulationCheck]:
	var compiled: Array[SimulationCheck] = []
	if spec.expect_root == null:
		return compiled
	var leaves: Array[SimSpec.Check] = spec.expect_root.leaves()
	var by_leaf: Dictionary = {}
	for leaf: SimSpec.Check in leaves:
		var check := (
			SimulationCheck
			. new(
				leaf.describe(),
				SimCheckLibrary.predicate(leaf, roster),
				_mode_of(leaf),
				int(round(leaf.deadline_seconds * Engine.physics_ticks_per_second)),
			)
		)
		by_leaf[leaf] = check
		compiled.append(check)
	var root: SimSpec.ExpectNode = spec.expect_root
	_verdict_resolver = func(_a_checks: Array) -> bool:
		var verdicts: Dictionary = {}
		for leaf: SimSpec.Check in by_leaf:
			verdicts[leaf] = (by_leaf[leaf] as SimulationCheck).passed()
		return root.resolve(verdicts)
	return compiled


static func _mode_of(a_leaf: SimSpec.Check) -> SimulationCheck.Mode:
	match a_leaf.mode:
		SimSpec.Check.Mode.LIVENESS:
			return SimulationCheck.Mode.LIVENESS
		SimSpec.Check.Mode.SAFETY:
			return SimulationCheck.Mode.SAFETY
		_:
			return SimulationCheck.Mode.AT_END
#endregion
