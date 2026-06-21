"""The analytical queries the framework exists to answer.

Each returns plain dataclasses/dicts so callers (CLI, tests, notebooks) can
format them however they like.
"""
from __future__ import annotations

from dataclasses import dataclass

from . import combat, graph
from .model import Buildable, Faction, World


# --------------------------------------------------------------------------- #
# Q1: obsolete units (off the Pareto frontier)
# --------------------------------------------------------------------------- #
@dataclass
class Domination:
    unit: str            # uid of the obsolete unit
    dominated_by: str    # uid of a unit that dominates it


def _dominates(table, a: Buildable, b: Buildable) -> bool:
    """True if ``a`` Pareto-dominates ``b``: no costlier and no worse on any
    benefit axis, and strictly better somewhere (cost or a benefit)."""
    if a.cost.scalar() > b.cost.scalar():
        return False
    fa = combat.feature_vector(table, a)
    fb = combat.feature_vector(table, b)
    better_anywhere = a.cost.scalar() < b.cost.scalar()
    for k, vb in fb.items():
        va = fa[k]
        if va < vb:
            return False
        if va > vb:
            better_anywhere = True
    return better_anywhere


def obsolete_units(world: World, faction_id: str) -> list[Domination]:
    """Units in a faction made redundant: dominated by another unit in the
    same faction (no more expensive, no worse on any axis, better somewhere)."""
    faction = world.factions[faction_id]
    units = [u for u in faction.units() if u.is_combatant]
    out: list[Domination] = []
    for b in units:
        for a in units:
            if a.uid != b.uid and _dominates(world.damage, a, b):
                out.append(Domination(unit=b.uid, dominated_by=a.uid))
                break
    return out


# --------------------------------------------------------------------------- #
# Q2: threats faction A has that faction B can't economically answer
# --------------------------------------------------------------------------- #
@dataclass
class UnansweredThreat:
    threat: str                 # uid in faction A
    best_response: str | None   # cheapest response in B (None if nothing can hit it)
    best_exchange_cost: float   # INF if unhittable
    threat_cost: float
    reason: str                 # "no_weapon_can_hit" | "no_favorable_trade"


def unanswered_threats(
    world: World,
    attacker_id: str,
    defender_id: str,
    defender_pool: list[Buildable] | None = None,
) -> list[UnansweredThreat]:
    """For each combat unit of ``attacker_id``, find B's cheapest response and
    flag it if no response is *economically favorable* (exchange_cost < cost)."""
    table = world.damage
    threats = [u for u in world.factions[attacker_id].units() if u.is_combatant]
    responses = defender_pool if defender_pool is not None else \
        [u for u in world.factions[defender_id].units() if u.is_combatant]

    out: list[UnansweredThreat] = []
    for t in threats:
        best_r: Buildable | None = None
        best_xc = combat.INF
        for r in responses:
            xc = combat.exchange_cost(table, r, t)
            if xc < best_xc:
                best_xc, best_r = xc, r
        favorable = best_r is not None and best_xc < t.cost.scalar()
        if not favorable:
            reason = "no_weapon_can_hit" if best_xc == combat.INF else "no_favorable_trade"
            out.append(UnansweredThreat(
                threat=t.uid,
                best_response=best_r.uid if best_r else None,
                best_exchange_cost=best_xc,
                threat_cost=t.cost.scalar(),
                reason=reason,
            ))
    return out


# --------------------------------------------------------------------------- #
# Q3: tech-tier asymmetry
# --------------------------------------------------------------------------- #
@dataclass
class TierGapReport:
    low_faction: str
    low_tier: int
    high_faction: str
    high_tier: int
    struggles_against: list[UnansweredThreat]


def tech_tier_gap(
    world: World,
    low_faction_id: str,
    low_tier: int,
    high_faction_id: str,
    high_tier: int,
) -> TierGapReport:
    """If the low faction is capped at ``low_tier`` and the high faction can
    field up to ``high_tier``, what can the low faction not answer?"""
    high = world.factions[high_faction_id]
    low = world.factions[low_faction_id]
    high_pool = graph.units_up_to_tier(high, high_tier)
    low_pool = graph.units_up_to_tier(low, low_tier)

    # Reuse the unanswered-threats logic but with both pools tier-restricted.
    table = world.damage
    out: list[UnansweredThreat] = []
    for t in high_pool:
        best_r, best_xc = None, combat.INF
        for r in low_pool:
            xc = combat.exchange_cost(table, r, t)
            if xc < best_xc:
                best_xc, best_r = xc, r
        if not (best_r is not None and best_xc < t.cost.scalar()):
            reason = "no_weapon_can_hit" if best_xc == combat.INF else "no_favorable_trade"
            out.append(UnansweredThreat(
                threat=t.uid,
                best_response=best_r.uid if best_r else None,
                best_exchange_cost=best_xc,
                threat_cost=t.cost.scalar(),
                reason=reason,
            ))
    return TierGapReport(
        low_faction=low_faction_id, low_tier=low_tier,
        high_faction=high_faction_id, high_tier=high_tier,
        struggles_against=out,
    )
