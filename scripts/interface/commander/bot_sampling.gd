class_name BotSampling
extends RefCounted

## BotSampling — a scored choice made with a TEMPERATURE instead of an argmax.
##
## Every scored decision in the bot ranked its options and took the best, so two matches on
## one map made the same choices. These statics draw instead: an option's weight is
## exp((score − best) / (τ · |best|)), so τ is RELATIVE — "an option within τ of the best is a
## live alternative" — and the same number means the same thing whether the scores are in
## energy (BotOpportunist), effectiveness × demand (BotProduction) or a normalised sum
## (BotScout). τ = 0, or no generator, is the argmax the bot had before, so a manager built
## without one in a test is exactly as deterministic as it was.
##
## The generator is the BOT'S OWN (BotBrain.rng), never SU.rng: two bots drawing from one
## shared stream in interleaved order get order-dependent numbers, which is the world-frame
## placement bug in another costume (gdd/systems/ai/bot-randomness.md).

## Below this a temperature is treated as zero — a τ that small cannot lift any weight above
## float noise, and dividing by it would.
const MIN_TEMPERATURE: float = 1.0e-6


## The index of the chosen item, or -1 when there is nothing to choose from.
static func pick(a_scores: Array, a_temperature: float, a_rng: RandomNumberGenerator) -> int:
	if a_scores.is_empty():
		return -1
	var weights: PackedFloat64Array = _weights(a_scores, a_temperature, a_rng)
	if weights.is_empty():
		return _argmax(a_scores)
	return _draw(weights, a_rng)


## Every index, in a sampled order: the first is drawn as `pick` would, the second from what
## is left, and so on (a Plackett–Luce draw). τ = 0 is a stable sort, best first.
static func order(
	a_scores: Array, a_temperature: float, a_rng: RandomNumberGenerator
) -> Array[int]:
	var out: Array[int] = []
	var remaining: Array[int] = []
	for i: int in a_scores.size():
		remaining.append(i)
	var weights: PackedFloat64Array = _weights(a_scores, a_temperature, a_rng)
	if weights.is_empty():
		remaining.sort_custom(
			func(a: int, b: int) -> bool: return float(a_scores[a]) > float(a_scores[b])
		)
		return remaining
	while not remaining.is_empty():
		var local: PackedFloat64Array = PackedFloat64Array()
		for i: int in remaining:
			local.append(weights[i])
		var chosen: int = remaining[_draw(local, a_rng)]
		out.append(chosen)
		remaining.erase(chosen)
	return out


## The weights, or an EMPTY array when the draw degenerates to an argmax: no generator, a
## temperature at zero, or a best score that is not positive (the relative scale has no
## meaning below zero, and nothing in the bot scores an option it wants at or under 0).
static func _weights(
	a_scores: Array, a_temperature: float, a_rng: RandomNumberGenerator
) -> PackedFloat64Array:
	var empty: PackedFloat64Array = PackedFloat64Array()
	if a_rng == null or a_temperature < MIN_TEMPERATURE or a_scores.is_empty():
		return empty
	var best: float = float(a_scores[_argmax(a_scores)])
	if best <= 0.0:
		return empty
	var scale: float = a_temperature * best
	var weights: PackedFloat64Array = PackedFloat64Array()
	for score: Variant in a_scores:
		weights.append(exp((float(score) - best) / scale))
	return weights


static func _argmax(a_scores: Array) -> int:
	var best: int = 0
	for i: int in range(1, a_scores.size()):
		if float(a_scores[i]) > float(a_scores[best]):
			best = i
	return best


## One weighted draw over `a_weights`, which are all positive.
static func _draw(a_weights: PackedFloat64Array, a_rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for w: float in a_weights:
		total += w
	var r: float = a_rng.randf() * total
	for i: int in a_weights.size():
		r -= a_weights[i]
		if r <= 0.0:
			return i
	return a_weights.size() - 1
