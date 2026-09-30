extends GutTest

## A Defend order that took a target and dropped it again on the very next tick, forever.
##
## Acquisition and release were two different tests over two different regions. Defend scans
## for threats around the POST (Commandable.get_aggro_near_position, handed the post as its
## centre) while Attack's ordinary leash is measured from the DEFENDER. Those coincide only
## while the defender happens to be standing on its post — and the whole march out to it is
## time when it is not.
##
## The result was a two-tick cycle: Defend picks up an intruder near the post, the Attack
## fails the leash on the tick it is created, Defend picks it up again. Neither command ever
## reached should_move, so the defender did not move either — it stood where the order was
## given, flickering between two orders, while the intruder walked past. Measured in a
## headless probe: 400 command changes in 400 ticks, zero distance covered.
##
## The fix is one region for both questions — see Defend._leash_to_defended_area.
##
## PATHS, not preloads (see CLAUDE.md): this file sorts early, and a file-scope preload of an
## entity scene poisons the Tool registry for the whole run.

const RECRUIT: Dictionary = FakePieces.SOLDIER
const IRREGULAR: Dictionary = FakePieces.BUILDER
const PLAYER: int = 1
const ENEMY: int = 2

## Far enough from the post that a leash measured from the defender cannot reach back to it,
## and close enough that a walk is plausible. The defender's own aggro radius is under 6.
const MARCH_DISTANCE: float = 24.0


func _unit(a_options: Dictionary, a_commander_id: int) -> Commandable:
	var u := FakePieces.make(a_options) as Commandable
	add_child_autofree(u)
	var c := Commander.new()
	c.id = a_commander_id
	add_child_autofree(c)
	u.ownership.commander = c
	return u


## A Defend order held at `a_post`, and the Attack it would hand back for `a_target`.
## _leash_to_defended_area is what get_updated_state applies to every command it produces;
## producing one takes a physics query, so the stamping is exercised directly.
func _engagement(a_defender: Commandable, a_post: Vector3, a_target: Commandable) -> Attack:
	var defend := Defend.new(CommandMessage.new(null, null, null, a_post))
	var message := CommandMessage.new(null, a_target)
	message.persist = false
	var attack := Attack.new(message)
	defend._leash_to_defended_area(a_defender, attack)
	return attack


func test_the_engagement_is_leashed_to_the_post_not_the_defender() -> void:
	var defender: Commandable = _unit(RECRUIT, PLAYER)
	var post := Vector3(MARCH_DISTANCE, 0.0, 0.0)
	var intruder: Commandable = _unit(IRREGULAR, ENEMY)
	var attack: Attack = _engagement(defender, post, intruder)
	assert_eq(attack.message.aggro_shape, defender.aggro_shape_ground,
		"with no region authored, the defended area is the defender's own aggro range")
	assert_eq(attack.message.aggro_center, post, "centred on the post it is holding")


func test_an_intruder_at_the_post_is_held_while_the_defender_is_still_marching() -> void:
	# The regression. The defender is 24 units from its post; the intruder is 3 units from
	# it. Measured from the defender that is far outside any leash, which is why the order
	# was thrown away the instant it was made.
	var defender: Commandable = _unit(RECRUIT, PLAYER)
	defender.global_position = Vector3.ZERO
	var post := Vector3(MARCH_DISTANCE, 0.0, 0.0)
	var intruder: Commandable = _unit(IRREGULAR, ENEMY)
	intruder.global_position = post + Vector3(3.0, 0.0, 0.0)
	assert_true(_engagement(defender, post, intruder)._target_within_leash(defender),
		"it is in the area this unit was told to defend, so it stays the target")


func test_an_intruder_that_leaves_the_defended_area_is_released() -> void:
	# The leash still has to let go, or a bait drags the defender off its post for good.
	var defender: Commandable = _unit(RECRUIT, PLAYER)
	defender.global_position = Vector3.ZERO
	var post := Vector3(MARCH_DISTANCE, 0.0, 0.0)
	var runner: Commandable = _unit(IRREGULAR, ENEMY)
	runner.global_position = post + Vector3(200.0, 0.0, 0.0)
	assert_false(_engagement(defender, post, runner)._target_within_leash(defender))


func test_an_authored_defend_region_still_wins() -> void:
	# A scripted defend names its own region (the largest aggro shape in the issuing group),
	# and that must keep overriding the fallback — every defender then reacts to the same
	# incursion instead of each one guarding its own little circle.
	var defender: Commandable = _unit(RECRUIT, PLAYER)
	var region: Commandable = _unit(RECRUIT, PLAYER)
	region.global_position = Vector3(100.0, 0.0, 0.0)
	var defend := Defend.new(CommandMessage.new(null, null, null, Vector3.ZERO))
	defend.message.aggro_shape = region.aggro_shape_ground
	var attack := Attack.new(CommandMessage.new(null, _unit(IRREGULAR, ENEMY)))
	defend._leash_to_defended_area(defender, attack)
	assert_eq(attack.message.aggro_shape, region.aggro_shape_ground)
	assert_eq(attack.message.aggro_center, region.aggro_shape_ground.global_transform.origin,
		"pinned where the region stood when the order was given")


func test_an_ordinary_aggro_attack_is_still_leashed_to_its_actor() -> void:
	# Only a Defend names a region. An idle unit that picks a target up on its own must keep
	# chasing it as it moves, which is what measuring from the actor buys.
	var actor: Commandable = _unit(RECRUIT, PLAYER)
	actor.global_position = Vector3.ZERO
	var target: Commandable = _unit(IRREGULAR, ENEMY)
	target.global_position = Vector3(1.0, 0.0, 0.0)
	var message := CommandMessage.new(null, target)
	message.persist = false
	var attack := Attack.new(message)
	assert_null(attack.message.aggro_center, "no region was named")
	assert_true(attack._target_within_leash(actor), "point blank is in range")
	target.global_position = Vector3(200.0, 0.0, 0.0)
	assert_false(attack._target_within_leash(actor), "and a fleeing target is let go")
