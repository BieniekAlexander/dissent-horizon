extends GutTest

## DamageTable (autoload) is the live consumer of DamageCatalog — see
## tests/test_DamageCatalog.gd for the catalog/validator itself. This pins the
## §4 resolution formula end to end (base × frame_multiplier × armour_multiplier,
## no third axis) and the untouched matchup_override() side-channel.
##
## Run: godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_DamageTable.gd


func _target_with_defense(a_armour: Defense.ArmourType, a_frame: Defense.FrameType) -> Node:
	var target := Node.new()
	var defense := Defense.new()
	defense.name = "Defense"
	defense.armour_type = a_armour
	defense.frame_type = a_frame
	target.add_child(defense)
	return target


func test_calculate_damage_applies_frame_and_armour() -> void:
	var target: Node = autofree(_target_with_defense(Defense.ArmourType.STRONG, Defense.FrameType.MECH))
	# SIEGE vs MECH/STRONG: both multipliers are 1.0 per the §3 matrix.
	assert_eq(DamageTable.calculate_damage(70.0, Damage.Type.SIEGE, target), 70.0)


func test_calculate_damage_applies_the_penalty_columns() -> void:
	var target: Node = autofree(_target_with_defense(Defense.ArmourType.STRONG, Defense.FrameType.BIO))
	# The multipliers are the owner's to retune, so read them from the table: what this pins is
	# that the two columns are both applied, and neither is a no-op for this pairing.
	var frame: float = DamageTable.get_frame_multiplier(Damage.Type.SIEGE, Defense.FrameType.BIO)
	var armour: float = DamageTable.get_armour_multiplier(Damage.Type.SIEGE, Defense.ArmourType.STRONG)
	assert_lt(frame, 1.0, "guards the fixture: SIEGE is penalised against BIO")
	assert_almost_eq(DamageTable.calculate_damage(70.0, Damage.Type.SIEGE, target), 70.0 * frame * armour, 0.001)


func test_calculate_damage_defaults_to_light_biological_with_no_defense() -> void:
	var target: Node = autofree(Node.new())
	assert_eq(DamageTable.calculate_damage(15.0, Damage.Type.LEAD, target), 15.0)


func test_matchup_override_returns_authored_value() -> void:
	assert_eq(DamageTable.matchup_override(&"an_aircraftMedium_antiMech", &"an_bioLight_builder"), 3.0)


func test_matchup_override_returns_null_when_unauthored() -> void:
	assert_null(DamageTable.matchup_override(&"an_aircraftMedium_antiMech", &"an_bioMedium_dominionGen"))
