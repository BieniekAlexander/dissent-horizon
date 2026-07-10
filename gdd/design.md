# Goals
- fast-paced combat
- minimal focus on macro - controls to make macro easier
# Mechanics
## Terrain
- Grid-based terrain
- Terraforming mechanics?
## Resources
- Ore - Basic resource, exists with limited availability on planets
- Dominion - influence over a planet
	- acquisition varies by faction
	- tech-limiter
	- incentivizes conflict
- 
## Pieces
- Buildings
	- Building with multiple units
- Units
	- Minions - primary unit, builds buildings, impacts dominion, can steal buildings
	- Veterancy
	- Slowed down when damaged?
	- Crushing?
- Ordnances
## Combat
- RPS
	- Different degrees of damage
		- varying degrees of minimal, normal, and high damage interactions, a la Generals
- Vision and range
	- long-range units have longer range than vision, requiring spotting
	- stealth units are revealed when attacking or standing close to enemy infantry units
- 
# Controls
- Commands
- Resources and production
	-  global training queue, allowing players to queue all building, units and upgrades, regardless of resources
	- Have some strategy around specifying production locations of units or being agnostic of it
# Physics
- electricity - stun/ministun
- fire - dot
- lazer - like RA2 tesla
- toxin
## Damage Calculations

| Type        | Bio | Mech | Light | Medium | Heavy | Properties                        |
| ----------- | --- | ---- | ----- | ------ | ----- | --------------------------------- |
| Toxic       | +   | -    |       |        |       |                                   |
| Sonic       | +   | -    | -     |        | +     |                                   |
| Lead        |     | -    | +     | -      | -     | hitscan                           |
| Plasma      |     |      | +     |        | -     | short range                       |
| Explosive   |     | +    |       |        |       |                                   |
| Siege       | -   | +    | -     |        | +     |                                   |
| Electricity | -   | +    | +     |        |       |                                   |
| Lazer       | -   | +    |       |        | +     | damage impacted by movement speed |
## Technologies
## Units
### T1

|      | Haus   | Bal    | Ward   | Tsel   | Succ   | Theo   |
| ---- | ------ | ------ | ------ | ------ | ------ | ------ |
| Inf  | Ranged | Ranged | Melee  | Ranged | Ranged | Ranged |
| Tank | Ranged | Melee  | Ranged | Ranged | Ranged | X      |
| Air  | X      | Ranged | Ranged | +Tank  | +Inf   | Ranged |

## Unit Modulators
- Price
- Health
- Armor type
- Shoots up, down, or both
- speed
- tech level
- flying/grounded
- range
- Projectile speed
- detector
- fire rate
- 

| Factions | Plasma | Radiation | Electricity | Cryogenics | Psychic/Sonic |
| -------- | ------ | --------- | ----------- | ---------- | ------------- |
| Col      |        |           |             |            | X             |
| Lib      |        |           |             |            |               |
| Tech     |        | X         |             |            |               |
| Marx     | X      |           |             |            |               |
| Auth     |        |           |             |            |               |
| Theo     |        |           |             | X          |               |

# Minigames
![[Untitled.base]]
