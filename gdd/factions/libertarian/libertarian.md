---
kind: Faction
title: The Warden
scene: res://scenes/factions/libertarian.tscn
starts_with: [lb_aircraftLight_builder, lb_aircraftLight_builder]
sanctions: []
---
# Introduction
[[world-building#The Warden|the-warden]]
# Overview
| **Themes**   | Decentralized, Aerial, Pacifying                              |
| ------------ | ------------------------------------------------------------- |
| **Minion**   | Slow Aircraft                                                 |
| Infrastructure       | Large power plant building                                    |
| **Dominion** | Build an obelisk, where dominion is generated per nearby area |
- Play Style
	- Unaggressive, booming at the start
	- Lots of hit-and-run
- Asymmetric Mechanics
	- Mobility - lots of flying units, even at low tech
	- Disable - rocket defense systems
	- Positional - Relays heal units around it
- Unique Mechanics
	- drones can attach to larger mechanical units
# Specifics
## Tech Tree

```mermaid
%% tech-graph:start
flowchart LR
    empty["libertarian: no pieces authored yet"]
%% tech-graph:end
```

```dataviewjs
await dv.view("_scripts/tech-graph")
```

## CCC
### Falcon
- fighter
### Viper
- single target elimination
### Purifier
- aurora bomber (req. tech)
# Specifics
## Tech Tree
- **lb_commandCenter** - Main building
	- Opticon - Generates dominion for each tile it sees that none of your own fixtures stands on
	- **Reactor** - provides a lot of infrastructure
		- **Security Tower** (`lb_defense`) - holds one drone, whose kind shapes the tower; detects stealth ([[static-defence]])
		- **Repair Station**
		- **Assembler** - T1 production
			- 
			- **Cyber Uplink**
				- **Quantum Mainframe**
			-
## Upgrades
- Generic
	- Rocket speed upgrade
	- No cooldown on unit self-repair
	- Increased lazer damage
	- Faster gatling spin-up time
	- Airplanes accelerate faster (less damage, better at escaping rockets) and arm faster
- Specific
	- decrease interceptor timer
	- make allied interceptor shock invulnerable
	- upgrade harpy repair speed
	- Falcon payload size
	- interceptor shock deals damage
	- Increase surveyor line of sight
	- vipers can clear garrisons
## Sanctions
- single-unit heal and shield
- Short-circuit a single unit
- Deploy peacekeeper drones anywhere
- Viper stealth
- particle cannon
- some sort of stasis ability
- Unlock additional drone production types by Absolution
