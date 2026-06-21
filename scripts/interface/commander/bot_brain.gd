class_name BotBrain
extends Node

## BotBrain — the decision + tick layer for a CPU-controlled commander.
##
## Architecture (perception → decision → action):
##   • Perception lives on the [Bot] this node is a child of (bot.gd — read-only
##     "senses": economy, army, threat, spatial, tech, phase).
##   • Decision lives HERE: a throttled think() pass that will host the strategy
##     managers (economy / production / military) coordinated by a posture FSM.
##   • Action will live in a thin actuator layer (the only place that issues
##     commands), kept separate so the decision code stays pure and testable.
##
## One BotBrain is attached per non-human, non-neutral commander by
## Scenario._attach_brain(). A neutral (id 0) or human-controlled commander never
## gets one. Set [active] = false (via Scenario.passive_bot_ids) for a brain that
## exists but does nothing — useful for isolating one bot during development.

## When false the think loop is skipped entirely: the bot is inert.
@export var active: bool = true

## Physics ticks between successive think() passes. AI decisions are coarse and
## relatively expensive, so we deliberately think a few times per second rather
## than every tick (30 tps → THINK_INTERVAL_TICKS=15 ≈ twice per second).
const THINK_INTERVAL_TICKS: int = 15

## The Bot (a Commander subclass carrying the perception API) this brain drives.
var bot: Bot

## Strategy layer — built lazily on the first think() once the Bot's map is
## resolved. The actuator is the shared command-issuing surface; the managers
## decide and call into it.
var _actuator: BotActuator
var _military: BotMilitary
var _production: BotProduction

var _ticks_since_think: int = 0


func _ready() -> void:
	bot = get_parent() as Bot
	if bot == null:
		push_warning("BotBrain expects to be a child of a Bot; found %s" % get_parent())


func _physics_process(_delta: float) -> void:
	if not active or bot == null or Engine.is_editor_hint():
		return
	_ticks_since_think += 1
	if _ticks_since_think < THINK_INTERVAL_TICKS:
		return
	_ticks_since_think = 0
	think()


## Decision entry point, run on the throttled cadence above. Runs the strategy
## managers in priority order: production fills idle buildings; military steers
## the army. Economy expansion (mines/dwellings) joins here in a later milestone.
func think() -> void:
	if not _ensure_managers():
		return
	_production.tick()
	_military.tick()


## Build the strategy layer once the Bot's map is available (Bot._ready resolves
## it from the scenario). Returns false until then so think() no-ops safely.
func _ensure_managers() -> bool:
	if _military != null:
		return true
	if bot == null or bot.map == null:
		return false
	_actuator = BotActuator.new(bot.map)
	_production = BotProduction.new(bot, _actuator)
	_military = BotMilitary.new(bot, _actuator)
	return true
