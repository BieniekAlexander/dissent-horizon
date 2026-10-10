extends GutTest

## RELATIONS ARE READ OFF THE PIECES: a mobile open garrison is a transport for whatever its
## masks admit, a bunker is cover for the armed, a BeaconRange or a Spot-granted unit spots for
## its commander's guns — and no kind is known by a piece's name
## (gdd/systems/ai/squads-and-relations.md §Relations).

const GUN: StringName = &"fake_gun"
const SPOT: StringName = &"fake_spot"


## Owns exactly the pieces the test hands it.
class FakeBot:
	extends Bot
	var own: Array = []

	func get_units() -> Array:
		return own.filter(func(p: Actor) -> bool: return not p.is_in_group("structure"))

	func get_structures() -> Array:
		return own.filter(func(p: Actor) -> bool: return p.is_in_group("structure"))


var _bot: FakeBot
var _them: Commander


func before_each() -> void:
	FakePieces.install_ability(GUN, {"command": "command_bombard"})
	FakePieces.install_ability(SPOT, {"command": "command_spot"})
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_them = Commander.new()
	_them.id = 2
	add_child_autofree(_them)


func after_each() -> void:
	FakePieces.restore_abilities()


func _unit(a_options: Dictionary, a_owner: Commander = null) -> Actor:
	return _own(FakePieces.unit(a_options), a_owner)


func _structure(a_options: Dictionary, a_owner: Commander = null) -> Actor:
	return _own(FakePieces.structure(a_options), a_owner)


func _own(a_piece: Actor, a_owner: Commander) -> Actor:
	var owner: Commander = a_owner if a_owner != null else _bot
	add_child_autofree(a_piece)
	a_piece.ownership.commander = owner
	if owner == _bot:
		_bot.own.append(a_piece)
	return a_piece


const CARRIER: Dictionary = {"speed": 4.0, "garrison": {"capacity": 4, "bunker": false}}

# ─── TRANSPORT ───────────────────────────────────────────────────────────────


func test_a_mobile_open_garrison_carries_the_soldier_it_admits() -> void:
	var carrier: Actor = _unit(CARRIER)
	var soldier: Actor = _unit(FakePieces.SOLDIER)
	var ride: Relation = Relation.transport()
	assert_true(ride.is_provider(carrier), "a mobile, open, releasable hold")
	assert_true(ride.serves(carrier, soldier), "a grounded unit of its own side")
	assert_false(ride.serves(carrier, carrier), "never itself")
	assert_eq(ride.reach, Relation.Reach.CONTAINED)
	assert_eq(ride.effect, Relation.Effect.MOVES)


func test_an_aircraft_is_not_carried() -> void:
	var carrier: Actor = _unit(CARRIER)
	var flyer: Actor = _unit(FakePieces.AIRCRAFT)
	assert_false(
		Relation.transport().serves(carrier, flyer), "the default masks admit the grounded"
	)


func test_an_enemys_unit_is_not_carried() -> void:
	var carrier: Actor = _unit(CARRIER)
	var theirs: Actor = _unit(FakePieces.SOLDIER, _them)
	assert_false(Relation.transport().serves(carrier, theirs))


func test_a_hold_kept_for_other_ids_carries_no_soldier() -> void:
	var truck: Actor = _unit(
		{"speed": 4.0, "garrison": {"capacity": 3, "bunker": false, "ids": [&"fake_builder"]}}
	)
	var soldier: Actor = _unit(FakePieces.SOLDIER)
	assert_true(Relation.transport().is_provider(truck), "it is a transport")
	assert_false(Relation.transport().serves(truck, soldier), "but not for him")


func test_a_closed_hold_is_no_transport() -> void:
	var cage: Actor = _unit(
		{
			"speed": 4.0,
			"garrison": {"capacity": 3, "bunker": false, "frames": 0, "armours": 0, "movements": 0}
		}
	)
	assert_false(Relation.transport().is_provider(cage), "nothing may be ordered into it")


