class_name DamageCatalog
extends Resource

## An in-memory instance of the damage matrix (gdd/tasks.md §2/§3): one
## DamageProfile per Damage.Type. resources/damage/damage_vs_{armour,frame}.tsv
## are the canonical, on-disk source — plain text so the Python balance/validation
## tooling under tools/balance/ can read them directly — so a catalog is always
## built at runtime via from_tsv(), never authored as a .tres.

@export var profiles: Array[DamageProfile] = []

func profile_for(a_id: Damage.Type) -> DamageProfile:
	for p: DamageProfile in profiles:
		if p.id == a_id:
			return p
	return null

## Builds a catalog by parsing the armour/frame multiplier TSVs. §5.3: each row
## is its own DamageProfile instance — nothing here is shared by reference, even
## where two rows' numbers happen to match, since every profile is constructed
## fresh per damage type found in either file.
static func from_tsv(armour_tsv_path: String, frame_tsv_path: String) -> DamageCatalog:
	var catalog := DamageCatalog.new()
	var armour_rows: Dictionary = _parse_multiplier_tsv(armour_tsv_path, Defense.ArmourType)
	var frame_rows: Dictionary = _parse_multiplier_tsv(frame_tsv_path, Defense.FrameType)

	var damage_types: Dictionary = {} # Damage.Type -> true, de-duplicated across both files
	for damage_type: int in armour_rows:
		damage_types[damage_type] = true
	for damage_type: int in frame_rows:
		damage_types[damage_type] = true

	for damage_type: int in damage_types:
		var profile := DamageProfile.new()
		profile.id = damage_type
		var armour_row: Dictionary = armour_rows.get(damage_type, {})
		profile.light_multiplier = armour_row.get(Defense.ArmourType.LIGHT, 1.0)
		profile.medium_multiplier = armour_row.get(Defense.ArmourType.MEDIUM, 1.0)
		profile.strong_multiplier = armour_row.get(Defense.ArmourType.STRONG, 1.0)
		var frame_row: Dictionary = frame_rows.get(damage_type, {})
		profile.bio_multiplier = frame_row.get(Defense.FrameType.BIO, 1.0)
		profile.mech_multiplier = frame_row.get(Defense.FrameType.MECH, 1.0)
		catalog.profiles.append(profile)

	return catalog

## Reads one damage_vs_<axis>.tsv into {Damage.Type -> {axis value -> float}}.
## axis_enum is Defense.ArmourType or Defense.FrameType, passed as the raw enum —
## GDScript enums double as {name: value} dictionaries, the same trick the
## original per-axis tsv loaders used before they were merged into this one.
static func _parse_multiplier_tsv(path: String, axis_enum: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DamageCatalog: could not open %s" % path)
		return result

	var header: PackedStringArray = file.get_csv_line("\t")
	var axis_keys: Array = axis_enum.keys()
	var col_map: Dictionary = {} # column index -> axis enum value
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in axis_keys:
			col_map[i] = axis_enum[col_name]

	var damage_keys: Array = Damage.Type.keys()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line("\t")
		if row.size() < 2:
			continue
		var row_name: String = row[0].strip_edges()
		if not (row_name in damage_keys):
			continue
		var damage_type: int = Damage.Type[row_name]
		var value_row: Dictionary = {}
		for col_idx: int in col_map:
			if col_idx < row.size():
				var cell: String = row[col_idx].strip_edges()
				if not cell.is_empty():
					value_row[col_map[col_idx]] = float(cell)
		result[damage_type] = value_row

	file.close()
	return result
