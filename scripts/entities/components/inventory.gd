class_name Inventory
extends Node

## Holds the Weapon nodes owned by a commandable. Each direct child that is a
## Weapon represents one weapon slot. Methods here are the single place that
## walks this list so callers don't do ad-hoc child iteration.

func get_weapons() -> Array:
	return get_children().filter(func(c: Node) -> bool: return c is Weapon)

func has_weapons() -> bool:
	for c in get_children():
		if c is Weapon:
			return true
	return false

## Returns the first Weapon child whose can_target() returns true for `target`,
## or null if none match.
func weapon_for_target(target: Entity) -> Weapon:
	for c in get_children():
		if c is Weapon and c.can_target(target):
			return c
	return null

func any_weapon_can_target(target: Entity) -> bool:
	return weapon_for_target(target) != null

func total_damage() -> float:
	var total := 0.0
	for w: Weapon in get_weapons():
		total += w.damage
	return total
