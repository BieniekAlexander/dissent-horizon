extends GutTest

## The threat senses are fog-limited: is_base_under_threat, get_enemies_threatening_base,
## most_threatened_structure and threatened_command_centre answer for the enemies the bot can
## SEE near its structures, never for the ones that are merely there.
##
## These senses drive the DEFEND posture, BotEconomy.safety() and defensive sanction aiming,
## and until 2026-10-06 they read Commander.get_enemies_near — a physics overlap with no fog
## gate — so the bot defended against raiders nobody could see. That fix landed on functions
## nothing asserted; this is the assertion (world-model.md §The fog boundary, leak 1).
##
## The physics overlap itself is replaced — a StubBot answers get_enemies_near by distance
## over a list — because what is under test is the gate above it: visible_enemies_near,
## Entity.is_visible_to, and the fog they consult. The fog is a real Fog node with its bytes
## driven by hand, in the manner of test_FogVisibility's _masked_fog.


## A Bot whose physics overlap is a list searched by distance, and whose matchup is a list
## too: every piece hurts every other except the `harmless` ones. Everything above the two —
## the visibility gate, the can-it-hurt filter, the structure walk — is the real code.
class StubBot:
	extends Bot
	var pieces: Array = []
	var harmless: Array = []
	const PRICE: int = 100

	func matchup(a_attacker: Actor, _a_target: Actor) -> float:
		return 0.0 if harmless.has(a_attacker) else 1.0

	func unit_cost(_a_unit_type) -> int:
		return PRICE

	func get_enemies_near(a_position: Vector3, a_radius: float) -> Array:
		return pieces.filter(
			func(p: Actor) -> bool:
				return (
					p.commander_id != id
					and p.commander_id != 0
					and p.global_position.distance_to(a_position) <= a_radius
				)
		)


class StubPiece:
	extends Actor

	static func make(a_is_structure: bool, a_stealthed: bool) -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()]
		]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		if a_is_structure:
			var structure := Fixture.new()
			structure.name = "Fixture"
			piece.add_child(structure)
		if a_stealthed:
			var stealth := Stealth.new()
			stealth.name = "Stealth"
			piece.add_child(stealth)
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


const BOT_ID: int = 1
const FOE_ID: int = 2
const RADIUS: float = 30.0
## The fog covers x, z ∈ [-64, 64) at one pixel per world unit.
const FOG_SIZE: int = 128
const FOG_HALF: float = 64.0
## _fog_bytes: 0 is "clear", anything else is shrouded (Fog.fog_clear_at).
const SHROUDED: int = 255

var _scenario: Scenario
var _bot: StubBot
var _foe: Commander
var _fog: Fog


func before_each() -> void:
	Fog._fogs_by_commander.clear()
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = _commander(StubBot.new(), BOT_ID) as StubBot
	_foe = _commander(Commander.new(), FOE_ID)
	_scenario.commanders = [_bot, _foe]
	# The senses answer nothing for a bot with no map; one out of the tree is enough, since
	# the overlap that would read it is the stub's.
	_bot.map = autofree(Map.new()) as Map
	_fog = _shrouded_fog(BOT_ID)


func after_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_commander: Commander, a_id: int) -> Commander:
	a_commander.id = a_id
	a_commander.initialize(null, _scenario)
	add_child_autofree(a_commander)
	return a_commander


## A Fog for `a_watching_id` with every pixel shrouded, driven by hand: no Map, so
## _initialize leaves it alone, and the registry in _ready is what is_visible_to looks up.
func _shrouded_fog(a_watching_id: int) -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = a_watching_id
	add_child_autofree(fog)
	fog._img_width = FOG_SIZE
	fog._img_height = FOG_SIZE
	fog._center = Vector2.ZERO
	fog._world_half_w = FOG_HALF
	fog._world_half_d = FOG_HALF
	fog.POINTS_PER_UNIT = 1.0
	fog._play_bounds_active = false
	fog._fog_bytes = PackedByteArray()
	fog._fog_bytes.resize(FOG_SIZE * FOG_SIZE)
	fog._fog_bytes.fill(SHROUDED)
	assert_eq(Fog.for_commander(a_watching_id), fog, "guards the fixture: the fog is registered")
	return fog


