class_name BotMomentum
extends RefCounted

## BotMomentum — WHETHER THE BOT IS WINNING OR LOSING, read two ways: the ARMY'S value trend,
## and the balance of THE FRONT a wave stands on.
##
## Before this existed nothing in the bot read its own position. `relative_threat_level()`
## computed an instantaneous strength ratio that no module consumed, and the blackboard
## recorded what exists and where but never what CHANGED. Every behaviour that separates a
## deliberate opponent from a scripted one — retreating, regrouping, noticing a counter —
## is a consumer of one of these two signals, which is why they come before any of them.
##
## THE GLOBAL READ samples `Bot.army_resource_value()` on the think cadence and reads the slope
## over a short window: how fast, as a fraction of the army, the bot is bleeding
## energy-equivalent value. It is BLIND TO THE ENEMY'S LOSSES, deliberately: the bot sees more
## of the enemy as it attacks (belief ratchets UP on sighting), so a trend over believed enemy
## value would read a successful push as a disaster. And it is DILUTED: home units and
## production raise the army's value while a wave bleeds at the front, so a bot reinforcing
## hard mid-battle reads as losing more slowly than its wave is. Both make it the wrong read
## for a wave's retreat, and the right one for the questions it still answers — the economy's
## "is it safe to expand right now" (BotEconomy) and the posture layer's risk dial
## (BotBrain.posture_signals): both are about the BOT's situation, not a front's.
##
## THE FRONT READ (front_balance; Alex, 2026-10-31, decision-pathologies.md §Rulings) is what
## the wave's retreat consumes: the bot's own and the believed enemy's ANSWERABLE strength
## reaching the wave's leading edge, from BotFields' strength fields, as a share, and the share's
## trend over the last few samples. A wave meeting a force that outguns it reads as
## losing the moment the fields show it, however the army at home is growing; a raid killing
## units at home does not touch a wave that is winning its own front. The enemy's losses count
## here where they could not above: a believed enemy that dies in sight leaves the belief.

## Seconds of history a trend is taken over. Long enough that one unit dying is not a
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

## THE FRONT IS LOST when the wave's share of the answerable strength there — own / (own +
## enemy), 0.5 even — is at or under this: the enemy at the front is worth at least one and a
## half times the wave, a force it cannot beat. A PLACEHOLDER like LOSING_LOSS_RATE: the shape
## is the rule, the number is the harness's to search.
const FRONT_LOSING_SHARE: float = 0.4
## THE FRONT IS SLIPPING when the share is under even and falling at least this much per
## second — a tenth of the balance over the window — so an even fight that is going the
## enemy's way is left before it is decisively lost, and one that is holding is not.
const FRONT_SLIPPING_PER_SECOND: float = 0.01
## The share of a front where the two sides are equal, or where nothing stands on either side.
const EVEN_SHARE: float = 0.5

var _bot: Bot

## Samples of [time_seconds, army_value], oldest first. Bounded by WINDOW_SECONDS rather
## than by count, so a bot thinking slowly (a low difficulty tier) keeps the same amount of
## HISTORY rather than the same number of readings.
##
## State, and the justification §1.1 asks for: a trend cannot be recomputed from the present
## instant — the past is not derivable from anything else the bot holds.
var _samples: Array = []
## Samples of [time_seconds, share] of the front, oldest first, kept like _samples and for the
## same reason; emptied when the wave they describe ends (forget_front).
var _front_samples: Array = []
## The last front read, as front_balance returned it, or empty before a wave reads one — what
## the match sample and the overlay show without taking a sample of their own.
var _last_front: Dictionary = {}


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
	_prune(_samples, now)
	return _bot.army_size() * UNIT_WORK_UNITS


## Change in army value per second across the window. Negative while losing units.
## 0.0 until there are two samples spanning real time.
func value_slope_per_second() -> float:
	return _slope(_samples)


## How fast the army is bleeding, as a fraction of its CURRENT value per second. Positive
## while losing, 0 while gaining or while there is no army to lose.
func loss_rate() -> float:
	var current: float = _samples[-1][1] if not _samples.is_empty() else 0.0
	if current <= 0.0:
		return 0.0
	return maxf(0.0, -value_slope_per_second() / current)


## The global signal: is the bot's army bleeding right now?
func is_losing() -> bool:
	return loss_rate() >= LOSING_LOSS_RATE


## Army value as of the most recent sample; 0 before the first tick.
func current_value() -> float:
	return _samples[-1][1] if not _samples.is_empty() else 0.0


# ─── THE FRONT ───────────────────────────────────────────────────────────────


## READ THE FRONT AT `a_position` — the wave's leading edge — and take a sample of it: {"own",
## "enemy": the answerable strength whose reach covers it (BotFields.front_strength_at),
## "share": own / (own + enemy), EVEN_SHARE where nothing stands on either side, "trend": the
## share's change per second over the window, 0 until two samples span real time}. EMPTY when
## the bot has no fields to read (BotFields is off for the tier, or there is no map): the
## consumer then falls back to the global read, as it did before the fields existed.
func front_balance(a_position: Vector3) -> Dictionary:
	var fields: BotFields = _bot.fields()
	if fields == null:
		return {}
	var strength: Dictionary = fields.front_strength_at(VU.in_xz(a_position))
	var share: float = share_of(float(strength["own"]), float(strength["enemy"]))
	var now: float = _bot.seconds_elapsed()
	_front_samples.append([now, share])
	_prune(_front_samples, now)
	_last_front = {
		"own": float(strength["own"]),
		"enemy": float(strength["enemy"]),
		"share": share,
		"trend": _slope(_front_samples),
	}
	return _last_front


## The front read as of the last front_balance; empty before one, or after forget_front.
func last_front() -> Dictionary:
	return _last_front


## Drop the front's history: the wave it described has ended, or a new one has launched, and
## the next wave's first sample is not a trend from the last one's.
func forget_front() -> void:
	_front_samples = []
	_last_front = {}


## THE FRONT RULE: a front read (front_balance's answer) is LOST when the wave's share is at or
## under FRONT_LOSING_SHARE, or under even and falling at FRONT_SLIPPING_PER_SECOND or faster.
## A wave whose own answerable strength is nothing against an enemy that can hurt it — infantry
## under aircraft it cannot shoot — has a share of 0 and is lost at once, which is the retreat
## eighty Recruits under five Clippers never made.
static func is_losing_front(front: Dictionary) -> bool:
	var share: float = float(front.get("share", EVEN_SHARE))
	if share <= FRONT_LOSING_SHARE:
		return true
	return share < EVEN_SHARE and float(front.get("trend", 0.0)) <= -FRONT_SLIPPING_PER_SECOND


## The wave's share of a front: own / (own + enemy); EVEN_SHARE with nothing on either side.
static func share_of(own: float, enemy: float) -> float:
	var total: float = own + enemy
	if total <= 0.0:
		return EVEN_SHARE
	return own / total


## Drop `samples` older than the window before `now`, keeping at least the last two.
static func _prune(samples: Array, now: float) -> void:
	while samples.size() > 2 and now - (samples[0][0] as float) > WINDOW_SECONDS:
		samples.remove_at(0)


## The slope of `samples`' values per second, first to last; 0 until two span real time.
static func _slope(samples: Array) -> float:
	if samples.size() < 2:
		return 0.0
	var span: float = (samples[-1][0] as float) - (samples[0][0] as float)
	if span <= 0.0:
		return 0.0
	return ((samples[-1][1] as float) - (samples[0][1] as float)) / span
