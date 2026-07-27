class_name BotMomentum
extends RefCounted

## BotMomentum — WHETHER THE BOT IS WINNING OR LOSING, as an army-value trend.
##
## Before this existed nothing in the bot read its own position. `relative_threat_level()`
## computed an instantaneous strength ratio that no module consumed, and the blackboard
## recorded what exists and where but never what CHANGED. Every behaviour that separates a
## deliberate opponent from a scripted one — retreating, regrouping, noticing a counter —
## is a consumer of this one signal, which is why it comes before any of them.
##
## WHAT IT MEASURES, and what it cannot. It samples `Bot.army_resource_value()` on the think
## cadence and reads the slope over a short window: how fast, as a fraction of the army, the
## bot is bleeding energy-equivalent value. That is enough to tell a costly fight from a
## cheap one and is the whole of what the army retreat needs.
##
## It is BLIND TO THE ENEMY'S LOSSES, and that blindness is deliberate rather than
## overlooked: the bot sees more of the enemy as it attacks (belief ratchets UP on sighting),
## so any trend taken over believed enemy value reads a successful push as a disaster. The
## honest consequence is that a costly-but-winning fight can read as losing here.
##
## TODO: per-engagement outcome — "did that trade well" — is the measure that would fix it,
## and is the option the design note holds in reserve. It needs an engagement to have a
## beginning and an end, which nothing currently defines. See
## gdd/systems/ai/bot-roadmap.md §Reading the game.
##
## Also note the masking: production RAISES army value while a fight lowers it, so a bot
## reinforcing hard mid-battle reads as losing more slowly than it is.

## Seconds of history the slope is taken over. Long enough that one unit dying is not a
## trend, short enough that the answer is about the fight now rather than the match so far.
const WINDOW_SECONDS: float = 8.0

## Fraction of the army's value per second, sustained across the window, at or above which
## the bot considers itself to be LOSING. 0.03 is ~a quarter of the army over the window.
##
## PLACEHOLDER, on the same footing as the difficulty ramp: the shape is settled, the number
## is what the self-play harness exists to search. It is not a difficulty parameter today —
## reading the game correctly is not a handicap — but it is an obvious candidate to become
## one, since a weak bot noticing late is exactly the kind of handicap a player cannot see.
const LOSING_LOSS_RATE: float = 0.03

var _bot: Bot

## Samples of [time_seconds, army_value], oldest first. Bounded by WINDOW_SECONDS rather
## than by count, so a bot thinking slowly (a low difficulty tier) keeps the same amount of
## HISTORY rather than the same number of readings.
##
## State, and the justification §1.1 asks for: a trend cannot be recomputed from the present
## instant — the past is not derivable from anything else the bot holds.
var _samples: Array = []


func _init(a_bot: Bot) -> void:
	_bot = a_bot


## Work units per owned unit valued (BotScheduler counts work in units of roughly a microsecond
## on the calibration machine).
const UNIT_WORK_UNITS: int = 2


## Take one sample. Runs at the top of the combat jobs (BotBrain), before the military reads the
## signal. Returns the work units spent.
func tick() -> int:
	var now: float = _bot.seconds_elapsed()
	_samples.append([now, _bot.army_resource_value()])
	while _samples.size() > 2 and now - (_samples[0][0] as float) > WINDOW_SECONDS:
		_samples.remove_at(0)
	return _bot.army_size() * UNIT_WORK_UNITS


## Change in army value per second across the window. Negative while losing units.
## 0.0 until there are two samples spanning real time.
func value_slope_per_second() -> float:
	if _samples.size() < 2:
		return 0.0
	var span: float = (_samples[-1][0] as float) - (_samples[0][0] as float)
	if span <= 0.0:
		return 0.0
	return ((_samples[-1][1] as float) - (_samples[0][1] as float)) / span


## How fast the army is bleeding, as a fraction of its CURRENT value per second. Positive
## while losing, 0 while gaining or while there is no army to lose.
func loss_rate() -> float:
	var current: float = _samples[-1][1] if not _samples.is_empty() else 0.0
	if current <= 0.0:
		return 0.0
	return maxf(0.0, -value_slope_per_second() / current)


## The signal itself: is the bot losing right now?
func is_losing() -> bool:
	return loss_rate() >= LOSING_LOSS_RATE


## Army value as of the most recent sample; 0 before the first tick.
func current_value() -> float:
	return _samples[-1][1] if not _samples.is_empty() else 0.0
