class_name BotPosture
extends RefCounted

## THE POSTURE LAYER: four dials above every decision the bot makes, recomputed from its
## signals and holding still between changes (gdd/systems/ai/objective-selection.md).
##
## A dial runs from 0 to 1 — `commitment` booming → all-in, `aggression` defensive →
## offensive, `risk` cautious → greedy, `curiosity` blind → informed — and DECIDES NOTHING
## ITSELF: it multiplies the difficulty parameters the decision modules already read
## (`applied_to`), so all-in and booming are the same decisions with different weights rather
## than modes a player could name. Each dial reads the one or two signals the note assigns it,
## a gain per pair and a bias per dial (decided 2026-10-09, over a full linear map and over an
## authored mapping): the bias is where the dial rests, and a gain of 0 — every tier's
## default — leaves the parameters exactly as the tier set them.
##
## HYSTERESIS (decided 2026-10-09, over smoothing): a dial moves only when its target has
## stood more than `dead_band` away from the held value for `hold_seconds` without returning,
## and then SNAPS to it. A posture that drifts with every wobble of a signal is noise; one that
## holds and then changes reads as a decision, which is what makes it legible to a player.
## The first update snaps outright — there is no history to hold against. State, and the
## reason: hysteresis is by definition a function of the past, which nothing else holds.
##
## The dials' reach into the parameter table is `DIVIDED_BY_DIAL`: a higher dial DIVIDES each
## field it names by `factor`, 2^(2d−1), so 0.5 changes nothing, 1 halves and 0 doubles. The
## curiosity dial has no field here: BotBrain scales BotScout's information price by it.

enum Dial { COMMITMENT, AGGRESSION, RISK, CURIOSITY }
const DIAL_COUNT: int = 4
const DIAL_NAMES: PackedStringArray = ["commitment", "aggression", "risk", "curiosity"]

## The signal keys `update` reads. Each is in [−1, 1] (the leads) or [0, 1] (the rest); a
## missing key reads as 0, which leaves the dial at its bias.
const SIGNAL_ECONOMY_LEAD: String = "economy_lead"
const SIGNAL_ARMY_LEAD: String = "army_lead"
const SIGNAL_EXPOSURE: String = "exposure"
const SIGNAL_MOMENTUM: String = "momentum"
const SIGNAL_THREAT: String = "threat"
const SIGNAL_STALE: String = "stale"

## A dial at this value multiplies nothing: 2^(2 × 0.5 − 1) = 1.
const NEUTRAL: float = 0.5
## What a dial at 1 multiplies a parameter by (and a dial at 0 divides it by).
const MODULATION_SPAN: float = 2.0

## The BotDifficulty fields each dial divides by its factor, so a higher dial LOWERS them: all-in
## wants fewer extractors before production and commits at a lower count; offence launches at
## a lower value ratio and holds less home; greed banks less and builds where it is cheap rather
## than where it is safe or spread. Sentinels (a value outside the
## field's search range) are never moved, exactly as the personality draw leaves them.
const DIVIDED_BY_DIAL: Dictionary = {
	Dial.COMMITMENT: ["income_structure_target", "army_commit_threshold"],
	Dial.AGGRESSION: ["attack_value_ratio", "guard_strength_ratio"],
	Dial.RISK: ["economy_reserve", "place_safety_weight", "place_spacing_weight"],
}

#region Parameters — pushed from BotDifficulty by read_params
var commitment_economy_gain: float = 0.0
var aggression_army_gain: float = 0.0
var aggression_exposure_gain: float = 0.0
var risk_momentum_gain: float = 0.0
var risk_threat_gain: float = 0.0
var curiosity_stale_gain: float = 0.0
var commitment_bias: float = NEUTRAL
var aggression_bias: float = NEUTRAL
var risk_bias: float = NEUTRAL
var curiosity_bias: float = NEUTRAL
var dead_band: float = 0.1
var hold_seconds: float = 10.0
#endregion

## The held dials; empty before the first update, when every dial reads NEUTRAL.
var _held: PackedFloat64Array = PackedFloat64Array()
## The targets of the last update, for the readout.
var _targets: PackedFloat64Array = PackedFloat64Array()
## Per dial, when its target first left the dead band; INF while it is inside.
var _left_band_at: PackedFloat64Array = PackedFloat64Array()


## Take the gains, biases and hysteresis from a difficulty config.
func read_params(a_config: BotDifficulty) -> void:
	commitment_economy_gain = a_config.commitment_economy_gain
	aggression_army_gain = a_config.aggression_army_gain
	aggression_exposure_gain = a_config.aggression_exposure_gain
	risk_momentum_gain = a_config.risk_momentum_gain
	risk_threat_gain = a_config.risk_threat_gain
	curiosity_stale_gain = a_config.curiosity_stale_gain
	commitment_bias = a_config.commitment_bias
	aggression_bias = a_config.aggression_bias
	risk_bias = a_config.risk_bias
	curiosity_bias = a_config.curiosity_bias
	dead_band = a_config.posture_dead_band
	hold_seconds = a_config.posture_hold_seconds


