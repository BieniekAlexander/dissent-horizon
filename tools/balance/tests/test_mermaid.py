"""Mermaid tech-graph emission — the three devices that carry the three relations.

The emitter's whole job is deciding what NOT to draw as an arrow. A production
line is containment (the unit sits inside its producer's subgraph), a unit's tech
prerequisite is a shared colour class, and the only thing left for an arrow is a
structure -> structure prerequisite. These tests pin each of the three, plus the
one case where the relations overlap: a structure that both trains a unit and is
named in that unit's ``requires`` is a production line stated twice, not a tech
gate.

Built on purpose-made factions rather than the shared fixture world, because the
overlap cases only have teeth on a roster shaped to produce them.
"""
from __future__ import annotations

import re

import pytest

from dh_balance.cli import _mermaid
from dh_balance.model import Buildable, Cost, Faction


_ARROW = re.compile(r"\s-->\s")


def _b(bid: str, kind: str, requires: list[str], trains: list[str] | None = None) -> Buildable:
    return Buildable(faction="f", id=bid, kind=kind, name=bid, cost=Cost(ore=100),
                     requires=requires, trains=trains or [])


def _faction(*pieces: Buildable, starts_with: list[str]) -> Faction:
    return Faction(id="f", name="F", description="",
                   buildables={b.id: b for b in pieces}, starts_with=starts_with)


@pytest.fixture
def interleaved() -> Faction:
    """`hq` unlocks two structures and trains two units whose names interleave
    when sorted: annex, marauder, raider, zeppelin_dock."""
    return _faction(
        _b("hq", "structure", [], trains=["marauder", "raider"]),
        _b("annex", "structure", ["hq"]),
        _b("zeppelin_dock", "structure", ["hq"]),
        _b("marauder", "unit", []),
        _b("raider", "unit", []),
        starts_with=["hq"],
    )


@pytest.fixture
def authored_order() -> Faction:
    """`hq` trains four units in an order NO sort reproduces — reverse-alphabetical
    on the first three, then one that would sort first. A fixture whose list is
    already alphabetical (like `interleaved`) cannot tell the two behaviours
    apart, which is why this one exists separately."""
    return _faction(
        _b("hq", "structure", [], trains=["zeppelin", "raider", "marauder", "annexer"]),
        _b("zeppelin", "unit", []),
        _b("raider", "unit", []),
        _b("marauder", "unit", []),
        _b("annexer", "unit", []),
        starts_with=["hq"],
    )


def _edges(text: str) -> list[tuple[str, str]]:
    out = []
    for line in text.splitlines():
        if _ARROW.search(line) and not line.strip().startswith(("class", "style")):
            u, v = _ARROW.split(line.strip(), maxsplit=1)
            out.append((u.strip(), v.strip()))
    return out


def _subgraph_members(text: str) -> dict[str, list[str]]:
    """Cluster id -> the node ids declared inside it."""
    out: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("subgraph "):
            current = line.removeprefix("subgraph ").split("[")[0]
            out[current] = []
        elif line == "end":
            current = None
        elif current is not None:
            out[current].append(line.split("[")[0].split("(")[0])
    return out


def _classes(text: str) -> dict[str, str]:
    """Node id -> the class name assigned to it."""
    out: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("class "):
            members, name = line.removeprefix("class ").rsplit(" ", 1)
            for member in members.split(","):
                out[member] = name
    return out


# --------------------------------------------------------------------------- #
# Containment replaces the `trains` edge
# --------------------------------------------------------------------------- #
def test_trained_units_are_declared_inside_their_producer(interleaved):
    assert _subgraph_members(_mermaid(interleaved, reachable_only=False)) == {
        "hq": ["marauder", "raider"],
    }


def test_no_edge_ever_points_at_a_unit(interleaved):
    """Both relations that could reach a unit are drawn without an arrow, so an
    arrow means one thing: a structure -> structure prerequisite."""
    out = _mermaid(interleaved, reachable_only=False)
    units = {b.id for b in interleaved.buildables.values() if b.is_unit}
    assert [(u, v) for u, v in _edges(out) if v in units] == []


def test_structure_prerequisites_are_solid_arrows(interleaved):
    assert sorted(_edges(_mermaid(interleaved, reachable_only=False))) == [
        ("hq", "annex"), ("hq", "zeppelin_dock"),
    ]


def test_shapes_distinguish_units_from_structures(interleaved):
    out = _mermaid(interleaved, reachable_only=False)
    assert '    annex["annex"]' in out
    assert 'raider(["raider"])' in out


def test_producer_clusters_are_styled(interleaved):
    """Left unstyled, mermaid draws a cluster in its own pale yellow, which reads
    as a highlight rather than as a container on either Obsidian theme."""
    assert "    style hq fill:" in _mermaid(interleaved, reachable_only=False)


