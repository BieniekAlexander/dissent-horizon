# Goals
- fast-paced combat
- minimal focus on macro - controls to make macro easier
# Mechanics
## Terrain
- Grid-based terrain
## Resources
- Energy - Basic resource, exists with limited availability on planets
- Infrastructure - "speed bump", a la supply and energy from other games
- Dominion - influence over a planet
	- acquisition varies by faction
	- incentivizes conflict
## Pieces
- Buildings
- Units
	- Minions - primary unit, builds buildings, impacts dominion, can steal buildings
	- Veterancy
	- Slowed down when damaged?
	- Crushing?
- Sanctions
## Combat
- RPS
	- Different degrees of damage
		- varying degrees of minimal, normal, and high damage interactions, a la Generals
- Vision and range
	- long-range units have longer range than vision, requiring spotting
	- stealth units are revealed when attacking or standing close to enemy infantry units
# Physics
- electricity - stun/ministun
- fire - dot
- lazer - like RA2 tesla
- toxin
## Damage Calculations

Nine damage types (`Damage.Type` in `scripts/entities/tools/damage.gd`). Their multipliers
live ONLY in `resources/damage/damage_vs_armour.tsv` and `damage_vs_frame.tsv`; this table
says what each type is FOR, which the numbers cannot.

| Type           | Role                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------- |
| Toxic          | anti-bio; persistent ground AOE, area denial                                             |
| Incendiary     | anti-bio; DoT that follows the unit + lingering patch                                    |
| Sonic          | anti-bio specialist                                                                      |
| Lead           | anti-light-bio; hitscan, high rate of fire                                               |
| Electricity    | anti-mech specialist (`ELECTRIC` in code)                                                |
| Explosive      | anti-mech, useless against bio; best against LIGHT, moderate against MEDIUM, weak against STRONG. Common early, which is why it falls off as armour rises |
| Siege          | anti-MEDIUM: the mid-tier answer to mid-tier armour. Middling against LIGHT (and cost-ineffective there) and against STRONG |
| Lazer          | anti-mech and anti-MEDIUM, tuned like Siege so it can arrive early or mid game; damage scales inverse to target speed |
| Plasma         | good against everything, frame-agnostic; reserved for the heaviest weapons and paid for in tech, cost and slow delivery |

No type reaches 1.0 against STRONG: it is a class that mitigates everything. Cryogenics is not a damage type: it arrives as a status effect (Freeze, and PLANNED for the
Avalanche's shell).

**Data model:** `DamageProfile` (`scripts/damage/damage_profile.gd`) holds one type's
row — just the two multiplier axes (armour: light/medium/strong; frame: bio/mech), no
base damage or flavor text on the resource itself. `DamageCatalog.from_tsv()`
(`scripts/damage/damage_catalog.gd`) builds the full catalog at runtime by parsing
`resources/damage/damage_vs_armour.tsv` and `damage_vs_frame.tsv` — those TSVs are the
canonical, on-disk data, kept as plain text so the Python balance tooling under
`tools/balance/` can read them directly too, not just Godot. `DamageTable` (autoload)
resolves `final = base × frame_multiplier × armour_multiplier` against the catalog;
base damage is supplied per-weapon at the point of firing, not stored per damage type.
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
 
| Factions | Plasma | Radiation | Electricity | Cryogenics | Psychic/Sonic |
| -------- | ------ | --------- | ----------- | ---------- | ------------- |
| Col      |        |           |             |            |               |
| Lib      |        |           |             |            |               |
| Tech     |        | X         |             |            |               |
| Marx     | X      |           |             |            |               |
| Auth     |        |           |             |            |               |
| Theo     |        |           |             | X          |               |
