"""Tests for the normalized catalog / by-id reference model."""
import textwrap
from pathlib import Path

import pytest

from dh_balance import combat
from dh_balance.loader import (
    load_status_effects,
    load_weapons,
)
from dh_balance.model import DamageType


def test_shared_projectile_is_the_same_object_across_files(world):
    w = world
    rifle = w.weapons["rifle"]            # iron_regime:conscript
    carbine = w.weapons["carbine"]        # sky_nomads:raider
    # Both reference lead_round_8 -> the resolver hands back one shared object.
    assert rifle.projectile is carbine.projectile
    assert rifle.projectile is w.projectiles["lead_round_8"]


def test_resolved_graph_reaches_status_effect(world):
    w = world
    beam = w.weapons["beam"]
    assert beam.projectile.status_effects[0] is w.status_effects["burn_dot_20"]


def test_melee_weapon_has_no_projectile(world):
    w = world
    blade = w.weapons["toxin_blade"]
    assert blade.projectile is None
    comps = combat.shot_components(blade)
    assert comps == [(12.0, DamageType.TOXIC)]


def test_dot_damage_is_folded_into_the_shot(world):
    w = world
    beam = w.weapons["beam"]
    # direct 20 LAZER + DoT total (5 * 12 = 60) LAZER = 80 raw before multipliers
    raw = sum(amount for amount, _ in combat.shot_components(beam))
    assert raw == pytest.approx(80.0)


def test_dangling_reference_is_an_error(tmp_path: Path):
    (tmp_path / "weapons.yaml").write_text(textwrap.dedent("""
        weapons:
          ghost_gun:
            name: Ghost
            projectile: does_not_exist
            split_time: 10
            hits: [ground]
    """))
    with pytest.raises(KeyError, match="does_not_exist"):
        load_weapons(tmp_path / "weapons.yaml", projectiles={})


def test_duplicate_id_is_an_error(tmp_path: Path):
    (tmp_path / "status_effects.yaml").write_text(textwrap.dedent("""
        status_effects:
          dup: {kind: damage_over_time, damage_per_tick: 1, duration_ticks: 1}
          dup: {kind: damage_over_time, damage_per_tick: 2, duration_ticks: 2}
    """))
    with pytest.raises(ValueError, match="duplicate key"):
        load_status_effects(tmp_path / "status_effects.yaml")
