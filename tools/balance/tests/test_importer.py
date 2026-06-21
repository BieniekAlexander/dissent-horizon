"""Tests for the Phase-3 import diff (dry-run core)."""
import shutil
from pathlib import Path

import yaml

from dh_balance.importer import diff_worlds
from dh_balance.loader import DATA_DIR, load_world


def _copy_data(tmp_path: Path) -> Path:
    dst = tmp_path / "desired"
    shutil.copytree(DATA_DIR, dst)
    return dst


def test_no_changes_when_identical(tmp_path):
    desired = _copy_data(tmp_path)
    changes, added, removed = diff_worlds(load_world(DATA_DIR), load_world(desired))
    assert changes == [] and added == [] and removed == []


def test_detects_hp_change(tmp_path):
    desired = _copy_data(tmp_path)
    f = desired / "factions" / "iron_regime.yaml"
    raw = yaml.safe_load(f.read_text())
    for b in raw["buildables"]:
        if b["id"] == "heavy_tank":
            b["hp"] = 999
    f.write_text(yaml.safe_dump(raw))
    changes, _, _ = diff_worlds(load_world(DATA_DIR), load_world(desired))
    hp = [c for c in changes if c.id == "iron_regime:heavy_tank" and c.field == "hp"]
    assert len(hp) == 1
    assert hp[0].current == 800.0 and hp[0].desired == 999.0


def test_detects_projectile_and_added(tmp_path):
    desired = _copy_data(tmp_path)
    proj = desired / "projectiles.yaml"
    raw = yaml.safe_load(proj.read_text())
    raw["projectiles"]["shell_explosive_50"]["base_damage"] = 70
    raw["projectiles"]["brand_new_round"] = {"base_damage": 5, "damage_type": "LEAD"}
    proj.write_text(yaml.safe_dump(raw))
    changes, added, _ = diff_worlds(load_world(DATA_DIR), load_world(desired))
    dmg = [c for c in changes if c.id == "shell_explosive_50" and c.field == "base_damage"]
    assert dmg and dmg[0].desired == 70.0
    assert any(a.id == "brand_new_round" for a in added)
