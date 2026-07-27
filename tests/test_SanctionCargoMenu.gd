extends GutTest

## A sanction that takes a CARGO — armed in two steps, exactly as Build is.
##
## Drop is the one that has them. Pressing its button opens a menu of pieces, picking one sets
## `CommandMessage.tool`, and the right-click that follows delivers that piece. Before this a
## level WAS its cargo: three levels were three event scenes with fixed `entity_scenes`, so
## "upgrade the recruit drop and also unlock the APC" had nowhere to live.
##
## Supersession is what makes upgrading free — the level that replaces its parent carries the
## same pieces at higher counts — so these tests read the counts as the design, not as balance.

const CITADEL: String = "res://scenes/entities/structures/cl/cl_commandCenter.tscn"
const RECRUIT: StringName = &"cl_bioLight_antiLight"
const APC: StringName = &"cl_mechMedium_antiLight"
const MATILDA: StringName = &"cl_mechMedium_antiMech"


## The Colonial faction's authored Drop levels, in order.
func _drop_levels() -> Array[Sanction]:
	var faction: Faction = (load("res://scenes/factions/colonial.tscn") as PackedScene) \
		.instantiate() as Faction
	add_child_autofree(faction)
	var out: Array[Sanction] = []
	for unlock: SanctionUnlock in faction.sanction_unlocks:
		if unlock.sanction != null and unlock.sanction.ability_id == &"drop":
			out.append(unlock.sanction)
	out.sort_custom(func(a: Sanction, b: Sanction) -> bool:
		return a.ability_level < b.ability_level)
	return out


func test_the_three_drop_levels_are_authored() -> void:
	assert_eq(_drop_levels().size(), 3)


## Level 1 offers one thing; each level after it offers strictly more.
func test_each_level_offers_at_least_what_the_last_one_did() -> void:
	var levels: Array[Sanction] = _drop_levels()
	assert_eq(levels[0].payload_pieces(), [RECRUIT] as Array[StringName])
	assert_eq(levels[1].payload_pieces(), [RECRUIT, APC] as Array[StringName])
	assert_eq(levels[2].payload_pieces(), [RECRUIT, APC, MATILDA] as Array[StringName])


## "Upgrading the recruit drop" is more of them, and it costs no machinery: the superseding
## level simply carries a higher count for the same piece.
func test_a_carried_over_piece_arrives_in_greater_numbers() -> void:
	var levels: Array[Sanction] = _drop_levels()
	assert_gt(levels[1].count_of(RECRUIT), levels[0].count_of(RECRUIT))
	assert_gt(levels[2].count_of(RECRUIT), levels[1].count_of(RECRUIT))
	assert_gt(levels[2].count_of(APC), levels[1].count_of(APC))


func test_a_piece_a_level_does_not_offer_counts_zero() -> void:
	assert_eq(_drop_levels()[0].count_of(MATILDA), 0, "Drop 1 flies no vehicles")


func test_only_a_sanction_with_payloads_takes_one() -> void:
	assert_true(_drop_levels()[0].takes_a_payload())
	var plain := Sanction.new()
	assert_false(plain.takes_a_payload(), "most sanctions simply happen")
	assert_eq(plain.payload_pieces(), [] as Array[StringName])


## The scene stores IDS, never PackedScenes: a resource-valued export inside a Resource
## crashes the Godot inspector, and the Tool registry is already the project's id-to-scene map.
func test_a_payload_is_stored_as_an_id_and_resolves_through_the_tool_registry() -> void:
	for piece: StringName in _drop_levels()[2].payload_pieces():
		var tool: Tool = Tool.for_id(piece)
		assert_not_null(tool, "%s is reachable as a tool" % piece)
		assert_not_null(tool.packed_scene, "%s has a scene to deliver" % piece)


# --- The two-step arming ----------------------------------------------------------

func _controller_with(a_sanction: Sanction) -> RTSController:
	var controller := autofree(RTSController.new()) as RTSController
	controller.command_message = CommandMessage.new(null)
	controller._pending_sanction = a_sanction
	return controller


func test_arming_a_cargo_sanction_opens_its_menu() -> void:
	var controller: RTSController = _controller_with(_drop_levels()[2])
	assert_not_null(controller.pending_payload_sanction(), "the menu is up")
	assert_eq(controller.payload_menu_commands().size(), 3,
		"one button per piece the level offers")


func test_picking_a_cargo_closes_the_menu() -> void:
	var controller: RTSController = _controller_with(_drop_levels()[2])
	controller.command_message.tool = Tool.for_id(APC)
	assert_null(controller.pending_payload_sanction(),
		"chosen, so the card goes back to what it was showing")


## The click that would otherwise fire it lands while the menu is still up. Firing then would
## send an empty transport.
func test_the_cast_is_refused_until_a_cargo_is_chosen() -> void:
	var controller: RTSController = _controller_with(_drop_levels()[2])
	controller._activate_pending_sanction()
	assert_not_null(controller._pending_sanction, "still armed, nothing issued")


func test_a_sanction_without_payloads_arms_in_one_step() -> void:
	var plain := Sanction.new()
	plain.sanction_name = "Blizzard"
	var controller: RTSController = _controller_with(plain)
	assert_null(controller.pending_payload_sanction())
	assert_eq(controller.payload_menu_commands(), [] as Array)


## A payload button IS the piece's own train button, reused — it already has a cell, a label,
## both tooltip tiers and a faction mask, and clicking it already sets the tool.
func test_a_payload_button_is_the_pieces_own_tool_button() -> void:
	var controller: RTSController = _controller_with(_drop_levels()[1])
	for command: String in controller.payload_menu_commands():
		assert_not_null(Tool.for_name(command), "%s is a real tool button" % command)
	assert_true(controller.payload_menu_commands().has(Tool.for_id(APC).command_name))
