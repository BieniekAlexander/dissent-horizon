extends GutTest

## Blueprints — the PLANNED state a structure lives in between "the player ordered it"
## and "a builder laid it down" (Commandable.plan_construction → commit_construction).
##
## A blueprint is the structure itself, not a decorative ghost: one node per ORDER
## (however many builders are walking to it), owned and selectable, and able to take
## train orders the same way a half-built structure can. What it is NOT is physically
## present — no grid cells, no collision, no line of sight, no infrastructure, no place in the
## commander's structure registry — until the builder commits it.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_PlannedStructures.gd -gexit

## A producing structure, so the same blueprint covers both the "can it be selected and
## queued at" and the "does it stay out of the economy" questions.
## A fake producer structure with a fake trainee, both registered as real tools for each test.
const PRODUCER_TYPE: StringName = &"fake_producer"
const TRAINEE_TYPE: StringName = &"fake_trainee"
var _trained_type: StringName = TRAINEE_TYPE
var _producer_tool: Tool


class StubMap:
	extends Map
	var placed: Array = []

	func _ready() -> void:
		pass

	func grid_to_world(a_cell: Vector2i) -> Vector3:
		return Vector3(a_cell.x, 0.0, a_cell.y)

	func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
		return a_coords.x >= 0 and a_coords.x < 17 and a_coords.y >= 0 and a_coords.y < 17

	func add_structure(
		a_structure: Entity, a_world_center: Vector2, _a_rotation: int = 0, _a_rebake: bool = true
	) -> void:
		placed.append({"structure": a_structure, "center": a_world_center})
		structure_cell_map[a_structure] = [world_to_grid(a_world_center)]
		a_structure.map = self
		a_structure.refresh_movement_collision()

	func remove_structure(a_structure: Entity, _a_rebake: bool = true) -> void:
		structure_cell_map.erase(a_structure)


var _world: Node3D
var _map: StubMap
var _commander: Commander


func after_each() -> void:
	FakePieces.restore_tools()


func before_each() -> void:
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
	_commander.add_energy(10000)
	_commander.technology_mapping = {
		PRODUCER_TYPE: FakePieces.tech(200), TRAINEE_TYPE: FakePieces.tech(100)
	}
	_producer_tool = FakePieces.register_tool(
		FakePieces.tool(
			PRODUCER_TYPE,
			{
				"structure": true,
				"produces": [TRAINEE_TYPE],
				"vision": 10.0,
				"dimensions": Vector2i(3, 3)
			}
		)
	)
	FakePieces.register_tool(
		FakePieces.tool(
			TRAINEE_TYPE, FakePieces.PLAIN, [], ControlBinding.ControlContext.TRAIN, [PRODUCER_TYPE]
		)
	)
	# These tests drive production_queue.tick() themselves and await frames to let
	# queue_free settle; the commander's own _physics_process would also run its fog /
	# blackboard perception pass, which needs a scenario rig none of this stands up.
	_commander.set_physics_process(false)


## Map resolves its terrain collider through @onready node paths on tree entry, and
## footprint_origin reads the heightmap's extent, so the stub carries both.
func _make_map() -> StubMap:
	var stub := StubMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	stub.add_child(region)
	var heights := HeightMapShape3D.new()
	heights.map_width = 17
	heights.map_depth = 17
	stub.height_map = heights
	return stub


func _tool() -> Tool:
	return _producer_tool


## The message one build order is issued from, as the controller builds it.
func _order(a_at: Vector2 = Vector2(2.0, 3.0)) -> CommandMessage:
	return CommandMessage.new(_map, null, _tool(), Vector3(a_at.x, 0.0, a_at.y))


func _plan(a_at: Vector2 = Vector2(2.0, 3.0)) -> Commandable:
	var message: CommandMessage = _order(a_at)
	Build.submit_purchase(_commander, message)
	return Build.plan_structure(_commander, message)


#region One order, one blueprint
## Every builder in a multi-select build order gets its own snapshot of the message, but
## they must all point at the SAME blueprint — this is what stopped the old ghost from
## drawing one building per builder (and, with the spread destinations removed, what
## keeps them co-building one structure instead of racing to found several).
func test_every_builder_in_an_order_shares_one_blueprint() -> void:
	var message: CommandMessage = _order()
	Build.submit_purchase(_commander, message)
	var blueprint: Commandable = Build.plan_structure(_commander, message)
	assert_not_null(blueprint, "the order raised a blueprint")

	var snapshots: Array[CommandMessage] = []
	for i in range(4):
		snapshots.append(CommandMessage.deep_copy(message))
	for snapshot: CommandMessage in snapshots:
		assert_same(
			snapshot.planned_structure,
			blueprint,
			"each builder's snapshot points at the one blueprint"
		)


