"""Combat math: DPS, time-to-kill, and the costed-response exchange ratio.

SCOPE — this is a deliberately SURFACE-LEVEL model. v1 approximates a matchup as
a 1v1 DPS race to the death. That is a useful first cut for "is there an
economically favorable response?", but it is NOT a fight predictor. By design it
IGNORES the following, every one of which can flip an outcome:

  * Area-of-effect — A may lose to N of B one-at-a-time yet win against all N at
    once (or vice-versa). DPS here is strictly single-target.
  * Range & movement speed — an out-ranging unit can win from far and lose up
    close (kiting). `reach`/`speed` are carried in the model but NOT yet used in
    any formula.
  * Compounding interactions — buffs, support units, terrain, combined arms.
  * Micromanagement — focus fire, retreating damaged units, ability timing.

When any of these dominates a real matchup, encode the corrected value via the
per-matchup `overrides:` block (see graph.py) rather than complicating the math.
These factors are where a future analytic-Lanchester or in-engine simulator
earns its keep; until then, treat results as a coarse triage, not a verdict.

Every formula is the documented baseline the "computed + overrides" layer can
override per matchup. Keep this module pure (no I/O) so it is trivially testable
and reusable by a future army-vs-army simulator.
"""
from __future__ import annotations

import math

from .model import Buildable, DamageType, DamageTable, Layer, Weapon

INF = math.inf


def shot_components(weapon: Weapon) -> list[tuple[float, DamageType]]:
    """The (amount, damage_type) packets one shot delivers.

    A shot is its projectile's direct hit plus, for each damage-over-time effect
    the projectile carries, the effect's full lifetime damage. A melee weapon
    delivers a single packet. Bundling per-type lets a single shot mix damage
    types (e.g. a LAZER bolt plus a separate FIRE burn) through the right armour
    multipliers. NOTE: folding the full DoT total into one shot is a coarse
    approximation (ignores stacking/refresh) — see the module scope notes.
    """
    if weapon.projectile is not None:
        p = weapon.projectile
        comps: list[tuple[float, DamageType]] = [(p.base_damage, p.damage_type)]
        for se in p.status_effects:
            if se.kind == "damage_over_time" and se.total_damage() > 0:
                comps.append((se.total_damage(), se.damage_type or p.damage_type))
        return comps
    return [(weapon.melee_damage, weapon.melee_damage_type)]


def damage_per_shot(table: DamageTable, weapon: Weapon, target: Buildable) -> float:
    """Resolved damage of one shot against ``target`` (0 if it can't be hit)."""
    if target.layer is not None and not weapon.can_hit(target.layer):
        return 0.0
    total = 0.0
    for amount, dtype in shot_components(weapon):
        armour_mult = table.armour_multiplier(dtype, target.armour) if target.armour else 1.0
        attr_mult = table.attribute_multiplier(dtype, target.attributes, target.layer)
        total += amount * armour_mult * attr_mult
    return total


def dps(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """Best sustained DPS ``attacker`` can put on ``target`` across its weapons."""
    best = 0.0
    for w in attacker.weapons:
        best = max(best, damage_per_shot(table, w, target) * w.shots_per_second())
    return best


def can_engage(attacker: Buildable, target: Buildable) -> bool:
    """True if any weapon can reach the target's layer at all."""
    if target.layer is None:
        return bool(attacker.weapons)
    return any(w.can_hit(target.layer) for w in attacker.weapons)


def time_to_kill(table: DamageTable, attacker: Buildable, target: Buildable) -> float:
    """Seconds for ``attacker`` to destroy ``target`` (INF if it cannot)."""
    d = dps(table, attacker, target)
    if d <= 0:
        return INF
    return target.effective_hp / d


def exchange_cost(table: DamageTable, response: Buildable, threat: Buildable) -> float:
    """Resources of ``response`` consumed to destroy one ``threat`` in a duel.

    ``exchange_cost = cost(R) * ttk(R->T) / ttk(T->R)``.

    Interpretation: in a duel, R needs ``ttk(R->T)`` seconds to kill T while
    losing itself at rate ``cost(R)/ttk(T->R)``. The product is the R-value
    spent per T destroyed. < cost(T) means an *economically favorable* trade;
    INF means R can't kill T (no answer). Lower is a better response.
    """
    ttk_rt = time_to_kill(table, response, threat)
    if ttk_rt == INF:
        return INF
    ttk_tr = time_to_kill(table, threat, response)
    if ttk_tr == INF:
        # R kills T and is never harmed -> a free answer.
        return 0.0
    return response.cost.scalar() * (ttk_rt / ttk_tr)


def is_favorable(table: DamageTable, response: Buildable, threat: Buildable) -> bool:
    """An 'economically favorable response' per Costed Response Analysis."""
    return exchange_cost(table, response, threat) < threat.cost.scalar()


def feature_vector(table: DamageTable, unit: Buildable) -> dict[str, float]:
    """Benefit axes for Pareto comparison (higher = better on every axis).

    Cost is handled separately (lower is better) by the Pareto routine. DPS is
    broken out per *armour class faced* so an anti-heavy unit isn't judged
    obsolete just because it underperforms against light targets.
    """
    from .model import Armour  # local import to avoid cycle at module load

    vec: dict[str, float] = {
        "eff_hp": unit.effective_hp,
        "reach": max((w.reach for w in unit.weapons), default=0.0),
        "hits_ground": 1.0 if any(w.can_hit(Layer.GROUND) for w in unit.weapons) else 0.0,
        "hits_air": 1.0 if any(w.can_hit(Layer.AIR) for w in unit.weapons) else 0.0,
    }
    # DPS vs a canonical dummy of each armour class (ground target).
    for armour in Armour:
        dummy = Buildable(
            faction="_dummy", id=f"_{armour.value}", kind="unit", name="dummy",
            cost=unit.cost, armour=armour, hp=100.0, layer=Layer.GROUND,
        )
        vec[f"dps_vs_{armour.value}"] = dps(table, unit, dummy)
    return vec