## Clear the bot's fog in a disc of `a_radius` about `a_at`.
func _reveal(a_at: Vector3, a_radius: float) -> void:
	for py: int in FOG_SIZE:
		for px: int in FOG_SIZE:
			var world := Vector2(px - FOG_HALF, py - FOG_HALF)
			if world.distance_to(VU.in_xz(a_at)) <= a_radius:
				_fog._fog_bytes[py * FOG_SIZE + px] = 0


func _piece(
	a_owner: Commander, a_is_structure: bool, a_at: Vector3, a_stealthed: bool = false
) -> Actor:
	var piece: StubPiece = StubPiece.make(a_is_structure, a_stealthed)
	a_owner.add_child(piece)
	piece.ownership.commander = a_owner
	piece.global_position = a_at
	var defense := autofree(Defense.new()) as Defense
	defense.hp_max = 100.0
	defense.hp = 100.0
	piece.defense = defense
	_bot.pieces.append(piece)
	return piece


func _own_structure(a_at: Vector3, a_hp: float = 100.0) -> Actor:
	var s: Actor = _piece(_bot, true, a_at)
	s.defense.hp = a_hp
	return s


func _enemy_unit(a_at: Vector3, a_stealthed: bool = false) -> Actor:
	return _piece(_foe, false, a_at, a_stealthed)


# ─── THE GATE ────────────────────────────────────────────────────────────────


func test_a_fogged_enemy_beside_a_structure_is_no_threat() -> void:
	# THE LEAK. Nothing of the bot's can see this raider, and until the fix the base read as
	# under attack anyway.
	_own_structure(Vector3.ZERO)
	_enemy_unit(Vector3(5.0, 0.0, 0.0))
	assert_false(_bot.is_base_under_threat(RADIUS))
	assert_eq(_bot.get_enemies_threatening_base(RADIUS), [])
	assert_null(_bot.most_threatened_structure(RADIUS))


