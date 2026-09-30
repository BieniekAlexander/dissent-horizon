extends GutTest

## Re-pressing an armed piece that has variants CYCLES them (the an_infrastructure tool: one
## button, one hotkey, several underlying forms), and the HUD says which form is armed and stays
## honest about a conversion. Driven through RTSController.process_command on a controller that
## was never put in a scene tree, the way test_ArmedCommandCard drives the card.
##
## Every expectation is read from the tool and the templates, never typed in.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_VariantCycle.gd -gexit

## Fake tools: one whose piece has variants, and one whose piece has none (re-pressing it is unchanged).
## Fake tools. The variants tool is of `EntityIds.AN_INFRASTRUCTURE` because that id is what the
## conversion rule is keyed on in code; its variants are a fake neutral-building family.
const TOOL_NAME: String = "command_tool_an_infrastructure"
## A tool whose piece has no variants, to prove re-pressing it is unchanged.
const PLAIN_TOOL_NAME: String = "command_tool_fake_plain"
const BUILDER_SCENE: Dictionary = {"speed": 2.0, "vision": 8.0,
	"builds": [&"an_infrastructure", &"fake_plain"]}
const BUILD_COMMAND: String = "command_ability"

const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1
const NEUTRAL_ORIGIN: Vector2i = Vector2i(2, 2)


class StubMap extends Map:
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
		return a_coords.x >= 0 and a_coords.x < GRID_CELLS \
			and a_coords.y >= 0 and a_coords.y < GRID_CELLS

	func add_structure(a_structure: Entity, a_world_center: Vector2, _a_rotation: int = 0, _a_rebake: bool = true) -> void:
		placed.append(a_structure)
		var obs := a_structure.get_node("Structure") as Structure
		var footprint: Array[Vector2i] = footprint_cells(a_world_center, obs.dimensions)
		for cell: Vector2i in footprint:
			cell_grid[cell.x][cell.y] = a_structure
		structure_cell_map[a_structure] = footprint
		a_structure.global_position = footprint_centroid(footprint_origin(a_world_center, obs.dimensions), obs.dimensions)
		a_structure.map = self
		a_structure.refresh_movement_collision()

	func remove_structure(a_structure: Entity, _a_rebake: bool = true) -> void:
		structure_cell_map.erase(a_structure)


var _world: Node3D
var _map: StubMap
var _commander: Commander
var _neutral: Commander
var _controller: RTSController
var _builder: Commandable


func after_each() -> void:
	FakePieces.restore_families()
	FakePieces.restore_tools()


func before_each() -> void:
	FakePieces.install_families([
		{"id": &"fake_form_a", "family": &"neutral_building", "footprint": Vector2i(4, 4)},
		{"id": &"fake_form_b", "family": &"neutral_building", "footprint": Vector2i(3, 5)}])
	var forms: Array[StringName] = [&"fake_form_a", &"fake_form_b"]
	FakePieces.register_tool(FakePieces.tool(EntityIds.AN_INFRASTRUCTURE,
		{"structure": true, "dimensions": Vector2i(4, 4)}, forms))
	FakePieces.register_tool(FakePieces.tool(&"fake_plain",
		{"structure": true, "dimensions": Vector2i(3, 3)}))
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
	_commander.technology_mapping = {EntityIds.AN_INFRASTRUCTURE: FakePieces.tech(), &"fake_plain": FakePieces.tech(),
		&"fake_form_a": FakePieces.tech(), &"fake_form_b": FakePieces.tech()}
	_builder = FakePieces.make(BUILDER_SCENE) as Commandable
	_world.add_child(_builder)
	var builds := _builder.get_node("Builds") as Builds
	builds.buildable_types = [_base_tool().type, Tool.for_name(PLAIN_TOOL_NAME).type]
	_builder.ownership.commander = _commander
	_builder.map = _map
	_controller = autofree(RTSController.new()) as RTSController
	autofree(_controller.selection_box)
	_controller.command_message = CommandMessage.new(_map)
	_controller.selection = [_builder]
	_controller.pending_command_name = BUILD_COMMAND


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


