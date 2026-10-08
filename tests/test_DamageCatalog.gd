extends GutTest

## Pins the damage catalog (gdd/design.md §Damage Calculations) against its
## validation rules, plus a few spot checks of the authored matrix and the
## resolution formula.
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


func test_every_damage_type_has_a_profile() -> void:
	# UNDEFINED is the enum's zero and never carries a row.
	assert_eq(catalog.profiles.size(), Damage.Type.size() - 1, "a damage type with no TSV row")


func test_no_two_profiles_share_a_row_resource() -> void:
	var seen: Array[DamageProfile] = []
	for p: DamageProfile in catalog.profiles:
		assert_false(p in seen, "§5.3: rows are owned, never shared by reference")
		seen.append(p)


func test_validator_reports_no_violations() -> void:
	var violations: Array[String] = DamageCatalogValidator.validate(catalog)
	assert_eq(violations, [] as Array[String], "\n".join(violations))


func test_electric_row_carries_the_spec_electricity_numbers() -> void:
	# §2's ELECTRICITY collided with this codebase's pre-existing Damage.Type.ELECTRIC —
	# per the resolved question, the code name won, so ELECTRIC carries the ELECTRICITY row.
	var electric: DamageProfile = catalog.profile_for(Damage.Type.ELECTRIC)
	assert_eq(electric.bio_multiplier, 0.4)
	assert_eq(electric.mech_multiplier, 1.0)


func test_net_new_types_are_present() -> void:
	for id: Damage.Type in [Damage.Type.INCENDIARY]:
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
	var strong_counter: DamageProfile = DamageProfile.new()
	strong_counter.strong_multiplier = 1.0
	assert_false(
		DamageCatalogValidator.check_tech_gate(strong_counter, 1),
		"§5.2/§6.5: a STRONG multiplier of 1.0 requires tech tier 2+"
	)
	assert_true(DamageCatalogValidator.check_tech_gate(strong_counter, 2))


func test_tech_gate_is_silent_when_not_a_strong_counter() -> void:
	var lead: DamageProfile = catalog.profile_for(Damage.Type.LEAD)
	assert_true(
		DamageCatalogValidator.check_tech_gate(lead, 1),
		"LEAD never reaches 1.0 against STRONG, so no tier is required"
	)
