extends GutTest

## Tests for MapFavor and GenerationRandom — the arithmetic and the draws the map generator is
## built on (gdd/systems/terrain-and-navigation/map-generation.md §Favor).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapFavor.gd \
##     -gdir=res://tests/none -gexit

func _two_starts() -> Array[MapStart]:
	var starts: Array[MapStart] = [MapStart.at(Vector2(0, 0), 0), MapStart.at(Vector2(10, 0), 1)]
	return starts


#region Access share
func test_a_point_between_the_starts_is_even() -> void:
	var share: PackedFloat32Array = MapFavor.access_share(Vector2(5, 3), _two_starts(), 2)
	assert_almost_eq(share[0], 0.5, 1e-6)
	assert_almost_eq(share[1], 0.5, 1e-6)


func test_a_point_on_a_start_belongs_to_it() -> void:
	var share: PackedFloat32Array = MapFavor.access_share(Vector2(0, 0), _two_starts(), 2)
	assert_almost_eq(share[0], 1.0, 1e-3)


func test_two_alliance_share_is_the_distance_ratio() -> void:
	# d0 = 2, d1 = 8: favor (d1 - d0) / (d0 + d1) = 0.6.
	var share: PackedFloat32Array = MapFavor.access_share(Vector2(2, 0), _two_starts(), 2)
	assert_almost_eq(share[0] - share[1], 0.6, 1e-6)


func test_an_alliance_takes_its_nearest_start() -> void:
	var starts: Array[MapStart] = _two_starts()
	starts.append(MapStart.at(Vector2(20, 0), 0))
	var share: PackedFloat32Array = MapFavor.access_share(Vector2(18, 0), starts, 2)
	assert_gt(share[0], share[1])
#endregion


#region Totals and steering
func test_accessible_value_splits_each_feature_by_its_share() -> void:
	var feature := MapFeature.new()
	feature.value = 100.0
	feature.realised_share = PackedFloat32Array([0.7, 0.3])
	var features: Array[MapFeature] = [feature]
	var totals: PackedFloat32Array = MapFavor.accessible_value(features, 2)
	assert_almost_eq(totals[0], 70.0, 1e-4)
	assert_almost_eq(totals[1], 30.0, 1e-4)


func test_steer_moves_the_mean_and_stays_a_distribution() -> void:
	var steered: PackedFloat32Array = MapFavor.steer(
		PackedFloat32Array([0.5, 0.5]), PackedFloat32Array([0.8, 0.2]))
	assert_almost_eq(steered[0], 0.8, 1e-6)
	var clamped: PackedFloat32Array = MapFavor.steer(
		PackedFloat32Array([0.1, 0.9]), PackedFloat32Array([1.0, 0.0]))
	assert_almost_eq(clamped[0] + clamped[1], 1.0, 1e-6)
	assert_gte(clamped[1], 0.0)


func test_worst_deviation_is_relative_to_the_target() -> void:
	assert_almost_eq(MapFavor.worst_deviation(PackedFloat32Array([110.0, 90.0]), 100.0), 0.1, 1e-6)
	assert_eq(MapFavor.worst_deviation(PackedFloat32Array([0.0, 0.0]), 0.0), 0.0)


func test_share_error_is_half_the_l1_distance() -> void:
	assert_almost_eq(MapFavor.share_error(
		PackedFloat32Array([1.0, 0.0]), PackedFloat32Array([0.0, 1.0])), 1.0, 1e-6)
#endregion


#region Draws
func test_skew_normal_stays_in_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in 200:
		var value: float = GenerationRandom.skew_normal(rng, 32.0, 18.0, 4.0, 30.0, 75.0)
		assert_between(value, 30.0, 75.0)


func test_dirichlet_is_a_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for concentration: float in [0.5, 2.0, 20.0]:
		var draw: PackedFloat32Array = GenerationRandom.dirichlet(rng, 3, concentration)
		assert_almost_eq(draw[0] + draw[1] + draw[2], 1.0, 1e-5)


func test_negative_binomial_has_its_mean() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var draws: int = 4000
	var total: int = 0
	for _i: int in draws:
		var value: int = GenerationRandom.negative_binomial(rng, 2, 0.4)
		assert_gte(value, 0)
		total += value
	# Mean r(1 - p) / p = 3; the tolerance is several standard errors at this draw count.
	assert_almost_eq(float(total) / draws, 3.0, 0.2)


func test_weighted_index_never_picks_a_zero_weight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in 100:
		assert_eq(GenerationRandom.weighted_index(rng, PackedFloat32Array([0.0, 1.0, 0.0])), 1)
	assert_eq(GenerationRandom.weighted_index(rng, PackedFloat32Array([0.0, 0.0])), -1)
#endregion
