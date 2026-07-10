extends GutTest

## Validates the PLANT interaction wiring (task 5) and shape-based interaction reach
## (task 6): the Anarchical sapper loads with a PLANT interaction whose duration is BY_HP
## and whose reach is authored as a Shape3D, the plant projectile carries the spec'd
## stats, and the Colonial recruit no longer carries the interaction.

const SAPPER := preload("res://scenes/entities/units/an/sapper.tscn")
const RECRUIT := preload("res://scenes/entities/units/cl/recruit.tscn")
const PLANT_BOMB := preload("res://scenes/entities/projectiles/an/plant_bomb.tscn")

func _plant_of(unit: Node) -> Interaction:
	var interactor: Interactor = unit.get_node_or_null("Interactor") as Interactor
	if interactor == null:
		return null
	for i: Interaction in interactor.interactions:
		if i.type == Interaction.Type.PLANT:
			return i
	return null

func test_sapper_has_plant_interaction() -> void:
	var sapper: Node = SAPPER.instantiate()
	add_child_autofree(sapper)
	var plant: Interaction = _plant_of(sapper)
	assert_not_null(plant, "sapper has a PLANT interaction")
	assert_eq(plant.duration_type, Interaction.DurationType.BY_HP, "PLANT uses BY_HP duration")
	assert_not_null(plant.interact_shape, "PLANT reach is a collision shape, not a radius")
	assert_true(plant.interact_shape is CylinderShape3D, "PLANT reach shape is a Cylinder")
	assert_not_null(plant.projectile_scene, "PLANT has a projectile scene")

func test_sapper_has_no_weapons() -> void:
	var sapper: Node = SAPPER.instantiate()
	add_child_autofree(sapper)
	assert_null(sapper.get_node_or_null("Loadout"), "sapper carries no Loadout/weapons")

func test_recruit_no_longer_has_plant_interaction() -> void:
	var recruit: Node = RECRUIT.instantiate()
	add_child_autofree(recruit)
	assert_null(_plant_of(recruit), "recruit no longer has the PLANT interaction")

func test_plant_required_ticks_scales_with_hp() -> void:
	# required_ticks for BY_HP = hp_factor * target.defense.hp.
	var sapper: Node = SAPPER.instantiate()
	add_child_autofree(sapper)
	var plant: Interaction = _plant_of(sapper)
	# Use the sapper itself as a stand-in Entity with a Defense component.
	var ticks: float = plant.required_ticks(sapper)
	assert_almost_eq(ticks, plant.hp_factor * sapper.defense.hp, 0.001, "BY_HP ticks = hp_factor * hp")

func test_plant_bomb_projectile_stats() -> void:
	var bomb: Projectile = PLANT_BOMB.instantiate() as Projectile
	add_child_autofree(bomb)
	assert_eq(bomb.damage_type, Damage.Type.EXPLOSIVE, "plant bomb is EXPLOSIVE")
	assert_almost_eq(bomb.base_damage, 10000.0, 0.001, "plant bomb damage = 10000")
	assert_almost_eq(bomb.speed, 0.0, 0.001, "plant bomb speed = 0")
	assert_eq(bomb.pre_impact_lifespan, 1, "pre_impact_lifespan = 1")
	assert_eq(bomb.post_impact_lifespan, 90, "post_impact_lifespan = 90")
	assert_eq(bomb.tick_rate, 90, "tick_rate = 90")
