@tool
class_name GenerationRandom
extends RefCounted

## The distributions the generator draws from, over a caller-owned seeded generator so a map
## is reproducible from its seed. Pure and static.

#region Constants
## Redraws a bounded draw may take before it clamps instead.
const _BOUNDED_REDRAWS: int = 32
## Marsaglia-Tsang needs shape >= 1; smaller shapes are boosted and corrected by this power.
const _GAMMA_BOOST: float = 1.0
#endregion


## A skew-normal draw (Azzalini), redrawn until inside [low, high] and clamped if it never
## lands. Positive `skew` leans the long tail upward.
static func skew_normal(
	rng: RandomNumberGenerator, location: float, scale: float, skew: float, low: float, high: float
) -> float:
	var delta: float = skew / sqrt(1.0 + skew * skew)
	var value: float = location
	for _i: int in _BOUNDED_REDRAWS:
		var u0: float = rng.randfn()
		var v: float = rng.randfn()
		value = location + scale * (delta * absf(u0) + sqrt(1.0 - delta * delta) * v)
		if value >= low and value <= high:
			return value
	return clampf(value, low, high)


## Failures before `successes` successes of chance `success_chance` — a sum of geometric
## draws, each by inversion.
static func negative_binomial(
	rng: RandomNumberGenerator, successes: int, success_chance: float
) -> int:
	var failures: int = 0
	for _i: int in successes:
		failures += floori(log(1.0 - rng.randf()) / log(1.0 - success_chance))
	return failures


## A Gamma(shape, 1) draw — Marsaglia and Tsang, with the shape < 1 boost.
static func gamma(rng: RandomNumberGenerator, shape: float) -> float:
	if shape < 1.0:
		return gamma(rng, shape + _GAMMA_BOOST) * pow(rng.randf(), 1.0 / shape)
	var d: float = shape - 1.0 / 3.0
	var c: float = 1.0 / sqrt(9.0 * d)
	while true:
		var x: float = rng.randfn()
		var v: float = pow(1.0 + c * x, 3.0)
		if v <= 0.0:
			continue
		var u: float = rng.randf()
		if log(maxf(u, 1e-12)) < 0.5 * x * x + d - d * v + d * log(v):
			return d * v
	return d


## A symmetric Dirichlet draw over `count` components.
static func dirichlet(
	rng: RandomNumberGenerator, count: int, concentration: float
) -> PackedFloat32Array:
	var draw := PackedFloat32Array()
	draw.resize(count)
	var total: float = 0.0
	for i: int in count:
		draw[i] = gamma(rng, concentration)
		total += draw[i]
	for i: int in count:
		draw[i] = draw[i] / total if total > 0.0 else 1.0 / float(count)
	return draw


## Index drawn in proportion to `weights`. -1 when every weight is zero.
static func weighted_index(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int:
	var total: float = 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return -1
	var pick: float = rng.randf() * total
	for i: int in weights.size():
		pick -= maxf(weights[i], 0.0)
		if pick < 0.0:
			return i
	return weights.size() - 1
