class_name Damage

enum Type {
	LEAD = 1,
	LAZER = 2,
	TOXIN = 3,
	FIRE = 4,
	ELECTRICITY = 5 ,
	SIEGE = 6,
	EXPLOSIVE = 7
}

static var multiplier_patterns: Dictionary = {
	Type.LEAD: [
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.LIGHT, 1),
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.HEAVY, .1)
	],
	Type.LAZER: [
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.LIGHT, .25),
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.HEAVY, 1)
	]
}
