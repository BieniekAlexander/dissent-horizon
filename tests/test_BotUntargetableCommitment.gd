extends GutTest

## AN ORDER A UNIT CANNOT CARRY OUT IS NOT AN ORDER, AND A PLACE NOTHING IN THE ARMY CAN
## HURT IS NOT AN OBJECTIVE.
##
## Reported from a watched Colonial-vs-Colonial match (gdd/tasks.md §Feedback Notes):
##
##   "Bot units appear to be receiving commands to attack targets which aren't applicable
##    for their weapon. For example, I placed a scan drone near the enemy base, and several
##    units had received a command to attack it … their weapons can't target it, so they
##    sort of waited near their target until it had expired."
##
## The scan drone (`scenes/entities/scout.tscn`) is the perfect witness: it is HOVERING, so
## `Entity._apply_targetable_layers` files it on TARGETABLE_AIR alone, and a ground-only
## loadout has no targeting mode for it whatsoever. That is a DIFFERENT fact from a damage
## multiplier of zero — `Bot.unit_effectiveness_vs` answers 0 for both — and the difference
## is exactly what the bot never asked. `Loadout.weapon_for_target` is the honest question,
## and aggro (`Commandable.get_aggro_near_position`) and `BotTargeting._retarget` had always
## asked it; the two places that did not were the ones that decide where an army GOES and
## what a drone COMMITS to.
##
## Three layers are pinned here, outermost first:
##   • `BotMilitary._objective_for(ATTACK)` — an army does not adopt a belief no member of
##     it can damage, and does not march at a belief the walk has already disproved.
##   • `Bot.kamikaze_best_target` — a suicide drone does not anchor a blast on a body it
##     cannot strike (it is HELD instead, which is BotKamikaze's designed answer).
##   • `BotActuator.attack` — the floor under both: the one place the bot issues an Attack
##     refuses to issue an impossible one. Nothing downstream would: `update_commands` does
##     not consult preconditions (that is the player UI's job), and a persistent Attack with
##     no usable weapon returns `self` from `get_updated_state` forever — the unit stands
##     next to its target holding an order it can neither finish nor abandon.
##
## See gdd/systems/ai/bot-engagement-fixes.md §The objective nobody could act on.
##
## Fixture note: pieces are STUBS that skip the full entity scene but ARE in the tree
## (`global_position` and `targetable_layers()` need that), same shape as
## tests/test_BotHostileTargets.gd. The scan drone is the REAL scene, because the reported
## bug is about that piece's real layers.

## The scan drone's scene, loaded INSIDE a test rather than preloaded at file scope: a
## file-scope preload of an entity scene fires Tool's static registry initialiser too early
## (see CLAUDE.md and tests/test_AirTargetAltitude.gd).
const SCOUT_SCENE: String = "res://scenes/entities/nt_aircraftLight_recon.tscn"


## A Commandable with the children Entity/Commandable resolve with a hard `$`, and nothing
## else. No Movement — which is also what keeps `load_destination` a no-op, so the actuator
## can be exercised without a navigation rig.
##
## Two additions over the stub in tests/test_BotHostileTargets.gd, both because this file is
## about TARGETING rather than about distances:
##   • a TargetBody, which is where `targetable_layers()` reads the ground/air bit from — a
##     stub without one is targetable by nothing at all, which would make every assertion
##     here pass for the wrong reason;
##   • `command_receiver.initialize`, normally done by Commandable._ready (which this stub
##     skips), so an order the actuator DOES issue can actually land on the piece.
class StubPiece:
	extends Commandable

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [["Ownership", Ownership.new()],
				["AvoidanceObstacle", NavigationObstacle3D.new()],
				["Veterancy", Veterancy.new()],
				["TargetBody", StaticBody3D.new()]]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		var bar := Node3D.new()
		bar.name = "HPBar"
		var fill := Sprite3D.new()
		fill.name = "HPBarFill"
		bar.add_child(fill)
		piece.add_child(bar)
		return piece

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		command_receiver.initialize(self)


