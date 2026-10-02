extends GutTest

## Two fog bugs that both ended in the same place: something the player should not be able
## to see behaving as though it were in plain sight.
##
## 1. THE REGISTRY KEY. Fog nodes filed themselves under the RAW `watching_commander_id`,
##    which for the player's own fog (placed in player.tscn) is the authoring default `-1`.
##    Every caller then had to remember to map the player's real id back to that key, and
##    `Commandable.is_visible_to` did not — so it looked up commander 1, found nothing, and
##    returned "visible" for every enemy on the map. That is what left the player's aggro
##    ungated by fog: units opened fire on things they could not see.
##
## 2. OUT-OF-PLAY PIXELS. The play mask holds pixels outside the play rectangle at byte 0 so
##    the shroud does not hang over the chopped-off corners of the grid. Byte 0 is also what
##    "revealed" looks like, so anything standing out there read as permanently in sight —
##    and since a structure is in vision when ANY of its footprint cells is, a base sited
##    near the play edge showed through the fog for the whole match.
##
## PATHS, not preloads (see CLAUDE.md): a file-scope preload of an entity scene poisons the
## Tool registry for the whole run, and this file sorts early.

const IRREGULAR: Dictionary = FakePieces.BUILDER
## A cross-script const is not a constant expression in GDScript, and a file that will not
## parse is SKIPPED by GUT rather than failed — so this is a var on purpose.
var PLAYER: int = RTSController.PLAYER_COMMANDER_ID

const OTHER: int = 7


func before_each() -> void:
	Fog._fogs_by_commander.clear()


func after_each() -> void:
	Fog._fogs_by_commander.clear()


## A Fog node in the tree with no Map to initialise against, so it stays inert — enough to
## exercise the registry, which is written in _ready.
func _fog(a_watching_id: int) -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = a_watching_id
	add_child_autofree(fog)
	return fog


func _unit(a_commander_id: int) -> Commandable:
	var u := FakePieces.make(IRREGULAR) as Commandable
	add_child_autofree(u)
	var c := Commander.new()
	c.id = a_commander_id
	add_child_autofree(c)
	u.ownership.commander = c
	return u


#region The registry key
func test_the_players_fog_is_filed_under_the_players_id() -> void:
	# NOT under -1. The -1 is an authoring default meaning "the local player", and resolving
	# it in one place is what stops each caller inventing its own re-mapping.
	var fog: Fog = _fog(-1)
	assert_eq(fog.viewer_commander_id(), PLAYER)
	assert_eq(Fog.for_commander(PLAYER), fog)


func test_a_bot_fog_is_filed_under_its_own_id() -> void:
	var fog: Fog = _fog(OTHER)
	assert_eq(fog.viewer_commander_id(), OTHER)
	assert_eq(Fog.for_commander(OTHER), fog)


func test_a_commander_with_no_fog_looks_up_to_nothing() -> void:
	assert_null(Fog.for_commander(OTHER))


func test_a_freed_fog_does_not_come_back_from_the_registry() -> void:
	# Entries outlive the nodes that made them — a freed Fog never deregisters — and reading
	# one back into a typed local is itself an error in Godot, never mind using it.
	var fog := Fog.new()
	add_child(fog)
	remove_child(fog)
	fog.free()
	assert_null(Fog.for_commander(PLAYER))


func test_visibility_consults_the_players_own_fog() -> void:
	# The regression itself: with the fog filed under the wrong key this returned true, and
	# every fogged enemy was a legal aggro target for the player's army.
	var enemy: Commandable = _unit(OTHER)
	assert_true(enemy.is_visible_to(PLAYER), "no fog registered — nothing to hide behind")
	var fog: Fog = _fog(-1)
	assert_eq(Fog.for_commander(PLAYER), fog, "guards the fixture")
	assert_false(
		enemy.is_visible_to(PLAYER),
		"an uninitialised fog has revealed nothing, so nothing is visible through it"
	)


#endregion


#region Out-of-play pixels are not vision
## A 4x4 fog with a known mask, driven directly. Building a real one needs a Map and a
## TerrainData; what is under test is the single rule that reads the mask, so the buffers
## are set up by hand rather than derived.
func _masked_fog(a_out_of_play: Array) -> Fog:
	var fog := Fog.new()
	add_child_autofree(fog)
	fog._img_width = 4
	fog._img_height = 4
	fog._center = Vector2.ZERO
	fog._world_half_w = 2.0
	fog._world_half_d = 2.0
	fog.POINTS_PER_UNIT = 1.0
	fog._play_bounds_active = true
	fog._play_mask = PackedByteArray()
	fog._play_mask.resize(16)
	fog._play_mask.fill(1)
	# Byte 0 IS the value _build_play_mask pre-clears out-of-play pixels to, which is the
	# whole trap: it is indistinguishable from "revealed" without the mask.
	fog._fog_bytes = PackedByteArray()
	fog._fog_bytes.resize(16)
	fog._fog_bytes.fill(0)
	for index: int in a_out_of_play:
		fog._play_mask[index] = 0
	return fog


