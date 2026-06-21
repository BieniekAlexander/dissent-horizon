"""Phase 3 — YAML -> Godot import planning.

The import direction is the reverse of the exporter: take edited YAML and push
the numbers back into the game. Unlike export (read-only), this *mutates game
files*, so the flow is split:

  1. diff_worlds(current, desired) — pure comparison of two loaded data dirs.
     "current" is a fresh `data_exported/` (what Godot has now); "desired" is
     your edited copy. This is safe and side-effect-free.
  2. plan(...) — annotate each change with the scene/resource it lives in, so a
     dry-run shows *where* a write would land.
  3. (apply) — the actual file write. Intentionally NOT implemented here yet:
     the write mechanism (surgical .tscn text-edit vs a runtime stat-loader vs
     pack-and-save) is a decision with real, irreversible consequences for the
     game's scene files. See the module note at the bottom.

Workflow::

    godot --headless -s res://tools/balance_export/godot_export.gd   # -> data_exported/
    cp -r data_exported/ data_edited/ && $EDITOR data_edited/...      # tune numbers
    python -m dh_balance import --current data_exported --desired data_edited
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .model import Buildable, Projectile, StatusEffect, Weapon, World

# Repo root, so res:// paths resolve to real files. importer.py lives at
# <root>/tools/balance/dh_balance/importer.py.
PROJECT_ROOT = Path(__file__).resolve().parents[3]

# YAML enum name -> the integer Godot stores in the .tscn (mirrors the game enums).
_ARMOUR_INT = {"UNARMORED": 0, "LIGHT": 1, "MEDIUM": 2, "HEAVY": 3}
_DAMAGE_INT = {"LEAD": 1, "LAZER": 2, "TOXIN": 3, "FIRE": 4,
               "ELECTRICITY": 5, "SIEGE": 6, "EXPLOSIVE": 7}
_HIT_BIT = {"ground": 1 << 1, "air": 1 << 2}   # CollisionLayers.Mask.TARGETABLE_*


@dataclass
class Change:
    kind: str          # status_effect | projectile | weapon | buildable
    id: str            # entity id (faction:id for buildables)
    field: str
    current: object
    desired: object
    scene: str | None = None   # best-effort owning scene/resource path

    def __str__(self) -> str:
        where = f"  [{self.scene}]" if self.scene else ""
        return f"{self.kind} {self.id}.{self.field}: {self.current!r} -> {self.desired!r}{where}"


@dataclass
class Added:
    kind: str
    id: str


@dataclass
class Removed:
    kind: str
    id: str


# --------------------------------------------------------------------------- #
# Field extraction (what's comparable per entity type)
# --------------------------------------------------------------------------- #
def _effect_fields(s: StatusEffect) -> dict:
    return {"kind": s.kind, "damage_per_tick": s.damage_per_tick,
            "tick_rate": s.tick_rate, "duration_ticks": s.duration_ticks,
            "damage_type": _enum(s.damage_type)}


def _projectile_fields(p: Projectile) -> dict:
    return {"base_damage": p.base_damage, "damage_type": _enum(p.damage_type),
            "speed": p.speed,
            "status_effects": [e.id for e in p.status_effects]}


def _weapon_fields(w: Weapon) -> dict:
    return {"split_time": w.split_time, "reload_time": w.reload_time,
            "clip_size": w.clip_size, "reach": w.reach,
            "hits": sorted(h.value for h in w.hits),
            "melee_damage": w.melee_damage,
            "melee_damage_type": _enum(w.melee_damage_type),
            "projectile": w.projectile.id if w.projectile else None}


def _buildable_fields(b: Buildable) -> dict:
    return {"kind": b.kind, "name": b.name, "ore": b.cost.ore,
            "population": b.cost.population, "dominion": b.cost.dominion,
            "armour": _enum(b.armour), "hp": b.hp, "layer": _enum(b.layer),
            "speed": b.speed, "attributes": sorted(b.attributes),
            "requires": b.requires, "weapons": [w.id for w in b.weapons]}


def _enum(v) -> object:
    return v.value if v is not None and hasattr(v, "value") else v


# --------------------------------------------------------------------------- #
# Diff
# --------------------------------------------------------------------------- #
def _diff_catalog(kind, current: dict, desired: dict, fields, scene_of=None):
    changes, added, removed = [], [], []
    for cid in desired:
        if cid not in current:
            added.append(Added(kind, cid))
            continue
        cf, df = fields(current[cid]), fields(desired[cid])
        for k in df:
            if cf.get(k) != df[k]:
                changes.append(Change(kind, cid, k, cf.get(k), df[k],
                                      scene_of(cid) if scene_of else None))
    for cid in current:
        if cid not in desired:
            removed.append(Removed(kind, cid))
    return changes, added, removed


def diff_worlds(current: World, desired: World, scene_for: dict[str, str] | None = None):
    """Return (changes, added, removed) across status effects, projectiles,
    weapons, and buildables. ``scene_for`` maps an entity id to its owning
    scene path (best-effort annotation for the dry-run)."""
    scene_for = scene_for or {}
    proj_scene = lambda pid: f"res://scenes/projectiles/{pid}.tscn"

    changes, added, removed = [], [], []
    for kind, cur, des, fields, scn in [
        ("status_effect", current.status_effects, desired.status_effects, _effect_fields,
         lambda sid: scene_for.get(f"status_effect:{sid}")),
        ("projectile", current.projectiles, desired.projectiles, _projectile_fields, proj_scene),
        ("weapon", current.weapons, desired.weapons, _weapon_fields,
         lambda wid: scene_for.get(f"weapon:{wid}")),
    ]:
        c, a, r = _diff_catalog(kind, cur, des, fields, scn)
        changes += c; added += a; removed += r

    # buildables, per faction (keyed by faction:id)
    cur_b = {b.uid: b for b in current.all_units()}
    des_b = {b.uid: b for b in desired.all_units()}
    # include structures too
    for f in current.factions.values():
        cur_b.update({b.uid: b for b in f.buildables.values()})
    for f in desired.factions.values():
        des_b.update({b.uid: b for b in f.buildables.values()})
    c, a, r = _diff_catalog("buildable", cur_b, des_b, _buildable_fields,
                            lambda uid: scene_for.get(f"buildable:{uid}"))
    changes += c; added += a; removed += r

    changes += _diff_damage(current, desired)
    return changes, added, removed


def _diff_damage(current: World, desired: World) -> list[Change]:
    """Diff the damage table cell-by-cell. A change writes back to the source
    CSVs (resources/damage/*.csv), not a scene. An absent cell means the default
    multiplier (1.0 / blank); current==None vs a value is filling a blank."""
    out: list[Change] = []
    for attr, kind in [("vs_armour", "damage_vs_armour"),
                       ("vs_attribute", "damage_vs_attribute")]:
        cmap = getattr(current.damage, attr)
        dmap = getattr(desired.damage, attr)
        for dt in set(cmap) | set(dmap):
            crow, drow = cmap.get(dt, {}), dmap.get(dt, {})
            for col in set(crow) | set(drow):
                cv, dv = crow.get(col), drow.get(col)
                if cv != dv:
                    out.append(Change(kind, _enum(dt), _enum(col), cv, dv))
    return out


# --------------------------------------------------------------------------- #
# Scene-ownership map (from the export manifest + conventions)
# --------------------------------------------------------------------------- #
def scene_map_from_manifest(manifest_path: Path, world: World) -> dict[str, str]:
    """Best-effort id -> owning scene path, for annotating the dry-run.

    - buildable: the scene declared in the manifest.
    - weapon: the scene of the buildable that fields it (weapons are scene nodes).
    - status_effect: the projectile scene that carries it.
    """
    out: dict[str, str] = {}
    raw = json.loads(manifest_path.read_text())
    bid_to_scene: dict[str, str] = {}
    for fac in raw.get("factions", []):
        for b in fac.get("buildables", []):
            bid_to_scene[f"{fac['id']}:{b['id']}"] = b["scene"]
            out[f"buildable:{fac['id']}:{b['id']}"] = b["scene"]

    for f in world.factions.values():
        for b in f.buildables.values():
            scene = bid_to_scene.get(b.uid)
            if scene:
                for w in b.weapons:
                    out[f"weapon:{w.id}"] = scene
    for pid, p in world.projectiles.items():
        for e in p.status_effects:
            out[f"status_effect:{e.id}"] = f"res://scenes/projectiles/{pid}.tscn"
    return out


# --------------------------------------------------------------------------- #
# Planning: Change -> Edit (surgical .tscn text-edit mechanism)
# --------------------------------------------------------------------------- #
@dataclass
class Edit:
    change: Change
    scope: str                  # "scene" | "manifest" | "skip"
    target: str | None          # res:// scene path, or "manifest"
    locator: tuple | None       # how to find the block (see _apply_scene_edit)
    prop: str | None            # Godot property name
    value: str | None           # formatted Godot text value
    skip_reason: str | None = None
    applied: bool = False

    def describe(self) -> str:
        tag = f"({self.change.kind} {self.change.id}.{self.change.field})"
        if self.scope == "skip":
            return f"SKIP  {self.change.kind} {self.change.id}.{self.change.field}  ({self.skip_reason})"
        if self.scope == "manifest":
            return f"EDIT  manifest.json  {self.prop} = {self.value}   {tag}"
        if self.scope == "csv":
            shown = self.value if self.value != "" else "(blank)"
            return f"EDIT  damage CSV ({self.target})  {self.change.id}/{self.prop} = {shown}   {tag}"
        loc = self.locator[1] if self.locator and len(self.locator) > 1 else self.locator[0]
        return f"EDIT  {self.target}  [{loc}] {self.prop} = {self.value}   {tag}"


def _fmt_float(v) -> str:
    v = float(v)
    return f"{int(v)}.0" if v == int(v) else repr(v)


def _mask_from_hits(hits: list[str]) -> str:
    m = 0
    for h in hits:
        m |= _HIT_BIT.get(h, 0)
    return str(m)


# (kind, field) -> (godot_prop, value_fn, locator_kind). locator_kind is resolved
# against the entity in _plan_one. None godot_prop => skip (structural/manual).
_SCENE_DISPATCH = {
    ("buildable", "hp"): ("hp_max", _fmt_float, "Defense"),
    ("buildable", "armour"): ("armour_type", lambda v: str(_ARMOUR_INT[v]), "Defense"),
    ("buildable", "speed"): ("speed", _fmt_float, "Movement"),
    ("weapon", "split_time"): ("split_time", str, "weapon"),
    ("weapon", "reload_time"): ("reload_time", str, "weapon"),
    ("weapon", "clip_size"): ("clip_size", str, "weapon"),
    ("weapon", "melee_damage"): ("melee_damage", _fmt_float, "weapon"),
    ("weapon", "melee_damage_type"): ("melee_damage_type", lambda v: str(_DAMAGE_INT[v]), "weapon"),
    ("weapon", "hits"): ("target_mask", _mask_from_hits, "weapon"),
    ("weapon", "reach"): ("radius", _fmt_float, "reach"),
    ("projectile", "base_damage"): ("base_damage", _fmt_float, "root"),
    ("projectile", "damage_type"): ("damage_type", lambda v: str(_DAMAGE_INT[v]), "root"),
    ("projectile", "speed"): ("speed", _fmt_float, "root"),
    ("status_effect", "damage_per_tick"): ("damage_per_tick", _fmt_float, "dot"),
    ("status_effect", "tick_rate"): ("tick_rate", str, "dot"),
    ("status_effect", "duration_ticks"): ("duration_ticks", str, "dot"),
    ("status_effect", "damage_type"): ("damage_type", lambda v: str(_DAMAGE_INT[v]), "dot"),
}
_MANIFEST_FIELDS = {"ore", "population", "dominion"}


def _plan_one(change: Change, world: World) -> Edit:
    key = (change.kind, change.field)
    if change.kind in ("damage_vs_armour", "damage_vs_attribute"):
        csv_key = "armour" if change.kind == "damage_vs_armour" else "attribute"
        value = "" if change.desired is None else _fmt_float(change.desired)
        return Edit(change, "csv", csv_key, None, change.field, value)
    if change.kind == "buildable" and change.field in _MANIFEST_FIELDS:
        return Edit(change, "manifest", "manifest", None, change.field, str(change.desired))
    spec = _SCENE_DISPATCH.get(key)
    if spec is None:
        return Edit(change, "skip", None, None, None, None,
                    skip_reason="structural/manual field — edit in the Godot editor")
    prop, value_fn, locator_kind = spec
    if not change.scene:
        return Edit(change, "skip", None, None, None, None, skip_reason="owning scene unknown")
    # Resolve the block locator, fetching a weapon's node name where needed.
    locator: tuple
    if locator_kind in ("weapon", "reach"):
        w = world.weapons.get(change.id)
        if w is None:
            return Edit(change, "skip", None, None, None, None, skip_reason="weapon not found")
        locator = (locator_kind, w.name)
    elif locator_kind in ("root", "dot"):
        locator = (locator_kind,)
    else:
        locator = ("node", locator_kind)   # Defense / Movement
    return Edit(change, "scene", change.scene, locator, prop, value_fn(change.desired))


def plan(changes: list[Change], world: World) -> list[Edit]:
    return [_plan_one(c, world) for c in changes]


# --------------------------------------------------------------------------- #
# Surgical .tscn text editing
# --------------------------------------------------------------------------- #
def _res_to_fs(res_path: str) -> Path:
    return PROJECT_ROOT / res_path.removeprefix("res://")


def _find_block(lines: list[str], predicate) -> int:
    for i, line in enumerate(lines):
        if line.startswith("[") and predicate(line):
            return i
    return -1


def _set_prop_in_block(lines: list[str], start: int, prop: str, value: str) -> bool:
    """Replace the RHS of ``prop = ...`` within the block beginning at ``start``
    (up to the next ``[...]`` header). Returns False if the property isn't
    present — we never *create* an override (that risks corrupting inheritance)."""
    pat = re.compile(rf"^(\s*{re.escape(prop)}\s*=\s*).*$")
    i = start + 1
    while i < len(lines) and not lines[i].startswith("["):
        m = pat.match(lines[i])
        if m:
            eol = lines[i][len(lines[i].rstrip("\r\n")):]   # preserve the line ending
            lines[i] = m.group(1) + value + eol
            return True
        i += 1
    return False


def _node_predicate(name: str, parent_substr: str | None = None):
    def pred(line: str) -> bool:
        if not line.startswith("[node ") or f'name="{name}"' not in line:
            return False
        return parent_substr is None or parent_substr in line
    return pred


def _apply_scene_edit(lines: list[str], edit: Edit) -> tuple[bool, str]:
    kind = edit.locator[0]
    if kind == "node":
        idx = _find_block(lines, _node_predicate(edit.locator[1]))
    elif kind == "weapon":
        idx = _find_block(lines, _node_predicate(edit.locator[1], parent_substr='parent="Loadout"'))
    elif kind == "dot":
        idx = _find_block(lines, _node_predicate("DamageOverTimeStatusEffect"))
    elif kind == "root":
        idx = _find_block(lines, lambda l: l.startswith("[node "))
    elif kind == "reach":
        return _apply_reach(lines, edit)
    else:
        return False, f"unknown locator {kind}"
    if idx < 0:
        return False, f"block for {edit.locator} not found"
    if _set_prop_in_block(lines, idx, edit.prop, edit.value):
        return True, ""
    return False, f"property '{edit.prop}' not overridden in this scene (skipped, not created)"


def _apply_reach(lines: list[str], edit: Edit) -> tuple[bool, str]:
    """reach -> the weapon's AttackRange child CollisionShape3D -> its SubResource
    shape's radius."""
    weapon_name = edit.locator[1]
    ar = _find_block(lines, _node_predicate("AttackRange", parent_substr=f"/{weapon_name}"))
    if ar < 0:
        return False, "AttackRange node not found"
    sub_id = None
    i = ar + 1
    while i < len(lines) and not lines[i].startswith("["):
        m = re.match(r'\s*shape\s*=\s*SubResource\("([^"]+)"\)', lines[i])
        if m:
            sub_id = m.group(1)
            break
        i += 1
    if sub_id is None:
        return False, "AttackRange shape is not a local SubResource"
    sub = _find_block(lines, lambda l: l.startswith("[sub_resource ") and f'id="{sub_id}"' in l)
    if sub < 0:
        return False, f"sub_resource {sub_id} not found"
    if _set_prop_in_block(lines, sub, "radius", edit.value):
        return True, ""
    return False, "radius not present on the shape"


def _apply_csv_edits(fs: Path, edits: list[Edit], dry_run: bool) -> None:
    """Set cells in a damage CSV. ``edit.change.id`` is the row (damage type),
    ``edit.prop`` the column header; a blank ``value`` clears the cell back to
    the default multiplier."""
    lines = fs.read_text().splitlines()
    if not lines:
        for e in edits:
            e.skip_reason = "empty CSV"
        return
    header = [h.strip() for h in lines[0].split(",")]
    col_of = {name: i for i, name in enumerate(header)}
    row_of = {lines[i].split(",")[0].strip(): i
              for i in range(1, len(lines)) if lines[i].strip()}
    changed = False
    for e in edits:
        ci, ri = col_of.get(e.prop), row_of.get(e.change.id)
        if ci is None or ri is None:
            e.skip_reason = f"cell {e.change.id}/{e.prop} not in CSV"
            continue
        cells = lines[ri].split(",")
        while len(cells) <= ci:
            cells.append("")
        cells[ci] = e.value
        lines[ri] = ",".join(cells)
        e.applied = True
        changed = True
    if changed and not dry_run:
        fs.write_text("\n".join(lines) + "\n")


def _apply_manifest_edit(text: str, edit: Edit) -> tuple[str, bool, str]:
    """Each buildable is one JSON line; replace ``"<resource>": N`` on the line
    carrying ``"id": "<bid>"``. Preserves the manifest's formatting."""
    bid = edit.change.id.split(":", 1)[-1]
    out_lines = []
    done = False
    for line in text.splitlines(keepends=True):
        if f'"id": "{bid}"' in line:
            new_line, n = re.subn(rf'("{edit.prop}"\s*:\s*)\d+', rf'\g<1>{edit.value}', line)
            if n:
                line, done = new_line, True
        out_lines.append(line)
    if not done:
        return text, False, f'could not find "{edit.prop}" for "{bid}" in manifest'
    return "".join(out_lines), True, ""


def apply(edits: list[Edit], manifest_path: Path, dry_run: bool = True) -> list[Edit]:
    """Apply (or, when dry_run, just resolve) the edits. Mutates each Edit's
    ``applied``/``skip_reason`` in place and returns the list. Scene files and
    the manifest are written only when ``dry_run`` is False."""
    by_scene: dict[str, list[Edit]] = {}
    by_csv: dict[str, list[Edit]] = {}
    manifest_edits: list[Edit] = []
    for e in edits:
        if e.scope == "scene":
            by_scene.setdefault(e.target, []).append(e)
        elif e.scope == "csv":
            by_csv.setdefault(e.target, []).append(e)
        elif e.scope == "manifest":
            manifest_edits.append(e)

    for res_path, scene_edits in by_scene.items():
        fs = _res_to_fs(res_path)
        if not fs.exists():
            for e in scene_edits:
                e.skip_reason = f"file not found: {fs}"
            continue
        lines = fs.read_text().splitlines(keepends=True)
        changed = False
        for e in scene_edits:
            ok, reason = _apply_scene_edit(lines, e)
            e.applied = ok
            if not ok:
                e.skip_reason = reason
            else:
                changed = True
        if changed and not dry_run:
            fs.write_text("".join(lines))

    if by_csv:
        damage_csv = json.loads(manifest_path.read_text()).get("damage_csv", {})
        for csv_key, csv_edits in by_csv.items():
            res = damage_csv.get(csv_key)
            if not res:
                for e in csv_edits:
                    e.skip_reason = f"manifest damage_csv has no '{csv_key}' path"
                continue
            fs = _res_to_fs(res)
            if not fs.exists():
                for e in csv_edits:
                    e.skip_reason = f"CSV not found: {fs}"
                continue
            _apply_csv_edits(fs, csv_edits, dry_run)

    if manifest_edits:
        text = manifest_path.read_text()
        changed = False
        for e in manifest_edits:
            text, ok, reason = _apply_manifest_edit(text, e)
            e.applied = ok
            if not ok:
                e.skip_reason = reason
            else:
                changed = True
        if changed and not dry_run:
            manifest_path.write_text(text)

    return edits
