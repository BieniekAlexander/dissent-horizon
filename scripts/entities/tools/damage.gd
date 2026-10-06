class_name Damage

enum Type {
	UNDEFINED = 0,
	LEAD = 1,
	TOXIC = 2,
	SONIC = 3,
	PLASMA = 4,
	SIEGE = 5,
	EXPLOSIVE = 6,
	ELECTRIC = 7,  ## the Damage System spec's ELECTRICITY — kept as ELECTRIC, the pre-existing name
	LAZER = 8,
	INCENDIARY = 9,
}

var amount: float
var type: Type


func _init(a_amount: float, a_type: Type = Type.LEAD) -> void:
	amount = a_amount
	type = a_type