func test_blueprint_stands_on_the_footprint_centre() -> void:
	var blueprint: Commandable = _plan(Vector2(2.0, 3.0))
	# an_barracks is 3×3, so its centre is the clicked cell itself.
	var expected: Vector3 = _map.footprint_centroid(
		_map.footprint_origin(Vector2(2.0, 3.0), Vector2i(3, 3)), Vector2i(3, 3)
	)
	assert_eq(
		blueprint.global_position, expected, "the blueprint stands where the structure will land"
	)


## The safehouse conversion transitions a building that already stands there; there is no
## site to mark, so no blueprint is raised.
func test_no_blueprint_without_a_chosen_structure() -> void:
	assert_null(
		Build.plan_structure(_commander, CommandMessage.new(_map)),
		"a Build with no tool yet plans nothing"
	)


#endregion


#region Not physically there
func test_blueprint_is_intangible() -> void:
	var blueprint: Commandable = _plan()
	assert_eq(
		blueprint.collision_layer & CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
		0,
		"units walk through a building that isn't there yet"
	)
	var target_body := blueprint.get_node_or_null("TargetBody") as StaticBody3D
	if target_body != null:
		assert_eq(
			target_body.collision_layer & CollisionLayers.TARGETABLE_ANY,
			0,
			"nothing can target a blueprint"
		)
		assert_eq(
			target_body.collision_layer & CollisionLayers.Mask.STRUCTURE_BLOCKER,
			0,
			"a blueprint doesn't block line of fire"
		)


func test_blueprint_occupies_no_cells() -> void:
	var blueprint: Commandable = _plan()
	assert_false(_map.structure_cell_map.has(blueprint), "no footprint registered")
	assert_false(blueprint.is_grid_obstruction(), "and so no navmesh hole")


## Ordering a build must not scout the site.
func test_blueprint_grants_no_vision() -> void:
	var blueprint: Commandable = _plan()
	assert_false(blueprint.is_in_group("los"), "a blueprint is not a vision source")


## It's owned enough to be clicked and tinted, but it is not one of the commander's
## buildings: no infrastructure upkeep, and nothing the tech tree or the AI can count.
func test_blueprint_is_not_registered_with_the_commander() -> void:
	var infrastructure_before: int = _commander.infrastructure_required
	var blueprint: Commandable = _plan()
	assert_eq(blueprint.commander, _commander, "it is owned")
	assert_eq(
		_commander.infrastructure_required,
		infrastructure_before,
		"a blueprint costs no infrastructure upkeep"
	)
	assert_false(
		_commander.structure_type_map.get(blueprint.id, Set.new()).contains(blueprint),
		"and isn't in the structure registry"
	)


func test_blueprint_runs_no_per_tick_logic() -> void:
	var blueprint: Commandable = _plan()
	assert_false(
		blueprint.is_physics_processing(),
		"nothing to produce, shoot or die — physics is off until it's placed"
	)


func test_blueprint_is_drawn_at_the_planned_opacity() -> void:
	var blueprint: Commandable = _plan()
	assert_eq(
		blueprint.construction_opacity(),
		MeshVisual.OPACITY_PLANNED,
		"fainter than a structure under construction"
	)
	var visual := blueprint.get_node_or_null("MeshVisual") as MeshVisual
	if visual != null:
		assert_eq(visual.opacity(), MeshVisual.OPACITY_PLANNED, "and the model shows it")


#endregion


#region Selectable, and orderable
func test_blueprint_can_be_selected() -> void:
	var blueprint: Commandable = _plan()
	assert_not_null(blueprint.selectable, "it carries the Selectable the cursor picks")
	blueprint.selectable.select()
	assert_true(blueprint.selectable.is_selected(), "and it can actually be selected")


