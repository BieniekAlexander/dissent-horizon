extends GutTest

## A piece built FROM another piece's form — the Anarchical an_infrastructure, built from a
## neutral building (`variants:` in its doc) — and its CONVERSION out of a neutral building where
## it stands. Both routes make the same piece through one routine (Repurposing), and price and time
## it from the underlying form's own numbers.
##
## Every expectation is read from the pieces' templates (PieceFamilies) or from the target piece's
## own scene, never typed in: which forms exist and what they cost is authored content, and the
## mechanic must hold whatever they are. Where a mechanic needs prices that DIFFER between forms,
## the test sets them on its own commander.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_VariantBuild.gd -gexit

const TOOL_NAME: String = "command_tool_an_infrastructure"
const BUILDER_SCENE: Dictionary = {
	"speed": 2.0, "vision": 8.0, "builds": [&"an_infrastructure", &"fake_plain"]
}
const EXTRACTION_SITE_SCENE: Dictionary = FakePieces.BUILDING
## Height-map corner count; the cell grid is one smaller in each axis.
const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1
const SITE: Vector2 = Vector2(4.0, 4.0)
## Where a neutral building's footprint starts, clear of the map edge whatever its size.
const NEUTRAL_ORIGIN: Vector2i = Vector2i(2, 2)
## Fixture prices, distinct so a test can tell which form priced an order.
const FIRST_FORM_PRICE: int = 111
const SECOND_FORM_PRICE: int = 222


## A Map with a real TerrainGrid (so flatness answers) and a hand-managed cell grid, none of the
## navmesh/terrain loading. add_structure records the footprint the piece's OWN Structure declares,
## which is what every assertion about "the variant's footprint" reads.
class StubMap:
	extends Map
	var placed: Array = []

	func _ready() -> void:
		cell_grid = []
		for x: int in GRID_CELLS:
			var col: Array = []
			for y: int in GRID_CELLS:
				col.append(null)
			cell_grid.append(col)
		terrain_grid = TerrainGrid.new()
		terrain_grid.height_map = height_map
		terrain_grid.terrain_body = terrain_body
		add_child(terrain_grid)

	func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
		return (
			a_coords.x >= 0
			and a_coords.x < GRID_CELLS
			and a_coords.y >= 0
			and a_coords.y < GRID_CELLS
		)

	func add_structure(
		a_structure: Entity, a_world_center: Vector2, _a_rotation: int = 0, _a_rebake: bool = true
	) -> void:
		placed.append(a_structure)
		var obs := a_structure.get_node("Structure") as Structure
		var footprint: Array[Vector2i] = footprint_cells(a_world_center, obs.dimensions)
		for cell: Vector2i in footprint:
			cell_grid[cell.x][cell.y] = a_structure
		structure_cell_map[a_structure] = footprint
		a_structure.global_position = footprint_centroid(
			footprint_origin(a_world_center, obs.dimensions), obs.dimensions
		)
		a_structure.map = self
		a_structure.refresh_movement_collision()

	func remove_structure(a_structure: Entity, _a_rebake: bool = true) -> void:
		structure_cell_map.erase(a_structure)


var _world: Node3D
var _map: StubMap
var _commander: Commander
var _neutral: Commander
## The fake neutral-building family the tool's variants are drawn from, and a tool with none.
const FAMILY: Array[Dictionary] = [
	{
		"id": &"fake_nb_square",
		"family": &"neutral_building",
		"footprint": Vector2i(4, 4),
		"options": {"garrison": {"capacity": 4}, "vision": 6.0}
	},
	{
		"id": &"fake_nb_long",
		"family": &"neutral_building",
		"footprint": Vector2i(3, 5),
		"options": {"garrison": {"capacity": 4}, "vision": 6.0}
	},
]


func after_each() -> void:
	FakePieces.restore_families()
	FakePieces.restore_tools()