func test_a_structures_garrison_is_cover_and_not_transport() -> void:
	var bunker: Actor = _structure({"garrison": {"capacity": 4, "bunker": true}})
	var soldier: Actor = _unit(FakePieces.SOLDIER)
	var unarmed: Actor = _unit(FakePieces.PLAIN)
	assert_false(Relation.transport().is_provider(bunker), "it cannot move")
	var cover: Relation = Relation.cover()
	assert_true(cover.is_provider(bunker))
	assert_true(cover.serves(bunker, soldier), "the armed fire from it")
	assert_false(cover.serves(bunker, unarmed), "the unarmed are the preservation path's")
	assert_eq(cover.effect, Relation.Effect.PROTECTS)


func test_a_mobile_bunker_is_both() -> void:
	var sloop: Actor = _unit({"speed": 4.0, "garrison": {"capacity": 6, "bunker": true}})
	assert_true(Relation.transport().is_provider(sloop))
	assert_true(Relation.cover().is_provider(sloop))


# ─── SPOTTING ────────────────────────────────────────────────────────────────


func test_a_beacon_range_carrier_spots_for_its_commanders_guns() -> void:
	var tower: Actor = _structure({"beacon_range": 12.0})
	var gun: Actor = _structure({"abilities": [{"grants": [GUN]}]})
	var their_gun: Actor = _structure({"abilities": [{"grants": [GUN]}]}, _them)
	var barracks: Actor = _structure({})
	var spotting: Relation = Relation.spotting_range()
	assert_true(spotting.is_provider(tower))
	assert_true(spotting.serves(tower, gun))
	assert_false(spotting.serves(tower, their_gun), "spotting is per commander")
	assert_false(spotting.serves(tower, barracks), "a piece with no Bombard is not a gun")
	assert_eq(spotting.reach, Relation.Reach.RADIUS)
	assert_almost_eq(spotting.radius_of(tower), 12.0, 0.001)
	assert_eq(spotting.effect, Relation.Effect.ENABLES)


func test_a_spot_granted_unit_calls_solutions_in_for_its_guns() -> void:
	var recruit: Actor = _unit({"speed": 2.0, "abilities": [{"grants": [SPOT]}]})
	var gun: Actor = _structure({"abilities": [{"grants": [GUN]}]})
	var rifleman: Actor = _unit(FakePieces.SOLDIER)
	var calling: Relation = Relation.spotting_call()
	assert_true(calling.is_provider(recruit))
	assert_false(calling.is_provider(rifleman), "read off the ability's command, not the unit")
	assert_true(calling.serves(recruit, gun))
	assert_eq(calling.reach, Relation.Reach.POINT)


# ─── THE BOT'S READ ──────────────────────────────────────────────────────────


func _names(a_relations: Array[Relation]) -> Array:
	return a_relations.map(func(r: Relation) -> StringName: return r.name)


func test_the_bot_lists_the_kinds_its_pieces_take_part_in() -> void:
	var carrier: Actor = _unit(CARRIER)
	var soldier: Actor = _unit(FakePieces.SOLDIER)
	var ride: Relation = Relation.transport()
	assert_has(_names(_bot.relations()), &"transport")
	assert_does_not_have(_names(_bot.relations()), &"spotting_range", "nobody spots")
	assert_eq(_bot.providers_of(ride), [carrier])
	assert_eq(_bot.consumers_of(ride, carrier), [soldier])


func test_a_soldier_alone_takes_part_in_no_ride() -> void:
	_unit(FakePieces.SOLDIER)
	assert_does_not_have(_names(_bot.relations()), &"transport")


func test_a_piece_outside_the_tree_still_declares_what_it_grants() -> void:
	# A build preview never enters the tree, so its pool never rebuilds its live list; the
	# relation reads the authored pools instead, or the siege rung finds no gun to buy.
	var gun: Actor = FakePieces.structure({"abilities": [{"grants": [GUN]}]})
	assert_true(Relation.grants_command(gun, "command_bombard"), "declared, not yet built")
	gun.free()