func _armed() -> Tool:
	return _controller.command_message.tool


func _neutral_building(a_id: StringName) -> Commandable:
	var template: PieceFamilies.Template = PieceFamilies.template(a_id)
	var building: Commandable = template.load_scene().instantiate() as Commandable
	_neutral.add_child(building)
	building.initialize(_map, _neutral)
	for tracked in get_errors():
		if tracked.contains_text("was given an empty description") \
				or tracked.contains_text("was given an empty verbose description") \
				or tracked.contains_text("entered the tree with no"):
			tracked.handled = true
	var dims: Vector2i = (building.get_node("Structure") as Structure).dimensions
	_map.add_structure(building, VU.inXZ(_map.footprint_centroid(NEUTRAL_ORIGIN, dims)))
	return building
#endregion


#region Cycling
func test_the_first_press_arms_the_default_variant() -> void:
	_controller.process_command(TOOL_NAME)
	assert_not_null(_armed())
	assert_true(_armed().is_variant_bound())
	assert_eq(_armed().variant_index(), 0)


func test_each_repress_arms_the_next_variant_and_wraps() -> void:
	var count: int = _base_tool().variants.size()
	_controller.process_command(TOOL_NAME)
	for step: int in count:
		assert_eq(_armed().variant_index(), step, "press %d" % (step + 1))
		_controller.process_command(TOOL_NAME)
	assert_eq(_armed().variant_index(), 0, "one more press than there are forms wraps")


func test_a_cycle_issues_nothing_even_with_the_additive_modifier_latched() -> void:
	_controller.additive_latched = true
	_controller.process_command(TOOL_NAME)
	_controller.process_command(TOOL_NAME)
	assert_true(_builder.current_command() == null, "the builder was given no order")
	assert_true(_controller.is_command_armed(), "and the Build is still armed")


func test_cancel_disarms_and_the_next_press_starts_from_the_default_again() -> void:
	_controller.process_command(TOOL_NAME)
	_controller.process_command(TOOL_NAME)
	_controller.process_command(RTSController.CANCEL_COMMAND)
	assert_null(_armed())
	_controller.pending_command_name = BUILD_COMMAND
	_controller.process_command(TOOL_NAME)
	assert_eq(_armed().variant_index(), 0)


func test_pressing_a_different_tool_arms_that_tool() -> void:
	_controller.process_command(TOOL_NAME)
	_controller.process_command(PLAIN_TOOL_NAME)
	assert_eq(_armed().command_name, PLAIN_TOOL_NAME)
	assert_false(_armed().is_variant_bound())


func test_returning_to_the_piece_after_another_tool_starts_at_the_default() -> void:
	_controller.process_command(TOOL_NAME)
	_controller.process_command(TOOL_NAME)
	_controller.process_command(PLAIN_TOOL_NAME)
	_controller.process_command(TOOL_NAME)
	assert_eq(_armed().variant_index(), 0)


func test_repressing_a_tool_without_variants_changes_nothing() -> void:
	_controller.process_command(PLAIN_TOOL_NAME)
	var before: Tool = _armed()
	_controller.process_command(PLAIN_TOOL_NAME)
	assert_eq(_armed().command_name, before.command_name)
	assert_false(_armed().is_variant_bound())
#endregion


#region What the HUD says
func test_the_banner_text_names_the_armed_variant() -> void:
	var banner := CardModeBanner.new()
	autofree(banner)
	banner.show_family(ControlBinding.CommandFamily.ACTIVE, CardModeBanner.ArmedState.READY, "Long building")
	assert_true(banner.text.contains("Long building"))
	banner.show_family(ControlBinding.CommandFamily.ACTIVE, CardModeBanner.ArmedState.READY)
	assert_false(banner.text.contains("Long building"), "no detail, no name")
	banner.show_family(ControlBinding.CommandFamily.ACTIVE, CardModeBanner.ArmedState.NONE, "Long building")
	assert_false(banner.text.contains("Long building"), "and an unarmed card names no form")