func before_each() -> void:
	FakePieces.install_families(FAMILY)
	var variants: Array[StringName] = [&"fake_nb_square", &"fake_nb_long"]
	FakePieces.register_tool(
		FakePieces.tool(
			EntityIds.AN_INFRASTRUCTURE,
			{
				"structure": true,
				"dimensions": Vector2i(4, 4),
				"vision": 12.0,
				"garrison": {"capacity": 4, "frames": Garrison.FRAME_BIO}
			},
			variants
		)
	)
	FakePieces.register_tool(
		FakePieces.tool(&"fake_plain", {"structure": true, "dimensions": Vector2i(3, 3)})
	)
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_neutral = Commander.new()
	_neutral.id = 0
	_world.add_child(_neutral)
	_neutral.map = _map
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
	_commander.add_energy(100000)
	_commander.set_physics_process(false)
	_neutral.set_physics_process(false)
	_commander.technology_mapping = {
		EntityIds.AN_INFRASTRUCTURE: FakePieces.tech(),
		&"fake_plain": FakePieces.tech(),
		&"fake_nb_square": FakePieces.tech(20),
		&"fake_nb_long": FakePieces.tech(30)
	}


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
	heights.map_width = MAP_CORNERS
	heights.map_depth = MAP_CORNERS
	heights.map_data = PackedFloat32Array()
	heights.map_data.resize(MAP_CORNERS * MAP_CORNERS)
	stub.height_map = heights
	return stub


#region Helpers
func _base_tool() -> Tool:
	return Tool.for_name(TOOL_NAME)


func _template(a_id: StringName) -> PieceFamilies.Template:
	return PieceFamilies.template(a_id)


## A builder that may build the piece, standing at `a_at`.
func _make_builder(a_at: Variant) -> Commandable:
	var at: Vector2 = _xz(a_at)
	var builder: Commandable = FakePieces.make(BUILDER_SCENE) as Commandable
	_world.add_child(builder)
	var builds := builder.get_node("Builds") as Builds
	builds.buildable_types = [_base_tool().type]
	builder.ownership.commander = _commander
	builder.map = _map
	builder.global_position = Vector3(at.x, 0.0, at.y)
	return builder


func _order(a_tool: Tool, a_at: Variant) -> CommandMessage:
	var at: Vector2 = _xz(a_at)
	return CommandMessage.new(_map, null, a_tool, Vector3(at.x, 0.0, at.y))


## A world position given as either a Vector2 (XZ) or a Vector3.
func _xz(a_at: Variant) -> Vector2:
	return VU.inXZ(a_at) if a_at is Vector3 else a_at as Vector2


## Scenes instanced here ship without flavor text, which Commandable reports with a push_error
## GUT would count as a failure: a content gap unrelated to what is under test, dismissed by
## message only.
func _dismiss_known_errors() -> void:
	for tracked in get_errors():
		if (
			tracked.contains_text("was given an empty description")
			or tracked.contains_text("was given an empty verbose description")
			or tracked.contains_text("entered the tree with no")
		):
			tracked.handled = true


## A neutral building of `a_id`, owned by the neutral commander and registered on the map at
## `a_origin` with the footprint its own scene declares.
func _neutral_building(a_id: StringName, a_origin: Vector2i = NEUTRAL_ORIGIN) -> Commandable:
	var building: Commandable = _template(a_id).load_scene().instantiate() as Commandable
	_neutral.add_child(building)
	building.initialize(_map, _neutral)
	_dismiss_known_errors()
	var dims: Vector2i = (building.get_node("Structure") as Structure).dimensions
	_map.add_structure(building, VU.inXZ(_map.footprint_centroid(a_origin, dims)))
	return building


## Take a structure off the world entirely: both commanders' books, the grid, then the node.
func _discard(a_node: Commandable) -> void:
	_commander.remove_structure(a_node)
	_neutral.remove_structure(a_node)
	a_node.free()
	_map.structure_cell_map.clear()
	_map.placed.clear()
	for x: int in GRID_CELLS:
		for y: int in GRID_CELLS:
			_map.cell_grid[x][y] = null
	_commander.infrastructure_provided = Commander.BASE_INFRASTRUCTURE


func _family() -> Array[PieceFamilies.Template]:
	return PieceFamilies.templates_of(PieceFamilies.NEUTRAL_BUILDING)


## The target piece's own scene, instanced — the reference for what a converted or built
## an_infrastructure must carry.
func _target_instance() -> Commandable:
	var instance: Commandable = (
		Tool.for_id(EntityIds.AN_INFRASTRUCTURE).packed_scene.instantiate() as Commandable
	)
	autofree(instance)
	return instance


