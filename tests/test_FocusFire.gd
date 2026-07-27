extends GutTest

## FocusFire — shooting at a PLACE. Its own command rather than a mode of Attack, because
## Attack is built end to end around a target entity and its one free hook, a null
## `message.target`, is the same null a dead target leaves behind (see Attack's
## `_target_attackable`, which carries the note about the bug that caused).
##
## What is checked: which weapons may be aimed at ground, the range arithmetic, and that
## the capability reaches the HUD.
##
## Scenes are load()ed INSIDE the tests, never preloaded at file scope — see CLAUDE.md
## §Running and testing for the registry poisoning a file-scope preload can cause.

const SHOOTER_PATH := "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"
const BUILDER_PATH := "res://scenes/entities/units/cl/cl_bioLight_builder.tscn"
const ANTI_AIR_PATH := "res://scenes/entities/structures/cl/cl_defense_antiAircraft.tscn"

func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

func _entity(a_path: String) -> Commandable:
	var e := (load(a_path) as PackedScene).instantiate() as Commandable
	add_child_autofree(e)
	e.ownership.commander = _commanded(1)
	return e

#region Which weapons can be aimed at ground
func test_a_ground_capable_projectile_weapon_can_shell_a_point() -> void:
	assert_not_null(FocusFire.ground_weapon_of(_entity(SHOOTER_PATH)))

func test_an_anti_air_weapon_cannot() -> void:
	# It is not allowed at the ground layer at all, so there is nothing for it to shoot at
	# down there whatever the shot would have done.
	assert_null(FocusFire.ground_weapon_of(_entity(ANTI_AIR_PATH)))

func test_an_unarmed_unit_cannot() -> void:
	assert_null(FocusFire.ground_weapon_of(_entity(BUILDER_PATH)))

## A melee weapon applies its damage straight to a target entity, and a map coordinate is
## not one — a bayonet has nothing it could do to a point.
func test_a_melee_weapon_cannot() -> void:
	var weapon := autofree(Weapon.new()) as Weapon
	weapon.target_mask = CollisionLayers.Mask.TARGETABLE_GROUND
	weapon.melee_damage = 10.0
	assert_null(weapon.projectile_scene, "the case being described: no projectile")
	assert_false(weapon.can_fire_at_ground())

func test_firing_a_melee_weapon_at_a_point_spends_nothing() -> void:
	var weapon := autofree(Weapon.new()) as Weapon
	weapon.target_mask = CollisionLayers.Mask.TARGETABLE_GROUND
	weapon.clip_size = 3
	weapon.fill_clip()
	weapon.fire_at_position(null, Vector3.ZERO)
	assert_eq(weapon.ammo(), 3, "a round the weapon cannot use is not spent")
#endregion

#region Range
## The gap from the firer's footprint to the point, against the range radius: a point is a
## footprint of no size, so this is the same test every piece-to-piece range makes.
func test_within_reach_is_the_radius() -> void:
	var at_origin := Hull.point(Vector2.ZERO)
	assert_true(FocusFire.within_reach(at_origin, Vector2(3.0, 4.0), 5.0), "on the edge")
	assert_true(FocusFire.within_reach(at_origin, Vector2(3.0, 4.0), 5.1))
	assert_false(FocusFire.within_reach(at_origin, Vector2(3.0, 4.0), 4.9))

func test_within_reach_is_measured_from_the_firer_s_footprint() -> void:
	var firer := Hull.circle(Vector2(10.0, 10.0), 1.0)
	assert_true(FocusFire.within_reach(firer, Vector2(14.0, 10.0), 3.0), "3 past its edge")
	assert_false(FocusFire.within_reach(firer, Vector2(14.5, 10.0), 3.0))

## -1.0 is what a weapon with no ground range shape reports, and it must never read as
## "in range everywhere".
func test_no_ground_range_is_never_in_reach() -> void:
	assert_false(FocusFire.within_reach(Hull.point(Vector2.ZERO), Vector2.ZERO, -1.0))
#endregion

#region The aim point
## The regression: the controller writes the piece under the cursor onto `message.target` for
## every order, and `CommandMessage.position` prefers it. Focus fire read `position`, so a
## Badger (ground-only) aimed over a hovering unit fired at the aircraft's altitude and its
## blast did what its target mask forbids. The order aims at the clicked GROUND, always.
func test_the_aim_point_is_the_clicked_ground_not_the_piece_under_the_cursor() -> void:
	var aircraft := _entity(SHOOTER_PATH)
	aircraft.global_position = Vector3(10.0, 6.0, 0.0)
	var ground := Vector3(12.0, 0.0, 3.0)
	var message := CommandMessage.new(null, aircraft, null, ground)
	assert_eq(message.position, aircraft.global_position, "fixture: position prefers the piece")
	assert_eq(FocusFire.aim_point(message), ground)

func test_the_order_turns_and_ranges_on_the_ground_point() -> void:
	var shooter := _entity(SHOOTER_PATH)
	shooter.global_position = Vector3.ZERO
	var hovering := _entity(SHOOTER_PATH)
	hovering.global_position = Vector3(2.0, 6.0, 0.0)  # in reach, but not where the order aims
	var order := FocusFire.new(CommandMessage.new(null, hovering, null, Vector3(40.0, 0.0, 0.0)))
	assert_true(order.should_move(shooter), "the ground point is out of reach, so it closes")
	assert_eq(str(order), "FocusFire: %s" % Vector3(40.0, 0.0, 0.0))
#endregion

#region Capability
func test_a_shooter_advertises_the_command() -> void:
	assert_true(CommandContextParser.commands_for(_entity(SHOOTER_PATH)).has("command_focus_fire"))

func test_an_unarmed_unit_does_not() -> void:
	assert_false(CommandContextParser.commands_for(_entity(BUILDER_PATH)).has("command_focus_fire"))

## An anti-air battery keeps Attack and attack-move — it has a Loadout — and loses only the
## order it could not carry out.
func test_an_anti_air_battery_keeps_attack_but_not_focus_fire() -> void:
	var commands: Array = CommandContextParser.commands_for(_entity(ANTI_AIR_PATH))
	assert_true(commands.has("command_attack"))
	assert_false(commands.has("command_focus_fire"))

func test_a_live_focus_fire_names_itself() -> void:
	var command := FocusFire.new(CommandMessage.new(null))
	assert_eq(CommandContextParser.name_for(command), "command_focus_fire")
#endregion

#region The grid
## F, beside the other orders every unit answers to. It took the cell Evacuate used to
## hold, which moved to V among the abilities it belongs with.
func test_fire_is_on_f_and_evacuate_moved_to_v() -> void:
	assert_eq(InputPrompt.action_text(CommandGrid.action_for_command("command_focus_fire")), "F")
	assert_eq(InputPrompt.action_text(CommandGrid.action_for_command("command_evacuate")), "V")

## The other half of the same row rearrangement: a plain move is orderable at last.
func test_go_is_on_g() -> void:
	assert_eq(InputPrompt.action_text(CommandGrid.action_for_command("command_move")), "G")
#endregion
