"""The Python damage-type mirrors must match the engine's ``Damage.Type``.

There are two of them, for two different reasons, and both had drifted:

  * ``dh_balance.model.DamageType`` — matched BY NAME, because the catalogs are
    YAML keyed by name. A missing member is a hard ``ValueError`` out of
    ``load_projectiles`` the moment a doc uses it, which takes down every
    consumer including the mermaid tech-graph.
  * ``gdd_to_balance.DAMAGE_TYPES`` — matched BY ORDINAL, because a projectile
    scene stores ``damage_type`` as the enum's integer and the exporter indexes
    this list with it. A missing member silently drops rows from
    ``damage_table.yaml``; a member inserted in the wrong POSITION would be
    worse, relabelling every projectile after it.

Both are checked against the engine source itself, so adding a Damage.Type in
Godot fails here rather than at the next unlucky import.
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

import pytest

from dh_balance.model import DamageType

REPO = Path(__file__).resolve().parents[3]
DAMAGE_GD = REPO / "scripts" / "entities" / "tools" / "damage.gd"


def _engine_damage_types() -> list[str]:
    """``Damage.Type`` member names, in ordinal order, read from damage.gd.

    Deliberately a second, independent parse rather than an import of the
    exporter's own: a test that reuses the code under test cannot catch that
    code reading the enum wrongly.
    """
    body = re.search(r"enum Type \{(.*?)\n\}", DAMAGE_GD.read_text(), re.S)
    assert body is not None, f"no `enum Type` in {DAMAGE_GD}"
    members: dict[int, str] = {}
    for line in body.group(1).splitlines():
        line = line.split("#")[0].strip().rstrip(",")
        if not line:
            continue
        name, _, value = line.partition("=")
        members[int(value.strip())] = name.strip()
    return [members[i] for i in sorted(members)]


def _exporter():
    """gdd_to_balance.py loaded by path — it is a script, not a package module."""
    path = REPO / "tools" / "balance" / "gdd_to_balance.py"
    spec = importlib.util.spec_from_file_location("gdd_to_balance", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_engine_enum_is_readable() -> None:
    # Guards the two tests below from passing vacuously if damage.gd is moved
    # or its enum reshaped.
    engine = _engine_damage_types()
    assert len(engine) >= 8
    assert engine[0] == "UNDEFINED", "the enum's zero is UNDEFINED"


def test_model_damage_type_matches_the_engine_by_name() -> None:
    assert {d.value for d in DamageType} == set(_engine_damage_types())


def test_exporter_damage_types_match_the_engine_by_ordinal() -> None:
    # Order matters here and only here: this list is indexed by the integer a
    # projectile scene stores.
    assert _exporter().DAMAGE_TYPES == _engine_damage_types()


@pytest.mark.parametrize("name", ["CRYO", "INCENDIARY", "HIGH_EXPLOSIVE"])
def test_the_three_that_had_gone_missing(name: str) -> None:
    # The regression that motivated this file: the engine, the damage-table TSVs
    # and the Avalanche's doc all had these; neither Python mirror did.
    assert name in {d.value for d in DamageType}
    assert name in _exporter().DAMAGE_TYPES
