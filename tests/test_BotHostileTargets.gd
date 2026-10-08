extends GutTest

## THE BOT'S ENEMY IS A HOSTILE COMMANDER, NEVER THE NEUTRAL ONE (id 0).
##
## `CLAUDE.md` §Things NOT to break states the rule — "commander_id = 0 is neutral/world …
## don't conflate 'unowned' with 'player-owned'" — and this file is the guard for the
## OBJECTIVE end of it, which had no test.
##
## Why it needs one: neutral pieces are permanent map furniture (extractors, shelters, the
## loose Terrestrials the Colonial dominion route captures), and they are numerous and
## CLOSE. A sense that counted them as enemies would give the bot a standing attack
## objective it can never resolve — it marches on a neutral, arrives, and stands there for
## the rest of the match while never looking for the actual opponent. The self-play
## harness's first write-up attributed exactly that to `BotMilitary._objective_for(ATTACK)`;
## the senses were in fact already clean (`Commander._enemy_commanders` filters id 0), and
## these tests are what keep them that way. See gdd/systems/ai/bot-engagement-fixes.md.
##
## Fixture note: the pieces are STUBS that skip `_ready` (Entity's @onready wiring wants a
## full entity scene) but ARE in the tree, because `global_position` is only defined for a
## node inside it — which every "nearest" sense here reads.


## A piece that can live in the tree without a scene behind it. `_ready` is skipped (the
## full entity wiring wants a real scene) and processing is off, so no per-frame code runs
## against the components it does NOT have. Godot still runs the @onready block on entering
## the tree, so `_bare` supplies the four children Entity/Actor resolve with a hard
## `$` — everything else is `get_node_or_null` and simply stays null.
class StubPiece:
	extends Actor

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		var ownership := Ownership.new()
		ownership.name = "Ownership"
		piece.add_child(ownership)
		var obstacle := NavigationObstacle3D.new()
		obstacle.name = "AvoidanceObstacle"
		piece.add_child(obstacle)
		var veterancy := Veterancy.new()
		veterancy.name = "Veterancy"
		piece.add_child(veterancy)
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


var _scenario: Scenario
var _bot: Bot
var _foe: Commander
var _neutral: Commander


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_neutral = _commander(Commander.new(), 0)
	_bot = _commander(Bot.new(), 1) as Bot
	_foe = _commander(Commander.new(), 2)
	_scenario.commanders = [_neutral, _bot, _foe]


## A commander in the tree, wired to the shared Scenario. `initialize` before `add_child`
## so `Commander._resolve_scene_references` finds the reference already set rather than
## walking a tree that is not a Scenario/Players rig.
func _commander(a_commander: Commander, a_id: int) -> Commander:
	a_commander.id = a_id
	a_commander.initialize(null, _scenario)
	add_child_autofree(a_commander)
	return a_commander


## One owned piece: a child of `a_owner` (which is what every owned-entity sense iterates),
## owning-commander set through Ownership, at `a_x, a_z`.
func _piece(a_owner: Commander, a_is_structure: bool, a_x: float, a_z: float) -> Actor:
	var piece: StubPiece = StubPiece.make()
	if a_is_structure:
		var structure := Fixture.new()
		structure.name = "Fixture"
		piece.add_child(structure)
	a_owner.add_child(piece)
	piece.ownership.commander = a_owner
	piece.global_position = Vector3(a_x, 0.0, a_z)
	return piece


## Give a piece something to fight with and something to lose, which is all
## `Bot.entity_strength` (and through it `relative_threat_level`) reads.
##
## The components are ASSIGNED rather than parented: the piece is already in the tree, so
## adding a Weapon under it would run that node's own @onready wiring against children a
## real weapon scene has and this one does not. The fields are what every sense reads.
func _arm(a_piece: Actor, a_damage: float) -> Actor:
	var defense := autofree(Defense.new()) as Defense
	defense.hp_max = 100.0
	defense.hp = 100.0
	a_piece.defense = defense
	var loadout := autofree(Loadout.new()) as Loadout
	var weapon := Weapon.new()
	weapon.melee_damage = a_damage
	loadout.add_child(weapon)
	a_piece.weapon_inventory = loadout
	return a_piece


