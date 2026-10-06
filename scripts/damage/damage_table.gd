extends Node

## Resolves damage per the "Damage System — Implementation Spec" (gdd/tasks.md):
## §4's formula is base × frame_multiplier × armour_multiplier — two axes, no
## third — so this carries no attribute-multiplier axis (the old
## damage_vs_attribute.tsv did IS_GROUNDED/IS_FLYING/HAS_STEALTH; dropped from
## the live path, per §1's "no third axis"). The armour/frame multipliers are
## parsed at boot into a DamageCatalog (DamageCatalog.from_tsv) — the two TSVs
## remain the canonical, on-disk data (plain text, readable by the Python
## balance tooling under tools/balance/ too); the catalog is only the in-memory
## shape this resolves against, never authored as a .tres.
##
## matchup_override() is untouched: it's a separate, orthogonal mechanism (a
## hand-authored per-UNIT override the bot consults for targeting/production
## effectiveness scoring, not part of calculate_damage's own multiply chain) and
## nothing in the spec bears on it.

const ARMOUR_TSV_PATH: String = "res://resources/damage/damage_vs_armour.tsv"
const FRAME_TSV_PATH: String = "res://resources/damage/damage_vs_frame.tsv"

var _catalog: DamageCatalog

## {attacker piece id -> {target piece id -> effectiveness multiplier}}.
## Hand-authored per-matchup overrides ("computed + overrides"): a value here WINS
## over the computed damage-table multiplier, for effectiveness the catalog can't
## express (AOE, kiting, …) — e.g. Kamikaze ≫ Irregular from its splash.
## Consulted by the bot's targeting + production effectiveness via matchup_override().
var _matchup_table: Dictionary = {}


func _ready() -> void:
	_load_catalog()
	_load_matchup_table()


func get_armour_multiplier(a_damage_type: Damage.Type, a_armour_type: Defense.ArmourType) -> float:
	var profile: DamageProfile = _catalog.profile_for(a_damage_type) if _catalog != null else null
	return profile.armour_multiplier(a_armour_type) if profile != null else 1.0


func get_frame_multiplier(a_damage_type: Damage.Type, a_frame_type: Defense.FrameType) -> float:
	var profile: DamageProfile = _catalog.profile_for(a_damage_type) if _catalog != null else null
	return profile.frame_multiplier(a_frame_type) if profile != null else 1.0


## The combined multiplier `a_damage_type` meets in a layer of `a_armour` and `a_frame` — a
## piece's Defense, or a Shield over it.
func multiplier(
	a_damage_type: Damage.Type, a_armour: Defense.ArmourType, a_frame: Defense.FrameType
) -> float:
	return (
		get_armour_multiplier(a_damage_type, a_armour)
		* get_frame_multiplier(a_damage_type, a_frame)
	)


func calculate_damage(a_base: float, a_damage_type: Damage.Type, a_target: Node) -> float:
	var defense: Defense = a_target.get_node_or_null("Defense") as Defense
	var armour: Defense.ArmourType = (
		defense.armour_type if defense != null else Defense.ArmourType.LIGHT
	)
	var frame: Defense.FrameType = defense.frame_type if defense != null else Defense.FrameType.BIO
	return (
		a_base
		* get_armour_multiplier(a_damage_type, armour)
		* get_frame_multiplier(a_damage_type, frame)
	)


## Hand-set effectiveness multiplier for [attacker_type] vs [target_type], or null
## when no override is authored (callers then use the computed damage-table value).
## This is the "computed + overrides" hook the bot consults — the override wins.
func matchup_override(a_attacker_type: StringName, a_target_type: StringName) -> Variant:
	return _matchup_table.get(a_attacker_type, {}).get(a_target_type)


func _load_catalog() -> void:
	_catalog = DamageCatalog.from_tsv(ARMOUR_TSV_PATH, FRAME_TSV_PATH)


## Optional per-matchup override table: rows = attacker piece ids, columns =
## target piece ids (matching the gdd spec docs / EntityIds — lowercase-first,
## camelCase allowed within each underscore-separated component), cells =
## effectiveness multiplier (blank = no override). Absent file is fine — it just
## means no overrides. Old-style enum names (UPPERCASE) are flagged so a stale
## table doesn't silently stop matching.
func _load_matchup_table() -> void:
	var file: FileAccess = FileAccess.open(
		"res://resources/damage/matchup_overrides.tsv", FileAccess.READ
	)
	if file == null:
		return

	var header: PackedStringArray = file.get_csv_line("\t")
	var col_map: Dictionary = {}  # col_index -> target piece id StringName
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name.is_empty():
			continue
		if col_name[0] != col_name[0].to_lower():
			push_warning(
				(
					(
						"matchup_overrides.tsv: column '%s' is not a piece id (starts "
						+ "uppercase — looks like a stale enum name) — ignored"
					)
					% col_name
				)
			)
			continue
		col_map[i] = StringName(col_name)

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line("\t")
		if row.size() < 2:
			continue
		var row_name: String = row[0].strip_edges()
		if row_name.is_empty():
			continue
		if row_name[0] != row_name[0].to_lower():
			push_warning(
				(
					(
						"matchup_overrides.tsv: row '%s' is not a piece id (starts "
						+ "uppercase — looks like a stale enum name) — ignored"
					)
					% row_name
				)
			)
			continue
		var attacker_id: StringName = StringName(row_name)
		var override_row: Dictionary = {}
		for col_idx: int in col_map:
			if col_idx < row.size():
				var cell: String = row[col_idx].strip_edges()
				if not cell.is_empty():
					override_row[col_map[col_idx]] = float(cell)
		if not override_row.is_empty():
			_matchup_table[attacker_id] = override_row

	file.close()
