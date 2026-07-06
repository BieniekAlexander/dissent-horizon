extends Node

var _armour_table: Dictionary = {}    # {Damage.Type -> {Defense.ArmourType -> float}}
var _frame_table: Dictionary = {}     # {Damage.Type -> {Defense.FrameType -> float}}
var _attribute_table: Dictionary = {} # {Damage.Type -> {EntityAttribute.Type -> float}}
## {attacker Entity.Type -> {target Entity.Type -> effectiveness multiplier}}.
## Hand-authored per-matchup overrides ("computed + overrides"): a value here WINS
## over the computed damage-table multiplier, for effectiveness the armour/attribute
## tables can't express (AOE, kiting, …) — e.g. Kamikaze ≫ Irregular from its splash.
## Consulted by the bot's targeting + production effectiveness via matchup_override().
var _matchup_table: Dictionary = {}

func _ready() -> void:
	_load_armour_table()
	_load_frame_table()
	_load_attribute_table()
	_load_matchup_table()

func get_armour_multiplier(damage_type: Damage.Type, armour_type: Defense.ArmourType) -> float:
	return _armour_table.get(damage_type, {}).get(armour_type, 1.0)

func get_frame_multiplier(damage_type: Damage.Type, frame_type: Defense.FrameType) -> float:
	return _frame_table.get(damage_type, {}).get(frame_type, 1.0)

func get_attribute_multipliers(damage_type: Damage.Type, entity: Node) -> float:
	var result: float = 1.0
	var row: Dictionary = _attribute_table.get(damage_type, {})
	for attr_type: int in row:
		if EntityAttribute.evaluate(attr_type, entity):
			result *= row[attr_type]
	return result

func calculate_damage(base: float, damage_type: Damage.Type, target: Node) -> float:
	var defense: Defense = target.get_node_or_null("Defense") as Defense
	var armour: Defense.ArmourType = defense.armour_type if defense != null else Defense.ArmourType.LIGHT
	var frame: Defense.FrameType = defense.frame_type if defense != null else Defense.FrameType.BIOLOGICAL
	return base \
		* get_armour_multiplier(damage_type, armour) \
		* get_frame_multiplier(damage_type, frame) \
		* get_attribute_multipliers(damage_type, target)

## Hand-set effectiveness multiplier for [attacker_type] vs [target_type], or null
## when no override is authored (callers then use the computed damage-table value).
## This is the "computed + overrides" hook the bot consults — the override wins.
func matchup_override(attacker_type: int, target_type: int) -> Variant:
	return _matchup_table.get(attacker_type, {}).get(target_type)

func _load_armour_table() -> void:
	var file: FileAccess = FileAccess.open("res://resources/damage/damage_vs_armour.tsv", FileAccess.READ)
	if file == null:
		push_error("DamageTable: could not open damage_vs_armour.tsv")
		return

	var header: PackedStringArray = file.get_csv_line("\t")
	var armour_keys: Array = Defense.ArmourType.keys()
	var col_map: Dictionary = {} # col_index -> ArmourType int
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in armour_keys:
			col_map[i] = Defense.ArmourType[col_name]

	var damage_keys: Array = Damage.Type.keys()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line("\t")
		if row.size() < 2:
			continue
		var row_name: String = row[0].strip_edges()
		if not (row_name in damage_keys):
			continue
		var damage_type: int = Damage.Type[row_name]
		var armour_row: Dictionary = {}
		for col_idx: int in col_map:
			if col_idx < row.size():
				var cell: String = row[col_idx].strip_edges()
				if not cell.is_empty():
					armour_row[col_map[col_idx]] = float(cell)
		_armour_table[damage_type] = armour_row

	file.close()

func _load_frame_table() -> void:
	# TODO(tune): damage_vs_frame.tsv is a neutral placeholder (all 1.0). Author
	# real BIOLOGICAL/METALLIC matchups and assign frame_type per unit.
	var file: FileAccess = FileAccess.open("res://resources/damage/damage_vs_frame.tsv", FileAccess.READ)
	if file == null:
		push_error("DamageTable: could not open damage_vs_frame.tsv")
		return

	var header: PackedStringArray = file.get_csv_line("\t")
	var frame_keys: Array = Defense.FrameType.keys()
	var col_map: Dictionary = {} # col_index -> FrameType int
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in frame_keys:
			col_map[i] = Defense.FrameType[col_name]

	var damage_keys: Array = Damage.Type.keys()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line("\t")
		if row.size() < 2:
			continue
		var row_name: String = row[0].strip_edges()
		if not (row_name in damage_keys):
			continue
		var damage_type: int = Damage.Type[row_name]
		var frame_row: Dictionary = {}
		for col_idx: int in col_map:
			if col_idx < row.size():
				var cell: String = row[col_idx].strip_edges()
				if not cell.is_empty():
					frame_row[col_map[col_idx]] = float(cell)
		_frame_table[damage_type] = frame_row

	file.close()

func _load_attribute_table() -> void:
	var file: FileAccess = FileAccess.open("res://resources/damage/damage_vs_attribute.tsv", FileAccess.READ)
	if file == null:
		push_error("DamageTable: could not open damage_vs_attribute.tsv")
		return

	var header: PackedStringArray = file.get_csv_line("\t")
	var attr_keys: Array = EntityAttribute.Type.keys()
	var col_map: Dictionary = {} # col_index -> EntityAttribute.Type int
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in attr_keys:
			col_map[i] = EntityAttribute.Type[col_name]

	var damage_keys: Array = Damage.Type.keys()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line("\t")
		if row.size() < 2:
			continue
		var row_name: String = row[0].strip_edges()
		if not (row_name in damage_keys):
			continue
		var damage_type: int = Damage.Type[row_name]
		var attr_row: Dictionary = {}
		for col_idx: int in col_map:
			if col_idx < row.size():
				var cell: String = row[col_idx].strip_edges()
				if not cell.is_empty():
					attr_row[col_map[col_idx]] = float(cell)
		if not attr_row.is_empty():
			_attribute_table[damage_type] = attr_row

	file.close()

## Optional per-matchup override table: rows = attacker Entity.Type names, columns =
## target Entity.Type names, cells = effectiveness multiplier (blank = no override).
## Absent file is fine — it just means no overrides.
func _load_matchup_table() -> void:
	var file: FileAccess = FileAccess.open("res://resources/damage/matchup_overrides.tsv", FileAccess.READ)
	if file == null:
		return

	var header: PackedStringArray = file.get_csv_line("\t")
	var type_keys: Array = Entity.Type.keys()
	var col_map: Dictionary = {} # col_index -> target Entity.Type int
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in type_keys:
			col_map[i] = Entity.Type[col_name]

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line("\t")
		if row.size() < 2:
			continue
		var row_name: String = row[0].strip_edges()
		if not (row_name in type_keys):
			continue
		var attacker_type: int = Entity.Type[row_name]
		var override_row: Dictionary = {}
		for col_idx: int in col_map:
			if col_idx < row.size():
				var cell: String = row[col_idx].strip_edges()
				if not cell.is_empty():
					override_row[col_map[col_idx]] = float(cell)
		if not override_row.is_empty():
			_matchup_table[attacker_type] = override_row

	file.close()