## The military manager, which is the consumer under test. It needs no actuator: the
## objective query only reads the bot's senses.
func _military() -> BotMilitary:
	return BotMilitary.new(_bot, null)


## Record a sighting of `a_piece` on the bot's blackboard, as gaining vision of it would.
##
## The ATTACK objective is fog-limited, so a hostile piece the bot has never SEEN is not an
## objective — which means every objective test now has to say when the sighting happened.
## Driven through the blackboard's own upsert rather than by faking vision: these stubs have
## no vision shapes and no Fog, and what is under test is the objective, not the fog.
func _believe(a_piece: Actor) -> Actor:
	_bot.blackboard._upsert(a_piece, 0.0)
	return a_piece


# ─── THE COMMANDER SET ───────────────────────────────────────────────────────


func test_the_neutral_commander_is_not_an_enemy() -> void:
	var ids: Array = _bot._enemy_commanders().map(func(c: Commander): return c.id)
	assert_eq(ids, [2], "only the other PLAYER is an enemy — not id 0, and not the bot itself")


# ─── THE SENSES ──────────────────────────────────────────────────────────────


func test_neutral_pieces_are_neither_enemy_units_nor_enemy_structures() -> void:
	_piece(_neutral, false, 1.0, 1.0)
	_piece(_neutral, true, 2.0, 2.0)
	assert_eq(_bot.get_all_enemies(), [], "map furniture is not an enemy")
	assert_eq(_bot.get_enemy_units(), [])
	assert_eq(_bot.get_enemy_structures(), [])


func test_a_hostile_piece_is_an_enemy_classified_by_its_structure_component() -> void:
	var unit: Actor = _piece(_foe, false, 10.0, 0.0)
	var base: Actor = _piece(_foe, true, 12.0, 0.0)
	assert_eq(_bot.get_enemy_units(), [unit])
	assert_eq(_bot.get_enemy_structures(), [base])


func test_the_nearest_enemy_structure_is_never_the_nearer_neutral_one() -> void:
	# The shape of a real map: neutral structures sit right next to the bot's base, the
	# opponent's is across the map. Distance must not be what decides this.
	_piece(_bot, true, 0.0, 0.0)
	_piece(_neutral, true, 2.0, 0.0)
	var hostile_base: Actor = _piece(_foe, true, 60.0, 0.0)
	assert_eq(_bot.nearest_enemy_structure_to_base(), hostile_base)


func test_a_neutral_army_does_not_raise_the_threat_level() -> void:
	_arm(_piece(_bot, false, 0.0, 0.0), 10.0)
	for i: int in 5:
		_arm(_piece(_neutral, false, float(i), 1.0), 40.0)
	assert_eq(
		_bot.relative_threat_level(),
		0.0,
		"neutral combatants are a capture target for the Opportunist, not a threat"
	)


func test_a_hostile_army_does_raise_the_threat_level() -> void:
	_arm(_piece(_bot, false, 0.0, 0.0), 10.0)
	_arm(_piece(_foe, false, 5.0, 0.0), 30.0)
	assert_gt(_bot.relative_threat_level(), 0.5, "the hostile army outguns ours")


# ─── THE OBJECTIVE THE SENSES FEED ───────────────────────────────────────────


func test_a_map_of_neutrals_gives_the_army_no_attack_objective() -> void:
	# The failure this file exists for: a true attack objective the bot can never resolve.
	# Neutrals are never believed (the blackboard folds in visible_enemies only), so a map of
	# them cannot produce an objective however close they are.
	_piece(_bot, true, 0.0, 0.0)
	_piece(_neutral, true, 3.0, 0.0)
	_arm(_piece(_neutral, false, 4.0, 0.0), 10.0)
	assert_null(
		_military()._objective_for(BotMilitary.Posture.ATTACK),
		"nothing to attack — the military falls back to MASS rather than marching on furniture"
	)