func _garrison_frames(a_node: Node) -> int:
	return (a_node.get_node("Garrison") as Garrison).occupiable_frames


## Fixture prices that tell the first two forms apart.
func _price_forms_distinctly() -> void:
	var variants: Array[StringName] = _base_tool().variants
	_commander.technology_mapping[variants[0]].energy_cost = FIRST_FORM_PRICE
	_commander.technology_mapping[variants[1]].energy_cost = SECOND_FORM_PRICE


#endregion


#region The variant-bound tool
func test_an_unbound_tool_of_a_piece_with_variants_is_not_bound() -> void:
	var base: Tool = _base_tool()
	assert_false(base.is_variant_bound())
	assert_eq(base.variant_index(), -1)
	assert_gt(
		base.variants.size(), 1, "the piece offers more than one form (the fixture of these tests)"
	)


func test_a_tool_resolves_to_its_default_variant() -> void:
	var base: Tool = _base_tool()
	var resolved: Tool = base.resolved()
	assert_eq(resolved.variant, base.variants[0], "the default is the first variant")
	assert_eq(resolved.variant_index(), 0)
	assert_same(resolved.resolved(), resolved, "a bound tool is already concrete")


func test_a_bound_tool_keeps_its_piece_and_takes_its_variants_scene() -> void:
	var base: Tool = _base_tool()
	for i: int in base.variants.size():
		var bound: Tool = base.with_variant(i)
		assert_eq(bound.type, base.type, "still the same piece, for tech and accounting")
		assert_eq(bound.command_name, base.command_name, "and the same button")
		assert_eq(bound.packed_scene.resource_path, _template(base.variants[i]).scene_path)
		assert_eq(bound.variant_index(), i)
		assert_eq(bound.variant_label(), _template(base.variants[i]).title)


func test_variant_index_wraps_in_both_directions() -> void:
	var base: Tool = _base_tool()
	var count: int = base.variants.size()
	assert_eq(base.with_variant(count).variant_index(), 0, "past the end is the first")
	assert_eq(base.with_variant(-1).variant_index(), count - 1, "before the start is the last")


func test_next_variant_cycles_and_wraps() -> void:
	var base: Tool = _base_tool()
	var tool: Tool = base.resolved()
	for i: int in base.variants.size():
		assert_eq(tool.variant_index(), i)
		tool = tool.next_variant()
	assert_eq(tool.variant_index(), 0, "after the last it is the first again")
	assert_eq(
		base.next_variant().variant_index(),
		1 % base.variants.size(),
		"from an unbound tool (which already means the first) the next is the second"
	)


func test_binding_the_same_variant_twice_is_the_same_tool() -> void:
	var base: Tool = _base_tool()
	assert_same(base.with_variant(1), base.with_variant(1))
	assert_same(base.with_variant(0).next_variant().next_variant(), base.with_variant(0))


func test_each_variant_previews_under_its_own_key() -> void:
	var base: Tool = _base_tool()
	assert_ne(base.with_variant(0).preview_key(), base.with_variant(1).preview_key())
	assert_eq(base.resolved().preview_key(), base.with_variant(0).preview_key())
	var first: Node = _commander.get_build_preview_instance(base.with_variant(0))
	var second: Node = _commander.get_build_preview_instance(base.with_variant(1))
	assert_ne(first, second, "one cached instance per variant")
	assert_same(_commander.get_build_preview_instance(base.with_variant(0)), first)
	assert_same(
		_commander.get_build_preview_instance(base), first, "an unbound tool previews its default"
	)


func test_a_tool_of_a_piece_without_variants_is_unchanged_by_all_of_it() -> void:
	var plain: Tool = Tool.for_name("command_tool_fake_plain")
	assert_same(plain.resolved(), plain)
	assert_same(plain.with_variant(3), plain)
	assert_same(plain.next_variant(), plain)
	assert_eq(plain.price_id(), plain.type)


