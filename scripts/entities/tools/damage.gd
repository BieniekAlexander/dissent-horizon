class_name Damage

enum Type {
	UNDEFINED = 0,
	LEAD = 1,
	TOXIC = 2,
	SONIC = 3,
	PLASMA = 4,
	SIEGE = 5,
	EXPLOSIVE = 6,
	ELECTRIC = 7,
	LAZER = 8
}

var amount: float
var type: Type

func _init(a_amount: float, a_type: Type = Type.LEAD) -> void:
	amount = a_amount
	type = a_type
