extends GutTest

## Faction scenes must stay consistent with the string-id world: every starting
## structure/unit they reference instantiates as an Entity with a non-empty
## piece id (spawnable by Skirmish, priced by the technology data). This covers
## the Faction -> starting-force data path without booting a full skirmish.

const FACTION_SCENES: Array = [
	"res://scenes/factions/anarchical.tscn",
	"res://scenes/factions/colonial.tscn",
]


func test_faction_starting_forces_have_ids_and_tech_entries() -> void:
	for path in FACTION_SCENES:
		var faction: Faction = (load(path) as PackedScene).instantiate()
		autofree(faction)
		assert_not_null(faction.starting_structure, "%s has a starting structure" % path)

		var scenes: Array = [faction.starting_structure]
		scenes.append_array(faction.starting_units)
		for packed: PackedScene in scenes:
			var inst: Node = packed.instantiate()
			assert_true(inst is Entity, "%s: %s is an Entity" % [path, packed.resource_path])
			if inst is Entity:
				var entity: Entity = inst
				assert_false(entity.id.is_empty(),
					"%s: %s has a piece id" % [path, packed.resource_path])
				# Trainable/buildable pieces must be priced in the generated tech
				# data (Skirmish spawns them free, but the roster must be coherent).
				var commander: Commander = Commander.new()
				assert_true(commander.technology_mapping.has(entity.id),
					"%s: '%s' is priced in technology.json" % [path, entity.id])
				commander.free()
			inst.free()


func test_faction_ordnance_unlocks_are_wired() -> void:
	for path in FACTION_SCENES:
		var faction: Faction = (load(path) as PackedScene).instantiate()
		autofree(faction)
		for unlock: OrdnanceUnlock in faction.ordnance_unlocks:
			assert_not_null(unlock.ordnance, "%s: unlock has an ordnance" % path)
			if unlock.ordnance != null:
				assert_false(String(unlock.ordnance.ordnance_name).is_empty())
