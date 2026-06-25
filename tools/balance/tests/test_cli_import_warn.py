"""The import command must WARN (not fail) when the flat files describe a
unit/structure that has no scene in the Godot files."""
import shutil

import yaml

from dh_balance.cli import main
from dh_balance.loader import DATA_DIR


def _copy(tmp_path, name):
    dst = tmp_path / name
    shutil.copytree(DATA_DIR, dst)
    return dst


def _run(current, desired, tmp_path, capsys):
    rc = main(["import", "--current", str(current), "--desired", str(desired),
               "--manifest", str(tmp_path / "no_such_manifest.json")])
    return rc, capsys.readouterr().out


def test_warns_on_flatfile_unit_with_no_godot_scene(tmp_path, capsys):
    current = _copy(tmp_path, "current")
    desired = _copy(tmp_path, "desired")
    fac = desired / "factions" / "iron_regime.yaml"
    raw = yaml.safe_load(fac.read_text())
    raw["buildables"].append(
        {"id": "phantom_walker", "kind": "unit", "name": "Phantom Walker",
         "hp": 500, "weapons": []})
    fac.write_text(yaml.safe_dump(raw))

    rc, out = _run(current, desired, tmp_path, capsys)

    assert rc == 0                                   # non-fatal
    assert "WARNING" in out
    assert "phantom_walker" in out
    assert "not found in the Godot files" in out
    assert "1 not in Godot" in out                   # surfaced in the summary line


def test_no_warning_when_every_unit_has_a_scene(tmp_path, capsys):
    current = _copy(tmp_path, "current")
    desired = _copy(tmp_path, "desired")               # identical copies
    rc, out = _run(current, desired, tmp_path, capsys)
    assert rc == 0
    assert "WARNING" not in out
    assert "0 not in Godot" in out
