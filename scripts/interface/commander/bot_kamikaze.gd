class_name BotKamikaze
extends RefCounted

## BotKamikaze — cost-effective micro for AOE-suicide units (kamikaze drones).
##
## A suicide drone should only spend itself when the blast destroys more than it
## costs. Each evaluation it asks the bot for each drone's most cost-effective blast
## target (Bot.kamikaze_best_target: a believed/visible enemy cluster whose summed
## HP-fraction × unit-cost beats the drone's own cost). If one exists, it commits the
## run (Attack → fly in → bomb → suicide). If not, it pulls the drone back to base so
## it doesn't waste itself auto-aggroing a lone target, and waits for a worthwhile
## cluster. These units are excluded from the normal army control (BotMilitary /
## BotTargeting), so this manager has sole say over them.
##
## The cost-effectiveness scan is deliberately INFREQUENT — on the order of seconds,
## not frames. It runs on the main thread (Godot's scene tree isn't thread-safe and
## the work is tiny: a few drones × visible enemies), just throttled.

## Thinks between evaluations. BotBrain thinks ~2×/s (THINK_INTERVAL_TICKS=15), so
## 14 ≈ every 7 seconds.
const EVAL_INTERVAL_THINKS: int = 14

var _bot: Bot
var _act: BotActuator
var _ticks_to_eval: int = 0


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


func tick() -> void:
	_ticks_to_eval -= 1
	if _ticks_to_eval > 0:
		return
	_ticks_to_eval = EVAL_INTERVAL_THINKS

	for k: Commandable in _bot.get_suicide_aoe_units():
		var best: Variant = _bot.kamikaze_best_target(k)
		if best != null:
			# Worth it: commit the suicide run (persist — see it through to the cluster).
			_act.attack([k], best["target"], true)
		else:
			_hold(k)


## No blast worth it — retreat the drone to base (away from enemies) so it doesn't
## auto-aggro and suicide on a low-value target while it waits for a cluster.
func _hold(k: Commandable) -> void:
	var home: Vector3 = _bot.base_centroid()
	if home != Vector3.ZERO:
		_act.move([k], home)
