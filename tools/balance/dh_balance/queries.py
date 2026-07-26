"""The analytical queries the framework exists to answer.

Each returns plain dataclasses/dicts so callers (CLI, tests, notebooks) can
format them however they like.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

from . import combat, distinctness, effectiveness, graph
from .model import Buildable, Faction, World


def _reachable_faction(faction: Faction, reachable_only: bool) -> Faction:
    """A copy of ``faction`` limited to buildables reachable from its starting
    state, or ``faction`` unchanged when the filter is disabled."""
    if not reachable_only:
        return faction
    reachable = graph.reachable_from(faction)
    buildables = {k: v for k, v in faction.buildables.items() if k in reachable}
    return replace(faction, buildables=buildables)


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


def obsolete_units(world: World, faction_id: str, reachable_only: bool = True) -> list[Domination]:
    """Units in a faction made redundant: dominated by another unit in the
    same faction (no more expensive, no worse on any axis, better somewhere)."""
    faction = _reachable_faction(world.factions[faction_id], reachable_only)
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
    reachable_only: bool = True,
) -> list[UnansweredThreat]:
    """For each combat unit of ``attacker_id``, find B's cheapest response and
    flag it if no response is *economically favorable* (exchange_cost < cost)."""
    table = world.damage
    attacker = _reachable_faction(world.factions[attacker_id], reachable_only)
    threats = [u for u in attacker.units() if u.is_combatant]
    responses = defender_pool if defender_pool is not None else \
        [u for u in _reachable_faction(world.factions[defender_id], reachable_only).units() if u.is_combatant]

    out: list[UnansweredThreat] = []
    for t in threats:
        best_r: Buildable | None = None
        best_xc = combat.INF
        for r in responses:
            xc = effectiveness.effective_exchange_cost(table, r, t)
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
    reachable_only: bool = True,
) -> TierGapReport:
    """If the low faction is capped at ``low_tier`` and the high faction can
    field up to ``high_tier``, what can the low faction not answer?"""
    high = world.factions[high_faction_id]
    low = world.factions[low_faction_id]
    high_pool = graph.units_up_to_tier(high, high_tier, reachable_only=reachable_only)
    low_pool = graph.units_up_to_tier(low, low_tier, reachable_only=reachable_only)

    # Reuse the unanswered-threats logic but with both pools tier-restricted.
    table = world.damage
    out: list[UnansweredThreat] = []
    for t in high_pool:
        best_r, best_xc = None, combat.INF
        for r in low_pool:
            xc = effectiveness.effective_exchange_cost(table, r, t)
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


# --------------------------------------------------------------------------- #
# Q4: faction roster distinctness
# --------------------------------------------------------------------------- #
def _units_in_tiers(
    world: World, faction_id: str, tiers: set[int] | None, reachable_only: bool = True,
) -> list[Buildable]:
    """A faction's units, optionally restricted to the given tech tiers."""
    faction = _reachable_faction(world.factions[faction_id], reachable_only)
    units = faction.units()
    if tiers is None:
        return units
    tier_of = graph.tech_tiers(faction)
    return [u for u in units if tier_of.get(u.id, 1) in tiers]


@dataclass
class FactionDistinctness:
    faction_a: str
    faction_b: str
    a_to_b: float                              # how poorly B shadows A
    b_to_a: float                              # how poorly A shadows B (asymmetric)
    most_similar: distinctness.SimilarPair | None


def faction_distinctness(
    world: World, faction_a: str, faction_b: str, tiers: set[int] | None = None,
    reachable_only: bool = True,
) -> FactionDistinctness:
    """How distinct two factions' rosters are (optionally within ``tiers``), in
    both directions, plus their single most-similar unit pairing."""
    table = world.damage
    ua = _units_in_tiers(world, faction_a, tiers, reachable_only)
    ub = _units_in_tiers(world, faction_b, tiers, reachable_only)
    return FactionDistinctness(
        faction_a=faction_a,
        faction_b=faction_b,
        a_to_b=distinctness.set_distinctness(table, ua, ub),
        b_to_a=distinctness.set_distinctness(table, ub, ua),
        most_similar=distinctness.most_similar_pair(table, ua, ub),
    )


def distinctness_matrix(
    world: World, tiers: set[int] | None = None, reachable_only: bool = True,
) -> dict[tuple[str, str], float]:
    """``set_distinctness`` for every ordered faction pair (asymmetric)."""
    table = world.damage
    fids = list(world.factions)
    pools = {fid: _units_in_tiers(world, fid, tiers, reachable_only) for fid in fids}
    out: dict[tuple[str, str], float] = {}
    for a in fids:
        for b in fids:
            if a != b:
                out[(a, b)] = distinctness.set_distinctness(table, pools[a], pools[b])
    return out
