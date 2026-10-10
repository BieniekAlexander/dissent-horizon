class_name Relation
extends RefCounted

## ONE PIECE GRANTING SOMETHING TO ANOTHER WITHIN A REACH — the model for every inter-piece
## dependency the bot reasons about: a spotter and a gun, a transport and its passengers, a
## bunker and the riflemen inside it. The Bot reads relations OFF THE PIECES rather than
## knowing any by name, the same rule as AnarchicalDominion asking what a piece GRANTS rather
## than naming the Warlord — so a new faction's transport is a doc, not a bot change.
## gdd/systems/ai/squads-and-relations.md §Relations.
##
## A Relation is a KIND: the predicates that say which piece provides it, which piece it is
## provided to, and how far it carries. The pieces instantiate it: `Bot.providers_of` and
## `Bot.consumers_of` are the live pairs. The catalogue (`all()`) is the kinds the code can
## read today, each off a component or an ability's `command:` and never off an id.
##
## TODO: `value` — what a relation is worth in the energy-equivalent currency — is not a field
## yet. Alex (gdd/tasks.md T-002, 2026-10-08) chose to build the read model and a consumer
## that needs no price first; the field arrives with its pricing rule.

## How far a relation carries.
enum Reach {
	## Within `radius_of(provider)` of the provider, on XZ.
	RADIUS,
	## At a point the provider marks (a beacon).
	POINT,
	## Edge contact between footprints.
	ADJACENT,
	## Inside the provider.
	CONTAINED,
	## Anywhere.
	ANY,
}

## What the provider does for the consumer.
enum Effect {
	## An action the consumer could not take alone (a shot needs spotted ground).
	ENABLES,
	## More output from the consumer (dominion per follower).
	SCALES,
	## Less damage to the consumer (cover, a shield).
	PROTECTS,
	## Mobility the consumer lacks (a ride).
	MOVES,
}

## A one-word name for the harness and the logs.
var name: StringName
var reach: Reach
var effect: Effect
## (Actor) -> bool: whether the piece provides this relation right now.
var _is_provider: Callable
## (Actor provider, Actor consumer) -> bool: whether the provider serves the consumer. Pairwise,
## because admission usually is (a garrison's masks are asked of the unit at the door).
var _serves: Callable
## (Actor provider) -> float: how far a RADIUS relation carries from this provider.
var _radius_of: Callable


func _init(
	a_name: StringName,
	a_reach: Reach,
	a_effect: Effect,
	a_is_provider: Callable,
	a_serves: Callable,
	a_radius_of: Callable = func(_a_provider: Actor) -> float: return 0.0
) -> void:
	name = a_name
	reach = a_reach
	effect = a_effect
	_is_provider = a_is_provider
	_serves = a_serves
	_radius_of = a_radius_of


func is_provider(a_piece: Actor) -> bool:
	return a_piece != null and is_instance_valid(a_piece) and bool(_is_provider.call(a_piece))


func serves(a_provider: Actor, a_consumer: Actor) -> bool:
	if a_provider == null or a_consumer == null or a_provider == a_consumer:
		return false
	if not is_instance_valid(a_provider) or not is_instance_valid(a_consumer):
		return false
	return bool(_serves.call(a_provider, a_consumer))


func radius_of(a_provider: Actor) -> float:
	return float(_radius_of.call(a_provider)) if reach == Reach.RADIUS else 0.0


#region The catalogue
## Every relation kind the code can read today. A fresh list each call: four RefCounteds are
## cheap, and a static cache would outlive the test that installed a fake ability.
static func all() -> Array[Relation]:
	return [spotting_range(), spotting_call(), transport(), cover()]


## A `BeaconRange` carrier spots the ground around it for every gun of its side: a shot needs
## spotted ground, and this ground costs nothing (bombardment.md §Two ways ground becomes
## bombardable).
static func spotting_range() -> Relation:
	return Relation.new(
		&"spotting_range",
		Reach.RADIUS,
		Effect.ENABLES,
		func(a_piece: Actor) -> bool:
			return a_piece.is_built and a_piece.get_node_or_null("BeaconRange") != null,
		func(a_provider: Actor, a_consumer: Actor) -> bool:
			return _same_commander(a_provider, a_consumer) and _is_gun(a_consumer),
		func(a_provider: Actor) -> float:
			var spotting: BeaconRange = a_provider.get_node_or_null("BeaconRange") as BeaconRange
			return spotting.radius if spotting != null else 0.0
	)