func test_an_order_carries_a_concrete_tool() -> void:
	var base: Tool = _base_tool()
	assert_same(_order(base, SITE).tool, base.with_variant(0), "the default when nobody chose")
	assert_same(_order(base.with_variant(1), SITE).tool, base.with_variant(1), "a choice is kept")
	assert_null(CommandMessage.new(_map).tool)


#endregion


#region The shared routine
func test_every_underlying_form_becomes_the_piece_it_is_built_from() -> void:
	var donor: Commandable = _target_instance()
	for template: PieceFamilies.Template in _family():
		var node: Commandable = template.load_scene().instantiate() as Commandable
		autofree(node)
		var frames_before: int = _garrison_frames(node)
		Repurposing.into(node, EntityIds.AN_INFRASTRUCTURE)
		var label: String = String(template.id)

		assert_eq(node.id, EntityIds.AN_INFRASTRUCTURE, "%s takes the piece's id" % label)
		assert_eq(node.built_from, template.id, "%s remembers what priced it" % label)
		assert_eq(node.pricing_id(), template.id)
		assert_eq(node.infrastructure, template.infrastructure, "%s's own infrastructure" % label)
		assert_eq(
			(node.get_node("Structure") as Structure).dimensions,
			template.footprint,
			"%s keeps its footprint" % label
		)
		assert_eq(
			(node.get_node("Defense") as Defense).hp_max, template.hp, "%s keeps its HP" % label
		)
		assert_eq(
			_garrison_frames(node),
			_garrison_frames(donor),
			"%s takes the piece's garrison masks" % label
		)
		assert_ne(
			_garrison_frames(node), frames_before, "which are a change from the neutral building's"
		)
		var garrison := node.get_node("Garrison") as Garrison
		var donor_garrison := donor.get_node("Garrison") as Garrison
		assert_eq(garrison.range_bonus, donor_garrison.range_bonus)
		assert_eq(garrison.occupiable_armours, donor_garrison.occupiable_armours)
		var defense := node.get_node("Defense") as Defense
		var donor_defense := donor.get_node("Defense") as Defense
		assert_eq(
			defense.armour_type, donor_defense.armour_type, "%s takes the piece's armour" % label
		)
		assert_eq(defense.frame_type, donor_defense.frame_type)
		assert_same(
			(node.get_node("VisionRange") as CollisionShape3D).shape,
			(donor.get_node("VisionRange") as CollisionShape3D).shape,
			"and its vision"
		)
		assert_false(
			node.is_in_group(template.family), "%s is no longer a neutral building" % label
		)


## The routine reads the target's SCENE, so what it copies is whatever that scene authored — proved
## on a fixture target that authors values no shipped piece does, with a footprint-side value (HP)
## it must leave alone.
func test_the_routine_copies_what_the_target_scene_authors_and_only_that() -> void:
	var target_root := Commandable.new()
	target_root.name = "Target"
	var defense := Defense.new()
	defense.name = "Defense"
	defense.armour_type = Defense.ArmourType.STRONG
	defense.hp_max = 12345.0
	target_root.add_child(defense)
	defense.owner = target_root
	var garrison := Garrison.new()
	garrison.name = "Garrison"
	garrison.range_bonus = 77.0
	garrison.capacity = 9
	target_root.add_child(garrison)
	garrison.owner = target_root
	var packed := PackedScene.new()
	assert_eq(packed.pack(target_root), OK)
	target_root.free()

	var node := Commandable.new()
	autofree(node)
	node.id = &"some_form"
	node.infrastructure = 40
	var own_defense := Defense.new()
	own_defense.name = "Defense"
	own_defense.hp_max = 500.0
	node.add_child(own_defense)
	var own_garrison := Garrison.new()
	own_garrison.name = "Garrison"
	node.add_child(own_garrison)

	Repurposing._copy_authored(node, packed.get_state())

	assert_eq(own_defense.armour_type, Defense.ArmourType.STRONG, "an authored armour travels")
	assert_eq(own_garrison.range_bonus, 77.0, "an authored range bonus travels")
	assert_eq(own_garrison.capacity, 9, "and so does any other authored garrison value")
	assert_eq(own_defense.hp_max, 500.0, "HP stays the building's own")
	assert_eq(node.infrastructure, 40, "so does infrastructure, which is set from the template")


#endregion