## A Bot whose suicide profile and vision are supplied rather than derived, so the kamikaze
## blast scan can be exercised without a faction, a tech tree or a train preview. Only the
## three inputs `kamikaze_best_target` reads are replaced; the scan itself is the real one.
class ProbeBot:
	extends Bot

	## Damage big enough to overkill a 100 HP stub whatever the armour column says, so the
	## blast's WORTH is decided by which bodies are candidates rather than by the damage table.
	var profile: Variant = {"radius": 6.0, "damage": 5000.0, "type": Damage.Type.EXPLOSIVE}
	var seen: Array = []
	## Only THIS piece id is a suicide unit. Answering for every id would make
	## `Bot.is_suicide_aoe_unit` true for the whole roster, and `BotMilitary._combat_units`
	## excludes kamikazes — the army would come out empty and every objective assertion below
	## would be testing an empty army rather than a ground-only one.
	var suicide_id: StringName = &"nobody"

	func aoe_suicide_profile(a_unit_type) -> Variant:
		return profile if a_unit_type == suicide_id else null

	func visible_enemies() -> Array:
		return seen

	func unit_cost(_a_unit_type) -> int:
		return 100


var _scenario: Scenario
var _bot: ProbeBot
var _foe: Commander


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = _commander(ProbeBot.new(), 1) as ProbeBot
	_foe = _commander(Commander.new(), 2)
	_scenario.commanders = [_bot, _foe]


func _commander(a_commander: Commander, a_id: int) -> Commander:
	a_commander.id = a_id
	a_commander.initialize(null, _scenario)
	add_child_autofree(a_commander)
	return a_commander


## One owned piece at `a_x, a_z`, with 100 HP so it is a legal Attack target.
func _piece(a_owner: Commander, a_is_structure: bool, a_x: float, a_z: float) -> Commandable:
	var piece: StubPiece = StubPiece.make()
	if a_is_structure:
		var structure := Structure.new()
		structure.name = "Structure"
		piece.add_child(structure)
	a_owner.add_child(piece)
	piece.ownership.commander = a_owner
	piece.global_position = Vector3(a_x, 0.0, a_z)
	var defense := autofree(Defense.new()) as Defense
	defense.hp_max = 100.0
	defense.hp = 100.0
	piece.defense = defense
	# A GROUND target, set on the body rather than derived: `_apply_targetable_layers` reads
	# a Structure component or a Movement's altitude, and this stub has neither.
	piece.target_body.collision_layer |= CollisionLayers.Mask.TARGETABLE_GROUND
	return piece


## Give `a_piece` one weapon that can lock onto `a_mask` (a CollisionLayers.Mask value).
## Assigned rather than parented under the piece: it is already in the tree, and a real
## Weapon node's own wiring wants children this stub does not have.
func _arm(a_piece: Commandable, a_mask: int) -> Commandable:
	var loadout := autofree(Loadout.new()) as Loadout
	var weapon := Weapon.new()
	weapon.target_mask = a_mask
	weapon.melee_damage = 10.0
	loadout.add_child(weapon)
	a_piece.weapon_inventory = loadout
	return a_piece


## A ground-only soldier owned by the bot — the ordinary army member.
func _soldier(a_x: float = 0.0, a_z: float = 0.0) -> Commandable:
	return _arm(_piece(_bot, false, a_x, a_z), CollisionLayers.Mask.TARGETABLE_GROUND)


## An anti-air soldier owned by the bot. Its presence is what proves every assertion below
## is about CAPABILITY and not about the scan drone specifically.
func _flak(a_x: float = 0.0, a_z: float = 0.0) -> Commandable:
	return _arm(_piece(_bot, false, a_x, a_z), CollisionLayers.Mask.TARGETABLE_AIR)


## THE SCAN DRONE, the real scene, hostile, hovering at cruise altitude.
##
## The altitude is set explicitly because `is_air_target` reads a HEIGHT, not a locomotion
## mode (see tests/test_AirTargetAltitude.gd), and nothing lifts a drone off the deck inside
## a test with no physics running — it would otherwise sit at 0 and file itself as a GROUND
## target, which would make every assertion here pass for the wrong reason.
func _scan_drone(a_x: float, a_z: float) -> Commandable:
	var drone: Commandable = (load(SCOUT_SCENE) as PackedScene).instantiate() as Commandable
	_foe.add_child(drone)
	autofree(drone)
	drone.ownership.commander = _foe
	drone.global_position = Vector3(a_x, 0.0, a_z)
	drone.aerial._current_height_offset = Aerial.AERIAL_HEIGHT
	drone.refresh_targetable_altitude()
	return drone


