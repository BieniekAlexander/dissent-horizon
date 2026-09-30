extends GutTest

## PLACING A STRUCTURE: press `command_armed_issue` to set it down, drag to turn it, release to order it.
## Driven through RTSController._unhandled_input on a controller that was never put in a scene tree,
## the way test_VariantCycle drives the card; the per-frame half (the cursor's ground point) is
## covered by its pure parts in test_FootprintRotation.
##
## Every expectation is read from the tool and the tool's own footprint, never typed in.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_PlacementRotation.gd -gexit

const TOOL_NAME: String = "command_tool_an_infrastructure"
## The long neutral building the tool's second variant places.
const LONG_DIMS: Vector2i = Vector2i(3, 5)
const BUILDER_SCENE: Dictionary = FakePieces.BUILDER
const MAP_CORNERS: int = 41
const GRID_CELLS: int = MAP_CORNERS - 1


class StubMap extends Map:
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


var _world: Node3D
var _map: StubMap
var _commander: Commander
var _controller: RTSController
var _builder: Commandable
var _saved_player_id: int = 0


func before_each() -> void:
	# A static other suites move: whose orders this controller may issue.
	_saved_player_id = RTSController.PLAYER_COMMANDER_ID
	RTSController.PLAYER_COMMANDER_ID = 1
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
	_commander.add_energy(100000)
	_commander.set_physics_process(false)
	_commander.technology_mapping[Tool.for_name(TOOL_NAME).type].required_structures = []
	_builder = FakePieces.make(BUILDER_SCENE) as Commandable
	_world.add_child(_builder)
	(_builder.get_node("Builds") as Builds).buildable_types = [Tool.for_name(TOOL_NAME).type]
	_builder.ownership.commander = _commander
	_builder.map = _map
	_controller = autofree(RTSController.new()) as RTSController
	autofree(_controller.selection_box)
	_controller.command_message = CommandMessage.new(_map)
	_controller.selection = [_builder]
	_controller.map = _map
	# The long (3×5) variant, so a quarter turn changes the cells.
	_controller.command_message.tool = Tool.for_name(TOOL_NAME).with_variant(1)
	_controller.current_command_type = Build
	watch_signals(_controller)


func after_each() -> void:
	RTSController.PLAYER_COMMANDER_ID = _saved_player_id


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
	stub.height_map = heights
	return stub


