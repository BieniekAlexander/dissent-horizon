extends GutTest

## A WEAPON NOT IN THE TREE CAN STILL SAY HOW FAR IT REACHES. `Weapon.preview_ground_reach`
## exists for a build preview, which never enters the tree, and the bot's static-defence
## placement reads it (`Bot.ground_reach_of_type`). It used to read the shape's GLOBAL
## transform, which the engine refuses outside the tree with an error and an identity
## transform — five such errors in one self-play match, 2026-10-08.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##       -gtest=res://tests/test_WeaponPreviewReach.gd -gexit


func test_a_weapon_outside_the_tree_reports_its_ground_reach_without_error() -> void:
	var piece: Actor = autofree(FakePieces.unit({"weapon": {"ground": 6.0}}))
	var weapon: Weapon = piece.get_node("Loadout").get_child(0) as Weapon
	assert_false(weapon.is_inside_tree())
	assert_almost_eq(weapon.preview_ground_reach(), 6.0, 0.001)


func test_a_weapon_with_no_range_reports_none() -> void:
	# A melee fake carries no range node at all (FakePieces: ground 0 is none).
	var piece: Actor = autofree(FakePieces.unit({"weapon": {}}))
	var weapon: Weapon = piece.get_node("Loadout").get_child(0) as Weapon
	assert_eq(weapon.preview_ground_reach(), -1.0)


func test_in_the_tree_the_reach_is_unchanged() -> void:
	var piece: Actor = FakePieces.unit({"weapon": {"ground": 6.0}})
	add_child_autofree(piece)
	var weapon: Weapon = piece.get_node("Loadout").get_child(0) as Weapon
	assert_almost_eq(weapon.ground_reach(), 6.0, 0.001)
	assert_almost_eq(weapon.preview_ground_reach(), 6.0, 0.001)
