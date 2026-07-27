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

Eleven damage types (`Damage.Type` in `scripts/entities/tools/damage.gd`): Toxic,
Incendiary, Sonic, Lead, Electricity (`ELECTRIC` in code), Explosive, Siege, Lazer,
High Explosive, Plasma, Cryo.

| Type           | Bio  | Mech | Light | Medium | Strong | Properties                                           |
| -------------- | ---- | ---- | ----- | ------ | ------ | ---------------------------------------------------- |
| Toxic          | 1.0  | 0.15 | 1.0   | 1.0    | 0.6    | persistent ground AOE; area denial                   |
| Incendiary     | 1.0  | 0.4  | 1.0   | 0.75   | 0.4    | DoT that follows the unit + lingering patch          |
| Sonic          | 1.0  | 0.15 | 0.6   | 1.0    | 0.4    | anti-bio specialist                                  |
| Lead           | 1.0  | 0.4  | 1.0   | 0.6    | 0.25   | hitscan, high rate of fire                           |
| Electricity    | 0.4  | 1.0  | 1.0   | 0.6    | 0.4    | anti-mech specialist                                 |
| Explosive      | 0.6  | 1.0  | 0.75  | 1.0    | 0.6    | cheap, portable, infantry-carryable baseline         |
| Siege          | 0.25 | 1.0  | 0.4   | 0.75   | 1.0    | direct-fire cannon; can't meaningfully hurt infantry |
| Lazer          | 0.25 | 1.0  | 1.0   | 1.0    | 1.0    | damage scales inverse to target speed                |
| High Explosive | 1.0  | 1.0  | 1.0   | 0.75   | 0.75   | splash; cost paid in slow/expensive delivery         |
| Plasma         | 1.0  | 1.0  | 1.0   | 0.75   | 0.6    | short range, frame-agnostic                          |
| Cryo           | 1.0  | 1.0  | 1.0   | 1.0    | 1.0    | damage is vestigial; value lies elsewhere            |

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
