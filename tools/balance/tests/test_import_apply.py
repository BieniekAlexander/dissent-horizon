"""Tests for the surgical .tscn text-edit write mechanism."""
from pathlib import Path

from dh_balance import importer
from dh_balance.importer import Change, Edit

SAMPLE = """[gd_scene load_steps=3 format=3]

[sub_resource type="SphereShape3D" id="Sphere_1"]
radius = 15.0

[node name="Unit" type="CharacterBody3D"]

[node name="Defense" parent="." index="9"]
hp_max = 12000.0
armour_type = 0

[node name="Movement" parent="." index="8"]
speed = 0.04

[node name="LazerWeapon" type="Node3D" parent="Loadout" index="0"]
split_time = 40
reload_time = 40

[node name="AttackRange" type="CollisionShape3D" parent="Loadout/LazerWeapon" index="0"]
shape = SubResource("Sphere_1")
"""


def _edit(locator, prop, value):
    ch = Change("x", "x", prop, None, None)
    return Edit(ch, "scene", "res://x.tscn", locator, prop, value)


def _apply(text, edit):
    lines = text.splitlines(keepends=True)
    ok, reason = importer._apply_scene_edit(lines, edit)
    return ok, reason, "".join(lines)


def test_edits_defense_hp_in_place():
    ok, _, out = _apply(SAMPLE, _edit(("node", "Defense"), "hp_max", "8000.0"))
    assert ok
    assert "hp_max = 8000.0\n" in out
    assert "armour_type = 0\n" in out          # neighbour untouched
    assert "speed = 0.04\n" in out             # other blocks untouched
    assert out.count("hp_max") == 1            # no duplication, newline preserved


def test_edits_weapon_property():
    ok, _, out = _apply(SAMPLE, _edit(("weapon", "LazerWeapon"), "split_time", "30"))
    assert ok and "split_time = 30\n" in out


def test_edits_reach_via_subresource():
    ok, _, out = _apply(SAMPLE, _edit(("reach", "LazerWeapon"), "radius", "10.0"))
    assert ok and "radius = 10.0\n" in out


def test_missing_property_is_appended_to_existing_block():
    # Category A: the Defense block exists but has no `regen` line — append it.
    ok, _, out = _apply(SAMPLE, _edit(("node", "Defense"), "regen", "5.0"))
    assert ok
    assert "regen = 5.0\n" in out
    assert out.count("regen") == 1             # appended once, not duplicated
    # appended inside the Defense block, before the blank line / next header
    block = out.split('[node name="Defense"')[1].split("\n\n")[0]
    assert "regen = 5.0" in block
    assert "speed = 0.04\n" in out             # neighbouring block untouched


def test_appends_into_root_node_block():
    # warlord_rocket.damage_type shape: root node exists, property line absent.
    text = '[node name="Projectile" type="CharacterBody3D"]\nbase_damage = 15.0\n'
    ok, _, out = _apply(text, _edit(("root",), "damage_type", "7"))
    assert ok and out == (
        '[node name="Projectile" type="CharacterBody3D"]\n'
        "base_damage = 15.0\n"
        "damage_type = 7\n"
    )


def test_missing_block_without_base_is_refused():
    # SAMPLE's root is a plain node (no `instance=`), so there's no base scene
    # to inherit Garrison from — synthesis must refuse, not invent a block.
    ok, reason, out = _apply(SAMPLE, _edit(("node", "Garrison"), "capacity", "4"))
    assert not ok and "not found" in reason
    assert "Garrison" not in out


# --- Category B: synthesise an override for an inherited node -------------- #
BASE = """[gd_scene format=3 uid="uid://base"]

[node name="Commandable" type="CharacterBody3D" unique_id=249815651]

[node name="Defense" type="Node" parent="." unique_id=637704181]
hp_max = 100.0
"""

DERIVED = """[gd_scene format=3 uid="uid://derived"]

[ext_resource type="PackedScene" uid="uid://base" path="res://base.tscn" id="1_b"]

[sub_resource type="SphereShape3D" id="Sphere_1"]
radius = 1.0

[node name="Unit" unique_id=111 instance=ExtResource("1_b")]

[node name="Movement" parent="." index="7"]
speed = 0.05
"""


def test_synthesises_inherited_override(tmp_path, monkeypatch):
    monkeypatch.setattr(importer, "PROJECT_ROOT", tmp_path)
    (tmp_path / "base.tscn").write_text(BASE)
    e = _edit(("node", "Defense"), "hp_max", "240.0")
    e.target = "res://derived.tscn"
    lines = DERIVED.splitlines(keepends=True)
    ok, reason = importer._apply_scene_edit(lines, e)
    out = "".join(lines)
    assert ok and reason == "" and e.created
    # carries the base node's unique_id + parent, omits index (Godot self-heals)
    assert '[node name="Defense" parent="." unique_id=637704181]\n' in out
    assert "hp_max = 240.0\n" in out
    assert "index=" not in out.split("Defense")[1].split("\n")[0]
    # inserted after the root block, before the first override — not in subresources
    assert out.index('name="Defense"') > out.index('name="Unit"')
    assert out.index('name="Defense"') < out.index('name="Movement"')
    assert out.index('name="Defense"') > out.index("SphereShape3D")


def test_synthesised_override_drops_uid_when_base_has_none(tmp_path, monkeypatch):
    # A node first defined in an intermediate scene without a unique_id (like
    # unit.tscn's Movement) must be synthesised without one too.
    monkeypatch.setattr(importer, "PROJECT_ROOT", tmp_path)
    base = BASE.replace(" unique_id=637704181", "").replace("Defense", "Garrison")
    (tmp_path / "base.tscn").write_text(base)
    e = _edit(("node", "Garrison"), "hp_max", "5.0")
    e.target = "res://derived.tscn"
    lines = DERIVED.splitlines(keepends=True)
    ok, _ = importer._apply_scene_edit(lines, e)
    assert ok and '[node name="Garrison" parent="."]\n' in "".join(lines)