func test_a_revealed_in_play_pixel_is_in_vision() -> void:
	var fog: Fog = _masked_fog([])
	assert_true(fog.fog_clear_at(Vector2(0.0, 0.0)))


func test_a_shrouded_in_play_pixel_is_not() -> void:
	var fog: Fog = _masked_fog([])
	fog._fog_bytes.fill(Fog.EXPLORED_ALPHA)
	assert_false(fog.fog_clear_at(Vector2(0.0, 0.0)))


func test_an_out_of_play_pixel_is_never_in_vision() -> void:
	# Pixel (2, 2) — world (0, 0) at this scale — held transparent for rendering.
	var fog: Fog = _masked_fog([2 * 4 + 2])
	assert_false(
		fog.fog_clear_at(Vector2(0.0, 0.0)),
		"transparent for the shroud is not the same as revealed"
	)
	assert_true(fog.fog_clear_at(Vector2(-1.0, 0.0)), "its in-play neighbour is unaffected")


func test_a_point_off_the_texture_is_not_in_vision() -> void:
	var fog: Fog = _masked_fog([])
	assert_false(fog.fog_clear_at(Vector2(100.0, 100.0)))


#endregion

#region Finding the Map
## 3. THE MAP LOOKUP. `Fog._initialize` used to start from `get_tree().current_scene` and
##    search it with the OWNED filter, which finds a Map only when the Scenario IS the
##    opened scene. Host the Scenario under anything else — the self-play harness
##    instantiates it as a child of a runner node — and a script-instantiated subtree has no
##    owner, so the search skipped it, every Fog stayed inert, and `fog_clear_at` then
##    answered FALSE for every point on the map.
##
##    That is a silent, TOTAL blinding rather than a visible failure: `is_visible_to`
##    returns false, so aggro, `BotTargeting` and the blackboard all see an empty world. Two
##    bots then fight for twenty minutes without either ever perceiving the other — which is
##    exactly what the first self-play matches measured (gdd/systems/ai/bot-engagement-fixes.md).
##
##    Fog now walks UP from itself instead, which cannot miss that way: a Fog is always a
##    descendant of the Scenario that owns the Map it belongs to.


## Map._ready builds a TerrainGrid / NavManager and asserts on scene children this does not
## have — these tests only exercise which node the search lands on.
class StubMap:
	extends Map

	## The three children Map resolves with a hard `$`; without them the @onready block errors
	## on entering the tree, whatever _ready does.
	static func make() -> StubMap:
		var map := StubMap.new()
		map.name = "Map"
		var region := NavigationRegion3D.new()
		region.name = "NavigationRegion"
		var body := StaticBody3D.new()
		body.name = "Body"
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		body.add_child(shape)
		region.add_child(body)
		map.add_child(region)
		return map

	func _ready() -> void:
		pass


## A Scenario-shaped subtree (Map + Fog) hosted under `a_host`, built entirely from script
## so nothing in it has an owner — the harness's shape, and a GUT test's.
func _hosted_map_and_fog(a_host: Node) -> Array:
	var scenario := Node3D.new()
	scenario.name = "HostedScenario"
	a_host.add_child(scenario)
	var map: StubMap = StubMap.make()
	scenario.add_child(map)
	var fog := Fog.new()
	scenario.add_child(fog)
	return [map, fog]


func test_fog_finds_its_map_when_the_scenario_is_hosted_under_another_node() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var built: Array = _hosted_map_and_fog(host)
	var found: Map = (built[1] as Fog)._resolve_map()
	# Freed inside the test, before the frame ends: Fog._ready defers _initialize, and this
	# stub Map has no heightmap for it to initialise against.
	host.free()
	assert_eq(found, built[0], "walking up from the Fog reaches the Map")


func test_the_owner_filtered_search_that_used_to_be_done_misses_it() -> void:
	# Not a test of Godot for its own sake: this IS the old lookup, and it is why the fog
	# went inert under the harness. A script-built subtree has no owner to filter on.
	var host := Node3D.new()
	add_child_autofree(host)
	_hosted_map_and_fog(host)
	var old_lookup: Node = host.find_child("Map", true, true)
	host.free()
	assert_null(old_lookup, "the owned filter skips a scene the harness instantiated itself")
#endregion
