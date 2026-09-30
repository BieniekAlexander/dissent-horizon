extends GutTest

## The ability under test, now a `kind: AbilityDefinition` doc id rather than an enum member — see
## the ability-module fold in gdd/systems/ux/ui/command-card-and-hotkeys.md.
const ABILITY: StringName = &"irradiate"

## The charge half of the additive modifier: an ability with nothing left in the pool is
## REFUSED like an unaffordable purchase, and QUEUED when the modifier is held.
##
## Why it works this way:
## gdd/systems/commands/cooldowns-and-preconditions.md §A spent charge is refused; the
## modifier is what queues it.
##
## The Bombard is the worked example the OLD rule was written around, which is why it is
## the piece tested here: "line up the next shell while the last is in the air" used to be
## the bare click and is now the modified one.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ChargeGating.gd -gexit

var _commander: Commander


func after_each() -> void:
	FakePieces.restore_abilities()


func before_each() -> void:
	FakePieces.install_ability(Bombard.ABILITY_ID, {"range": 30.0})
	FakePieces.install_ability(ABILITY, {"range": 30.0})
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


## A finished Colonial gun owned by `_commander`. The scene is loaded INSIDE the test
## rather than preloaded at file scope: a file-scope preload of an entity scene runs at
## parse time and can build Tool's static registry before it is ready (see CLAUDE.md).
func _gun(a_ready: bool) -> Commandable:
	# The gun costs 75 infrastructure of upkeep, and a commander with only
	# BASE_INFRASTRUCTURE cannot cover two of them — an unpowered building casts nothing
	# (see tests/test_InfrastructureStrain.gd), which is not what is under test here.
	_commander.add_infrastructure(1000)
	var gun: Commandable = FakePieces.structure({"dimensions": Vector2i(2, 2), "beacon_range": 30.0,
		"abilities": [{"grants": [Bombard.ABILITY_ID], "cooldown_ticks": 100}]})
	_commander.add_child(gun)
	autofree(gun)
	gun.top_level = true
	gun.ownership.commander = _commander
	gun.global_position = Vector3.ZERO
	gun.build_progress = 1.0
	if not a_ready:
		(gun.get_node("Abilities") as Abilities).spend(Bombard.ABILITY_ID)
	return gun


## An order aimed at ground the gun spots for itself, carrying the deferral flag the
## additive modifier stamps.
func _aim(a_defer: bool) -> CommandMessage:
	var message := CommandMessage.new(null, null, null, Vector3(10.0, 0.0, 0.0))
	message.defer_if_unaffordable = a_defer
	return message


## --- the gate ------------------------------------------------------------------

func test_a_loaded_gun_takes_the_order_with_no_modifier() -> void:
	assert_eq(
		Bombard.meets_precondition(_gun(true), _aim(false)),
		MoveCommand.PreconditionFailureCause.NONE,
		"a ready gun is never refused for its cooldown"
	)


func test_a_reloading_gun_is_refused_without_the_modifier() -> void:
	assert_eq(
		Bombard.meets_precondition(_gun(false), _aim(false)),
		MoveCommand.PreconditionFailureCause.ABILITY_NO_CHARGES,
		"the bare click is refused while the barrel is hot"
	)


func test_a_reloading_gun_accepts_the_order_with_the_modifier() -> void:
	# The behaviour that used to be the DEFAULT. It is still expressible — it is now the
	# modified click, which is the whole substance of the rule change.
	assert_eq(
		Bombard.meets_precondition(_gun(false), _aim(true)),
		MoveCommand.PreconditionFailureCause.NONE,
		"holding the modifier queues the shot instead of refusing it"
	)


func test_the_refusal_has_a_message_the_player_can_read() -> void:
	# A cause with no entry in the map shows an empty error line, which reads as no
	# feedback at all — the exact failure test_BombardCursor was written for.
	assert_ne(
		MoveCommand.precondition_message_map.get(
			MoveCommand.PreconditionFailureCause.ABILITY_NO_CHARGES, ""
		),
		"",
		"the spent-charge refusal names itself"
	)


func test_the_cooldown_still_only_greys_the_button() -> void:
	# actor_is_recharging stays a SEPARATE question from meets_precondition: the grid reads
	# it, it takes no message, and so it cannot know whether the modifier is down. A gun
	# that is orderable-with-the-modifier still has to look unready.
	assert_true(Bombard.actor_is_recharging(_gun(false)), "a hot barrel greys its button")
	assert_false(Bombard.actor_is_recharging(_gun(true)), "a cool one does not")


## --- Ability.can_act: a queued order must WAIT, not be thrown away ---------------

## A real ability-carrying unit, standing at the origin, holding `charges` of the one
## ability under test. A real scene rather than a bare Commandable because `can_act`
## reads `xz_position` — i.e. `global_position` — which errors outside the tree, and a
## `Commandable.new()` added TO the tree runs a `_ready` that wants its own `Ownership`.
## Its authored specs are replaced so the test does not ride on the doc's charge counts.
func _caster(a_charges: int) -> Commandable:
	# The Vanguard, which is one of the three pieces actually granted the ability. The Warlord
	# stood here while charges lived in an `Inventory` any unit could be handed at runtime;
	# a pool is authored per piece, so the fixture has to be a piece that carries one.
	var actor: Commandable = FakePieces.unit({"speed": 2.0, "vision": 8.0, "abilities": [{}]})
	_commander.add_child(actor)
	autofree(actor)
	actor.top_level = true
	actor.global_position = Vector3.ZERO
	# Its authored pool is replaced so the test does not ride on the doc's charge counts.
	var pool := actor.get_node("Abilities") as Abilities
	pool.groups = [{
		"initial_charges": a_charges, "max_charges": 2, "cooldown_ticks": 90,
		"grants": [ABILITY],
	}]
	pool._rebuild()
	return actor


func _cast(a_defer: bool) -> Ability:
	var message := CommandMessage.new(null)
	message.defer_if_unaffordable = a_defer
	message.ability_type = ABILITY
	return Ability.new(message)


func test_an_in_range_caster_with_no_charge_cannot_act_yet() -> void:
	# The regression this guards: fulfill_action returns null when consume() fails, and a
	# null return DROPS the command (CommandReceiver sets _command = null). Without the
	# charge test in can_act, a queued ability whose pool was empty was silently discarded
	# the moment the actor was in range, instead of waiting out the reload — which is the
	# one thing a queued order must never do. Bombard and UseSanction always gated can_act
	# this way; Ability did not.
	assert_false(_cast(true).can_act(_caster(0)), "an empty pool is not ready to act")


func test_an_in_range_caster_with_a_charge_acts() -> void:
	assert_true(_cast(true).can_act(_caster(1)), "a charged caster on the point acts")


func test_a_spent_ability_is_refused_without_the_modifier() -> void:
	assert_eq(
		Ability.meets_precondition(_caster(0), _cast(false).message),
		MoveCommand.PreconditionFailureCause.ABILITY_NO_CHARGES,
		"the bare click is refused when the pool is empty"
	)