## A unit granted a `command_spot` ability calls a solution in at a point, and a gun of its
## side fires on it (bombardment.md §Spotting is a commitment).
static func spotting_call() -> Relation:
	return Relation.new(
		&"spotting_call",
		Reach.POINT,
		Effect.ENABLES,
		func(a_piece: Actor) -> bool: return grants_command(a_piece, "command_spot"),
		func(a_provider: Actor, a_consumer: Actor) -> bool:
			return _same_commander(a_provider, a_consumer) and _is_gun(a_consumer)
	)


## A MOBILE open garrison carries what it admits: the ride is mobility the passenger lacks.
## Which units it takes is the host's own masks (Occupy.host_admits), so the Stock Truck —
## which admits only Servants — carries no soldier, and a hold nothing may be ordered into
## (a closed cage) or out of (not releasable) is no transport at all.
##
## Mobility is read off the piece's Movement, not its state: an aircraft on the ground to
## take passengers aboard has its live movement switched off, and `can_move()` is false for
## exactly the moments the relation matters most.
static func transport() -> Relation:
	return Relation.new(
		&"transport",
		Reach.CONTAINED,
		Effect.MOVES,
		func(a_piece: Actor) -> bool:
			var hold: Garrison = _garrison_of(a_piece)
			return (
				hold != null
				and a_piece.is_built
				and speed_of(a_piece) > 0.0
				and not hold.is_closed()
				and hold.can_release()
			),
		func(a_provider: Actor, a_consumer: Actor) -> bool:
			return a_consumer.can_move() and Occupy.host_admits(a_consumer, a_provider)
	)


## A bunker garrison shelters the armed units it admits, and they fire out of it: cover. A
## mobile bunker (the Sloop) is a transport and cover both.
static func cover() -> Relation:
	return Relation.new(
		&"cover",
		Reach.CONTAINED,
		Effect.PROTECTS,
		func(a_piece: Actor) -> bool:
			var hold: Garrison = _garrison_of(a_piece)
			return hold != null and a_piece.is_built and hold.bunker and not hold.is_closed(),
		func(a_provider: Actor, a_consumer: Actor) -> bool:
			return (
				a_consumer.weapon_inventory != null
				and a_consumer.weapon_inventory.has_weapons()
				and Occupy.host_admits(a_consumer, a_provider)
			)
	)


#endregion


#region Predicates
## Whether `a_piece`'s ability pool grants an ability whose doc names `a_command` — the
## player's own route to the verb, so no ability is known by name. Read off the DECLARED pools,
## so a build preview answers the same as a live piece: the live list is built in _ready, which
## a preview never runs, and the siege rung's gun search found no gun for a night because of it.
static func grants_command(a_piece: Actor, a_command: String) -> bool:
	var pool: Abilities = a_piece.get_node_or_null("Abilities") as Abilities
	if pool == null:
		return false
	return pool.declared_abilities().any(
		func(id: StringName) -> bool: return AbilityCatalog.command_of(id) == a_command
	)


## A finished piece that can fire a Bombard.
static func _is_gun(a_piece: Actor) -> bool:
	return a_piece.is_built and grants_command(a_piece, "command_bombard")


## Spotting is read per commander (BombardTargeting scans the commander's own entities), so
## a spotter serves only its own commander's guns — an ally's are not asked.
static func _same_commander(a_provider: Actor, a_consumer: Actor) -> bool:
	return a_provider.commander_id == a_consumer.commander_id


## The piece's Garrison, read directly rather than through `Actor.garrison`: that field is
## `@onready`, and a build preview never enters the tree.
static func _garrison_of(a_piece: Actor) -> Garrison:
	return a_piece.get_node_or_null("Garrison") as Garrison


## How fast the piece moves when it moves, in world units per second — read off its navigated
## Movement whether or not that is live, so a landed aircraft is still as fast as it flies. 0
## for a piece with no navigated movement.
static func speed_of(a_piece: Actor) -> float:
	var movement: Movement = a_piece.get_node_or_null("Locomotion") as Movement
	return movement.speed if movement != null else 0.0
#endregion
