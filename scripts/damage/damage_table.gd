extends Node

var _armour_table: Dictionary = {}    # {Damage.Type -> {Defense.ArmourType -> float}}
var _attribute_table: Dictionary = {} # {Damage.Type -> {EntityAttribute.Type -> float}}

func _ready() -> void:
	_load_armour_table()
	_load_attribute_table()

func get_armour_multiplier(damage_type: Damage.Type, armour_type: Defense.ArmourType) -> float:
	return _armour_table.get(damage_type, {}).get(armour_type, 1.0)

func get_attribute_multipliers(damage_type: Damage.Type, entity: Node) -> float:
	var result: float = 1.0
	var row: Dictionary = _attribute_table.get(damage_type, {})
	for attr_type: int in row:
		if EntityAttribute.evaluate(attr_type, entity):
			result *= row[attr_type]
	return result

func calculate_damage(base: float, damage_type: Damage.Type, target: Node) -> float:
	var defense: Defense = target.get_node_or_null("Defense") as Defense
	var armour: Defense.ArmourType = defense.armour_type if defense != null else Defense.ArmourType.UNARMORED
	return base * get_armour_multiplier(damage_type, armour) * get_attribute_multipliers(damage_type, target)

func _load_armour_table() -> void:
	var file: FileAccess = FileAccess.open("res://resources/damage/damage_vs_armour.csv", FileAccess.READ)
	if file == null:
		push_error("DamageTable: could not open damage_vs_armour.csv")
		return

	var header: PackedStringArray = file.get_csv_line()
	var armour_keys: Array = Defense.ArmourType.keys()
	var col_map: Dictionary = {} # col_index -> ArmourType int
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in armour_keys:
			col_map[i] = Defense.ArmourType[col_name]

	var damage_keys: Array = Damage.Type.keys()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
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

func _load_attribute_table() -> void:
	var file: FileAccess = FileAccess.open("res://resources/damage/damage_vs_attribute.csv", FileAccess.READ)
	if file == null:
		push_error("DamageTable: could not open damage_vs_attribute.csv")
		return

	var header: PackedStringArray = file.get_csv_line()
	var attr_keys: Array = EntityAttribute.Type.keys()
	var col_map: Dictionary = {} # col_index -> EntityAttribute.Type int
	for i: int in range(1, header.size()):
		var col_name: String = header[i].strip_edges()
		if col_name in attr_keys:
			col_map[i] = EntityAttribute.Type[col_name]

	var damage_keys: Array = Damage.Type.keys()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
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