def test_reach_radius_not_invented_on_shape():
    # reach edits stay conservative: never append `radius` to an arbitrary shape.
    no_radius = SAMPLE.replace("radius = 15.0\n", "")
    ok, reason, out = _apply(no_radius, _edit(("reach", "LazerWeapon"), "radius", "10.0"))
    assert not ok and "radius not present" in reason
    assert "radius = 10.0" not in out


def test_manifest_single_line_edit():
    text = '        {"id": "badger", "scene": "res://x.tscn", "cost": {"ore": 300}, "requires": []}\n'
    ch = Change("buildable", "prototype:badger", "ore", 300, 250)
    e = Edit(ch, "manifest", "manifest", None, "ore", "250")
    new, ok, _ = importer._apply_manifest_edit(text, e)
    assert ok and '"ore": 250' in new and '"id": "badger"' in new


def test_plan_routes_fields_correctly():
    from dh_balance.loader import load_world
    w = load_world()
    def ch(kind, cid, field, scene=None):
        return Change(kind, cid, field, 1, 2, scene)
    edits = importer.plan([
        ch("buildable", "iron_regime:heavy_tank", "hp", "res://t.tscn"),
        ch("buildable", "iron_regime:heavy_tank", "ore"),
        ch("buildable", "iron_regime:heavy_tank", "weapons"),
    ], w)
    assert edits[0].scope == "scene" and edits[0].prop == "hp_max"
    assert edits[1].scope == "manifest"
    assert edits[2].scope == "skip"


CSV_ARMOUR = (
    "damage_type,LIGHT,MEDIUM,HEAVY\n"
    "LEAD,1.0,0.5,0.1\n"
    "LAZER,0.25,0.75,1.5\n"
)
CSV_ATTR = (
    "damage_type,IS_GROUNDED,IS_FLYING,HAS_STEALTH\n"
    "TOXIN,,0.5,\n"
    "EXPLOSIVE,,0.5,\n"
)


def test_diff_detects_damage_table_change(tmp_path):
    import shutil
    import yaml
    from dh_balance.loader import DATA_DIR, load_world
    dst = tmp_path / "d"
    shutil.copytree(DATA_DIR, dst)
    dt = dst / "damage_table.yaml"
    raw = yaml.safe_load(dt.read_text())
    raw["vs_armour"]["LEAD"]["HEAVY"] = 0.2
    dt.write_text(yaml.safe_dump(raw))
    changes, _, _ = importer.diff_worlds(load_world(DATA_DIR), load_world(dst))
    hit = [c for c in changes if c.kind == "damage_vs_armour" and c.id == "LEAD" and c.field == "HEAVY"]
    assert len(hit) == 1 and hit[0].current == 0.1 and hit[0].desired == 0.2


def test_apply_csv_writes_targeted_cell(tmp_path):
    csv = tmp_path / "damage_vs_armour.csv"
    csv.write_text(CSV_ARMOUR)
    ch = Change("damage_vs_armour", "LEAD", "HEAVY", 0.1, 0.2)
    e = Edit(ch, "csv", "armour", None, "HEAVY", "0.2")
    importer._apply_csv_edits(csv, [e], dry_run=False)
    out = csv.read_text()
    assert e.applied
    assert "LEAD,1.0,0.5,0.2\n" in out               # only the targeted cell
    assert "LAZER,0.25,0.75,1.5\n" in out             # other row untouched


def test_frame_change_routes_to_scene_frame_type():
    from dh_balance.loader import load_world
    w = load_world()
    ch = Change("buildable", "iron_regime:heavy_tank", "frame",
                "BIOLOGICAL", "METALLIC", "res://t.tscn")
    e = importer.plan([ch], w)[0]
    assert e.scope == "scene" and e.locator == ("node", "Defense")
    assert e.prop == "frame_type" and e.value == "1"   # METALLIC -> 1


def test_appends_frame_type_into_existing_defense_block():
    # SAMPLE's Defense overrides hp_max/armour_type but not frame_type -> append.
    ok, _, out = _apply(SAMPLE, _edit(("node", "Defense"), "frame_type", "1"))
    assert ok and "frame_type = 1\n" in out
    assert out.count("frame_type") == 1
    assert "armour_type = 0\n" in out                  # neighbour untouched


def test_apply_csv_fills_blank_attribute_cell(tmp_path):
    csv = tmp_path / "damage_vs_attribute.csv"
    csv.write_text(CSV_ATTR)
    ch = Change("damage_vs_attribute", "TOXIN", "HAS_STEALTH", None, 0.25)
    e = Edit(ch, "csv", "attribute", None, "HAS_STEALTH", "0.25")
    importer._apply_csv_edits(csv, [e], dry_run=False)
    assert e.applied
    assert "TOXIN,,0.5,0.25\n" in csv.read_text()    # previously-blank cell filled


def test_end_to_end_apply_on_temp_copy(tmp_path, monkeypatch):
    # Apply through the real file path machinery against a throwaway copy.
    scene_dir = tmp_path / "scenes" / "entities" / "units"
    scene_dir.mkdir(parents=True)
    (scene_dir / "x.tscn").write_text(SAMPLE)
    monkeypatch.setattr(importer, "PROJECT_ROOT", tmp_path)
    e = _edit(("node", "Defense"), "hp_max", "8000.0")
    e.target = "res://scenes/entities/units/x.tscn"
    importer.apply([e], tmp_path / "manifest.json", dry_run=False)
    assert e.applied
    assert "hp_max = 8000.0\n" in (scene_dir / "x.tscn").read_text()
