"""Faction-distinctness heuristics — "are these two factions' rosters actually
different, or re-skins of each other?"

Built bottom-up: per-weapon and per-unit *difference* functions sum into a
``unit_distinctness`` score, which ``set_distinctness`` rolls up across rosters.
Higher = more distinct. Like the effectiveness factors these are admitted
HEURISTICS — every bucket cutoff / weight is a named constant marked
``# TODO(tune)`` so calibrating is a one-line edit. Pure (no I/O), so each piece
is testable in isolation.

NOTE the set roll-up is deliberately asymmetric (``set_distinctness(A, B)`` need
not equal ``(B, A)``): it asks "how well is each A-unit shadowed by *some* B-unit",
which is direction-dependent. That's fine for the intended use (matrices).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from .model import Armour, Buildable, DamageType, DamageTable, Frame, Layer, Weapon

# --- tunable knobs ---------------------------------------------------------- #
# TODO(tune): all cutoffs/weights below are first-pass guesses. Revisit once
# movement speeds, ranges, and costs are themselves tuned.
RANGE_BUCKETS = (3.0, 8.0)      # reach (world units): close < 3 <= medium < 8 <= long
SPEED_BUCKETS = (0.05, 0.10)    # speed: slow < 0.05 <= medium < 0.10 <= fast
COST_BUCKETS = (150.0, 400.0)   # ore: cheap < 150 <= medium < 400 <= expensive
BUCKET_STEP = 0.5               # added per ordinal bucket of separation
GREATLY_DIFFER_COS = 0.8        # damage profiles below this cosine "greatly differ"
TARGET_DISJOINT = 3.0           # weapons whose hittable layers don't overlap at all
TARGET_PARTIAL = 1.0            # one weapon hits something the other can't
FRAME_DIFF = 1.0               # differing chassis material
AERIAL_VS_GROUND = 1.0          # one flies, the other doesn't
DAMAGE_TYPE_DIFF = 0.5          # weapons use different damage types
DAMAGE_GREATLY_DIFF = 1.0       # ...and those types specialise against opposite targets
UNARMED_VS_ARMED = 2.0          # one unit has weapons, the other none


def _bucket(value: float, cutoffs: tuple[float, float]) -> int:
    return sum(1 for c in cutoffs if value >= c)


def _bucket_distance(a: float, b: float, cutoffs: tuple[float, float]) -> float:
    return BUCKET_STEP * abs(_bucket(a, cutoffs) - _bucket(b, cutoffs))


# --------------------------------------------------------------------------- #
# Weapon-level
# --------------------------------------------------------------------------- #
def _weapon_damage_type(w: Weapon) -> DamageType:
    return w.projectile.damage_type if w.projectile is not None else w.melee_damage_type


def _damage_vector(table: DamageTable, dtype: DamageType) -> list[float]:
    """A damage type's effectiveness profile across every defensive class — the
    armour columns followed by the frame columns."""
    return ([table.armour_multiplier(dtype, a) for a in Armour]
            + [table.frame_multiplier(dtype, f) for f in Frame])


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 1.0
    return dot / (na * nb)


def damage_types_greatly_differ(table: DamageTable, a: DamageType, b: DamageType) -> bool:
    """True when two damage types specialise against opposite defences (e.g.
    LAZER↑heavy/metallic vs LEAD↑light) — measured as a low cosine between their
    effectiveness profiles."""
    if a == b:
        return False
    return _cosine(_damage_vector(table, a), _damage_vector(table, b)) < GREATLY_DIFFER_COS


def weapon_difference(table: DamageTable, wa: Weapon, wb: Weapon) -> float:
    """How different two weapons are: target coverage + reach bucket + damage
    type (with a bonus when the types specialise against opposite defences)."""
    score = 0.0

    # what they can shoot at
    if wa.hits.isdisjoint(wb.hits):
        score += TARGET_DISJOINT
    elif wa.hits != wb.hits:
        score += TARGET_PARTIAL

    # reach bucket separation
    score += _bucket_distance(wa.reach, wb.reach, RANGE_BUCKETS)

    # damage type
    da, db = _weapon_damage_type(wa), _weapon_damage_type(wb)
    if da != db:
        score += DAMAGE_TYPE_DIFF
        if damage_types_greatly_differ(table, da, db):
            score += DAMAGE_GREATLY_DIFF

    return score


# --------------------------------------------------------------------------- #
# Unit-level
# --------------------------------------------------------------------------- #
def loadout_difference(table: DamageTable, ua: Buildable, ub: Buildable) -> float:
    """The minimum weapon overlap between two units: the difference of their most
    similar weapon pairing (0 when each fields an identical weapon). An unarmed
    unit vs an armed one is a flat ``UNARMED_VS_ARMED``."""
    if not ua.weapons and not ub.weapons:
        return 0.0
    if not ua.weapons or not ub.weapons:
        return UNARMED_VS_ARMED
    return min(weapon_difference(table, wa, wb)
               for wa in ua.weapons for wb in ub.weapons)


def defense_difference(ua: Buildable, ub: Buildable) -> float:
    """Frame mismatch + armour-class bucket separation."""
    score = 0.0
    if ua.frame is not None and ub.frame is not None and ua.frame != ub.frame:
        score += FRAME_DIFF
    order = list(Armour)
    if ua.armour is not None and ub.armour is not None:
        score += BUCKET_STEP * abs(order.index(ua.armour) - order.index(ub.armour))
    return score


def movement_difference(ua: Buildable, ub: Buildable) -> float:
    """Aerial-vs-ground split + speed bucket separation.

    TODO(tune): the +0.5 for *different kinds of aerial movement* (hover vs fly)
    isn't expressible yet — the exporter collapses Movement.Mode to air/ground.
    Surface the sub-mode to implement it."""
    score = 0.0
    a_air = ua.layer == Layer.AIR
    b_air = ub.layer == Layer.AIR
    if a_air != b_air:
        score += AERIAL_VS_GROUND
    score += _bucket_distance(ua.speed, ub.speed, SPEED_BUCKETS)
    return score


def expensiveness_difference(ua: Buildable, ub: Buildable) -> float:
    """Cost bucket separation (cheap / medium / expensive)."""
    return _bucket_distance(ua.cost.scalar(), ub.cost.scalar(), COST_BUCKETS)


def unit_distinctness(table: DamageTable, ua: Buildable, ub: Buildable) -> float:
    """Total distinctness between two units — the sum of the loadout, defense,
    movement, and cost differences. Symmetric; 0 means indistinguishable on
    these axes.

    TODO(tune): candidate extra axes if these prove too coarse — durability
    (eff_hp bucket), production role (builder/harvester), or vision range."""
    return (loadout_difference(table, ua, ub)
            + defense_difference(ua, ub)
            + movement_difference(ua, ub)
            + expensiveness_difference(ua, ub))


# --------------------------------------------------------------------------- #
# Set-level (asymmetric)
# --------------------------------------------------------------------------- #
def set_distinctness(table: DamageTable, list_a: list[Buildable], list_b: list[Buildable]) -> float:
    """For each unit in ``list_a``, find its closest analogue in ``list_b`` and
    sum those minimum distances. Asymmetric: how poorly ``B`` shadows ``A``."""
    if not list_b:
        return 0.0
    return sum(min(unit_distinctness(table, a, b) for b in list_b) for a in list_a)


@dataclass
class SimilarPair:
    unit_a: str          # uid
    unit_b: str          # uid
    distinctness: float


def most_similar_pair(table: DamageTable, list_a: list[Buildable],
                      list_b: list[Buildable]) -> SimilarPair | None:
    """The least-distinct (most similar) unit pairing across the two lists."""
    best: SimilarPair | None = None
    for a in list_a:
        for b in list_b:
            d = unit_distinctness(table, a, b)
            if best is None or d < best.distinctness:
                best = SimilarPair(a.uid, b.uid, d)
    return best
