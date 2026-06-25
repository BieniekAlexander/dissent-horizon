"""Emergent matchup factors — the layer the base DPS race in ``combat.py`` omits.

``combat.py`` models a matchup as a 1v1 single-target DPS race and deliberately
ignores range, speed, dodging, overkill, and AoE (see its scope note). This
module adds those as **per-pair multiplicative factors**: each emergent
interaction is ONE small, pure, independently-tunable function

    factor_*(... , attacker, target) -> float

returning a multiplier on the *attacker's effective combat power vs that target*
(1.0 = no effect, >1 = attacker favoured, <1 = attacker hindered, 0 = can't
engage). ``combined_factor`` multiplies them together; ``effective_dps`` /
``effective_exchange_cost`` fold the result into the costed-response math the
queries consume.

These are admitted HEURISTICS — coarse stand-ins to be tuned as the real game
physics (rocket homing, charge-up times, unit sizes) settle. Every magic number
lives in a named module constant up top so tuning is a one-line edit. Keep the
module pure (no I/O) so each factor is trivially testable in isolation.
"""
from __future__ import annotations

from .model import Buildable, DamageTable, Weapon
from . import combat

_EPS = 1e-9

# --- tunable knobs (see each factor for how they're used) ------------------- #
# TODO(tune): every constant below is a placeholder magnitude chosen to nudge,
# not dominate. Recalibrate against real matchups once the game physics settle.
SPEED_EDGE = 0.25        # max ± swing a full speed advantage grants (kiting/chase)
RANGE_EDGE = 0.5         # max ± swing a full reach advantage grants (kiting)
DODGE_MAX = 0.5          # max fraction of effectiveness a target can dodge away
OVERKILL_FLOOR = 0.5     # min multiplier when a shot massively overkills the target
AOE_MAX_CLUSTER = 3.0    # most targets an AoE shot is credited with hitting at once
AOE_REF_COST = 150.0     # target cost treated as the "1 unit" cluster baseline
AOE_REF_RADIUS = 3.0     # blast radius (world units) at which the AoE bonus saturates


# --------------------------------------------------------------------------- #
# Small shared helpers
# --------------------------------------------------------------------------- #
def _best_weapon(table: DamageTable, attacker: Buildable, target: Buildable) -> Weapon | None:
    """The attacker weapon that lands the most damage on ``target`` (the one the
    DPS race would pick), or None if the attacker is unarmed."""
    best: Weapon | None = None
    best_d = -1.0
    for w in attacker.weapons:
        d = combat.damage_per_shot(table, w, target)
        if d > best_d:
            best_d, best = d, w
    return best


def _max_reach(attacker: Buildable, target: Buildable) -> float:
    """Longest reach among the attacker's weapons that can strike ``target``."""
    layer = target.layer
    return max((w.reach for w in attacker.weapons if layer is None or w.can_hit(layer)),
               default=0.0)


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else hi if v > hi else v


# --------------------------------------------------------------------------- #
# The emergent factors (one function per interaction)
# --------------------------------------------------------------------------- #
def factor_can_hit(attacker: Buildable, target: Buildable) -> float:
    """0 if no attacker weapon can reach the target's layer at all, else 1.

    The hard gate (e.g. a ground-only unit vs an aircraft). Redundant with the
    DPS being 0 in ``combat`` but kept explicit so the breakdown shows *why* a
    matchup is hopeless."""
    if target.layer is None:
        return 1.0 if attacker.weapons else 0.0
    return 1.0 if any(w.can_hit(target.layer) for w in attacker.weapons) else 0.0


def factor_relative_speed(attacker: Buildable, target: Buildable) -> float:
    """Faster unit gets an edge (chase down / keep distance). Neutral (1.0) when
    either side is immobile — there's no kiting dynamic against/for a structure.
    Bounded to ``1 ± SPEED_EDGE``."""
    if attacker.speed <= 0 or target.speed <= 0:
        return 1.0
    rel = (attacker.speed - target.speed) / max(attacker.speed, target.speed, _EPS)
    return 1.0 + SPEED_EDGE * rel


