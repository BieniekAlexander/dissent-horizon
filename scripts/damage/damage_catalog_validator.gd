class_name DamageCatalogValidator

## §6 validation rules for a DamageCatalog. Each check returns a list of
## human-readable violation strings (empty = clean) rather than asserting
## directly, so a test can report every problem in one run instead of stopping
## at the first. Static and read-only — nothing here mutates the catalog.

static func validate(catalog: DamageCatalog) -> Array[String]:
	var violations: Array[String] = []
	violations.append_array(check_frame_normalization(catalog))
	violations.append_array(check_armour_normalization(catalog))
	violations.append_array(check_ladder_conformance(catalog))
	violations.append_array(check_column_coverage(catalog))
	return violations

## §6.1: the larger of the two frame multipliers is exactly 1.0, for every type.
static func check_frame_normalization(catalog: DamageCatalog) -> Array[String]:
	var violations: Array[String] = []
	for p: DamageProfile in catalog.profiles:
		if maxf(p.bio_multiplier, p.mech_multiplier) != 1.0:
			violations.append(
				"%s: frame row does not normalize to 1.0 (bio=%.2f mech=%.2f)"
				% [Damage.Type.keys()[p.id], p.bio_multiplier, p.mech_multiplier]
			)
	return violations

## §6.2: the largest of the three armour multipliers is exactly 1.0, for every type.
static func check_armour_normalization(catalog: DamageCatalog) -> Array[String]:
	var violations: Array[String] = []
	for p: DamageProfile in catalog.profiles:
		var largest: float = maxf(p.light_multiplier, maxf(p.medium_multiplier, p.strong_multiplier))
		if largest != 1.0:
			violations.append(
				"%s: armour row does not normalize to 1.0 (light=%.2f medium=%.2f strong=%.2f)"
				% [Damage.Type.keys()[p.id], p.light_multiplier, p.medium_multiplier, p.strong_multiplier]
			)
	return violations

## §6.3: every multiplier is a member of the §3.1 ladder.
static func check_ladder_conformance(catalog: DamageCatalog) -> Array[String]:
	var violations: Array[String] = []
	for p: DamageProfile in catalog.profiles:
		var values: Dictionary = {
			"bio": p.bio_multiplier,
			"mech": p.mech_multiplier,
			"light": p.light_multiplier,
			"medium": p.medium_multiplier,
			"strong": p.strong_multiplier,
		}
		for column: String in values:
			var value: float = values[column]
			if not _on_ladder(value):
				violations.append(
					"%s: %s multiplier %.3f is off the §3.1 ladder"
					% [Damage.Type.keys()[p.id], column, value]
				)
	return violations

static func _on_ladder(value: float) -> bool:
	for rung: float in DamageProfile.MULTIPLIER_LADDER:
		if is_equal_approx(value, rung):
			return true
	return false

## §6.4: for each of bio, mech, light, medium, strong, at least one
## damage type in the catalog has 1.0 in that column.
static func check_column_coverage(catalog: DamageCatalog) -> Array[String]:
	var covered: Dictionary = {
		"bio": false, "mech": false,
		"light": false, "medium": false, "strong": false,
	}
	for p: DamageProfile in catalog.profiles:
		if p.bio_multiplier == 1.0: covered.bio = true
		if p.mech_multiplier == 1.0: covered.mech = true
		if p.light_multiplier == 1.0: covered.light = true
		if p.medium_multiplier == 1.0: covered.medium = true
		if p.strong_multiplier == 1.0: covered.strong = true
	var violations: Array[String] = []
	for column: String in covered:
		if not covered[column]:
			violations.append("no damage type reaches 1.0 against %s" % column)
	return violations

## §6.5/§5.2: any weapon whose damage type profile has a STRONG multiplier of
## 1.0 must be tech tier 2 or later. No per-faction weapon carries a tech tier
## in this codebase yet — that assignment is explicitly out of this task's
## scope (see gdd/tasks.md §Scope) — so this is a pure function for whatever
## weapon-authoring validation is built later to call per weapon, rather than
## a catalog-wide scan over data that doesn't exist.
static func check_tech_gate(profile: DamageProfile, weapon_tech_tier: int) -> bool:
	if profile.strong_multiplier == 1.0:
		return weapon_tech_tier >= 2
	return true
