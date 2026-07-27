---
kind: Faction
title: Successors of Tenjin
scene: res://scenes/factions/technocratic.tscn
starts_with: [tc_bioLight_builder]
sanctions: []
---
# Introduction
[[world-building#Successors of Tenjin|successors-of-tenjin]]
# Overview

| **Themes**   | Advanced, Volatile, Elusiveness                                        |
| ------------ | ---------------------------------------------------------------------- |
| **Minion**   | Vulnerable Infantry                                                    |
| Infrastructure        | Reconnaissance Vehicles                                                |
| **Dominion** | Reactors generate, but have some byproduct that needs to be dealt with |
- Play Style
	- slow to start, needs some tech
	- High risk, high reward
	- checkmate
- Constraints
	- Deal with air harass vs buildings -> Good anti-air options
- Asymmetric mechanics
	- Mobility - portals
	- Heal - technicians can repair mechs and vehicles
	- disable - ~~hacking structures~~
	- positional - portals seem fine
- Unique Mechanics
	- Lab discharge
	- technicians build units on battlefield
# Specifics
## Tech Tree

```mermaid
%% tech-graph:start
%%{init: {'flowchart': {'nodeSpacing': 25, 'rankSpacing': 18, 'subGraphTitleMargin': {'top': 0, 'bottom': 8}}}}%%
flowchart TB
    nt_extractor["Extractor"]
    subgraph tc_commandCenter["Outpost"]
        tc_bioLight_builder(["Technician"])
        tc_mechMedium_infrastructure(["Surveyor"])
    end
    tc_tech1["Observatory"]
    subgraph tc_barracks["Armory"]
        tc_bioLight_antiMech(["Vanguard"])
    end
    tc_dominion["Laboratory"]
    tc_support1["Obfuscator"]
    tc_tech2["Quarantine"]
    tc_tech3["Accelerator"]
    tc_warFactory["Production Plant"]
    tc_tech1 --> tc_barracks
    tc_tech1 --> tc_dominion
    tc_tech1 --> tc_support1
    tc_tech1 --> tc_tech2
    tc_tech2 --> tc_tech3
    tc_tech2 --> tc_warFactory
    style tc_barracks fill:#80808020,stroke:#8a8a8a,stroke-width:1px
    style tc_commandCenter fill:#80808020,stroke:#8a8a8a,stroke-width:1px
%% tech-graph:end
```

```dataviewjs
await dv.view("_scripts/tech-graph")
```


## Compound
- minigunner, expensive and strong, shoots up
- lazer soldier
- Cyborg, lazer swords (T2 tech)
## Dispatch
- Looking Glass - observer
- Rainbird - drops off nuke shit
- Dunno - Anti-personnel and aircraft helicopter
- Siege Prism - flying artillery, redirects lazers (tech)
## Science Lab
- **Lazer Turret** - short range, shoots up, detects
- **Portal**
- T1 Tech
	- Buggy
	- Slingshot
	- Scorpion
	- **T2 Tech**
		- magnetron - magnetizes ballistics, one-way portal
		- Nuke Cannon, taking charges from science lab
		- **T3 Tech**
			- Giant Walker (super unit)
## Upgrades
Rainbirds can carry units
Science labs have more capacity
Galvanizer powers up more quickly
Technicians resistant to toxins
technicians build things more quickly
Missile with toxins, drains a science lab
## Sanctions
- Scan
- Technician drop
# Scenarios
## Tutorial
- Start with a building (idk what kind)
- abilities: 
	- technician drop
	- Upgrade rainbird garrison
	- Unlock target teleport
## Sanctions
- T1
	- Haste - give a single unit 50% more movement speed for some time
- T2
	- Turns a group of technicians into sentries
	- 
- T3
	- particle cannon
	- Teleport units from teleporter anywhere