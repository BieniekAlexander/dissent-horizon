extends GutTest

## What a right-click MEANS to a mixed selection, and who receives the resulting order.
##
## Two halves, and they are separate mechanisms:
##   - RESOLUTION — RTSController.resolve_command_class_for_selection picks ONE class for
##     the whole selection, letting the units that can actually execute something decide,
##     rather than whatever unit happens to sit at selection[0].
##   - ISSUE — assign_command_to_units then filters per unit by precondition, so the units
##     the order doesn't apply to are skipped while the rest carry it out. That filter is
##     long-standing; what these tests pin is that resolution now agrees with it.
##
## The command classes are resolved through the controller's STATIC entry points, so no
## controller instance, HUD, or map is stood up.

const RECRUIT: Dictionary = FakePieces.SOLDIER
## An unarmed carrier that takes one kind of occupant only, and banks prisoners.
const SUPPLY_TRUCK: Dictionary = {"speed": 2.0, "garrison": {"capacity": 3, "ids": [&"fake_servant"]},
	"interactions": [Interaction.Type.DEPOSIT]}
## Ground and air gun.
const WARLORD: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0, "air": 8.0}}
const CLIPPER: Dictionary = FakePieces.AIRCRAFT
const IRREGULAR: Dictionary = FakePieces.BUILDER
## A transport that admits anyone.
const MERCURY: Dictionary = {"speed": 2.0, "garrison": {"capacity": 4}}
## load()ed inside the test, never preloaded: a file-scope preload of a STRUCTURE scene runs
## at parse time and fires Tool's static registry before it can be built, which fails every
## scene load in the run. See CLAUDE.md §Running and testing.
const COMPOUND_PATH: Dictionary = {"structure": true, "garrison": {"capacity": 6, "sentence_length": 30.0,
	"frames": 0, "armours": 0, "movements": 0}}
const PLAYER: int = 1
const ENEMY: int = 2

func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

## A live unit owned by [a_commander_id]. Ownership is assigned directly (not through
## initialize) so no Map is needed; entering the tree is what resolves its components and
## its targetable layers, which weapon matching reads.
func _unit(a_options: Dictionary, a_commander_id: int) -> Commandable:
	var u := FakePieces.make(a_options) as Commandable
	add_child_autofree(u)
	u.ownership.commander = _commanded(a_commander_id)
	return u

func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)

func _resolve(a_selection: Array, a_target: Entity) -> Variant:
	return RTSController.resolve_command_class_for_selection("", a_selection, _message_for(a_target))

## --- Some units can attack, some can't ------------------------------------

func test_a_selection_resolves_attack_when_only_some_units_can_attack():
	# The truck is FIRST and cannot shoot at all — the old lead-only resolution took the
	# whole group's meaning from it and the recruit never fired.
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var enemy: Commandable = _unit(IRREGULAR, ENEMY)
	assert_eq(_resolve([truck, recruit], enemy), Attack,
		"the group attacks because a selected unit can attack")

func test_resolution_does_not_depend_on_selection_order():
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var enemy: Commandable = _unit(IRREGULAR, ENEMY)
	assert_eq(_resolve([recruit, truck], enemy), _resolve([truck, recruit], enemy),
		"whichever unit was clicked first, the order is the same")

func test_the_unit_that_cannot_attack_is_the_one_left_out():
	# The issue-time filter (assign_command_to_units) reads exactly this.
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var message: CommandMessage = _message_for(_unit(IRREGULAR, ENEMY))
	assert_eq(Attack.meets_precondition(recruit, message),
		MoveCommand.PreconditionFailureCause.NONE, "the armed unit receives the attack")
	assert_ne(Attack.meets_precondition(truck, message),
		MoveCommand.PreconditionFailureCause.NONE, "the unarmed truck does not")

func test_the_selection_reads_as_valid_when_any_unit_can_act():
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var message: CommandMessage = _message_for(_unit(IRREGULAR, ENEMY))
	assert_eq(
		RTSController.selection_precondition(Attack, [truck, recruit], message),
		MoveCommand.PreconditionFailureCause.NONE,
		"one capable unit is enough for the cursor to read the order as issuable"
	)

func test_the_selection_reads_as_invalid_only_when_nobody_can_act():
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	var other_truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	var message: CommandMessage = _message_for(_unit(IRREGULAR, ENEMY))
	assert_ne(
		RTSController.selection_precondition(Attack, [truck, other_truck], message),
		MoveCommand.PreconditionFailureCause.NONE,
		"with no unit able to attack, a concrete failure cause is surfaced"
	)

## --- Some units can't hit THIS target -------------------------------------

func test_an_air_target_resolves_attack_from_the_air_capable_unit():
	# The user's second case: the recruit's weapon can't reach air at all, the Warlord's can.
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var warlord: Commandable = _unit(WARLORD, PLAYER)
	var helicopter: Commandable = _unit(CLIPPER, ENEMY)
	assert_true(helicopter.is_airborne(), "the target is an air unit")
	assert_eq(_resolve([recruit, warlord], helicopter), Attack,
		"the group attacks because the Warlord can shoot air")
	var message: CommandMessage = _message_for(helicopter)
	assert_eq(Attack.meets_precondition(warlord, message),
		MoveCommand.PreconditionFailureCause.NONE, "the AA-capable unit receives it")
	assert_ne(Attack.meets_precondition(recruit, message),
		MoveCommand.PreconditionFailureCause.NONE, "the ground-only unit does not")

func test_a_ground_only_selection_falls_back_to_a_move_against_an_air_target():
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var other_recruit: Commandable = _unit(RECRUIT, PLAYER)
	var helicopter: Commandable = _unit(CLIPPER, ENEMY)
	assert_eq(_resolve([recruit, other_recruit], helicopter), MoveCommand,
		"nothing in the selection can shoot air, so the click is just a move")

## --- A lone specialist keeps its specialty ---------------------------------

func test_a_lone_truck_still_deposits():
	# The Attack-over-Interact precedence only settles MIXED selections; it must not take
	# the truck's own interaction away from it.
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	truck.garrison.garrison(_unit(RECRUIT, ENEMY))
	assert_eq(_resolve([truck], _unit(COMPOUND_PATH, PLAYER)), Interact,
		"selected alone, the loaded truck banks its prisoners")

## Capture has no command of its own — driving over the prey IS the mechanic — so the
## right-click that starts one is a plain move at it. See test_CaptureByCrushing.gd.
func test_a_truck_clicking_its_prey_just_drives_at_it():
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	assert_eq(_resolve([truck], _unit(IRREGULAR, ENEMY)), MoveCommand,
		"an unarmed truck has nothing to offer an enemy but its wheels")

## --- Garrison targets ------------------------------------------------------

func test_a_garrison_host_resolves_occupy():
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var transport: Commandable = _unit(MERCURY, PLAYER)
	assert_eq(_resolve([recruit], transport), Occupy,
		"an own-team transport that admits the unit is an occupy order")

func test_a_host_whose_allowlist_rejects_the_unit_falls_back_to_a_move():
	# Regression: the ladder used to re-state Occupy's rule as "target has a Garrison and
	# the actor is grounded", which resolved Occupy for a host that would not take the unit.
	# The order could never be issued, so the click did nothing at all instead of moving.
	var recruit: Commandable = _unit(RECRUIT, PLAYER)
	var truck: Commandable = _unit(SUPPLY_TRUCK, PLAYER)
	assert_false((truck.garrison as Garrison).admits(recruit), "the truck takes Servants only")
	assert_eq(_resolve([recruit], truck), MoveCommand,
		"right-clicking your own truck is a move, not an impossible occupy")
