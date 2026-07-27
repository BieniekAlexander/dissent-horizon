class_name BotKamikaze
extends RefCounted

## BotKamikaze — cost-effective micro for AOE-suicide units (kamikaze drones).
##
## A suicide drone should only spend itself when the blast destroys more than it
## costs. Each evaluation it asks the bot for each drone's most cost-effective blast
## target (Bot.kamikaze_best_target: a believed/visible enemy cluster whose summed
## HP-fraction × unit-cost beats the drone's own cost). If one exists, it commits the
## run (Attack → fly in → bomb → suicide). If not, it HOLDS the drone — suppressing its own
## target acquisition and taking it home — and waits for a worthwhile cluster. These units
## are excluded from the normal army control (BotMilitary / BotTargeting), so this manager
## has sole say over them, and the hold is what makes that true rather than nominal (see
## _hold).
##
## The cost-effectiveness scan is deliberately INFREQUENT — on the order of seconds,
## not frames (EVAL_PERIOD_SECONDS). It runs on the main thread (Godot's scene tree isn't
## thread-safe and the work is tiny: a few drones × visible enemies), just throttled.

## Seconds between evaluations — this manager's BotScheduler job period. A time rather than a
## count of thinks, so a faster-thinking tier no longer micros its drones more often.
const EVAL_PERIOD_SECONDS: float = 7.0

## The owner name this module claims drones under (BotClaims): it has sole say over them.
const CLAIM_OWNER: StringName = &"kamikaze"

## Work units per drone evaluated (BotScheduler counts work in units of roughly a microsecond
## on the calibration machine); the blast search walks the visible enemies for each.
const DRONE_WORK_UNITS: int = 20

## Which manager owns which unit; the brain replaces this with the bot's shared registry. A
## fresh one by default, so a bare manager in a test sees every unit unclaimed.
var claims: BotClaims = BotClaims.new()

var _bot: Bot
var _act: BotActuator


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


## Evaluate every drone. Returns the work units spent.
func tick() -> int:
	var drones: Array = _bot.get_suicide_aoe_units()
	for k: Commandable in drones:
		claims.claim(k, CLAIM_OWNER, BotClaims.Priority.EXCLUSIVE)
		var best: Variant = _bot.kamikaze_best_target(k)
		if best != null:
			_commit(k, best["target"])
		else:
			_hold(k)
	return drones.size() * DRONE_WORK_UNITS


## Worth it: release the hold and commit the suicide run (persist — see it through to the
## cluster). The release has to come FIRST, or the drone flies in under a hold and cannot
## re-acquire if the leash ever drops.
func _commit(a_k: Commandable, a_target: Entity) -> void:
	a_k.is_holding_fire = false
	_act.attack([a_k], a_target, true)


## NO BLAST WORTH IT — the drone waits, and waiting has to be enforced.
##
## Three steps, and the middle one is the whole fix. Walking the drone home was all this used
## to do, which does not stop it from being spent: idle aggro picks up whatever is in range
## on the way, and the manager's cost-effectiveness decision — the only reason this module
## exists — is silently overridden by proximity. Worse, the walk home only happened when the
## bot owned a structure, so a drone with no base to return to was not even walked.
##
## So: suppress the drone's own target acquisition (Commandable.is_holding_fire); drop any
## engagement it has already been committed to by aggro, since suppression only prevents the
## NEXT pickup; and only then, if there is a home to go to, take it out of harm's way.
##
## The order matters: cancelling first and suppressing second would leave a one-tick window
## in which the drone is idle, unsuppressed and standing next to a target.
func _hold(a_k: Commandable) -> void:
	a_k.is_holding_fire = true
	if a_k.current_command() is Attack or a_k.current_command() is AttackMove:
		a_k.update_commands(null)
	var home: Vector3 = _bot.base_centroid()
	if home != Vector3.ZERO:
		_act.move([a_k], home)