func test_the_controller_reports_the_armed_variants_label_and_follows_a_cycle() -> void:
	assert_eq(_controller.armed_variant_label(), "")
	_controller.process_command(TOOL_NAME)
	var first: String = _armed().variant_label()
	assert_ne(first, "")
	assert_eq(_controller.armed_variant_label(), first)
	_controller.process_command(TOOL_NAME)
	assert_eq(_controller.armed_variant_label(), _armed().variant_label())
	_controller.process_command(PLAIN_TOOL_NAME)
	assert_eq(_controller.armed_variant_label(), "")
#endregion


#region Conversion
## Aim the armed tool at `a_building` as the frame loop would have.
func _aim_at(a_building: Commandable) -> void:
	_controller.current_command_type = Build
	_controller.command_message.world_position = a_building.global_position


func test_aimed_at_a_neutral_building_the_conversion_target_is_found_and_priced_discounted() -> void:
	_controller.process_command(TOOL_NAME)
	for template: PieceFamilies.Template in PieceFamilies.templates_of(PieceFamilies.NEUTRAL_BUILDING):
		var building: Commandable = _neutral_building(template.id)
		_aim_at(building)
		assert_eq(_controller.armed_conversion_target(), building, "%s is the target" % template.id)
		assert_eq(_controller.previewed_conversion_energy(), Build.conversion_energy(building))
		assert_eq(_controller.previewed_conversion_energy(),
			roundi(float(template.energy_cost) * Build.ENERGY_DISCOUNT))
		_map.remove_structure(building)
		for x: int in GRID_CELLS:
			for y: int in GRID_CELLS:
				_map.cell_grid[x][y] = null
		building.free()


func test_aimed_at_empty_ground_there_is_no_conversion_and_no_override() -> void:
	_controller.process_command(TOOL_NAME)
	_controller.current_command_type = Build
	_controller.command_message.world_position = Vector3(12.0, 0.0, 12.0)
	assert_null(_controller.armed_conversion_target())
	assert_eq(_controller.previewed_conversion_energy(), -1)


func test_a_conversion_is_only_previewed_by_the_conversion_tool() -> void:
	_controller.process_command(PLAIN_TOOL_NAME)
	var building: Commandable = _neutral_building(PieceFamilies.templates_of(PieceFamilies.NEUTRAL_BUILDING)[0].id)
	_aim_at(building)
	assert_null(_controller.armed_conversion_target())
	assert_eq(_controller.previewed_conversion_energy(), -1)


func test_hovering_a_button_previews_that_buttons_price_not_the_conversion() -> void:
	_controller.process_command(TOOL_NAME)
	var building: Commandable = _neutral_building(PieceFamilies.templates_of(PieceFamilies.NEUTRAL_BUILDING)[0].id)
	_aim_at(building)
	var button := Button.new()
	button.name = TOOL_NAME
	autofree(button)
	_controller.hovered_command_button = button
	assert_eq(_controller.previewed_conversion_energy(), -1)


func test_the_conversion_target_wears_the_marker_and_loses_it_when_aim_moves_off() -> void:
	_controller.process_command(TOOL_NAME)
	var building: Commandable = _neutral_building(PieceFamilies.templates_of(PieceFamilies.NEUTRAL_BUILDING)[0].id)
	var marker := building.get_node_or_null("TargetIndicator") as Node3D
	if marker == null:
		pending("this piece scene carries no TargetIndicator")
		return
	_aim_at(building)
	_controller._update_conversion_marker()
	assert_true(marker.visible)
	_controller.command_message.world_position = Vector3(12.0, 0.0, 12.0)
	_controller._update_conversion_marker()
	assert_false(marker.visible)
#endregion
