extends GutTest

## Unit tests for BotSanction's target-selection math — the novel decision logic
## the bot uses to aim commander sanctions. Plain Node3D nodes stand in for enemy
## units; the clustering math only reads global_position. They're added to the test
## tree so their global transforms resolve (an orphan node reports a zero global
## position).
##
## A bare Bot (never added to the tree) is enough to construct BotSanction: its
## faction is null (→ no owned sanctions) and seconds_elapsed() returns 0, so
## _init does no work. We then call the decision helpers directly. The actuator is null
## because nothing here casts — these tests are about WHERE a sanction is aimed, and the
## cast itself now goes through UseSanction like the player's.

var _bot: Bot
var _bo: BotSanction


func before_each() -> void:
	_bot = Bot.new()
	_bo = BotSanction.new(_bot, null)


func after_each() -> void:
	_bot.free()


## A positioned stand-in enemy unit. Added to the tree so global_position resolves.
func _unit_at(a_x: float, a_z: float) -> Node3D:
	var u := Node3D.new()
	add_child_autofree(u)
	u.global_position = Vector3(a_x, 0.0, a_z)
	return u


func test_densest_cluster_picks_the_tightest_group() -> void:
	# Three units bunched near the origin; one loner far away.
	var enemies := [_unit_at(0, 0), _unit_at(1, 0), _unit_at(0, 1), _unit_at(50, 50)]
	var cluster: Dictionary = _bo._densest_cluster(enemies, 6.0)
	assert_eq(cluster["count"], 3, "catches the three bunched units, not the loner")
	# Centre is the centroid of the three caught units (~0.33 in X and Z).
	assert_almost_eq((cluster["center"] as Vector3).x, 0.333, 0.05)


func test_densest_cluster_empty_is_zero() -> void:
	var cluster: Dictionary = _bo._densest_cluster([], 6.0)
	assert_eq(cluster["count"], 0)


func test_aim_enemy_cluster_returns_centre_when_enough_targets() -> void:
	var ord := Sanction.new()
	ord.targeting = Sanction.Targeting.ENEMY_CLUSTER
	ord.effect_radius = 6.0
	ord.min_targets = 2
	var zone := {
		"mode": BotSanction.Mode.ATTACK,
		"enemies": [_unit_at(0, 0), _unit_at(1, 0)],
		"anchor": Vector3(20, 0, 20),
	}
	assert_not_null(_bo._aim(ord, zone), "two clustered targets meets min_targets = 2")


func test_aim_enemy_cluster_holds_when_below_min_targets() -> void:
	var ord := Sanction.new()
	ord.targeting = Sanction.Targeting.ENEMY_CLUSTER
	ord.effect_radius = 6.0
	ord.min_targets = 3
	var zone := {
		"mode": BotSanction.Mode.ATTACK,
		"enemies": [_unit_at(0, 0), _unit_at(1, 0)],  # only 2 < 3
		"anchor": Vector3(20, 0, 20),
	}
	assert_null(_bo._aim(ord, zone), "won't spend an AoE on too few targets")


func test_aim_reinforce_on_defense_targets_the_anchor() -> void:
	var ord := Sanction.new()
	ord.targeting = Sanction.Targeting.REINFORCE
	var anchor := Vector3(5, 0, 5)
	var zone := {"mode": BotSanction.Mode.DEFEND, "enemies": [_unit_at(5, 5)], "anchor": anchor}
	assert_eq(_bo._aim(ord, zone), anchor, "defensive reinforcements spawn at the defended structure")


func test_aim_reinforce_on_attack_lands_between_us_and_them() -> void:
	var ord := Sanction.new()
	ord.targeting = Sanction.Targeting.REINFORCE
	ord.effect_radius = 6.0
	var zone := {
		"mode": BotSanction.Mode.ATTACK,
		"enemies": [_unit_at(10, 0)],  # their cluster
		"anchor": Vector3(0, 0, 0),    # our army
	}
	var target: Vector3 = _bo._aim(ord, zone)
	# REINFORCE_PUSH = 0.5 → midway toward the enemy: allies land on our side of the front.
	assert_almost_eq(target.x, 5.0, 0.5)


func test_engagement_zone_is_null_with_no_enemies() -> void:
	# A bare bot owns nothing and sees nothing → hold (don't waste a charge).
	assert_null(_bo._engagement_zone())
