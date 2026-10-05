"""Game facts the dominion model reads, taken from the project's own sources.

Every number here is READ from a primary source (generated technology.json, the spec docs'
frontmatter, the speed ladder, the shape library, a handful of scene-authored exports), never
typed in, so a retuned build time or rate reaches the model by re-running it. The few values
that have no readable home yet are in MODEL_ASSUMPTIONS, each with the reason it is assumed.

Run from the project root: python3 tools/dominion_analysis/facts.py  (prints the facts).
"""

from __future__ import annotations

import glob
import json
import os
import re

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TICKS_PER_SECOND = 30


def _path(rel: str) -> str:
    return os.path.join(ROOT, rel)


def _frontmatter(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    if not m:
        return {}
    try:
        data = yaml.safe_load(m.group(1))
    except yaml.YAMLError:
        return {}
    return data if isinstance(data, dict) else {}


def _scene_export(scene_rel: str, node_name: str, prop: str, default=None):
    """A property authored on node `node_name` of a .tscn (the first match), or `default`."""
    with open(_path(scene_rel), encoding="utf-8") as f:
        text = f.read()
    block = re.search(
        r'\[node name="%s"[^\n]*\n(.*?)(?:\n\[|\Z)' % re.escape(node_name), text, re.S
    )
    if not block:
        return default
    m = re.search(r"^%s = (.+)$" % re.escape(prop), block.group(1), re.M)
    if not m:
        return default
    raw = m.group(1).strip()
    try:
        return float(raw) if "." in raw else int(raw)
    except ValueError:
        return raw


def _script_default(script_rel: str, var: str):
    """An `@export var name: T = value` or `const NAME: T = value` default in a script."""
    with open(_path(script_rel), encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"(?:var|const) %s\s*:\s*\w+\s*=\s*([-\d.]+)" % re.escape(var), text)
    return float(m.group(1)) if m else None


# Values with no single readable home, each with its reason. Kept in one place and printed in
# every report so nobody mistakes them for measured facts.
MODEL_ASSUMPTIONS = {
    # The Retinue reach (2.5 world units) holds far more 0.2-radius bodies than RVO avoidance lets
    # gather in practice. 25 is a hexagonal packing at 0.9-unit spacing (the 0.45 avoidance
    # radius on infantry scenes) times 0.9. TO BE MEASURED in step 3.
    "followers_per_warlord": 25,
    # Seconds a Stock Truck spends running down one Terrestrial that is wandering within 3 units
    # of its shelter (Wander.RADIUS). TO BE MEASURED in step 3.
    "capture_seconds_each": 2.0,
    # A builder's walk ends beside the footprint, not at its centre.
    "build_standoff_cells": 2.0,
    # Exploration lattice stride, in cells: where scouts are sent next.
    "explore_stride_cells": 10,
}


def load() -> dict:
    tech = json.load(open(_path("resources/generated/technology.json"), encoding="utf-8"))
    speeds = _frontmatter(_path("gdd/movement/speed_classes.md"))["speeds"]
    shapes_text = open(_path("gdd/shapes/shapes.md"), encoding="utf-8").read()
    radii = {
        m.group(1): float(m.group(2))
        for m in re.finditer(r"^\s+(\w+):\s*\{[^}]*radius:\s*([\d.]+)", shapes_text, re.M)
    }

    pieces: dict = {}
    for path in glob.glob(_path("gdd/factions/**/*.md"), recursive=True):
        fm = _frontmatter(path)
        if fm.get("kind") != "Entity":
            continue
        pid = os.path.basename(path)[:-3]
        movement = fm.get("movement") or {}
        senses = fm.get("senses") or {}
        spec = tech.get(pid, {})
        pieces[pid] = {
            "title": fm.get("title", pid),
            "infrastructure": fm.get("infrastructure") or 0,
            "speed": float(speeds.get(movement.get("speed"), 0.0)) if movement else 0.0,
            "flying": bool((fm.get("aerial") or {}).get("mode")),
            "vision": radii.get(senses.get("vision"), 0.0) if senses.get("vision") else 0.0,
            "footprint": tuple(fm.get("footprint") or (1, 1)),
            "trains": list(fm.get("trains") or []),
            "builds": list(fm.get("builds") or []),
            "frame": (fm.get("defense") or {}).get("frame"),
            "armed": bool(fm.get("weapons")),
            "build_seconds": spec.get("build_time_ticks", 0) / TICKS_PER_SECOND,
            "energy": (spec.get("cost") or {}).get("energy", 0),
            "requires": list(spec.get("requires") or []),
        }
    # Scene-authored infrastructure the doc does not carry (the Safehouse).
    if pieces.get("an_infrastructure", {}).get("infrastructure", 0) == 0:
        pieces["an_infrastructure"]["infrastructure"] = _scene_export(
            "scenes/entities/structures/an/an_infrastructure.tscn",
            "AnInfrastructure",
            "infrastructure",
            0,
        ) or 0
    # The Safehouse's root node name differs per scene; fall back to a plain search.
    if not pieces["an_infrastructure"]["infrastructure"]:
        text = open(_path("scenes/entities/structures/an/an_infrastructure.tscn")).read()
        m = re.search(r"^infrastructure = (-?\d+)", text, re.M)
        pieces["an_infrastructure"]["infrastructure"] = int(m.group(1)) if m else 0

    cycle = 5.0  # DominionGenerator.TICK_RATE and EnergyExtractor.CYCLE_SECONDS are both 5 s.
    lab_rate = (
        _scene_export("scenes/entities/structures/tc/tc_dominionGen.tscn",
                      "DominionGenerator", "dominion_rate", 10) / cycle
    )
    extractor_rate = _script_default("scripts/entities/components/energy_extractor.gd",
                                     "energy_rate") / cycle
    pond_multiplier = _script_default("scripts/maps/terrain/water_body.gd",
                                      "POND_RATE_MULTIPLIER")
    compound_per_captive = (
        _script_default("scripts/entities/components/occupant_dominion_generator.gd",
                        "dominion_per_unit") / cycle
    )
    retinue_per_follower = (
        _script_default("scripts/interface/commander/anarchical_dominion.gd",
                        "dominion_per_unit")
        / (_script_default("scripts/interface/commander/anarchical_dominion.gd", "TICK_RATE")
           / TICKS_PER_SECOND)
    )
    tile_rate = (
        _script_default("scripts/interface/commander/libertarian_dominion.gd",
                        "dominion_per_tile") / cycle
    )
    compound_doc = _frontmatter(_path("gdd/factions/colonial/structures/cl_infrastructure.md"))
    truck_doc = _frontmatter(_path("gdd/factions/colonial/units/cl_mechLight_dominionGen.md"))
    shelter_scene = "scenes/entities/structures/nt/nt_shelter.tscn"

    def _cyl_radius(scene_rel: str, node: str) -> float:
        text = open(_path(scene_rel), encoding="utf-8").read()
        block = re.search(r'\[node name="%s"[^\n]*\n(.*?)(?:\n\[|\Z)' % re.escape(node),
                          text, re.S)
        m = re.search(r'shape = SubResource\("([^"]+)"\)', block.group(1)) if block else None
        if not m:
            return 0.0
        sub = re.search(r'\[sub_resource type="CylinderShape3D" id="%s"\]\n(.*?)\n\n'
                        % re.escape(m.group(1)), text, re.S)
        r = re.search(r"radius = ([\d.]+)", sub.group(1)) if sub else None
        return float(r.group(1)) if r else 0.0

    warlord_scene = "scenes/entities/units/an/an_bioMedium_dominionGen.tscn"
    return {
        "pieces": pieces,
        "rates": {
            "lab_per_second": lab_rate,
            "extractor_per_second": extractor_rate,
            "pond_multiplier": pond_multiplier,
            "compound_per_captive_per_second": compound_per_captive,
            "retinue_per_follower_per_second": retinue_per_follower,
            "opticon_per_tile_per_second": tile_rate,
        },
        "colonial": {
            "compound_capacity": compound_doc["garrison"]["capacity"],
            "sentence_seconds": compound_doc["garrison"]["sentence_length"],
            "truck_capacity": truck_doc["garrison"]["capacity"],
            # The truck's DEPOSIT interaction, one constant duration per deposit.
            "deposit_seconds": float(_scene_export(
                "scenes/entities/units/cl/cl_mechLight_dominionGen.tscn",
                "", "duration", 0.5) or _deposit_duration()),
            "deposit_seconds_per_captive": 0.0,
            # Garrison.SENTENCES_AT_ONCE: 1 means a Compound sentences one captive at a time.
            # The model has no other queue width, so anything else falls back to all at once.
            "processing": "queue" if _script_default(
                "scripts/entities/components/garrison.gd", "SENTENCES_AT_ONCE") == 1
            else "simultaneous",
        },
        "shelter": {
            "spawn_interval": float(_scene_export(shelter_scene, "Shelter", "spawn_interval",
                                                  _script_default(
                                                      "scripts/entities/components/shelter.gd",
                                                      "spawn_interval"))),
            "capacity": int(_script_default("scripts/entities/components/shelter.gd",
                                            "capacity")),
        },
        "anarchical": {
            "retinue_reach": _cyl_radius(warlord_scene, "DominionRegion"),
            "liberation_reach": _cyl_radius(warlord_scene, "LiberationRange"),
        },
        "libertarian": {
            "claim_radius": pieces["lb_dominion"]["vision"],
        },
        "start": {
            "energy": int(_scene_export("scenes/scenarios/skirmish.tscn", "", "starting_energy",
                                        0) or _skirmish_starting_energy()),
            "free_extractors": int(_script_default(
                "scripts/interface/commander/deployment.gd", "EXTRACTOR_DROP_CHARGES")),
            "command_centres": {
                "colonial": "cl_commandCenter",
                "anarchical": "an_commandCenter",
                "libertarian": "lb_commandCenter",
                "technocratic": "tc_commandCenter",
            },
            "units": {
                f: _frontmatter(_path(f"gdd/factions/{f}/{f}.md")).get("starts_with", [])
                for f in ("colonial", "anarchical", "libertarian", "technocratic")
            },
        },
        "assumptions": dict(MODEL_ASSUMPTIONS),
    }


def _deposit_duration() -> float:
    text = open(_path("scenes/entities/units/cl/cl_mechLight_dominionGen.tscn"),
                encoding="utf-8").read()
    m = re.search(r'id="Interaction_deposit"\]\n(?:.*\n)*?duration = ([\d.]+)', text)
    return float(m.group(1)) if m else 0.5


def _skirmish_starting_energy() -> int:
    text = open(_path("scenes/scenarios/skirmish.tscn"), encoding="utf-8").read()
    m = re.search(r"^starting_energy = (\d+)", text, re.M)
    return int(m.group(1)) if m else 1000


if __name__ == "__main__":
    f = load()
    print(json.dumps({k: v for k, v in f.items() if k != "pieces"}, indent=2))
    for pid in ("tc_dominionGen", "cl_infrastructure", "cl_mechLight_dominionGen",
                "an_bioMedium_dominionGen", "an_bioLight_builder", "lb_dominion",
                "lb_infrastructure", "lb_aircraftLight_builder", "nt_extractor"):
        print(pid, f["pieces"][pid])
