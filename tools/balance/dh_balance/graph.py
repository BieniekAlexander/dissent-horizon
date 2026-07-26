"""NetworkX graph construction: the tech DAG and the counter graph.

The graphs are where "computed + overrides" is reconciled and where future
extensions (tech-up timing, reachability) plug in. Queries consume these.
"""
from __future__ import annotations

from dataclasses import replace

import networkx as nx

from . import combat, effectiveness
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


def reachable_from(faction: Faction) -> set[str]:
    """Ids of everything the faction can actually field, from its starting state.

    Two ways a buildable becomes available, explored together to a fixpoint:

    * ``requires`` edges — owning a prereq unlocks its dependents (this also
      covers training, since a structure's ``trains`` list is inverted into the
      trained unit's ``requires`` by the exporter).
    * ``builds`` lists — a builder unit can construct those structures outright.
      They are DAG *sources*, not dependents of the builder: you do not tech
      through the builder to reach them. At least one starting unit is a
      builder, so this is what opens the tree up.

    The fixpoint matters because a structure reached this way may train a
    further builder, which unlocks structures of its own.
    """
    g = tech_graph(faction)
    reachable: set[str] = set()
    queue: list[str] = [b for b in faction.starts_with if b in faction.buildables]
    reachable.update(queue)

    while queue:
        node = queue.pop()
        buildable = faction.buildables[node]
        unlocked = list(g.successors(node)) + buildable.builds
        for nxt in unlocked:
            if nxt in faction.buildables and nxt not in reachable:
                reachable.add(nxt)
                queue.append(nxt)
    return reachable


def with_external_buildables(world: World, faction: Faction) -> Faction:
    """``faction`` plus out-of-faction pieces its builders can construct.

    Neutral structures (mines, deposits) are authored outside any faction's
    directory, so they land in another catalog — but a faction's own builders
    raise them, and they belong in that faction's tech graph.

    Only pieces a REACHABLE builder can raise are pulled in: an unreachable
    unit's ``builds`` list says nothing about what the faction can field, and
    honouring it would let a stray cross-faction reference drag in an unrelated
    roster. Reachability and the merged catalog grow together to a fixpoint,
    since a pulled-in structure may itself unlock more.
    """
    elsewhere = {bid: b
                 for other in world.factions.values() if other.id != faction.id
                 for bid, b in other.buildables.items()}
    merged = dict(faction.buildables)
    while True:
        reached = reachable_from(replace(faction, buildables=merged))
        new = {target: elsewhere[target]
               for bid in reached
               for target in merged[bid].builds
               if target in elsewhere and target not in merged}
        if not new:
            break
        merged.update(new)
    if merged.keys() == faction.buildables.keys():
        return faction
    return replace(faction, buildables=merged)


def units_up_to_tier(faction: Faction, max_tier: int, reachable_only: bool = True) -> list[Buildable]:
    """Combatants reachable when the faction is capped at ``max_tier``."""
    buildables = faction.buildables
    if reachable_only:
        reachable = reachable_from(faction)
        buildables = {k: v for k, v in buildables.items() if k in reachable}
    faction = replace(faction, buildables=buildables) if reachable_only else faction
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
                xc = effectiveness.effective_exchange_cost(world.damage, r, t)
                source = "computed"
            g.add_edge(
                r.uid, t.uid,
                exchange_cost=xc,
                favorable=xc < t.cost.scalar(),
                can_engage=combat.can_engage(r, t),
                source=source,
            )
    return g