#region Building a variant
func test_a_new_build_of_each_variant_is_that_variants_body_with_the_pieces_properties() -> void:
	var base: Tool = _base_tool()
	for i: int in base.variants.size():
		var template: PieceFamilies.Template = _template(base.variants[i])
		var builder: Commandable = _make_builder(SITE)
		var message: CommandMessage = _order(base.with_variant(i), SITE)
		var command := Build.new(message)
		var next: Variant = command.fulfill_action(builder)
		_dismiss_known_errors()

		assert_true(next is Assemble, "the builder goes on to build what it placed")
		var built: Commandable = _map.placed[0] as Commandable
		var label: String = String(template.id)
		assert_eq(built.id, EntityIds.AN_INFRASTRUCTURE, "%s is built as the piece" % label)
		assert_eq(built.scene_file_path, template.scene_path, "from its own scene")
		assert_eq(built.infrastructure, template.infrastructure)
		assert_eq((built.get_node("Structure") as Structure).dimensions, template.footprint)
		assert_eq(
			_map.structure_cell_map[built].size(),
			template.footprint.x * template.footprint.y,
			"and it holds that footprint on the grid"
		)
		assert_eq((built.get_node("Defense") as Defense).hp_max, template.hp)
		assert_false(built.is_built, "under construction")
		assert_lt(
			(built.get_node("Defense") as Defense).hp,
			template.hp,
			"with the HP of an unfinished construction"
		)
		assert_eq(built.commander, _commander)
		assert_true(
			_commander.structure_type_map[EntityIds.AN_INFRASTRUCTURE].contains(built),
			"counted as the piece for the tech tree"
		)
		assert_eq(
			_commander.infrastructure_provided,
			Commander.BASE_INFRASTRUCTURE,
			"but it provides nothing until it is finished"
		)
		assert_true(built.advance_build_progress(1.0), "finishing it")
		assert_eq(
			_commander.infrastructure_provided,
			Commander.BASE_INFRASTRUCTURE + template.infrastructure,
			"credits exactly the form's own infrastructure"
		)
		_discard(built)
		builder.free()


func test_a_finished_build_is_timed_by_its_form() -> void:
	var base: Tool = _base_tool()
	_commander.technology_mapping[base.variants[0]].creation_time = 100
	_commander.technology_mapping[base.variants[1]].creation_time = 1000
	var first: Commandable = _template(base.variants[0]).load_scene().instantiate() as Commandable
	var second: Commandable = _template(base.variants[1]).load_scene().instantiate() as Commandable
	autofree(first)
	autofree(second)
	Repurposing.into(first, base.type)
	Repurposing.into(second, base.type)
	_world.add_child(first)
	_world.add_child(second)
	first.ownership.commander = _commander
	second.ownership.commander = _commander
	_dismiss_known_errors()
	assert_gt(
		first.effective_build_increment(),
		second.effective_build_increment(),
		"the form priced at fewer ticks is built faster, though both are the same piece"
	)


func test_an_order_is_priced_and_timed_by_its_variant() -> void:
	_price_forms_distinctly()
	var base: Tool = _base_tool()
	for i: int in base.variants.size():
		var transaction: PurchaseTransaction = PurchaseTransaction.for_tool(
			_commander, PurchaseTransaction.Kind.BUILD, base.with_variant(i)
		)
		var spec: TechnologySpec = _commander.technology_mapping[base.variants[i]]
		assert_eq(transaction.energy_cost, spec.energy_cost)
		assert_eq(transaction.creation_time, spec.creation_time)
		assert_eq(transaction.type, base.type, "still a purchase of the piece")
	assert_eq(
		(
			PurchaseTransaction
			. for_tool(_commander, PurchaseTransaction.Kind.BUILD, base.with_variant(0))
			. energy_cost
		),
		FIRST_FORM_PRICE
	)


