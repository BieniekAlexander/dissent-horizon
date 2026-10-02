extends GutTest

## Pins the "Damage System — Implementation Spec" catalog (gdd/tasks.md) against
## its own §6 validation rules, plus a few spot checks of the authored §3 matrix
## and the §4 resolution formula.
##
## Run: godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_DamageCatalog.gd
##
## Built via DamageCatalog.from_tsv() against the real on-disk TSVs rather than a
## fixture, so this also exercises the authored data — a typo in a multiplier
## there fails here, not just at balance-review time.

var catalog: DamageCatalog


func before_each() -> void:
	catalog = DamageCatalog.from_tsv(
		"res://resources/damage/damage_vs_armour.tsv", "res://resources/damage/damage_vs_frame.tsv"
	)


func test_catalog_has_eleven_profiles() -> void:
	assert_eq(catalog.profiles.size(), 11, "§2 names eleven damage types")


func test_no_two_profiles_share_a_row_resource() -> void:
	var seen: Array[DamageProfile] = []
	for p: DamageProfile in catalog.profiles:
		assert_false(p in seen, "§5.3: rows are owned, never shared by reference")
		seen.append(p)


func test_validator_reports_no_violations() -> void:
	var violations: Array[String] = DamageCatalogValidator.validate(catalog)
	assert_eq(violations, [] as Array[String], "\n".join(violations))


func test_matrix_spot_check_cryo() -> void:
	var cryo: DamageProfile = catalog.profile_for(Damage.Type.CRYO)
	assert_eq(cryo.strong_multiplier, 1.0, "CRYO is armour-flat per §5.1, damage is vestigial")


func test_electric_row_carries_the_spec_electricity_numbers() -> void:
	# §2's ELECTRICITY collided with this codebase's pre-existing Damage.Type.ELECTRIC —
	# per the resolved question, the code name won, so ELECTRIC carries the ELECTRICITY row.
	var electric: DamageProfile = catalog.profile_for(Damage.Type.ELECTRIC)
	assert_eq(electric.bio_multiplier, 0.4)
	assert_eq(electric.mech_multiplier, 1.0)


func test_net_new_types_are_present() -> void:
	for id: Damage.Type in [Damage.Type.INCENDIARY, Damage.Type.HIGH_EXPLOSIVE, Damage.Type.CRYO]:
		assert_not_null(
			catalog.profile_for(id), "%s should be parsed from the TSVs" % Damage.Type.keys()[id]
		)


func test_resolve_applies_frame_then_armour() -> void:
	var lead: DamageProfile = catalog.profile_for(Damage.Type.LEAD)
	assert_eq(lead.frame_multiplier(Defense.FrameType.BIO), 1.0)
	assert_eq(lead.armour_multiplier(Defense.ArmourType.LIGHT), 1.0)
	assert_almost_eq(lead.frame_multiplier(Defense.FrameType.MECH), 0.4, 0.001)
	assert_almost_eq(lead.armour_multiplier(Defense.ArmourType.STRONG), 0.25, 0.001)


func test_tech_gate_blocks_tier_one_strong_counters() -> void:
	var siege: DamageProfile = catalog.profile_for(Damage.Type.SIEGE)
	assert_false(
		DamageCatalogValidator.check_tech_gate(siege, 1),
		"§5.2/§6.5: a STRONG multiplier of 1.0 requires tech tier 2+"
	)
	assert_true(DamageCatalogValidator.check_tech_gate(siege, 2))


func test_tech_gate_is_silent_when_not_a_strong_counter() -> void:
	var lead: DamageProfile = catalog.profile_for(Damage.Type.LEAD)
	assert_true(
		DamageCatalogValidator.check_tech_gate(lead, 1),
		"LEAD never reaches 1.0 against STRONG, so no tier is required"
	)
