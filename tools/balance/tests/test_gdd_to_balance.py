"""gdd_to_balance's doc classification and reach resolution, against synthetic docs.

Every piece doc says ``kind: Entity``, so the converter derives a piece's role from
its keys; a regression there empties every faction file and the tech graph with it.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]


@pytest.fixture(scope="module")
def converter():
    """gdd_to_balance.py loaded by path — it is a script, not a package module."""
    path = REPO / "tools" / "balance" / "gdd_to_balance.py"
    spec = importlib.util.spec_from_file_location("gdd_to_balance", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize("doc, role", [
    ({"kind": "Entity", "footprint": [2, 2]}, "structure"),
    ({"kind": "Entity", "movement": {"speed": "SLOW"}}, "unit"),
    ({"kind": "Entity", "footprint": [2, 2], "movement": {"speed": "SLOW"}}, "structure"),
    ({"kind": "Entity", "phases": [], "movement": {}}, "projectile"),
    ({"kind": "Entity", "damage": 5}, "projectile"),
    ({"kind": "Entity", "hp": 10}, None),
])
def test_role_is_derived_from_keys(converter, doc, role):
    assert converter.role_of(doc) == role


def test_reach_accepts_a_number(converter):
    assert converter.reach_value(3) == 3.0


def test_reach_resolves_a_shape_bucket(converter, monkeypatch):
    monkeypatch.setattr(converter, "SHAPE_RADII", {"fake_range": 7.0})
    assert converter.reach_value("fake_range") == 7.0


def test_reach_refuses_an_unknown_bucket(converter, monkeypatch):
    monkeypatch.setattr(converter, "SHAPE_RADII", {})
    with pytest.raises(SystemExit):
        converter.reach_value("no_such_range")


@pytest.mark.parametrize("piece, airborne", [
    ({"aerial": {"mode": "HOVERING"}}, True),
    ({"aerial": {"mode": "FLYING"}}, True),
    ({"aerial": {"mode": "GROUNDED"}}, False),
    ({"movement": {"speed": "SLOW"}}, False),
])
def test_flight_is_read_from_the_aerial_block(converter, piece, airborne):
    assert converter.is_airborne(piece) == airborne