## The whole point of it being a real entity: units can be queued at a building that
## hasn't been started, exactly as they can at one that's half-built.
func test_blueprint_accepts_train_orders() -> void:
	var blueprint: Commandable = _plan()
	var train_message := CommandMessage.new(_map, null, Tool.for_id(_trained_type))
	assert_eq(
		Train.meets_precondition(blueprint, train_message),
		MoveCommand.PreconditionFailureCause.NONE,
		"a blueprint takes train orders"
	)


## Queued units wait for the building rather than being dropped or trained early — the
## same rule a structure still under construction follows.
func test_units_queued_at_a_blueprint_wait_for_it() -> void:
	var blueprint: Commandable = _plan()
	var energy_before: int = _commander.energy
	var purchase: PurchaseTransaction = _commander.production_queue.submit_train(
		Tool.for_id(_trained_type), [blueprint]
	)
	assert_false(purchase.is_settled(), "the purchase is held, not fulfilled")
	assert_eq(blueprint.production.job_count(), 0, "nothing is training yet")
	# Charged at request time like any affordable purchase — a blueprint is just the extreme
	# case of "no producer is ready yet", and the player has committed to buying this. If the
	# blueprint is later dropped, _prune cancels the purchase and refunds it in full.
	assert_true(purchase.is_funded(), "but it is paid for")
	assert_lt(_commander.energy, energy_before, "so the energy has left the pool")
	assert_true(_commander.production_queue.pending().has(purchase), "it stays queued")


#endregion


#region Placement
func test_committing_makes_the_same_node_the_real_structure() -> void:
	var blueprint: Commandable = _plan(Vector2(2.0, 3.0))
	var infrastructure_before: int = _commander.infrastructure_required
	blueprint.commit_construction(_map, Vector2(2.0, 3.0))

	assert_false(blueprint.is_planned, "it is a real structure now")
	assert_eq(_map.placed.size(), 1, "registered on the grid exactly once")
	assert_same(_map.placed[0]["structure"], blueprint, "and it's the same node")
	assert_true(blueprint.is_physics_processing(), "per-tick logic is on")
	assert_true(blueprint.is_in_group("los"), "it sees for its owner now")
	# Infrastructure follows FINISHING, not starting (see Commandable.advance_build_progress
	# and tests/test_UnfinishedConstruction.gd) — a foundation is not yet a working relay or a
	# load-bearing upkeep, so laying it must not move the pool at all.
	assert_eq(
		_commander.infrastructure_required,
		infrastructure_before,
		"a foundation does not carry its infrastructure upkeep yet"
	)
	assert_almost_eq(
		blueprint.build_progress,
		Commandable.INITIAL_BUILD_PROGRESS,
		0.0001,
		"construction has started"
	)
	assert_eq(
		blueprint.construction_opacity(),
		MeshVisual.OPACITY_CONSTRUCTING,
		"and it is drawn as under construction"
	)


func test_committing_starts_construction_hp() -> void:
	var blueprint: Commandable = _plan()
	blueprint.commit_construction(_map, Vector2(2.0, 3.0))
	assert_almost_eq(
		blueprint.defense.hp,
		blueprint.defense.hp_max * Commandable.INITIAL_HEALTH_FACTOR,
		0.001,
		"a just-founded structure starts at the construction hp fraction"
	)


## Committing is what releases the purchase's claim on the node — a later cancel must
## never free a building that now exists.
func test_a_consumed_purchase_no_longer_owns_the_blueprint() -> void:
	var message: CommandMessage = _order()
	var purchase: PurchaseTransaction = Build.submit_purchase(_commander, message)
	var blueprint: Commandable = Build.plan_structure(_commander, message)
	purchase.consume()
	purchase.cancel()
	assert_true(is_instance_valid(blueprint), "the placed structure survives the cancel")
	assert_false(blueprint.is_queued_for_deletion(), "and isn't queued for deletion")


#endregion


#region Cancellation and refunds
## Abandoning the order — every builder killed or re-tasked — refunds the reserved cost
## and takes the blueprint down with it.
func test_cancelling_the_order_refunds_and_removes_the_blueprint() -> void:
	var energy_before: int = _commander.energy
	var message: CommandMessage = _order()
	var purchase: PurchaseTransaction = Build.submit_purchase(_commander, message)
	var blueprint: Commandable = Build.plan_structure(_commander, message)
	assert_lt(_commander.energy, energy_before, "the build cost was reserved")

	purchase.cancel()
	assert_eq(_commander.energy, energy_before, "cancelling refunds it")
	assert_true(blueprint.is_queued_for_deletion(), "and the blueprint comes down")


