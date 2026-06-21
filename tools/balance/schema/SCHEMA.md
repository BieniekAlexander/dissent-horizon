# Data schema

The data is a **graph**, modeled as normalized **catalogs** (one file each) plus
**by-id references**. Shareable things — status effects, projectiles, weapons —
are defined once and referenced by id from anywhere (within or across files).
Ids are global within their catalog; a dangling reference or duplicate id is a
hard load error.

```
data/
  damage_table.yaml      # rock-paper-scissors multipliers (synced from game CSVs)
  status_effects.yaml    # catalog: id -> effect
  projectiles.yaml       # catalog: id -> projectile   (references status_effects)
  weapons.yaml           # catalog: id -> weapon        (references a projectile)
  factions/<id>.yaml     # buildables reference weapons by id
```

References are **bare ids inside a typed field** — the field name picks the
catalog (`projectile: shell_explosive_50` resolves against `projectiles.yaml`),
so no type-prefixing is needed. Fields mirror the live Godot components so the
Phase-2 bridge is a mechanical translation. Numbers use the game's native units
(ticks at 60 physics ticks/sec, world-unit reach) — do not pre-convert.

## `status_effects.yaml`
```yaml
status_effects:
  burn_dot_20:
    kind: damage_over_time      # damage_over_time | slow | ... (only DoT affects v1 combat math)
    damage_per_tick: 5
    duration_ticks: 12          # total lifetime damage = damage_per_tick * duration_ticks
    damage_type: LAZER          # optional; omit to inherit the carrier projectile's type
```

## `projectiles.yaml`
```yaml
projectiles:
  shell_explosive_50:
    base_damage: 50
    damage_type: EXPLOSIVE      # LEAD|LAZER|TOXIN|FIRE|ELECTRICITY|SIEGE|EXPLOSIVE
    aoe_radius: 1.5             # informational in v1 (AoE is out of model scope)
    speed: 0.3
    status_effects: [burn_dot_20]   # 0+ refs into status_effects.yaml
```
The numeric stats live here; the projectile's visual/collision **PackedScene
stays in Godot**, joined to this entry by the shared id.

## `weapons.yaml`
```yaml
weapons:
  cannon:                       # ranged: carries a projectile
    name: Cannon
    projectile: shell_explosive_50
    split_time: 45              # ticks between shots      (Weapon.split_time)
    reload_time: 45             # ticks to refill a clip   (Weapon.reload_time)
    clip_size: 1                # shots per clip           (Weapon.clip_size)
    reach: 7.5                  # AttackRange radius, world units
    hits: [ground]             # target layers: ground / air (Weapon.target_mask)

  toxin_blade:                  # melee: omit `projectile`, use melee_damage
    name: Toxin Blade
    melee_damage: 12
    melee_damage_type: TOXIN
    split_time: 20
    reload_time: 20
    reach: 3.0
    hits: [ground]
```

## `factions/<id>.yaml`
```yaml
faction: iron_regime          # unique id (snake_case)
name: Iron Regime
description: One-line design intent.

buildables:
  - id: heavy_tank            # unique within the faction
    kind: unit                # unit | structure
    name: Heavy Tank
    cost: {ore: 600}          # v1 = ore only. TODO: pop + dominion + build_time -> weighted scalar
    requires: [compound]      # buildable ids that must exist first (tech DAG edges)

    # --- unit-only combat fields (omit for non-combat structures) ---
    armour: HEAVY             # UNARMORED | LIGHT | MEDIUM | HEAVY  (Defense.armour_type)
    hp: 800                   # Defense.hp_max
    movement:
      layer: ground           # ground | air — drives movement AND how it's targeted
      speed: 0.1
    attributes: []            # extra EntityAttribute flags, e.g. [HAS_STEALTH]
    weapons: [cannon]         # weapon ids (shared, referenced from weapons.yaml)

# Optional per-matchup overrides ("computed + overrides"). A hand-set value wins
# over the computed math. Ids may be cross-faction as "faction_id:buildable_id".
overrides:
  - attacker: sky_nomads:gunship
    target: iron_regime:heavy_tank
    exchange_cost: 250
    note: "Gunship kites the tank; raw stats understate it."
```

## Derived concepts (computed, not stored)
- **Tech tier**: longest `requires` chain depth in the tech DAG (roots = tier 1).
- **Targetable layer**: from `movement.layer` (ground/air).
- **DPS / TTK / exchange_cost**: see `dh_balance/combat.py`.

## Loader guarantees
- Duplicate id within a catalog → `ValueError`.
- Reference to an undefined id → `KeyError` naming the ref and its owner.
- The model handed to queries is fully **resolved**: a `Buildable` holds real
  `Weapon` objects holding real `Projectile`/`StatusEffect` objects (shared refs
  are the *same* object), so analysis code never touches ids.
