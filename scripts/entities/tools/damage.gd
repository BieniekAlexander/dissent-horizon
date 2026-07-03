class_name Damage

enum Type {
	UNDEFINED = 0,
	LEAD = 1,
	LAZER = 2,
	TOXIN = 3,
	FIRE = 4,
	ELECTRICITY = 5,
	SIEGE = 6,
	EXPLOSIVE = 7
}

var amount: float
var type: Type

func _init(a_amount: float, a_type: Type = Type.LEAD) -> void:
	amount = a_amount
	type = a_type
