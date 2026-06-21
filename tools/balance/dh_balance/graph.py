"""NetworkX graph construction: the tech DAG and the counter graph.

The graphs are where "computed + overrides" is reconciled and where future
extensions (tech-up timing, reachability) plug in. Queries consume these.
"""
from __future__ import annotations

import networkx as nx

from . import combat
from .model import Buildable, Faction, World


# --------------------------------------------------------------------------- #
# Tech DAG
# --------------------------------------------------------------------------- #
def tech_graph(faction: Faction) -> nx.DiGraph:
    """Directed acyclic graph of prerequisites: edge prereq -> dependent."""
    g = nx.DiGraph()
    for b in faction.buildables.values():
        g.add_node(b.id, buildable=b)
    for b in faction.buildables.values():
        for req in b.requires:
            if req in faction.buildables:
                g.add_edge(req, b.id)
    return g


def tech_tiers(faction: Faction) -> dict[str, int]:
    """Tier = longest prerequisite chain depth (roots = tier 1)."""
    g = tech_graph(faction)
    tiers: dict[str, int] = {}
    for node in nx.topological_sort(g):
        preds = list(g.predecessors(node))
        tiers[node] = 1 if not preds else 1 + max(tiers[p] for p in preds)
    return tiers


def units_up_to_tier(faction: Faction, max_tier: int) -> list[Buildable]:
    """Combatants reachable when the faction is capped at ``max_tier``."""
    tiers = tech_tiers(faction)
    return [b for b in faction.combatants() if tiers.get(b.id, 1) <= max_tier]


# --------------------------------------------------------------------------- #
# Counter graph
# --------------------------------------------------------------------------- #
def _override_map(world: World) -> dict[tuple[str, str], dict]:
    out: dict[tuple[str, str], dict] = {}
    for f in world.factions.values():
        for ov in f.overrides:
            out[(ov["attacker"], ov["target"])] = ov
    return out


def counter_graph(world: World) -> nx.DiGraph:
    """Directed graph over all units; edge R -> T carries the costed response.

    Edge attributes:
      exchange_cost : resources of R spent to kill one T (lower = better answer)
      favorable     : bool, exchange_cost < cost(T)
      can_engage    : bool, R can hit T's layer at all
      source        : "computed" | "override"
    """
    g = nx.DiGraph()
    units = world.all_units()
    for u in units:
        g.add_node(u.uid, buildable=u)

    overrides = _override_map(world)
    for r in units:
        for t in units:
            if r.uid == t.uid or not r.is_combatant:
                continue
            ov = overrides.get((r.uid, t.uid))
            if ov is not None and "exchange_cost" in ov:
                xc = float(ov["exchange_cost"])
                source = "override"
            else:
                xc = combat.exchange_cost(world.damage, r, t)
                source = "computed"
            g.add_edge(
                r.uid, t.uid,
                exchange_cost=xc,
                favorable=xc < t.cost.scalar(),
                can_engage=combat.can_engage(r, t),
                source=source,
            )
    return g