func test_an_UNSCOUTED_hostile_base_gives_the_army_no_attack_objective() -> void:
	# THE FOG RULE: the opponent exists, on the map, right now — and the bot has never seen
	# it, so it has nowhere to march. Scouting is the precondition for aggression.
	_piece(_bot, true, 0.0, 0.0)
	_piece(_foe, true, 60.0, 0.0)
	_arm(_piece(_foe, false, 55.0, 0.0), 10.0)
	assert_null(
		_military()._objective_for(BotMilitary.Posture.ATTACK),
		"an enemy it has not found is not an objective"
	)


func test_the_attack_objective_is_the_hostile_base_once_it_has_been_SEEN() -> void:
	_piece(_bot, true, 0.0, 0.0)
	_piece(_neutral, true, 3.0, 0.0)
	var hostile_base: Actor = _believe(_piece(_foe, true, 60.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), hostile_base.global_position)


func test_the_nearer_of_two_believed_bases_is_the_objective() -> void:
	_piece(_bot, true, 0.0, 0.0)
	var near: Actor = _believe(_piece(_foe, true, 30.0, 0.0))
	_believe(_piece(_foe, true, 90.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), near.global_position)


func test_a_remembered_base_stays_the_objective_after_it_is_destroyed() -> void:
	# A belief is a LAST-KNOWN LOCATION, and it outlives the building: the bot has no way to
	# know the structure is gone until it walks back and looks. Marching there is the correct
	# behaviour, and the arrival is what corrects it.
	_piece(_bot, true, 0.0, 0.0)
	var hostile_base: Actor = _believe(_piece(_foe, true, 60.0, 0.0))
	var remembered: Vector3 = hostile_base.global_position
	hostile_base.get_parent().remove_child(hostile_base)
	hostile_base.free()
	assert_eq(_bot.get_enemy_structures(), [], "the building really is gone")
	assert_eq(
		_military()._objective_for(BotMilitary.Posture.ATTACK),
		remembered,
		"the bot still marches on where it last saw the base"
	)


func test_with_no_believed_structures_the_army_marches_on_a_believed_UNIT() -> void:
	_piece(_bot, true, 0.0, 0.0)
	_piece(_neutral, false, 3.0, 0.0)
	var hostile_unit: Actor = _believe(_piece(_foe, false, 40.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), hostile_unit.global_position)


func test_a_believed_structure_outranks_a_believed_unit() -> void:
	# Razing the base is the win condition; a unit is only where the army goes when there is
	# no structure left that the bot knows about.
	_piece(_bot, true, 0.0, 0.0)
	_believe(_piece(_foe, false, 5.0, 0.0))
	var hostile_base: Actor = _believe(_piece(_foe, true, 60.0, 0.0))
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), hostile_base.global_position)


# ─── HEGEMONY: THE COMMAND CENTRE IS THE OBJECTIVE ──────────────────────────


func test_under_hegemony_the_believed_command_centre_beats_a_nearer_building() -> void:
	_scenario.win_condition = Scenario.WinCondition.HEGEMONY
	_piece(_bot, true, 0.0, 0.0)
	_believe(_piece(_foe, true, 30.0, 0.0))
	var centre: Actor = _piece(_foe, true, 60.0, 0.0)
	centre.id = Deployment.command_centre_ids()[0]
	_believe(centre)
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), centre.global_position)


func test_under_mission_the_nearest_believed_building_is_still_the_objective() -> void:
	_piece(_bot, true, 0.0, 0.0)
	var nearer: Actor = _believe(_piece(_foe, true, 30.0, 0.0))
	var centre: Actor = _piece(_foe, true, 60.0, 0.0)
	centre.id = Deployment.command_centre_ids()[0]
	_believe(centre)
	assert_eq(_military()._objective_for(BotMilitary.Posture.ATTACK), nearer.global_position)
