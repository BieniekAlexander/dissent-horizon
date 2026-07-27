@tool
class_name MapFavor
extends RefCounted

## Favor arithmetic: how much of a feature each alliance can reach, and what a currency adds up
## to. Pure and static. The definitions and why they are these are map-generation.md §Favor.

#region Constants
## Distance floor, so a feature exactly on a start gives that alliance all of it instead of
## dividing by zero.
const MIN_DISTANCE_CELLS: float = 0.001
#endregion


## Access share per alliance of a feature at `point`: inverse distance to each alliance's
## nearest start, normalised to sum to 1. An alliance with no start gets 0.
static func access_share(
	point: Vector2, starts: Array[MapStart], alliance_count: int
) -> PackedFloat32Array:
	var nearest := PackedFloat32Array()
	nearest.resize(alliance_count)
	nearest.fill(INF)
	for start: MapStart in starts:
		nearest[start.alliance] = minf(nearest[start.alliance], point.distance_to(start.position))
	var share := PackedFloat32Array()
	share.resize(alliance_count)
	var total: float = 0.0
	for a: int in alliance_count:
		share[a] = 0.0 if is_inf(nearest[a]) else 1.0 / maxf(nearest[a], MIN_DISTANCE_CELLS)
		total += share[a]
	if total > 0.0:
		for a: int in alliance_count:
			share[a] /= total
	return share


## Accessible value per alliance: each feature's value split by its realised share.
static func accessible_value(
	features: Array[MapFeature], alliance_count: int
) -> PackedFloat32Array:
	var totals := PackedFloat32Array()
	totals.resize(alliance_count)
	for feature: MapFeature in features:
		for a: int in alliance_count:
			totals[a] += feature.value * feature.realised_share[a]
	return totals


## Half the L1 distance between two share vectors: 0 when equal, 1 when disjoint. For two
## alliances it is half the difference in favor.
static func share_error(share: PackedFloat32Array, target: PackedFloat32Array) -> float:
	var error: float = 0.0
	for a: int in share.size():
		error += absf(share[a] - target[a])
	return error * 0.5


## Aim a feature at `desired` plus `freedom` of the random draw's lean (`raw` minus an even
## split), projected back onto the simplex (clamp to non-negative, renormalise). `freedom` is
## the share of the currency's value still to come AFTER this feature: the last feature has
## none, so it aims exactly where balance needs it, and early ones may lean because later ones
## can make up for it.
static func steer(
	raw: PackedFloat32Array, desired: PackedFloat32Array, freedom: float = 1.0
) -> PackedFloat32Array:
	var k: int = raw.size()
	var even: float = 1.0 / float(k)
	var steered := PackedFloat32Array()
	steered.resize(k)
	var total: float = 0.0
	for a: int in k:
		steered[a] = maxf(0.0, desired[a] + (raw[a] - even) * freedom)
		total += steered[a]
	for a: int in k:
		steered[a] = steered[a] / total if total > 0.0 else even
	return steered


## Largest relative deviation of any alliance's accessible value from `target_each`. 0 for a
## currency with nothing in it — there is nothing to be unfair about.
static func worst_deviation(accessible: PackedFloat32Array, target_each: float) -> float:
	if target_each <= 0.0:
		return 0.0
	var worst: float = 0.0
	for value: float in accessible:
		worst = maxf(worst, absf(value - target_each) / target_each)
	return worst
