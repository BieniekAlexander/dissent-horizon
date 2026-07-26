"""Typed data model for factions, units, weapons, projectiles, and effects.

The data is a *graph*, not a tree: units reference weapons, weapons reference a
projectile, projectiles reference status effects, and any of those may be shared
by many owners. We model that with normalized **catalogs** (id -> object) plus
by-id references resolved at load time (see ``loader.py``). These dataclasses
hold the *resolved* graph — a ``Buildable`` already carries real ``Weapon``
objects, each carrying its real ``Projectile`` — so combat/query code never
touches ids.

Fields mirror the live Godot components (Defense, Weapon, Projectile,
StatusEffect, TechnologySpec) so the Phase-2 bridge can map them one-to-one.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

# Godot's Engine.physics_ticks_per_second. Cadence/durations are authored in
# ticks. The game sets this to 30 (project.godot: physics/common/
# physics_ticks_per_second=30). NOTE: it cancels in every ratio-based query
# (exchange_cost, Pareto), so it only affects absolute shots/sec and a future
# real-time army sim — keep it in sync with project.godot regardless.
PHYSICS_TICKS_PER_SECOND = 30.0


class Armour(str, Enum):
    LIGHT = "LIGHT"
    MEDIUM = "MEDIUM"
    HEAVY = "HEAVY"


class Frame(str, Enum):
    """Chassis material — a second damage axis alongside Armour (mirrors
    Defense.FrameType in-game)."""
    BIOLOGICAL = "BIOLOGICAL"
    METALLIC = "METALLIC"


class DamageType(str, Enum):
    LEAD = "LEAD"
    LAZER = "LAZER"
    TOXIC = "TOXIC"
    PLASMA = "PLASMA"
    ELECTRIC = "ELECTRIC"
    SIEGE = "SIEGE"
    EXPLOSIVE = "EXPLOSIVE"
    SONIC = "SONIC"


class Layer(str, Enum):
    """Where a unit lives — drives movement and how it is targeted."""
    GROUND = "ground"
    AIR = "air"


@dataclass(frozen=True)
class StatusEffect:
    """A shareable effect applied on hit (catalog: status_effects.yaml)."""
    id: str
    kind: str                          # "damage_over_time" | "slow" | ...
    damage_per_tick: float = 0.0
    tick_rate: int = 1                 # ticks between applications (DamageOverTime.tick_rate)
    duration_ticks: int = 0
    damage_type: DamageType | None = None   # None -> inherit carrier's type

    def total_damage(self) -> float:
        """Full damage one application deals over its lifetime. The DoT fires
        every ``tick_rate`` ticks for ``duration_ticks`` ticks, so it lands
        ``duration_ticks // tick_rate`` times (matches DamageOverTimeStatusEffect
        in-game). Approximation — ignores stacking/refresh; see combat.py scope."""
        if self.tick_rate <= 0:
            return 0.0
        return self.damage_per_tick * (self.duration_ticks // self.tick_rate)


@dataclass(frozen=True)
class Projectile:
    """A shareable projectile (catalog: projectiles.yaml). The numeric stats
    live here; the visual/collision PackedScene stays in Godot, joined by id."""
    id: str
    base_damage: float
    damage_type: DamageType
    aoe_radius: float = 0.0            # informational in v1 (AoE is out of scope)
    speed: float = 0.0
    status_effects: tuple[StatusEffect, ...] = ()


@dataclass(frozen=True)
class Weapon:
    """A shareable weapon (catalog: weapons.yaml).

    Ranged weapons carry a ``projectile``; melee weapons leave it ``None`` and
    use ``melee_damage``/``melee_damage_type`` (mirrors Weapon.gd).
    """
    id: str
    name: str
    split_time: int                    # ticks between shots
    reload_time: int                   # ticks to refill a clip
    clip_size: int                     # shots per clip
    reach: float                       # AttackRange radius, world units
    hits: frozenset[Layer]             # target layers it can strike
    projectile: Projectile | None = None
    melee_damage: float = 0.0
    melee_damage_type: DamageType = DamageType.LEAD

    def shots_per_second(self) -> float:
        """Sustained fire rate. A clip of ``clip_size`` shots fires over
        ``(clip_size-1)*split_time`` ticks, then ``reload_time`` ticks pass. For
        the common ``clip_size == 1`` case the game forces ``reload_time ==
        split_time`` -> ``1/split_time`` shots per tick."""
        cycle_ticks = max(1, (self.clip_size - 1) * self.split_time + self.reload_time)
        return self.clip_size / cycle_ticks * PHYSICS_TICKS_PER_SECOND

    def can_hit(self, layer: Layer) -> bool:
        return layer in self.hits


@dataclass(frozen=True)
class Cost:
    ore: int = 0
    # TODO(weighted-scalar): population, dominion, build_time. v1 ranks on ore
    # only; `scalar()` is the single place to fold the others in later.
    population: int = 0
    dominion: int = 0

    def scalar(self) -> float:
        """The single number used for cost-efficiency ranking. v1 = ore only."""
        return float(self.ore)


@dataclass
class Buildable:
    faction: str
    id: str
    kind: str                          # "unit" | "structure"
    name: str
    cost: Cost
    requires: list[str] = field(default_factory=list)
    builds: list[str] = field(default_factory=list)   # structure ids this unit can construct

    # unit-only combat fields (None/empty for non-combat structures)
    armour: Armour | None = None
    frame: Frame | None = None
    hp: float = 0.0
    layer: Layer | None = None
    speed: float = 0.0
    attributes: list[str] = field(default_factory=list)
    weapons: list[Weapon] = field(default_factory=list)   # resolved, shared

    @property
    def uid(self) -> str:
        """Globally-unique key: ``faction:id``."""
        return f"{self.faction}:{self.id}"

    @property
    def is_unit(self) -> bool:
        return self.kind == "unit"

    @property
    def is_combatant(self) -> bool:
        return bool(self.weapons)

    @property
    def effective_hp(self) -> float:
        return self.hp


@dataclass
class Faction:
    id: str
    name: str
    description: str
    buildables: dict[str, Buildable]            # id -> Buildable
    overrides: list[dict] = field(default_factory=list)
    starts_with: list[str] = field(default_factory=list)   # buildable ids owned/available at scenario start

    def units(self) -> list[Buildable]:
        return [b for b in self.buildables.values() if b.is_unit]

    def combatants(self) -> list[Buildable]:
        return [b for b in self.buildables.values() if b.is_combatant]


@dataclass
class DamageTable:
    """Mirrors the live DamageTable: damage_type x {armour, frame, attribute} -> multiplier."""
    vs_armour: dict[DamageType, dict[Armour, float]]
    vs_attribute: dict[DamageType, dict[str, float]]
    vs_frame: dict[DamageType, dict[Frame, float]] = field(default_factory=dict)

    def armour_multiplier(self, dtype: DamageType, armour: Armour) -> float:
        return self.vs_armour.get(dtype, {}).get(armour, 1.0)

    def frame_multiplier(self, dtype: DamageType, frame: Frame) -> float:
        return self.vs_frame.get(dtype, {}).get(frame, 1.0)

    def attribute_multiplier(self, dtype: DamageType, attributes: list[str], layer: Layer | None) -> float:
        row = self.vs_attribute.get(dtype, {})
        if not row:
            return 1.0
        # Layer implies the IS_GROUNDED / IS_FLYING attributes the game derives
        # from Movement.mode, in addition to explicit attributes (stealth).
        active = set(attributes)
        if layer == Layer.AIR:
            active.add("IS_FLYING")
        elif layer == Layer.GROUND:
            active.add("IS_GROUNDED")
        result = 1.0
        for attr, mult in row.items():
            if attr in active:
                result *= mult
        return result


@dataclass
class World:
    """Everything loaded: the damage table, the shared catalogs, and factions."""
    damage: DamageTable
    factions: dict[str, Faction]
    weapons: dict[str, Weapon] = field(default_factory=dict)
    projectiles: dict[str, Projectile] = field(default_factory=dict)
    status_effects: dict[str, StatusEffect] = field(default_factory=dict)

    def all_units(self) -> list[Buildable]:
        out: list[Buildable] = []
        for f in self.factions.values():
            out.extend(f.units())
        return out

    def get(self, uid: str) -> Buildable:
        fid, _, bid = uid.partition(":")
        return self.factions[fid].buildables[bid]