func test_a_visible_enemy_beside_a_structure_is_a_threat() -> void:
	# Hurt, because most_threatened_structure answers only for a structure BELOW full HP
	# (it starts its search at 1.0 and keeps strictly lower) — unlike threatened_command_centre,
	# which starts at INF. TODO: whether an unhurt structure with an enemy beside it is "most
	# threatened" is one question with two answers today; the sanctions' DEFEND zone keys off
	# this one, so it opens only once something has taken damage.
	var home: Actor = _own_structure(Vector3.ZERO, 80.0)
	var raider: Actor = _enemy_unit(Vector3(5.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 10.0)
	assert_true(_bot.is_base_under_threat(RADIUS))
	assert_eq(_bot.get_enemies_threatening_base(RADIUS), [raider])
	assert_eq(_bot.most_threatened_structure(RADIUS), home)


func test_a_stealthed_enemy_in_clear_fog_is_still_no_threat() -> void:
	# The second half of the gate: fog is not the only thing that hides a piece.
	_own_structure(Vector3.ZERO)
	_enemy_unit(Vector3(5.0, 0.0, 0.0), true)
	_reveal(Vector3.ZERO, 10.0)
	assert_false(_bot.is_base_under_threat(RADIUS))


func test_a_visible_enemy_out_of_the_radius_is_no_threat() -> void:
	_own_structure(Vector3.ZERO)
	_enemy_unit(Vector3(RADIUS + 5.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, RADIUS + 10.0)
	assert_false(_bot.is_base_under_threat(RADIUS), "the gate adds vision; it does not widen reach")


func test_an_enemy_that_cannot_hurt_the_structure_is_no_threat() -> void:
	# An unarmed builder, a recon drone over an extractor: standing beside a structure is not
	# threatening it, and a threat that cannot be ended held the base "threatened" for good.
	var home: Actor = _own_structure(Vector3.ZERO, 80.0)
	_bot.harmless.append(_enemy_unit(Vector3(5.0, 0.0, 0.0)))
	_reveal(Vector3.ZERO, 10.0)
	assert_false(_bot.is_base_under_threat(RADIUS))
	assert_eq(_bot.base_threats(RADIUS), [])
	assert_null(_bot.most_threatened_structure(RADIUS))
	assert_ne(_bot.most_threatened_structure(RADIUS), home)


func test_a_threat_is_valued_at_its_cost_times_its_matchup() -> void:
	var home: Actor = _own_structure(Vector3.ZERO)
	var raider: Actor = _enemy_unit(Vector3(5.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 10.0)
	assert_eq(
		_bot.base_threats(RADIUS),
		[{"enemy": raider, "structure": home, "value": float(StubBot.PRICE)}]
	)


func test_a_command_centre_is_threatened_from_further_off_when_asked() -> void:
	var centre: Actor = _own_structure(Vector3.ZERO)
	centre.id = Deployment.command_centre_ids()[0]
	_enemy_unit(Vector3(15.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 20.0)
	assert_eq(_bot.base_threats(10.0).size(), 0, "outside the plain radius")
	assert_eq(_bot.base_threats(10.0, 20.0).size(), 1, "inside the centre's")


## The real matchup, not the stub's: a piece with no weapon and no weight reads 0.
func test_an_unarmed_piece_has_no_matchup() -> void:
	var real: Bot = autofree(Bot.new()) as Bot
	var builder: Actor = _enemy_unit(Vector3(5.0, 0.0, 0.0))
	assert_eq(real.matchup(builder, _own_structure(Vector3.ZERO)), 0.0)


func test_a_neutral_piece_is_never_a_threat() -> void:
	var neutral := _commander(Commander.new(), 0)
	_own_structure(Vector3.ZERO)
	_piece(neutral, false, Vector3(5.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 10.0)
	assert_false(_bot.is_base_under_threat(RADIUS))


# ─── WHICH STRUCTURE ─────────────────────────────────────────────────────────


func test_the_most_threatened_structure_is_the_most_hurt_one_with_a_visible_enemy_near() -> void:
	var whole: Actor = _own_structure(Vector3.ZERO, 100.0)
	var hurt: Actor = _own_structure(Vector3(40.0, 0.0, 0.0), 20.0)
	_enemy_unit(Vector3(5.0, 0.0, 0.0))
	_enemy_unit(Vector3(45.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 60.0)
	assert_eq(_bot.most_threatened_structure(RADIUS), hurt)
	assert_ne(_bot.most_threatened_structure(RADIUS), whole)


func test_a_hurt_structure_whose_attacker_is_fogged_is_not_the_most_threatened() -> void:
	# Its enemy is the one the bot cannot see, so the barely-scratched structure under a
	# VISIBLE enemy is the answer — and the badly hurt one is not read as under attack at all.
	var scratched: Actor = _own_structure(Vector3.ZERO, 90.0)
	_own_structure(Vector3(40.0, 0.0, 0.0), 20.0)
	_enemy_unit(Vector3(5.0, 0.0, 0.0))
	_enemy_unit(Vector3(45.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 10.0)
	assert_eq(_bot.most_threatened_structure(RADIUS), scratched)


func test_threats_near_two_structures_are_counted_once() -> void:
	_own_structure(Vector3.ZERO)
	_own_structure(Vector3(10.0, 0.0, 0.0))
	var raider: Actor = _enemy_unit(Vector3(5.0, 0.0, 0.0))
	_reveal(Vector3.ZERO, 20.0)
	assert_eq(_bot.get_enemies_threatening_base(RADIUS), [raider])