func test_the_energy_gate_reads_the_armed_variants_price() -> void:
	_price_forms_distinctly()
	var base: Tool = _base_tool()
	_commander.energy = (FIRST_FORM_PRICE + SECOND_FORM_PRICE) / 2
	assert_eq(_commander.get_unmet_need_for(base.with_variant(0)), TechnologySpec.UnmetNeed.NONE)
	assert_eq(
		_commander.get_unmet_need_for(base.with_variant(1)),
		TechnologySpec.UnmetNeed.NOT_ENOUGH_ENERGY
	)
	assert_eq(
		_commander.get_blocking_need_for(base.with_variant(1), false),
		TechnologySpec.UnmetNeed.NOT_ENOUGH_ENERGY
	)
	assert_eq(
		_commander.get_blocking_need_for(base.with_variant(1), true),
		TechnologySpec.UnmetNeed.NONE,
		"an unaffordable price is queued when deferral is allowed"
	)


func test_placement_validity_uses_the_variants_footprint() -> void:
	var base: Tool = _base_tool()
	var footprints: Array[Vector2i] = []
	for i: int in base.variants.size():
		var dims: Vector2i = _template(base.variants[i]).footprint
		footprints.append(dims)
		assert_eq(Build._tool_dimensions(_commander, base.with_variant(i)), dims)
		# Aimed where the footprint would spill over an occupied cell only if it is that wide.
		var origin: Vector2i = _map.footprint_origin(SITE, dims)
		var far_cell: Vector2i = origin + dims - Vector2i.ONE
		_map.cell_grid[far_cell.x][far_cell.y] = Node3D.new()
		var blocked: Node = _map.cell_grid[far_cell.x][far_cell.y]
		assert_false(
			Structure.valid_placement(_order(base.with_variant(i), SITE), dims),
			"the variant's own far corner blocks it"
		)
		_map.cell_grid[far_cell.x][far_cell.y] = null
		blocked.free()
		assert_true(Structure.valid_placement(_order(base.with_variant(i), SITE), dims))


func test_the_blueprint_and_its_reservation_use_the_variants_footprint() -> void:
	var base: Tool = _base_tool()
	for i: int in base.variants.size():
		var template: PieceFamilies.Template = _template(base.variants[i])
		var message: CommandMessage = _order(base.with_variant(i), SITE)
		Build.submit_purchase(_commander, message)
		var blueprint: Commandable = Build.plan_structure(_commander, message)
		_dismiss_known_errors()
		assert_not_null(blueprint)
		assert_eq(blueprint.id, EntityIds.AN_INFRASTRUCTURE)
		assert_eq((blueprint.get_node("Structure") as Structure).dimensions, template.footprint)
		assert_eq(
			_commander.planned_footprint_cells().size(),
			template.footprint.x * template.footprint.y,
			"the reservation covers the variant's cells"
		)
		message.transaction.cancel()
		_dismiss_known_errors()
		assert_true(_commander.planned_footprint_cells().is_empty(), "and goes with the order")


## The CPU commander orders a piece by id; it gets the default form, sized and priced as that form.
func test_an_order_by_id_alone_is_the_default_variant() -> void:
	var by_id: Tool = Tool.for_type(EntityIds.AN_INFRASTRUCTURE)
	var default: PieceFamilies.Template = _template(by_id.variants[0])
	var preview: Commandable = _commander.get_build_preview_instance(by_id) as Commandable
	assert_eq((preview.get_node("Structure") as Structure).dimensions, default.footprint)
	assert_eq(preview.infrastructure, default.infrastructure)
	var transaction: PurchaseTransaction = PurchaseTransaction.for_tool(
		_commander, PurchaseTransaction.Kind.BUILD, _order(by_id, SITE).tool
	)
	assert_eq(transaction.energy_cost, _commander.technology_mapping[by_id.variants[0]].energy_cost)


#endregion


#region Conversion
## Converts `a_building` with `a_tool` armed, returns [seconds it took, the transaction].
func _convert(a_building: Commandable, a_tool: Tool, a_aim: Vector2) -> Array:
	var message: CommandMessage = _order(a_tool, a_aim)
	var transaction: PurchaseTransaction = Build.submit_purchase(_commander, message)
	var builder: Commandable = _make_builder(a_building.global_position)
	var command := Build.new(message)
	await wait_physics_frames(1)
	var delta: float = builder.get_physics_process_delta_time()
	var ticks: int = 0
	var limit: int = 100000
	while command.fulfill_action(builder) != null and ticks < limit:
		ticks += 1
	return [float(ticks + 1) * delta, transaction]