def test_chart_is_top_down_with_a_layout_directive(interleaved):
    """A producer's units stack in a column only because the PARENT flows TB —
    mermaid ignores a subgraph's own `direction` once it is linked to the outside,
    which every producer is. `rankSpacing` is then the gap between those units."""
    out = _mermaid(interleaved, reachable_only=False)
    assert "flowchart TB" in out
    assert out.startswith("%%{init:") and "rankSpacing" in out.splitlines()[0]


# --------------------------------------------------------------------------- #
# Colour replaces the `requires` edge into a unit
# --------------------------------------------------------------------------- #
@pytest.fixture
def gated() -> Faction:
    """`lab` gates a unit trained elsewhere; `dock` names ITSELF in the requires
    of a unit it trains, which is a production line stated twice."""
    return _faction(
        _b("hq", "structure", [], trains=["grunt", "veteran"]),
        _b("lab", "structure", ["hq"]),
        _b("dock", "structure", ["hq"], trains=["skiff"]),
        _b("grunt", "unit", []),
        _b("veteran", "unit", ["lab"]),
        _b("skiff", "unit", ["dock"]),
        starts_with=["hq"],
    )


def test_gate_and_the_units_it_gates_share_one_class(gated):
    classes = _classes(_mermaid(gated, reachable_only=False))
    assert classes["lab"] == classes["veteran"]
    assert "grunt" not in classes


def test_a_gate_class_is_defined_with_a_fill_and_white_text(gated):
    """A border alone is what the dark theme's own node border swallows; the
    fill plus white text is the treatment that survives both themes."""
    out = _mermaid(gated, reachable_only=False)
    name = _classes(out)["lab"]
    assert f"    classDef {name} fill:#" in out
    assert "color:#ffffff" in out


def test_a_producer_naming_itself_is_not_a_tech_gate(gated):
    """`dock` trains `skiff` AND appears in its requires. Containment already
    says that; colouring it would announce a tech step that does not exist."""
    classes = _classes(_mermaid(gated, reachable_only=False))
    assert "dock" not in classes
    assert "skiff" not in classes


def test_two_gates_get_different_classes():
    faction = _faction(
        _b("hq", "structure", [], trains=["a_unit", "b_unit"]),
        _b("lab_a", "structure", ["hq"]),
        _b("lab_b", "structure", ["hq"]),
        _b("a_unit", "unit", ["lab_a"]),
        _b("b_unit", "unit", ["lab_b"]),
        starts_with=["hq"],
    )
    classes = _classes(_mermaid(faction, reachable_only=False))
    assert classes["lab_a"] == classes["a_unit"]
    assert classes["lab_b"] == classes["b_unit"]
    assert classes["lab_a"] != classes["lab_b"]


def test_a_gate_that_also_trains_takes_a_border_not_a_fill():
    """A cluster is a REGION: filling it recolours the ground behind the units it
    holds, so the colour lands on its border instead. `class` reaches only a
    subgraph's label, which is why this goes through `style`."""
    faction = _faction(
        _b("hq", "structure", [], trains=["grunt"]),
        _b("lab", "structure", ["hq"], trains=["tech_unit"]),
        _b("grunt", "unit", ["lab"]),
        _b("tech_unit", "unit", []),
        starts_with=["hq"],
    )
    out = _mermaid(faction, reachable_only=False)
    assert _classes(out)["grunt"]
    assert "lab" not in _classes(out)
    assert "    style lab fill:none,stroke:#" in out


# --------------------------------------------------------------------------- #
# Shape checks over the real rosters
# --------------------------------------------------------------------------- #
def test_real_factions_emit_no_edge_into_a_unit(world):
    for faction in world.factions.values():
        out = _mermaid(faction, reachable_only=False)
        for _, v in _edges(out):
            assert not faction.buildables[v].is_unit, f"{faction.id}: edge into unit {v}"


def test_real_factions_put_every_trained_unit_in_exactly_one_cluster(world):
    """A node declared in two subgraphs is invalid mermaid, so the emitter has to
    pick one producer per unit."""
    for faction in world.factions.values():
        members = _subgraph_members(_mermaid(faction, reachable_only=False))
        seen = [uid for kids in members.values() for uid in kids]
        assert len(seen) == len(set(seen)), f"{faction.id}: unit in two clusters"


# --------------------------------------------------------------------------- #
# A producer lists its units in the order its doc authored them
# --------------------------------------------------------------------------- #
def test_units_follow_the_producers_trains_order(authored_order):
    """The `trains:` list is authored, and the command grid already reads it
    positionally — a train button takes its COLUMN from the unit's index in that
    list. Sorting it here would make the diagram disagree with the HUD about the
    shape of the roster."""
    assert _subgraph_members(_mermaid(authored_order, reachable_only=False)) == {
        "hq": ["zeppelin", "raider", "marauder", "annexer"],
    }


