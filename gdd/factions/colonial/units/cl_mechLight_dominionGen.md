---
kind: Entity
title: Stock Truck
scene: res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn
flavor:
  description: armoured POW carrier; captures infantry for dominion
  verbose: The Colonial dominion unit. Drives over light biological units — enemy or neutral — and takes them into a cage holding three, then delivers them to a Compound, where each serves a sentence before being consumed. A full truck crushes what it runs over instead.
build:
  cost:
    energy: 500
  time: 15
  requires: [cl_infrastructure]
defense:
  hp: 300
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: QUICK
  turn_rate: 180
  max_acceleration: 3
  max_deceleration: -6
  crush_class: MEDIUM
  min_turn_speed_ratio: 1
garrison:
  capacity: 3
  frames: [BIO]
  armours: [LIGHT]
  movements: [GROUNDED]
  releasable: true
  bunker: false
  pieces: [cl_bioLight_builder]
ui:
  grid: [1, 1]
  factions:
    - colonial
---
## Visuals
- can use the Collective model for now
# Stock Truck

Built at the [[cl_commandCenter|Citadel]]. The Colonial dominion unit — the counterpart
of the Anarchists' [[an_bioMedium_dominionGen|Warlord]], taking by force what the Warlord takes by
persuasion.

- **Armoured POW carrier.** It takes light biological units — enemy soldiers, or a
  [[nt_shelter|Shelter]]'s neutral [[nt_bioLight_terrestrial|Terrestrials]] — into a closed cage
  holding three, and delivers them to a [[cl_infrastructure|Compound]], where each one starts
  serving a sentence
- **It captures by DRIVING OVER them.** There is no capture order: the truck is a crusher,
  and running over a unit it has room for takes that unit prisoner instead of killing it.
  A truck with a full cage crushes as any other vehicle would
- **It carries Servants, and only Servants, by order.** A [[cl_bioLight_builder|Servant]] can
  be ordered into the truck (`pieces:`), sharing the cage's three places with captives; no
  other piece can. Capture is unaffected — being run over is still the way a prisoner gets
  in, and a Servant aboard takes a place a prisoner could have had
- **Only the Servants come out by order.** Evacuate, or an occupant's card in the info panel,
  lets out the owner's own Servants; captives stay in the cage. A captive leaves only by being
  delivered to a [[cl_infrastructure|Compound]], or by the truck being destroyed, which
  frees it to the commander it was taken from
- **A delivery takes the Servants too.** Depositing at a Compound hands over everything in the
  cage, so Servants riding along start serving a sentence there — a costly way to buy
  dominion (500 energy each) that can be walked back: see the Compound
- **It does not build or repair.** Both belong to the [[cl_bioLight_builder|Servant]]; the
  truck is a capture unit and nothing else
- **Armoured for the roads it lives its life on** (`MEDIUM`, up from `LIGHT`) and slow
  (`1.75`, barely above infantry) — the Colonial "slow to traverse the map" identity lives
  on the dominion route itself. It is no longer a scout, and capturing an enemy soldier is
  opportunistic rather than a chase. See
  [colonial-dominion](../../systems/combat/colonial-dominion.md) §The pieces this changes.