func test_any_neutral_building_converts_whichever_variant_is_armed() -> void:
	var base: Tool = _base_tool()
	for template: PieceFamilies.Template in _family():
		for i: int in base.variants.size():
			var building: Commandable = _neutral_building(template.id)
			var message: CommandMessage = _order(base.with_variant(i), building.global_position)
			assert_same(
				Build._conversion_target(_commander, message),
				building,
				"%s converts with variant %d armed" % [template.id, i]
			)
			assert_false(
				Build.places_new_structure(_commander, message),
				"and aiming at it lays no new structure"
			)
			_discard(building)


func test_the_target_is_the_building_whose_footprint_holds_the_aimed_cell() -> void:
	var building: Commandable = _neutral_building(_family().back().id)
	var footprint: Array = _map.structure_cell_map[building]
	for cell: Vector2i in footprint:
		var message: CommandMessage = _order(_base_tool(), VU.inXZ(_map.grid_to_world(cell)))
		assert_same(
			Build._conversion_target(_commander, message),
			building,
			"any cell of the footprint aims at it, not only the middle"
		)
	var outside: Vector2i = footprint.back() + Vector2i(2, 2)
	var away: CommandMessage = _order(_base_tool(), VU.inXZ(_map.grid_to_world(outside)))
	assert_null(Build._conversion_target(_commander, away), "a cell beside it does not")
	assert_true(Build.places_new_structure(_commander, away))


func test_only_a_neutral_family_member_is_a_target() -> void:
	var building: Commandable = _neutral_building(_family()[0].id)
	var aim: Vector2 = VU.inXZ(building.global_position)
	building.commander = _commander
	assert_null(
		Build._conversion_target(_commander, _order(_base_tool(), aim)), "an owned building is not"
	)
	var site: Entity = FakePieces.make(EXTRACTION_SITE_SCENE) as Entity
	_neutral.add_child(site)
	site.initialize(_map, _neutral)
	_dismiss_known_errors()
	_map.add_structure(site, VU.inXZ(_map.footprint_centroid(Vector2i(10, 10), Vector2i(2, 2))))
	assert_null(
		Build._conversion_target(_commander, _order(_base_tool(), VU.inXZ(site.global_position))),
		"a neutral piece outside the family is not"
	)


func test_a_conversion_costs_and_takes_the_targets_discounted_numbers() -> void:
	var base: Tool = _base_tool()
	for template: PieceFamilies.Template in _family():
		var building: Commandable = _neutral_building(template.id)
		var energy_before: int = _commander.energy
		var result: Array = await _convert(
			building, base.with_variant(0), VU.inXZ(building.global_position)
		)
		_dismiss_known_errors()
		var transaction: PurchaseTransaction = result[1]
		var expected_energy: int = roundi(float(template.energy_cost) * Build.ENERGY_DISCOUNT)
		var expected_seconds: float = (
			TimeUtils.seconds_from_ticks(template.build_time_ticks) * Build.BUILD_TIME_DISCOUNT
		)
		assert_eq(transaction.energy_cost, expected_energy, "%s's price" % template.id)
		assert_eq(energy_before - _commander.energy, expected_energy, "is what it debited")
		assert_almost_eq(float(result[0]), expected_seconds, 0.1, "%s's time" % template.id)
		_discard(building)
		_commander.infrastructure_provided = Commander.BASE_INFRASTRUCTURE


func test_a_conversion_is_refused_without_the_discounted_price_unless_deferred() -> void:
	var template: PieceFamilies.Template = _family()[0]
	var building: Commandable = _neutral_building(template.id)
	var builder: Commandable = _make_builder(building.global_position)
	var message: CommandMessage = _order(_base_tool(), VU.inXZ(building.global_position))
	var price: int = roundi(float(template.energy_cost) * Build.ENERGY_DISCOUNT)
	_commander.energy = price - 1
	message.defer_if_unaffordable = false
	assert_eq(
		Build.meets_precondition(builder, message),
		MoveCommand.PreconditionFailureCause.NOT_ENOUGH_ENERGY
	)
	_commander.energy = price
	assert_eq(
		Build.meets_precondition(builder, message),
		MoveCommand.PreconditionFailureCause.NONE,
		"the discounted price is enough, where the full one would not be"
	)
	_commander.energy = 0
	message.defer_if_unaffordable = true
	assert_eq(
		Build.meets_precondition(builder, message),
		MoveCommand.PreconditionFailureCause.NONE,
		"an unaffordable conversion is queued under the additive modifier"
	)