func _press(a_action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = a_action
	event.pressed = true
	_controller._unhandled_input(event)


func _release(a_action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = a_action
	event.pressed = false
	_controller._unhandled_input(event)


## Aim at a spot well inside the map where the long building fits at every turn.
func _aim() -> void:
	_controller.command_message.world_position = Vector3(2.0, 0.0, 3.0)


## The builder's queued Build, or null.
func _ordered_build() -> Build:
	return _builder.current_command() as Build if _builder.current_command() is Build else null


# ─── THE ROTATE KEYS ────────────────────────────────────────────────────────

func test_rotate_left_turns_counter_clockwise_and_right_turns_back() -> void:
	_press(&"rotate_left")
	assert_eq(_controller.placement_quarter_turns, 1)
	_press(&"rotate_left")
	assert_eq(_controller.placement_quarter_turns, 2)
	_press(&"rotate_right")
	assert_eq(_controller.placement_quarter_turns, 1)


func test_the_rotate_keys_wrap_in_both_directions() -> void:
	_press(&"rotate_right")
	assert_eq(_controller.placement_quarter_turns, 3, "0 turned right is 3")
	_press(&"rotate_left")
	assert_eq(_controller.placement_quarter_turns, 0, "and back around")


func test_the_rotate_keys_do_nothing_with_no_tool_armed() -> void:
	_controller.command_message.tool = null
	_press(&"rotate_left")
	assert_eq(_controller.placement_quarter_turns, 0)


func test_the_rotate_keys_do_nothing_when_it_is_not_a_build() -> void:
	_controller.current_command_type = null
	_press(&"rotate_left")
	assert_eq(_controller.placement_quarter_turns, 0)


# ─── PRESS, DRAG, RELEASE ───────────────────────────────────────────────────

func test_the_press_orders_nothing() -> void:
	_aim()
	_press(&"command_armed_issue")
	assert_true(_controller._placing, "the structure is set down and waiting")
	assert_signal_not_emitted(_controller, "command_issued")
	assert_null(_ordered_build())


func test_the_press_freezes_the_placement_where_it_landed() -> void:
	_aim()
	_press(&"command_armed_issue")
	# The cursor moves on; the per-frame update must not carry the placement with it.
	_controller.command_message.world_position = Vector3(30.0, 0.0, 30.0)
	_controller._freeze_placement()
	assert_eq(_controller.command_message.world_position, Vector3(2.0, 0.0, 3.0))


func test_the_release_orders_the_build_with_the_turn_it_ended_on() -> void:
	_aim()
	_press(&"rotate_left")
	_press(&"command_armed_issue")
	_release(&"command_armed_issue")
	assert_signal_emitted(_controller, "command_issued")
	var build: Build = _ordered_build()
	assert_not_null(build, "the builder was given the order")
	if build != null:
		assert_eq(build.message.quarter_turns, 1)
	assert_false(_controller._placing)


func test_a_plain_click_orders_the_build_at_the_facing_already_chosen() -> void:
	# No drag: nothing in the press-to-release turns it, so the rotate keys' answer stands.
	_aim()
	_press(&"rotate_left")
	_press(&"rotate_left")
	_press(&"command_armed_issue")
	_release(&"command_armed_issue")
	var build: Build = _ordered_build()
	assert_not_null(build)
	if build != null:
		assert_eq(build.message.quarter_turns, 2)


func test_the_release_behaves_as_the_press_used_to_about_staying_armed() -> void:
	# Issuing puts the tool down, and the additive modifier keeps it for the next — unchanged by
	# moving the order from the press to the release.
	_aim()
	_press(&"command_armed_issue")
	_release(&"command_armed_issue")
	assert_null(_controller.command_message.tool, "an ordinary order puts the tool down")
	_controller.command_message.tool = Tool.for_name(TOOL_NAME).with_variant(1)
	_controller.additive_latched = true
	_controller.command_message.world_position = Vector3(-8.0, 0.0, -8.0)
	_press(&"command_armed_issue")
	_release(&"command_armed_issue")
	assert_not_null(_controller.command_message.tool, "held, it stays for the next")


# ─── A TURN THAT MAKES THE PLACEMENT ILLEGAL ────────────────────────────────

func test_a_turn_that_lands_on_something_is_refused_and_the_tool_stays_armed() -> void:
	_aim()
	var at := Vector2(2.0, 3.0)
	var dims: Vector2i = LONG_DIMS
	var plain: Array[Vector2i] = _map.footprint_cells(at, dims)
	var turned: Array[Vector2i] = _map.footprint_cells(at, Vector2i(dims.y, dims.x))
	var only_turned: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in turned:
		if not plain.has(cell):
			only_turned = cell
			break
	assert_ne(only_turned, Vector2i(-1, -1), "guards the fixture: the two footprints must differ")
	_map.cell_grid[only_turned.x][only_turned.y] = Node.new()
	_press(&"rotate_left")
	_press(&"command_armed_issue")
	_release(&"command_armed_issue")
	assert_signal_not_emitted(_controller, "command_issued")
	assert_null(_ordered_build(), "nothing was submitted")
	assert_not_null(_controller.command_message.tool, "the Build is still armed with the same tool")
	assert_eq(_controller.placement_quarter_turns, 1, "and the facing is as it was left")
	# Turned back, the same spot is fine and orders normally.
	_press(&"rotate_right")
	_press(&"command_armed_issue")
	_release(&"command_armed_issue")
	assert_signal_emitted(_controller, "command_issued")


# ─── CANCELLING ─────────────────────────────────────────────────────────────

func test_disarming_mid_press_orders_nothing_when_the_button_comes_up() -> void:
	_aim()
	_press(&"command_armed_issue")
	_controller.disarm_command()
	assert_false(_controller._placing)
	_release(&"command_armed_issue")
	assert_signal_not_emitted(_controller, "command_issued")
	assert_null(_ordered_build())
	assert_null(_controller.command_message.tool)


func test_putting_the_tool_down_forgets_the_turn() -> void:
	_press(&"rotate_left")
	_controller.disarm_command()
	assert_eq(_controller.placement_quarter_turns, 0)


# ─── WHAT A DRAG MEANS ──────────────────────────────────────────────────────

func test_a_drag_turns_the_structure_to_face_the_cursor() -> void:
	_aim()
	_press(&"command_armed_issue")
	var press: Vector3 = Vector3(2.0, 0.0, 3.0)
	var far: float = RTSController.PLACEMENT_ROTATE_DEADZONE * 4.0
	_controller._turn_placement_toward(press + Vector3(far, 0.0, 0.0))
	assert_eq(_controller.placement_quarter_turns, 1, "dragged toward +X")
	_controller._turn_placement_toward(press + Vector3(0.0, 0.0, -far))
	assert_eq(_controller.placement_quarter_turns, 2, "toward -Z")
	_controller._turn_placement_toward(press + Vector3(-far, 0.0, 0.0))
	assert_eq(_controller.placement_quarter_turns, 3, "toward -X")
	_controller._turn_placement_toward(press + Vector3(0.0, 0.0, far))
	assert_eq(_controller.placement_quarter_turns, 0, "toward +Z, the unturned front")


func test_a_wobble_inside_the_dead_zone_keeps_the_facing_the_keys_chose() -> void:
	_aim()
	_press(&"rotate_left")
	_press(&"command_armed_issue")
	var press: Vector3 = Vector3(2.0, 0.0, 3.0)
	_controller._turn_placement_toward(press + Vector3(-RTSController.PLACEMENT_ROTATE_DEADZONE * 0.5, 0.0, 0.0))
	assert_eq(_controller.placement_quarter_turns, 1)


func test_the_order_carries_the_turn_the_drag_ended_on() -> void:
	_aim()
	_press(&"command_armed_issue")
	_controller._turn_placement_toward(Vector3(2.0, 0.0, 3.0) \
		+ Vector3(RTSController.PLACEMENT_ROTATE_DEADZONE * 4.0, 0.0, 0.0))
	_release(&"command_armed_issue")
	var build: Build = _ordered_build()
	assert_not_null(build)
	if build != null:
		assert_eq(build.message.quarter_turns, 1)