## THE MAPPING: each dial's target from the signals, bias plus gain × signal, clamped to [0, 1].
func targets_for(a_signals: Dictionary) -> PackedFloat64Array:
	var economy: float = float(a_signals.get(SIGNAL_ECONOMY_LEAD, 0.0))
	var army: float = float(a_signals.get(SIGNAL_ARMY_LEAD, 0.0))
	var exposure: float = float(a_signals.get(SIGNAL_EXPOSURE, 0.0))
	var momentum: float = float(a_signals.get(SIGNAL_MOMENTUM, 0.0))
	var threat: float = float(a_signals.get(SIGNAL_THREAT, 0.0))
	var stale: float = float(a_signals.get(SIGNAL_STALE, 0.0))
	return PackedFloat64Array(
		[
			clampf(commitment_bias + commitment_economy_gain * economy, 0.0, 1.0),
			clampf(
				aggression_bias + aggression_army_gain * army + aggression_exposure_gain * exposure,
				0.0,
				1.0
			),
			clampf(risk_bias + risk_momentum_gain * momentum + risk_threat_gain * threat, 0.0, 1.0),
			clampf(curiosity_bias + curiosity_stale_gain * stale, 0.0, 1.0),
		]
	)


## Recompute the targets at `a_now` seconds and move whichever dials have held out of the dead
## band for the hold. Returns true when any dial moved (the first update moves them all).
func update(a_signals: Dictionary, a_now: float) -> bool:
	_targets = targets_for(a_signals)
	if _held.is_empty():
		_held = _targets.duplicate()
		_left_band_at = PackedFloat64Array([INF, INF, INF, INF])
		return true
	var moved: bool = false
	for i: int in DIAL_COUNT:
		if absf(_targets[i] - _held[i]) <= dead_band:
			_left_band_at[i] = INF
			continue
		if _left_band_at[i] == INF:
			_left_band_at[i] = a_now
		if a_now - _left_band_at[i] >= hold_seconds:
			_held[i] = _targets[i]
			_left_band_at[i] = INF
			moved = true
	return moved


## The held value of a dial; NEUTRAL before the first update.
func dial(a_dial: Dial) -> float:
	return _held[a_dial] if not _held.is_empty() else NEUTRAL


## What a dial multiplies the parameters it reaches by.
func factor(a_dial: Dial) -> float:
	return factor_of(dial(a_dial))


## 2^(2d − 1): NEUTRAL multiplies by 1, 1 by MODULATION_SPAN, 0 by its reciprocal.
static func factor_of(value: float) -> float:
	return pow(MODULATION_SPAN, 2.0 * value - 1.0)


## A copy of `a_config` with the fields in DIVIDED_BY_DIAL modulated by the held dials — the
## parameters the bot PLAYS BY this posture, where `a_config` is what it was given.
func applied_to(a_config: BotDifficulty) -> BotDifficulty:
	var out: BotDifficulty = a_config.copied()
	for which: Dial in DIVIDED_BY_DIAL:
		for field: String in DIVIDED_BY_DIAL[which]:
			modulate(out, field, 1.0 / factor(which))
	return out


## Multiply one searchable field in place, clamped to its search range (the range is what the
## field means: a commit ratio below the stalemate floor, say, is not a posture). A sentinel —
## a value outside the range — is left alone. Ints stay ints.
static func modulate(config: BotDifficulty, field: String, multiplier: float) -> void:
	var lo: float = float(BotDifficulty.SEARCH_RANGES[field][0])
	var hi: float = float(BotDifficulty.SEARCH_RANGES[field][1])
	var current: Variant = config.get(field)
	if float(current) < lo or float(current) > hi:
		return
	var moved: float = clampf(float(current) * multiplier, lo, hi)
	config.set(field, roundi(moved) if typeof(current) == TYPE_INT else moved)


## Dial name → held value, for the brain sample and the readout.
func dials() -> Dictionary:
	var out: Dictionary = {}
	for i: int in DIAL_COUNT:
		out[DIAL_NAMES[i]] = dial(i as Dial)
	return out


## Per dial: its held value, its last target, its factor, and how long until a target outside
## the band is taken (−1 while inside).
func debug_state(a_now: float) -> Array:
	var out: Array = []
	for i: int in DIAL_COUNT:
		var since: float = _left_band_at[i] if not _left_band_at.is_empty() else INF
		(
			out
			. append(
				{
					"name": DIAL_NAMES[i],
					"held": dial(i as Dial),
					"target": _targets[i] if not _targets.is_empty() else NEUTRAL,
					"factor": factor(i as Dial),
					"snaps_in": maxf(0.0, hold_seconds - (a_now - since)) if since != INF else -1.0,
				}
			)
		)
	return out