func test_a_converted_building_is_the_piece_in_the_building_it_was() -> void:
	var base: Tool = _base_tool()
	var donor: Commandable = _target_instance()
	for template: PieceFamilies.Template in _family():
		var building: Commandable = _neutral_building(template.id)
		var defense := building.get_node("Defense") as Defense
		defense.hp = defense.hp_max * .5
		var hp_before: float = defense.hp
		var footprint_before: Array = _map.structure_cell_map[building].duplicate()
		var frames_before: int = _garrison_frames(building)
		var infrastructure_before: int = _commander.infrastructure_provided

		await _convert(
			building, base.with_variant(base.variants.size() - 1), VU.inXZ(building.global_position)
		)
		_dismiss_known_errors()
		var label: String = String(template.id)

		assert_eq(building.commander, _commander, "%s is ours" % label)
		assert_eq(building.id, EntityIds.AN_INFRASTRUCTURE)
		assert_eq(defense.hp, hp_before, "%s keeps its HP" % label)
		assert_eq((building.get_node("Structure") as Structure).dimensions, template.footprint)
		assert_eq(_map.structure_cell_map[building], footprint_before, "and its cells")
		assert_ne(_garrison_frames(building), frames_before, "%s's garrison masks changed" % label)
		assert_eq(_garrison_frames(building), _garrison_frames(donor), "to the piece's own")
		assert_eq(_garrison_frames(building), Garrison.FRAME_BIO, "which admit flesh only")
		assert_eq(building.infrastructure, template.infrastructure)
		assert_eq(
			_commander.infrastructure_provided,
			infrastructure_before + template.infrastructure,
			"the commander is credited exactly the building's own value"
		)
		assert_true(_commander.structure_type_map[EntityIds.AN_INFRASTRUCTURE].contains(building))
		assert_false(
			_neutral.structure_type_map.get(template.id, Set.new()).contains(building),
			"and it is off the neutral commander's books"
		)
		assert_eq(building.pricing_id(), template.id)
		assert_false(building.is_in_group(template.family))
		assert_false(
			Build._is_conversion(_commander, _order(base, VU.inXZ(building.global_position))),
			"now owned, it is not a target again"
		)

		_discard(building)


func test_losing_a_converted_building_withdraws_its_infrastructure() -> void:
	var template: PieceFamilies.Template = _family()[0]
	var building: Commandable = _neutral_building(template.id)
	await _convert(building, _base_tool(), VU.inXZ(building.global_position))
	_dismiss_known_errors()
	assert_eq(
		_commander.infrastructure_provided, Commander.BASE_INFRASTRUCTURE + template.infrastructure
	)
	building.free()
	assert_eq(
		_commander.infrastructure_provided,
		Commander.BASE_INFRASTRUCTURE,
		"what was credited is what is withdrawn"
	)


#endregion


#region A neutral building grants nothing
func test_a_neutral_building_grants_no_infrastructure_by_existing_or_being_garrisoned() -> void:
	for template: PieceFamilies.Template in _family():
		var building: Commandable = _neutral_building(template.id)
		assert_eq(building.infrastructure, 0, "%s's scene carries none" % template.id)
		assert_eq(_neutral.infrastructure_provided, Commander.BASE_INFRASTRUCTURE)

		var occupant: Commandable = _make_builder(Vector2(12.0, 12.0))
		(building.get_node("Garrison") as Garrison).garrison(occupant)
		assert_eq(building.commander, _commander, "ownership is adopted through the garrison")
		assert_eq(
			_commander.infrastructure_provided,
			Commander.BASE_INFRASTRUCTURE,
			"and grants %s's garrisoner nothing" % template.id
		)
		assert_eq(_neutral.infrastructure_provided, Commander.BASE_INFRASTRUCTURE)

		# The garrison frees the occupant it still holds when its host goes.
		_discard(building)
#endregion
