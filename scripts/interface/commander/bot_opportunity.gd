class_name BotOpportunity
extends RefCounted

## BotOpportunity — one scored, executable action the bot COULD take, weighed purely
## by the utility (net value) it would yield. The [BotOpportunist] manager gathers
## these from every domain each think, ranks them by utility(), and executes the best
## ones (at most one per actor per tick).
##
## To add a new utility-driven decision: subclass this — set [actor] and override
## utility() + execute() — then have a gatherer in BotOpportunist emit instances of it.
## Nothing else in the decision loop changes; that's the whole extension point.

## The owned unit that would carry out this action. The opportunist lets each actor
## take at most one opportunity per tick, so this doubles as the conflict key.
var actor: Commandable


## Estimated net value (gain minus cost) of taking this action right now, expressed in
## ore-equivalent units so opportunities from different domains are directly
## comparable. Only positive-utility opportunities are ever acted on.
func utility() -> float:
	return 0.0


## Carry out the action through the actuator — the bot's sole command-issuing surface.
func execute(_act: BotActuator) -> void:
	pass


## Human-readable label, for debugging / logging.
func describe() -> String:
	return "opportunity"
