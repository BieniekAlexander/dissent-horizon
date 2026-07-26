"""Shared test fixtures.

Tests load a small SYNTHETIC world (``tests/fixtures/``), never the real
``data/`` catalogs. ``data/`` is a generated artifact — ``gdd_to_balance.py``
rewrites it wholesale from the gdd docs — so pointing tests at it made them
depend on whatever the design docs happened to say, and an export would delete
the faction files out from under them.

The fixture world is hand-authored to exercise specific balance properties
(iron_regime = ground-only LEAD/HEAVY roster, sky_nomads = air + shared
projectile), so assertions stay meaningful regardless of game balance changes.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from dh_balance.loader import load_world
from dh_balance.model import World

FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def fixture_dir() -> Path:
    """Path to the fixture catalogs, for tests that copy or re-load them."""
    return FIXTURE_DIR


@pytest.fixture
def world() -> World:
    """The synthetic fixture world."""
    return load_world(FIXTURE_DIR)
