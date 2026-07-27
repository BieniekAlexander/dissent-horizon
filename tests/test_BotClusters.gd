extends GutTest

## Unit tests for the bot's clustering primitives — the perception layer's answer to
## "how many enemy forces are there" (enemy_clusters / _cluster_of) and "where should a
## radius-R effect land" (best_covered_point).
##
## The two are deliberately different questions: a group's centroid does not answer the
## coverage one, which is why both exist. best_covered_point is the scan BotSanction's
## aiming and BotKamikaze's blast valuation now share.
##
## Plain Node3Ds stand in wherever only position is read; they are added to the tree so
## their global transforms resolve (an orphan reports none).

var _bot: Bot


func before_each() -> void:
	_bot = Bot.new()
	add_child_autofree(_bot)


## A positioned stand-in at (x, z).
func _at(a_x: float, a_z: float) -> Node3D:
	var n := Node3D.new()
	add_child_autofree(n)
	n.global_position = Vector3(a_x, 0.0, a_z)
	return n


## Everything counts as one body — the weighting BotSanction uses.
func _one(_a_node: Node3D) -> float:
	return 1.0


func test_the_best_drop_point_is_the_tightest_group() -> void:
	var enemies: Array = [_at(0, 0), _at(1, 0), _at(0, 1), _at(50, 50)]
	var best: Dictionary = _bot.best_covered_point(enemies, 6.0, _one)
	assert_eq(best["weight"], 3.0, "catches the three bunched bodies, not the loner")
	assert_almost_eq((best["center"] as Vector3).x, 0.333, 0.05, "centroid of what it caught")


func test_the_drop_point_is_somewhere_a_body_actually_is() -> void:
	# The anchor is always a real candidate, which is what makes the answer reachable.
	var enemies: Array = [_at(0, 0), _at(2, 0)]
	var best: Dictionary = _bot.best_covered_point(enemies, 6.0, _one)
	assert_true(enemies.has(best["anchor"]))


func test_nothing_to_cover_is_a_weightless_answer() -> void:
	var best: Dictionary = _bot.best_covered_point([], 6.0, _one)
	assert_eq(best["weight"], 0.0)
	assert_null(best["anchor"], "no candidate to centre on")


func test_a_radius_too_small_to_reach_anyone_else_still_catches_one() -> void:
	var best: Dictionary = _bot.best_covered_point([_at(0, 0), _at(40, 0)], 1.0, _one)
	assert_eq(best["weight"], 1.0)


func test_weight_beats_headcount() -> void:
	# Two cheap bodies against one valuable one: the scan follows the weight it is given,
	# which is what lets BotKamikaze value a blast rather than count it.
	var prize: Node3D = _at(30, 0)
	var enemies: Array = [_at(0, 0), _at(1, 0), prize]
	var best: Dictionary = _bot.best_covered_point(
		enemies, 3.0, func(n: Node3D): return 100.0 if n == prize else 1.0
	)
	assert_eq(best["anchor"], prize)


# ─── GROUPING ────────────────────────────────────────────────────────────────

## A stand-in enemy: no position (it never enters the tree, so it has none), but real
## health, weaponry, velocity and a price — everything the valuation half reads.
func _enemy(a_cost: int, a_damage: float, a_hp_fraction: float,
		a_velocity: Vector3 = Vector3.ZERO) -> Commandable:
	var c: Commandable = autofree(Commandable.new()) as Commandable
	c.velocity = a_velocity
	c.id = StringName("stand_in_%d_%d" % [a_cost, int(a_damage)])
	_bot.technology_mapping[c.id] = TechnologySpec.new(a_cost, 0, 0, 30)
	var defense := Defense.new()
	defense.hp_max = 100.0
	defense.hp = 100.0 * a_hp_fraction
	c.defense = defense
	c.add_child(defense)
	if a_damage > 0.0:
		var loadout := Loadout.new()
		var weapon := Weapon.new()
		weapon.melee_damage = a_damage
		loadout.add_child(weapon)
		c.weapon_inventory = loadout
		c.add_child(loadout)
	return c


func test_a_groups_centre_is_the_mean_of_its_positions() -> void:
	assert_almost_eq(Bot.centroid_of([_at(0, 0), _at(4, 0), _at(2, 6)]).x, 2.0, 0.01)
	assert_almost_eq(Bot.centroid_of([_at(0, 0), _at(4, 0), _at(2, 6)]).z, 2.0, 0.01)


func test_an_empty_group_has_no_centre() -> void:
	assert_eq(Bot.centroid_of([]), Vector3.ZERO)


func test_a_group_is_priced_at_what_destroying_it_is_worth() -> void:
	var profile: Dictionary = _bot._cluster_profile([_enemy(100, 10.0, 1.0), _enemy(250, 10.0, 1.0)])
	assert_eq(profile["energy_value"], 350.0)


func test_a_wounded_force_is_weaker_than_a_whole_one() -> void:
	var whole: Dictionary = _bot._cluster_profile([_enemy(100, 10.0, 1.0)])
	var wounded: Dictionary = _bot._cluster_profile([_enemy(100, 10.0, 0.25)])
	assert_eq(whole["strength"], 10.0, "full health, full damage output")
	assert_eq(wounded["strength"], 2.5, "strength is damage scaled by what is left of it")


func test_an_unarmed_force_is_priced_but_rates_as_no_threat() -> void:
	var profile: Dictionary = _bot._cluster_profile([_enemy(100, 0.0, 1.0)])
	assert_eq(profile["strength"], 0.0, "it cannot hurt anyone")
	assert_eq(profile["energy_value"], 100.0, "it is still worth killing")


func test_a_groups_heading_is_the_mean_of_its_velocities() -> void:
	var profile: Dictionary = _bot._cluster_profile([
		_enemy(100, 10.0, 1.0, Vector3(1, 0, 0)),
		_enemy(100, 10.0, 1.0, Vector3(3, 0, 0)),
	])
	assert_almost_eq((profile["heading"] as Vector3).x, 2.0, 0.01)


func test_an_empty_group_has_no_heading() -> void:
	assert_eq(_bot._cluster_profile([])["heading"], Vector3.ZERO)
