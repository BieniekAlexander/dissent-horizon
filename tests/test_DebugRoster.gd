extends GutTest

## The debug spawner's card layout (DebugRoster.groups) and the generator that lists an
## undocumented scene (SpecGenerators.untracked_roster_entry). Both are pure, and both run
## against entries built here rather than the shipped roster.

const SpecGenerators := preload("res://tools/spec_import/generators.gd")


func _entry(a_id: String, a_faction: String, a_is_fixture: bool,
		a_producers: Array = []) -> Dictionary:
	return {"id": a_id, "label": a_id.capitalize(), "faction": a_faction, "scene": "",
		"is_fixture": a_is_fixture, "producers": a_producers, "tool": ""}


func _titles(a_groups: Array[Dictionary]) -> Array:
	return a_groups.map(func(g: Dictionary) -> String: return g["title"])


func _ids(a_group: Dictionary) -> Array:
	return a_group["entries"].map(func(e: Dictionary) -> String: return e["id"])


func test_fixtures_lead_then_producers_then_the_untrained() -> void:
	var entries: Array = [
		_entry("drone", "red", false),
		_entry("soldier", "red", false, ["barracks"]),
		_entry("barracks", "red", true),
	]
	var groups: Array[Dictionary] = DebugRoster.groups(entries, "red")
	assert_eq(_titles(groups), [DebugRoster.FIXTURES_TITLE, "Barracks", DebugRoster.UNTRAINED_TITLE])
	assert_eq(_ids(groups[1]), ["soldier"], "a trained unit sits under its producer")


func test_a_unit_with_two_producers_is_under_each() -> void:
	var entries: Array = [
		_entry("soldier", "red", false, ["barracks", "fort"]),
		_entry("barracks", "red", true),
		_entry("fort", "red", true),
	]
	var titles: Array = _titles(DebugRoster.groups(entries, "red"))
	assert_eq(titles, [DebugRoster.FIXTURES_TITLE, "Barracks", "Fort"])


func test_only_the_chosen_faction_is_listed() -> void:
	var entries: Array = [_entry("barracks", "red", true), _entry("tower", "blue", true)]
	var groups: Array[Dictionary] = DebugRoster.groups(entries, "blue")
	assert_eq(groups.size(), 1)
	assert_eq(_ids(groups[0]), ["tower"])


func test_a_faction_with_nothing_has_no_groups() -> void:
	assert_eq(DebugRoster.groups([_entry("tower", "blue", true)], "red").size(), 0)


func test_factions_are_listed_once_and_sorted() -> void:
	var entries: Array = [
		_entry("a", "red", true), _entry("b", "blue", true), _entry("c", "red", false),
	]
	assert_eq(DebugRoster.factions(entries), ["blue", "red"] as Array[String])


const _UNIT_SCENE: String = """[gd_scene format=3]

[node name="Unit" type="CharacterBody3D" groups=["piece", "unit"]]
id = &"xx_scout"

[node name="Locomotion" type="Node" parent="."]
"""


func test_an_undocumented_unit_is_read_from_its_root() -> void:
	var entry: Dictionary = SpecGenerators.untracked_roster_entry(
		"res://scenes/entities/units/tc/scout.tscn", _UNIT_SCENE)
	assert_eq(entry["id"], "xx_scout")
	assert_eq(entry["faction"], "technocracy", "the folder code names the faction")
	assert_false(entry["is_fixture"])


func test_a_scene_in_neither_group_is_not_a_piece_to_place() -> void:
	var token: String = _UNIT_SCENE.replace('groups=["piece", "unit"]', 'groups=["piece"]')
	assert_eq(SpecGenerators.untracked_roster_entry("res://x/nt/drone.tscn", token), {})


func test_a_scene_with_no_id_is_an_abstract_base() -> void:
	var base: String = _UNIT_SCENE.replace('id = &"xx_scout"\n', "")
	assert_eq(SpecGenerators.untracked_roster_entry("res://x/nt/base.tscn", base), {})


func test_a_folder_naming_no_faction_lists_under_neutral() -> void:
	assert_eq(SpecGenerators.folder_faction("res://scenes/entities/parachute.tscn"),
		SpecGenerators.DEFAULT_ROSTER_FACTION)


# --- The local player's faction ----------------------------------------------------------

func test_a_players_faction_is_found_by_the_scenes_of_its_pieces() -> void:
	var soldier := _entry("soldier", "red", false)
	soldier["scene"] = "res://red/soldier.tscn"
	var tank := _entry("tank", "blue", false)
	tank["scene"] = "res://blue/tank.tscn"
	assert_eq(DebugRoster.faction_of_scenes([soldier, tank], ["res://blue/tank.tscn"]), "blue")


func test_the_first_matching_scene_decides() -> void:
	var soldier := _entry("soldier", "red", false)
	soldier["scene"] = "res://red/soldier.tscn"
	var tank := _entry("tank", "blue", false)
	tank["scene"] = "res://blue/tank.tscn"
	assert_eq(DebugRoster.faction_of_scenes([soldier, tank],
		["res://nowhere.tscn", "res://red/soldier.tscn", "res://blue/tank.tscn"]), "red")


func test_no_matching_scene_names_no_faction() -> void:
	assert_eq(DebugRoster.faction_of_scenes([_entry("soldier", "red", false)], ["res://x.tscn"]), "")