## Record a sighting of `a_piece` on the bot's blackboard, as gaining vision of it would.
func _believe(a_piece: Commandable) -> Commandable:
	_bot.blackboard._upsert(a_piece, 0.0)
	return a_piece


func _military() -> BotMilitary:
	return BotMilitary.new(_bot, null)


# ─── THE FIXTURE IS HONEST ───────────────────────────────────────────────────

func test_the_scan_drone_really_is_air_only() -> void:
	# If this ever fails, every other test in the file is passing for the wrong reason.
	var drone: Commandable = _scan_drone(40.0, 0.0)
	assert_ne(drone.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR, 0,
		"the drone is on the anti-air layer")
	assert_eq(drone.targetable_layers() & CollisionLayers.Mask.TARGETABLE_GROUND, 0,
		"and on no other — a ground weapon has nothing to lock onto")


# ─── CAN THIS UNIT HURT THAT THING? ──────────────────────────────────────────

func test_a_ground_loadout_has_no_targeting_mode_for_the_drone() -> void:
	assert_false(Bot.unit_can_shoot(_soldier(), _scan_drone(40.0, 0.0)))
	assert_false(Bot.unit_can_damage(_soldier(), _scan_drone(41.0, 0.0)),
		"and there is no other way to reach it either")


func test_the_same_loadout_can_hurt_an_ordinary_enemy() -> void:
	assert_true(Bot.unit_can_shoot(_soldier(), _piece(_foe, false, 40.0, 0.0)))


func test_an_anti_air_loadout_can_hurt_the_drone() -> void:
	# The rule is about capability, not about drones: bring the right weapon and it is a
	# target like any other.
	assert_true(Bot.unit_can_shoot(_flak(), _scan_drone(40.0, 0.0)))


func test_an_unarmed_unit_shoots_nothing() -> void:
	assert_false(Bot.unit_can_shoot(_piece(_bot, false, 0.0, 0.0), _piece(_foe, false, 1.0, 0.0)))


# ─── AND CRUSHING COUNTS ─────────────────────────────────────────────────────
# `Bot.unit_has_combat_utility` already rules that an UNARMED Stock Truck is an army member,
# because running light infantry over is how the Colonials take prisoners. A weapon-only
# damageability test would therefore judge an army of trucks unable to hurt anything and
# leave the bot with no objective at all — the fix turning into a new way of standing still.

## A heavy, unarmed unit — the Stock Truck shape: no Loadout, a Movement that outranks the
## smallest crush class. The Movement is ASSIGNED rather than parented: the stub is already
## in the tree and a real Movement node's wiring wants a NavigationAgent it does not have.
func _truck(a_class: Movement.CrushClass, a_mode: Movement.Mode = Movement.Mode.GROUNDED) -> Commandable:
	var piece: Commandable = _piece(_bot, false, 0.0, 0.0)
	var mv := autofree(Movement.new()) as Movement
	mv.crush_class = a_class
	mv.mode = a_mode
	piece.movement = mv
	return piece


## Something small enough to be driven over.
func _infantry(a_owner: Commander) -> Commandable:
	var piece: Commandable = _piece(a_owner, false, 1.0, 0.0)
	var mv := autofree(Movement.new()) as Movement
	mv.crush_class = Movement.CrushClass.TINY
	piece.movement = mv
	return piece


func test_an_unarmed_crusher_can_damage_what_it_can_drive_over() -> void:
	assert_true(Bot.unit_can_damage(_truck(Movement.CrushClass.LARGE), _infantry(_foe)),
		"the truck is in the army precisely because this is a way of killing things")
	assert_false(Bot.unit_can_shoot(_truck(Movement.CrushClass.LARGE), _infantry(_foe)),
		"…and it is not a way of SHOOTING, which is a different question")