def factor_relative_range(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """Out-ranging the enemy is an edge (hit before being hit). Compares the
    longest reach each side can bring to bear on the other, bounded to
    ``1 ± RANGE_EDGE``."""
    a = _max_reach(attacker, target)
    t = _max_reach(target, attacker)
    if a <= 0 and t <= 0:
        return 1.0
    rel = (a - t) / max(a, t, _EPS)
    return 1.0 + RANGE_EDGE * rel


def factor_dodge(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """A fast target dodges slow projectiles. Hitscan/melee can't be dodged
    (1.0). For a projectile weapon the loss scales with how fast the target
    moves relative to the projectile, capped at ``DODGE_MAX``.

    This is the hook for the physics the user wants to tune later (homing vs
    oncoming/outbound aircraft, charge-up times) — extend this one function."""
    if target.speed <= 0:
        return 1.0
    w = _best_weapon(table, attacker, target)
    if w is None or w.projectile is None or w.projectile.speed <= 0:
        return 1.0   # melee / hitscan / instant — nothing to dodge
    # TODO(tune): only models target-speed vs projectile-speed. Fold in homing
    # (oncoming vs outbound aircraft) and weapon charge-up / targeting time.
    severity = _clamp(target.speed / (w.projectile.speed + _EPS), 0.0, 1.0)
    return 1.0 - DODGE_MAX * severity


def factor_overkill(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """A shot that vastly exceeds the target's HP wastes the overshoot — poor
    value against many small targets. The multiplier is the useful fraction of
    one shot (``hp / damage_per_shot``), floored at ``OVERKILL_FLOOR``; 1.0 when
    a shot does not overkill."""
    w = _best_weapon(table, attacker, target)
    if w is None:
        return 1.0
    dmg = combat.damage_per_shot(table, w, target)
    if dmg <= 0 or target.effective_hp <= 0:
        return 1.0
    # TODO(tune): weight the penalty by fire rate / targeting time — a slow,
    # one-shot weapon wastes far more against a group than a fast one does.
    efficiency = min(1.0, target.effective_hp / dmg)
    return OVERKILL_FLOOR + (1.0 - OVERKILL_FLOOR) * efficiency


def factor_aoe(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """Splash damage is worth more than its single-target DPS suggests against
    cheap (numerous, clustered) targets. Bonus grows with blast radius (up to
    ``AOE_REF_RADIUS``) and target cheapness (cost vs ``AOE_REF_COST``), capped
    so an AoE shot is credited with at most ``AOE_MAX_CLUSTER`` targets.

    NOTE: true clustering depends on unit body size, which the model doesn't
    carry yet — target cost is used as a swarm-density proxy."""
    aoe = max((w.projectile.aoe_radius for w in attacker.weapons if w.projectile),
              default=0.0)
    if aoe <= 0:
        return 1.0
    # TODO(tune): replace the cost-as-swarm-density proxy with real unit body
    # size + footprint once the model carries it (cluster = how many fit in blast).
    cluster = _clamp(AOE_REF_COST / max(target.cost.scalar(), 1.0), 1.0, AOE_MAX_CLUSTER)
    radius_factor = _clamp(aoe / AOE_REF_RADIUS, 0.0, 1.0)
    return 1.0 + (cluster - 1.0) * radius_factor


# --------------------------------------------------------------------------- #
# Aggregation + factor-aware combat
# --------------------------------------------------------------------------- #
def matchup_factors(table: DamageTable, attacker: Buildable, target: Buildable) -> dict[str, float]:
    """Every emergent factor for ``attacker`` vs ``target``, keyed by name, for
    inspection/iteration (the CLI ``matchup`` breakdown)."""
    return {
        "can_hit": factor_can_hit(attacker, target),
        "speed": factor_relative_speed(attacker, target),
        "range": factor_relative_range(table, attacker, target),
        "dodge": factor_dodge(table, attacker, target),
        "overkill": factor_overkill(table, attacker, target),
        "aoe": factor_aoe(table, attacker, target),
    }


def combined_factor(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """Product of all emergent factors — the net multiplier on the attacker's
    effective combat power vs this target."""
    result = 1.0
    for v in matchup_factors(table, attacker, target).values():
        result *= v
    return result


def effective_dps(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """``combat.dps`` scaled by the emergent matchup factors."""
    return combat.dps(table, attacker, target) * combined_factor(table, attacker, target)


def effective_time_to_kill(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    d = effective_dps(table, attacker, target)
    return combat.INF if d <= 0 else target.effective_hp / d


def effective_exchange_cost(table: DamageTable, response: Buildable, threat: Buildable) -> float:
    """``combat.exchange_cost`` computed with factor-adjusted time-to-kill in
    both directions, so emergent edges (range, speed, dodge, overkill, AoE) move
    the costed-response verdict, not just the raw damage table."""
    ttk_rt = effective_time_to_kill(table, response, threat)
    if ttk_rt == combat.INF:
        return combat.INF
    ttk_tr = effective_time_to_kill(table, threat, response)
    if ttk_tr == combat.INF:
        return 0.0
    return response.cost.scalar() * (ttk_rt / ttk_tr)


def is_favorable(table: DamageTable, response: Buildable, threat: Buildable) -> bool:
    """Economically favorable response, factoring in the emergent interactions."""
    return effective_exchange_cost(table, response, threat) < threat.cost.scalar()
