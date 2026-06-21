"""Load the YAML catalogs into the resolved model.

Layout (relative to ``tools/balance/``)::

    data/damage_table.yaml
    data/status_effects.yaml     # catalog: id -> effect
    data/projectiles.yaml        # catalog: id -> projectile  (refs status_effects)
    data/weapons.yaml            # catalog: id -> weapon       (refs a projectile)
    data/factions/*.yaml         # buildables reference weapons by id

Load is two-pass: parse every catalog into ``id -> raw`` maps, then resolve
references bottom-up (status_effects -> projectiles -> weapons -> factions),
building the object graph. References are bare ids inside a typed field; a
dangling reference or duplicate id is a hard error (see ``_resolve`` /
``_load_yaml``), because by-id links fail silently otherwise.
"""
from __future__ import annotations

from pathlib import Path

import yaml

from .model import (
    Armour,
    Buildable,
    Cost,
    DamageTable,
    DamageType,
    Faction,
    Layer,
    Projectile,
    StatusEffect,
    Weapon,
    World,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


# --------------------------------------------------------------------------- #
# YAML helpers
# --------------------------------------------------------------------------- #
class _UniqueKeyLoader(yaml.SafeLoader):
    """SafeLoader that rejects duplicate mapping keys (catches duplicate ids)."""


def _no_duplicates(loader: _UniqueKeyLoader, node: yaml.MappingNode) -> dict:
    mapping: dict = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=True)
        if key in mapping:
            raise ValueError(f"duplicate key {key!r} in mapping")
        mapping[key] = loader.construct_object(value_node, deep=True)
    return mapping


_UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates
)


def _load_yaml(path: Path) -> dict:
    try:
        return yaml.load(path.read_text(), Loader=_UniqueKeyLoader) or {}
    except ValueError as e:
        raise ValueError(f"{path.name}: {e}") from e


def _resolve(catalog: dict, ref: str, kind: str, owner: str):
    if ref not in catalog:
        raise KeyError(
            f"{kind} '{ref}' referenced by {owner} is not defined in the {kind} catalog"
        )
    return catalog[ref]


# --------------------------------------------------------------------------- #
# Catalogs (resolved bottom-up)
# --------------------------------------------------------------------------- #
def load_status_effects(path: Path) -> dict[str, StatusEffect]:
    raw = _load_yaml(path).get("status_effects", {})
    out: dict[str, StatusEffect] = {}
    for sid, d in raw.items():
        out[sid] = StatusEffect(
            id=sid,
            kind=d["kind"],
            damage_per_tick=float(d.get("damage_per_tick", 0.0)),
            tick_rate=int(d.get("tick_rate", 1)),
            duration_ticks=int(d.get("duration_ticks", 0)),
            damage_type=DamageType(d["damage_type"]) if d.get("damage_type") else None,
        )
    return out


def load_projectiles(path: Path, status_effects: dict[str, StatusEffect]) -> dict[str, Projectile]:
    raw = _load_yaml(path).get("projectiles", {})
    out: dict[str, Projectile] = {}
    for pid, d in raw.items():
        effects = tuple(
            _resolve(status_effects, ref, "status_effect", f"projectile '{pid}'")
            for ref in d.get("status_effects", [])
        )
        out[pid] = Projectile(
            id=pid,
            base_damage=float(d["base_damage"]),
            damage_type=DamageType(d["damage_type"]),
            aoe_radius=float(d.get("aoe_radius", 0.0)),
            speed=float(d.get("speed", 0.0)),
            status_effects=effects,
        )
    return out


def load_weapons(path: Path, projectiles: dict[str, Projectile]) -> dict[str, Weapon]:
    raw = _load_yaml(path).get("weapons", {})
    out: dict[str, Weapon] = {}
    for wid, d in raw.items():
        proj = None
        if d.get("projectile"):
            proj = _resolve(projectiles, d["projectile"], "projectile", f"weapon '{wid}'")
        out[wid] = Weapon(
            id=wid,
            name=d.get("name", wid),
            split_time=int(d.get("split_time", 1)),
            reload_time=int(d.get("reload_time", d.get("split_time", 1))),
            clip_size=int(d.get("clip_size", 1)),
            reach=float(d.get("reach", 0.0)),
            hits=frozenset(Layer(h) for h in d.get("hits", ["ground"])),
            projectile=proj,
            melee_damage=float(d.get("melee_damage", 0.0)),
            melee_damage_type=DamageType(d.get("melee_damage_type", "LEAD")),
        )
    return out


# --------------------------------------------------------------------------- #
# Factions
# --------------------------------------------------------------------------- #
def _buildable(faction_id: str, d: dict, weapons: dict[str, Weapon]) -> Buildable:
    cost = Cost(
        ore=int(d.get("cost", {}).get("ore", 0)),
        population=int(d.get("cost", {}).get("population", 0)),
        dominion=int(d.get("cost", {}).get("dominion", 0)),
    )
    move = d.get("movement", {}) or {}
    resolved_weapons = [
        _resolve(weapons, ref, "weapon", f"{faction_id}:{d['id']}")
        for ref in d.get("weapons", [])
    ]
    return Buildable(
        faction=faction_id,
        id=d["id"],
        kind=d.get("kind", "unit"),
        name=d.get("name", d["id"]),
        cost=cost,
        requires=list(d.get("requires", [])),
        armour=Armour(d["armour"]) if d.get("armour") else None,
        hp=float(d.get("hp", 0.0)),
        layer=Layer(move["layer"]) if move.get("layer") else None,
        speed=float(move.get("speed", 0.0)),
        attributes=list(d.get("attributes", [])),
        weapons=resolved_weapons,
    )


def load_faction(path: Path, weapons: dict[str, Weapon]) -> Faction:
    raw = _load_yaml(path)
    fid = raw["faction"]
    buildables = {b["id"]: _buildable(fid, b, weapons) for b in raw.get("buildables", [])}
    return Faction(
        id=fid,
        name=raw.get("name", fid),
        description=raw.get("description", ""),
        buildables=buildables,
        overrides=list(raw.get("overrides", [])),
    )


def load_damage_table(path: Path) -> DamageTable:
    raw = _load_yaml(path)
    vs_armour = {
        DamageType(dt): {Armour(a): float(m) for a, m in row.items()}
        for dt, row in raw.get("vs_armour", {}).items()
    }
    vs_attribute = {
        DamageType(dt): {a: float(m) for a, m in row.items()}
        for dt, row in raw.get("vs_attribute", {}).items()
    }
    return DamageTable(vs_armour=vs_armour, vs_attribute=vs_attribute)


def load_world(data_dir: Path | None = None) -> World:
    data_dir = data_dir or DATA_DIR
    damage = load_damage_table(data_dir / "damage_table.yaml")
    status_effects = load_status_effects(data_dir / "status_effects.yaml")
    projectiles = load_projectiles(data_dir / "projectiles.yaml", status_effects)
    weapons = load_weapons(data_dir / "weapons.yaml", projectiles)
    factions: dict[str, Faction] = {}
    for path in sorted((data_dir / "factions").glob("*.yaml")):
        f = load_faction(path, weapons)
        factions[f.id] = f
    return World(
        damage=damage,
        factions=factions,
        weapons=weapons,
        projectiles=projectiles,
        status_effects=status_effects,
    )