func test_a_crusher_cannot_reach_the_scan_drone() -> void:
	# The refusal that matters: nothing crushes an aerial piece, whatever its size class, so
	# widening the question to crushing does not quietly re-admit the drone.
	assert_false(Bot.unit_can_damage(_truck(Movement.CrushClass.LARGE), _scan_drone(1.0, 0.0)))


func test_a_target_that_cannot_be_INTERROGATED_is_not_called_untargetable() -> void:
	# UNKNOWN IS NOT UNTARGETABLE. A belief outlives the thing it remembers, and an army that
	# refused to march on the last-known position of a destroyed base because the memory can
	# no longer be questioned would lose exactly the self-correcting walk the fog-limited
	# objective is built on.
	assert_true(Bot.any_unit_can_damage([_soldier()], null))


func test_an_empty_army_is_not_asked() -> void:
	assert_true(Bot.any_unit_can_damage([], _scan_drone(40.0, 0.0)))


func test_one_capable_member_answers_for_the_army() -> void:
	var drone: Commandable = _scan_drone(40.0, 0.0)
	assert_false(Bot.any_unit_can_damage([_soldier(), _truck(Movement.CrushClass.LARGE)], drone))
	assert_true(Bot.any_unit_can_damage([_soldier(), _flak()], drone),
		"one anti-air unit is enough to make the drone worth going to")


# ─── THE ACTUATOR REFUSES AN IMPOSSIBLE ORDER ────────────────────────────────

func _actuator() -> BotActuator:
	# A Map that is never entered into the tree: CommandMessage only stores it, and the
	# actuator's only use of it is the null check and the navmesh snap the Attack path does
	# not take.
	return BotActuator.new(autofree(Map.new()) as Map)


func test_the_actuator_does_not_order_an_attack_the_unit_cannot_carry_out() -> void:
	# THE REPORTED SYMPTOM, at the point of issue. Without the guard this unit ends the call
	# holding a persistent Attack that `can_act` refuses and `get_updated_state` never
	# clears — it stands there until the drone's lifespan expires.
	var soldier: Commandable = _soldier()
	_actuator().attack([soldier], _scan_drone(40.0, 0.0))
	assert_false(soldier.has_command(), "no weapon for it, so no order for it")


func test_the_actuator_still_orders_the_unit_that_can() -> void:
	var flak: Commandable = _flak()
	_actuator().attack([flak], _scan_drone(40.0, 0.0))
	assert_true(flak.has_command(), "the anti-air unit is sent")
	assert_true(flak.current_command() is Attack)


func test_a_mixed_group_is_split_rather_than_refused() -> void:
	var soldier: Commandable = _soldier()
	var flak: Commandable = _flak()
	_actuator().attack([soldier, flak], _scan_drone(40.0, 0.0))
	assert_false(soldier.has_command())
	assert_true(flak.has_command())


# ─── THE ARMY'S OBJECTIVE ────────────────────────────────────────────────────

func test_the_army_does_not_adopt_an_objective_no_member_can_damage() -> void:
	# THE SCAN-DRONE FIXTURE. The drone is the only thing this bot has ever seen, and the
	# whole army is ground-only, so there is no attack objective at all — tick() demotes the
	# posture to MASS and the army gathers instead of walking out to stand under it.
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	_soldier()
	_believe(_scan_drone(40.0, 0.0))
	assert_null(_military()._objective_for(BotMilitary.Posture.ATTACK),
		"an army that cannot touch the drone has no business marching to it")


func test_one_anti_air_unit_in_the_army_makes_the_drone_an_objective() -> void:
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	_flak()
	var drone: Commandable = _believe(_scan_drone(40.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), drone.global_position,
		"bring a weapon for it and it is an objective like any other")


func test_the_drone_is_SKIPPED_rather_than_vetoing_the_whole_offensive() -> void:
	# The filter runs BEFORE the nearest is taken, which is the difference between skipping a
	# belief and being stopped by it: the drone is the nearest thing the bot knows about, and
	# the army still marches on the base behind it.
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	_believe(_scan_drone(20.0, 0.0))
	var base: Commandable = _believe(_piece(_foe, true, 60.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), base.global_position)