def test_that_order_is_not_merely_alphabetical(authored_order):
    """Guards the test above from passing by coincidence if the emitter goes back
    to sorting and someone reorders the fixture into alphabetical order."""
    members = _subgraph_members(_mermaid(authored_order, reachable_only=False))["hq"]
    assert members != sorted(members)


def test_reordering_the_doc_reorders_the_diagram(authored_order):
    """The property, stated directly: the list is the only thing deciding it."""
    before = _subgraph_members(_mermaid(authored_order, reachable_only=False))["hq"]
    authored_order.buildables["hq"].trains.reverse()
    after = _subgraph_members(_mermaid(authored_order, reachable_only=False))["hq"]
    assert after == list(reversed(before))


def test_a_unit_the_producer_lists_but_the_graph_drops_is_skipped(authored_order):
    """Order is taken from `trains:` but membership still is not: a listed unit
    outside the drawn node set leaves no gap and no phantom node."""
    del authored_order.buildables["marauder"]
    assert _subgraph_members(_mermaid(authored_order, reachable_only=False)) == {
        "hq": ["zeppelin", "raider", "annexer"],
    }


# --------------------------------------------------------------------------- #
# Declaration order is chosen to keep edges from crossing
# --------------------------------------------------------------------------- #
@pytest.fixture
def crossing_shape() -> Faction:
    """The shape that made the Colonials' chart cross: a rank whose members sort into
    the OPPOSITE order from their parents.

    `p_left` sorts before `p_right`, so it is laid out on the left. But `p_right`'s child
    `aaa` sorts before `p_left`'s child `zzz` — so declaring the lower rank by id puts
    the left parent's child on the right and vice versa, and the two edges cross.
    """
    return _faction(
        _b("root", "structure", []),
        _b("p_left", "structure", ["root"]),
        _b("p_right", "structure", ["root"]),
        _b("zzz", "structure", ["p_left"]),
        _b("aaa", "structure", ["p_right"]),
        starts_with=["root"],
    )


def _declared(text: str) -> list[str]:
    """Node ids in the order the emitter declares them, clusters included."""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("subgraph "):
            out.append(line.removeprefix("subgraph ").split("[")[0])
        elif _ARROW.search(line) or line.startswith(("class", "style", "flowchart", "%%", "end")):
            continue
        elif line:
            out.append(line.split("[")[0].split("(")[0])
    return out


def test_a_ranks_children_follow_their_parents_order(crossing_shape):
    """The fix, stated directly: `zzz` is declared before `aaa` because its PARENT is
    declared before `aaa`'s — the opposite of what sorting by id gives."""
    declared = _declared(_mermaid(crossing_shape, reachable_only=False))
    assert declared.index("p_left") < declared.index("p_right")
    assert declared.index("zzz") < declared.index("aaa")


def test_that_order_is_not_merely_alphabetical(crossing_shape):
    """Guards the test above from passing by coincidence if the emitter reverts to
    sorting: `aaa` < `zzz`, so an id-sorted emitter fails this."""
    declared = _declared(_mermaid(crossing_shape, reachable_only=False))
    lower_rank = [n for n in declared if n in ("aaa", "zzz")]
    assert lower_rank != sorted(lower_rank)


def test_parents_are_always_declared_before_their_children(interleaved, crossing_shape):
    """The invariant the sweep rests on: it reads each node's parents' positions, so a
    parent must already be placed. True for any DAG, since ranks are longest-path."""
    for faction in (interleaved, crossing_shape):
        declared = _declared(_mermaid(faction, reachable_only=False))
        for b in faction.buildables.values():
            for req in b.requires:
                if b.id in declared and req in declared:
                    assert declared.index(req) < declared.index(b.id), f"{req} before {b.id}"


def test_the_emitted_order_is_stable(crossing_shape):
    """Ties break by id, so a re-run is byte-identical — the baked block in a faction
    note only churns when the roster actually changes."""
    a = _mermaid(crossing_shape, reachable_only=False)
    b = _mermaid(crossing_shape, reachable_only=False)
    assert a == b


def test_the_top_rank_is_ordered_by_id(crossing_shape):
    """Every parent is in an earlier rank, so the "no parents" case is reached only at
    rank 0 — where nothing has an opinion, everything ties, and id order decides. That is
    what keeps the roots (and stray unconnected pieces like nt_extractor) in a stable,
    readable order instead of an arbitrary one."""
    crossing_shape.buildables["loner"] = _b("loner", "structure", [])
    declared = _declared(_mermaid(crossing_shape, reachable_only=False))
    roots = [n for n in declared if n in ("root", "loner")]
    assert roots == sorted(roots)
