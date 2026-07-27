---
kind: Entity
title: shelter
scene: res://scenes/entities/structures/nt/nt_shelter.tscn
editor_description: Neutral map feature that houses and repopulates Terrestrials.
commandable: false
footprint: [3, 3]
shelter: true
---

# Shelter

A neutral map feature holding the inhabitants of the land being fought over. A shelter
produces one [[nt_bioLight_terrestrial|Terrestrial]] every 10 seconds and sustains 3 of them: each
new resident is registered with the shelter and wanders around it, and the spawn timer
only runs while the shelter is below its population of 3. The 30 → 10 second change is what
makes arrivals frequent and small — see
[colonial-dominion](../../systems/combat/colonial-dominion.md) §The pieces this changes.
`spawn_interval` is authored directly on `nt_shelter.tscn`; Shelter is not yet part of the
spec-doc schema (see `tools/spec_import/README.md` §Doc schema).

Players capitalize on the residents, not on the building itself:

- **Colonials** — a [[cl_mechLight_dominionGen|Stock Truck]] abducts terrestrials one at a time and
  deposits them at a [[cl_infrastructure|Compound]], where each serves a sentence before being
  consumed
- **Anarchists** — a [[an_bioMedium_dominionGen|Warlord]] liberates them by proximity: any neutral
  terrestrial that comes within its liberation range converts into an [[an_bioLight_builder]]
  under that Warlord's commander

A terrestrial is unregistered from its shelter the moment it leaves play by any route
(killed, abducted, liberated), which restarts production.