func test_an_untargetable_UNIT_belief_is_skipped_for_the_next_one() -> void:
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	_believe(_scan_drone(10.0, 0.0))
	var foe_unit: Commandable = _believe(_piece(_foe, false, 50.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), foe_unit.global_position)


# ─── A BELIEF THE WALK HAS ALREADY DISPROVED ─────────────────────────────────

func test_a_unit_belief_is_kept_while_the_unit_is_still_where_we_remember_it() -> void:
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	var foe_unit: Commandable = _believe(_piece(_foe, false, 50.0, 0.0))
	assert_false(_bot.belief_is_disproved(_bot.blackboard.believed_units()[0]))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), foe_unit.global_position)


func test_a_unit_belief_is_disproved_once_we_can_see_the_spot_is_empty() -> void:
	# THE GHOST MARCH. An enemy SCOUT wanders past the bot's base, is seen once, and leaves.
	# The belief lapses only on a three-minute timer, so with no enemy structure ever seen
	# the army's objective is a patch of ground near its own base — and standing on it,
	# looking straight at nothing, it goes on believing.
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	var wanderer: Commandable = _believe(_piece(_foe, false, 10.0, 0.0))
	wanderer.global_position = Vector3(90.0, 0.0, 0.0)   # it moved on
	assert_true(_bot.belief_is_disproved(_bot.blackboard.believed_units()[0]))
	assert_null(_military()._objective_for(BotMilitary.Posture.ATTACK),
		"the army is looking at the spot; there is nothing there to march on")


func test_a_disproved_belief_yields_to_a_live_one_rather_than_ending_the_offensive() -> void:
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	var wanderer: Commandable = _believe(_piece(_foe, false, 10.0, 0.0))
	wanderer.global_position = Vector3(90.0, 0.0, 0.0)
	var standing: Commandable = _believe(_piece(_foe, false, 50.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), standing.global_position)


func test_a_STRUCTURE_belief_is_never_disproved_here() -> void:
	# Structures already have this rule, and it lives in CommanderBlackboard.update: a
	# structure belief is dropped when the commander regains vision of its cell and the
	# building is gone. Asking again here would double-judge it — and would break the
	# deliberate behaviour that a razed base stays the objective until the walk confirms it.
	_piece(_bot, true, 0.0, 0.0)
	_soldier()
	var razed: Commandable = _believe(_piece(_foe, true, 60.0, 0.0))
	var remembered: Vector3 = razed.global_position
	assert_false(_bot.belief_is_disproved(_bot.blackboard.believed_structures()[0]))
	razed.get_parent().remove_child(razed)
	razed.free()
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), remembered,
		"the bot still marches on where it last saw the base")


# ─── THE KAMIKAZE'S BLAST SCAN ───────────────────────────────────────────────

## A stub that IS a suicide unit, from `ProbeBot`'s point of view.
func _kamikaze() -> Commandable:
	var drone: Commandable = _soldier()
	drone.id = _bot.suicide_id
	return drone


func test_a_kamikaze_does_not_anchor_a_blast_on_a_body_it_cannot_strike() -> void:
	# Same failure, a different decision: the blast used to be priced purely off the damage
	# table, which answers for anything with armour. Anchoring on the drone produced a
	# persist = true Attack the drone could never act on and never drop.
	var drone: Commandable = _scan_drone(40.0, 0.0)
	_bot.seen = [drone]
	assert_null(_bot.kamikaze_best_target(_kamikaze()),
		"no blast worth flying to — BotKamikaze HOLDS the drone instead")


func test_a_kamikaze_still_finds_a_blast_it_can_deliver() -> void:
	var body: Commandable = _piece(_foe, false, 40.0, 0.0)
	_bot.seen = [_scan_drone(41.0, 0.0), body]
	var best: Variant = _bot.kamikaze_best_target(_kamikaze())
	assert_not_null(best, "the reachable body is still worth a run")
	if best != null:
		assert_eq(best["target"], body, "and it is the anchor, not the drone beside it")
