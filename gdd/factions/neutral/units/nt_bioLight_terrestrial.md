---
kind: Entity
title: terrestrial
scene: res://scenes/entities/units/nt/nt_bioLight_terrestrial.tscn
editor_description: Neutral inhabitant spawned by a Shelter. Unarmed, cannot build.
flavor:
  description: potato
  verbose: potato
defense:
  hp: 80
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
body:
  radius: .3
movement: {speed: SLUGGISH, turn_rate: 1080, crush_class: TINY, min_turn_speed_ratio: 0}
---

# Terrestrial

- **TINY, so a vehicle can drive over one.** That is not flavour: it is the whole of the
  Colonial route to a Shelter's population, since a [[cl_mechLight_dominionGen|Stock Truck]]
  captures by running its prey over. A Terrestrial that outsized the truck could never be
  taken — see `gdd/systems/combat/garrison-and-transport.md` §Capture is a crush.

The people who already live on the land being fought over. Terrestrials are owned by
the neutral commander (id 0), are produced by [[nt_shelter|Shelters]], and mill about
their shelter under a `Wander` command until a player capitalizes on them.

- unarmed — no weapons, and no `Builds`, so they contribute nothing militarily on
  their own
- same body as an [[an_bioLight_builder]] (hp / armour / frame / vision / speed), so what a
  faction gets out of one is decided entirely by how it converts them
- interactions:
	- **Colonials** abduct them with the [[cl_mechLight_dominionGen|Stock Truck]] and intern them
	  in a [[cl_infrastructure|Compound]], which converts each into a [[cl_bioLight_builder|Servant]]
	- **Anarchists** liberate them on contact: a [[an_bioMedium_dominionGen|Warlord]] walking up to a
	  terrestrial converts it into an [[an_bioLight_builder]] under that Warlord's commander