## Units queued at a blueprint whose order is cancelled lose their only producer, so the
## purchase is dropped rather than left blocking the queue forever.
func test_cancelling_the_order_drops_units_queued_at_the_blueprint() -> void:
	var message: CommandMessage = _order()
	var purchase: PurchaseTransaction = Build.submit_purchase(_commander, message)
	var blueprint: Commandable = Build.plan_structure(_commander, message)
	var train: PurchaseTransaction = _commander.production_queue.submit_train(
		Tool.for_id(_trained_type), [blueprint]
	)
	var energy_after_order: int = _commander.energy

	purchase.cancel()
	await get_tree().process_frame  # queue_free settles

	_commander.production_queue.tick()
	assert_false(
		_commander.production_queue.pending().has(train),
		"the unit purchase is dropped with the building it was queued at"
	)
	assert_true(train.is_settled(), "and settled, not left dangling")
	assert_gte(_commander.energy, energy_after_order, "no energy was kept for it")


## A destroyed producer must not swallow the energy for units it never trained: jobs already
## in its own queue are refunded here...
func test_destroying_a_producer_refunds_its_queued_jobs() -> void:
	var structure: Commandable = _tool().packed_scene.instantiate()
	structure.initialize(_map, _commander)
	var cost: int = _commander.technology_mapping.get(_trained_type).energy_cost
	_commander.add_energy(-cost)
	var energy_before: int = _commander.energy
	structure.production.enqueue(100, null, _trained_type)

	structure._on_death()
	assert_eq(
		_commander.energy,
		energy_before + cost,
		"the queued unit's cost comes back when its barracks dies"
	)


## ...and purchases still waiting in the commander's global queue for that producer are
## dropped on the next tick, since nothing can fulfil them any more.
func test_destroying_a_producer_drops_purchases_waiting_on_it() -> void:
	var structure: Commandable = _tool().packed_scene.instantiate()
	# Still going up, so the purchase waits at it rather than being dispatched at once —
	# which is exactly the state that would strand energy if the building were lost.
	structure.begin_construction()
	structure.initialize(_map, _commander)
	var train: PurchaseTransaction = _commander.production_queue.submit_train(
		Tool.for_id(_trained_type), [structure]
	)
	assert_true(_commander.production_queue.pending().has(train), "queued at the structure")

	structure._on_death()
	await get_tree().process_frame  # queue_free settles

	_commander.production_queue.tick()
	assert_false(
		_commander.production_queue.pending().has(train),
		"the purchase is dropped once its only producer is gone"
	)
	assert_true(train.is_settled(), "and refunded/settled")


#endregion

#region A plan claims its site
const CLAIM_AT: Vector2 = Vector2(-4.0, -4.0)


## A blueprint holds no grid cells, but its footprint is spoken for: this is what refuses a
## second plan on the same ground (Build.meets_precondition → SITE_PLANNED).
##
## Planned at CLAIM_AT: StubMap's grid_to_world skips the map's centring offset, so a blueprint
## stands off its order's cells, and this aim keeps where it stands inside the stub's bounds.
func test_a_blueprint_claims_its_footprint() -> void:
	var blueprint: Commandable = _plan(CLAIM_AT)
	var dims: Vector2i = (blueprint.get_node("Structure") as Structure).dimensions
	var footprint: Array = _map.footprint_cells(VU.in_xz(blueprint.global_position), dims)
	assert_eq(footprint.size(), dims.x * dims.y, "guards the fixture: it stands in bounds")
	var claimed: Dictionary = _commander.planned_footprint_cells()
	for cell: Vector2i in footprint:
		assert_true(claimed.has(cell), "cell %s is claimed" % cell)
	assert_eq(claimed.size(), footprint.size())


## The order asking about its own site must not be refused by its own blueprint.
func test_an_order_does_not_collide_with_its_own_blueprint() -> void:
	var blueprint: Commandable = _plan(CLAIM_AT)
	assert_true(_commander.planned_footprint_cells(blueprint).is_empty())


## Once laid, the building holds real cells; the plan no longer claims anything.
func test_a_committed_blueprint_stops_claiming() -> void:
	var blueprint: Commandable = _plan(CLAIM_AT)
	blueprint.commit_construction(_map, CLAIM_AT)
	assert_true(_commander.planned_footprint_cells().is_empty())
#endregion
