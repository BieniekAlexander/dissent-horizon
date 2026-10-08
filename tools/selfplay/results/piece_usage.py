#!/usr/bin/env python3
"""Which of a faction's pieces the bot fields, and for the ones it does not, why not.

    python3 tools/selfplay/results/piece_usage.py colonial results.jsonl [more.jsonl ...]
    python3 tools/selfplay/results/piece_usage.py colonial --catalogue      # the roster alone

One row per piece the faction can field — every structure and unit it can build or train,
every upgrade, every ability a piece grants and every sanction in its grid — with a VERDICT:

    USED                   fielded; the counts follow
    CHOSEN_NOT_ORDERED     a module picked it and the spend gate then held it every time — a
                           prerequisite the bot does not own, or a price above its reserve:
                           the decision wants a piece the bot cannot have, and the producer
                           stands idle on it (a signalling bug, in the picker)
    CONSIDERED_NOT_CHOSEN  a module scored it and always preferred something else: the bot's
                           own valuation ranks it below its alternatives. A balance question
                           (the piece is not worth its price) or a scorer question (the
                           valuation misses what makes it worth it) — the mean score ratio
                           against the winner says how far off it sat
    REFUSED                chosen, ordered, and the command refused it: an actuation bug,
                           with the cause
    NEVER_CONSIDERED       reachable and actuable, and no module ever scored it: a signalling
                           gap — the bot has no decision that would want this piece
    NO_ACTUATION           no bot module can issue the order that uses it (the command is
                           in test_BotCommandCoverage's MISSING bucket): an actuation gap
    PASSIVE                an ability with nothing to cast (`passive: true`): it works by
                           being owned, so its use is its carrier's
    UNREACHABLE            the faction's own tree never offers it to a bot: no builder lists
                           it, no reachable producer trains it, or its prerequisite is
                           itself unreachable — content, not the bot
    STUB                   the piece's own doc says it does nothing yet
    NO_DATA                reachable and actuable, but the results carry no usage ledger
                           (recorded before 2026-10-04) and the piece never appeared

Plus, for a targeted sanction that WAS used, how spread its cast positions were: a bot that
puts every Scan on the same spot shows as a repeat fraction near 1.

The roster is read from the authored content, not from a running game: resources/generated
(tools.json for what produces what, technology.json for prerequisites, abilities.json) plus
the spec docs' `builds:`, `abilities:` and `kind:` keys, and the faction scene's sanction
cells. Usage is read from run_match result rows: `produced_by_id` and `usage` per slot (both
added 2026-10-04), with the per-sample `units_by_id`/`structures_by_id` as the presence
fallback for older rows. See gdd/systems/ai/piece-usage-audit.md.
"""

import argparse
import glob
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GENERATED = os.path.join(PROJECT, "resources", "generated")
GDD = os.path.join(PROJECT, "gdd")
COVERAGE_TEST = os.path.join(PROJECT, "tests", "test_BotCommandCoverage.gd")

# Which usage-ledger domains and action kinds speak for which acquisition route.
CHOICE_DOMAINS = {"train": ["train", "train_opening"], "build": ["production_structure", "defence_structure"]}
ACTION_KINDS = {"train": "train", "build": "build", "sanction": "use_sanction",
                "unit_ability": "use_ability", "spot": "spot"}
# The command class each route needs the bot to issue, matched against the coverage test's
# ISSUED / MISSING buckets so this report and that test cannot disagree about what the bot
# can order.
# Research is an ordinary train job at the structure that lists it (upgrades.md §The rules).
ROUTE_COMMAND = {"train": "Train", "build": "Build", "sanction": "UseSanction",
                 "research": "Train", "unit_ability": "Ability"}
REPEAT_RADIUS = 2.0  # world units: two casts closer than this are "the same spot"


# ── Authored content ─────────────────────────────────────────────────────────────────

def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---"):
        return ""
    end = text.find("\n---", 3)
    return text[3:end] if end > 0 else ""


def key_value(front, key):
    m = re.search(r"^%s:\s*(.*)$" % re.escape(key), front, re.M)
    return m.group(1).strip() if m else None


def list_under(front, key):
    """The scalar list items directly under a top-level `key:` block."""
    m = re.search(r"^%s:\s*(\[.*\])?\s*$" % re.escape(key), front, re.M)
    if not m:
        return []
    if m.group(1):
        return [x.strip().strip("'\"") for x in m.group(1).strip("[]").split(",") if x.strip()]
    items = []
    for line in front[m.end():].splitlines()[1:]:
        if not line.startswith(" ") and line.strip():
            break
        item = re.match(r"^\s+-\s*(\S.*)$", line)
        if item:
            items.append(item.group(1).strip().strip("'\""))
    return items


def granted_abilities(front):
    """Every ability id under any `grants:` list in an `abilities:` block."""
    block = re.search(r"^abilities:\n((?:[ \t]+.*\n?)+)", front, re.M)
    if not block:
        return []
    return re.findall(r"^\s+-\s*([a-z_]+)\s*$", re.sub(r"^\s+-\s*\w+:.*$", "", block.group(1), flags=re.M), re.M)


def docs():
    """id -> (kind, frontmatter) for every importable spec doc."""
    out = {}
    for path in glob.glob(os.path.join(GDD, "**", "*.md"), recursive=True):
        front = frontmatter(path)
        kind = key_value(front, "kind")
        if kind:
            out[os.path.splitext(os.path.basename(path))[0]] = (kind, front, path)
    return out


def sanction_grid(faction):
    """[(ability_id, level, tier)] from the faction scene's cells. A cell is two
    sub-resources — the Sanction (ability, level) and the SanctionUnlock (tier) that points
    at it — so the two are joined by the unlock's `sanction = SubResource(...)`."""
    scene = os.path.join(PROJECT, "scenes", "factions", "%s.tscn" % faction)
    text = open(scene, encoding="utf-8").read()
    blocks = {}
    for block in re.split(r"\n\[sub_resource ", text)[1:]:
        ident = re.search(r'id="([^"]+)"', block)
        if ident:
            blocks[ident.group(1)] = block
    cells = []
    for block in blocks.values():
        link = re.search(r'sanction = SubResource\("([^"]+)"\)', block)
        if not link or link.group(1) not in blocks:
            continue
        sanction = blocks[link.group(1)]
        ability = re.search(r'ability_id = &"(\w+)"', sanction)
        if not ability:
            continue
        level = re.search(r"ability_level = (\d+)", sanction)
        tier = re.search(r"\btier = (\d+)", block)
        cells.append((ability.group(1), int(level.group(1)) if level else 1, int(tier.group(1)) if tier else 0))
    return cells


def bot_can_issue():
    """Command class -> True if test_BotCommandCoverage lists it as ISSUED or COVERED_OTHERWISE."""
    text = open(COVERAGE_TEST, encoding="utf-8").read()
    def names(const):
        block = re.search(r"const %s[^=]*=\s*[\[{](.*?)\n[\]}]" % const, text, re.S)
        return set(re.findall(r'^\s*"(\w+)"', block.group(1), re.M)) if block else set()
    issued = names("ISSUED") | names("COVERED_OTHERWISE")
    return {c: True for c in issued} | {c: False for c in names("MISSING") | names("NOT_THE_BOTS")}


def catalogue(faction):
    tools = {v["id"]: v for v in json.load(open(os.path.join(GENERATED, "tools.json"))).values()
             if faction in v.get("factions", [])}
    tech = json.load(open(os.path.join(GENERATED, "technology.json")))
    abilities = json.load(open(os.path.join(GENERATED, "abilities.json")))
    spec = docs()
    can_issue = bot_can_issue()

    rows = {}
    builders = {}  # unit id -> what its Builds component lists
    for pid, tool in tools.items():
        kind, front, path = spec.get(pid, ("", "", ""))
        route = "research" if tool.get("upgrade") else ("build" if tool["context"] == "BUILD" else "train")
        rows[pid] = {"piece": pid, "route": route, "title": tool.get("label", pid),
                     "producers": tool.get("producers", []),
                     "requires": tech.get(pid, {}).get("requires", []),
                     "cost": tech.get(pid, {}).get("cost", {}).get("energy"),
                     "grants": granted_abilities(front) if front else []}
        built = list_under(front, "builds") if front else []
        if built:
            builders[pid] = built

    # Reachability: a fixpoint over "some reachable builder lists it" / "some reachable
    # producer trains it" / "its prerequisites are reachable". The command centre and the
    # opening roster are reachable by fiat (the scenario deploys them).
    faction_front = spec.get(faction, ("", "", ""))[1]
    reachable = {p for p in rows if rows[p]["route"] == "build" and re.search(r"commandCenter|extractor", p)}
    reachable |= {p for p in rows if "builder" in p}
    changed = True
    while changed:
        changed = False
        for pid, row in rows.items():
            if pid in reachable:
                continue
            if any(r not in reachable and r in rows for r in row["requires"]):
                continue
            if row["route"] == "build":
                ok = any(b in reachable and pid in built for b, built in builders.items())
            else:
                ok = any(p in reachable for p in row["producers"])
            if ok:
                reachable.add(pid)
                changed = True
    for pid, row in rows.items():
        row["reachable"] = pid in reachable
        row["actuable"] = can_issue.get(ROUTE_COMMAND[row["route"]], False)

    # Abilities granted by the faction's pieces (unit abilities) and the sanction grid.
    for pid in list(rows):
        for ability in rows[pid]["grants"]:
            aid = "ability:" + ability
            row = rows.setdefault(aid, {"piece": ability, "route": "unit_ability", "title": ability,
                                        "granted_by": [], "reachable": False, "actuable": None})
            row["granted_by"].append(pid)
            row["reachable"] = row["reachable"] or rows[pid]["reachable"]
            definition = abilities.get(ability, {})
            command = key_value(spec.get(ability, ("", "", ""))[1] or "", "command") or ""
            # The command class that casts it: `command_spot` -> Spot, `command_bombard` -> Bombard;
            # an ability with no command of its own goes through the generic Ability.
            cls = command.replace("command_", "").title().replace("_", "") if command else "Ability"
            row["actuable"] = can_issue.get(cls, can_issue.get("Ability", False))
            row["command"] = cls
            row["stub"] = "STUB" in json.dumps(definition)
            row["passive"] = (key_value(spec.get(ability, ("", "", ""))[1] or "", "passive") or "").lower() == "true"
    for ability, level, tier in sanction_grid(faction):
        aid = "sanction:" + ability
        row = rows.setdefault(aid, {"piece": ability, "route": "sanction", "title": ability,
                                    "levels": [], "reachable": True, "actuable": can_issue.get("UseSanction", False)})
        row["levels"].append({"level": level, "tier": tier})
        row["stub"] = "STUB" in json.dumps(abilities.get(ability, {}))
        # The grid is HOW this ability is acquired; the piece whose pool grants it is its
        # caster, not a second route. One row, carrying both.
        granted = rows.pop("ability:" + ability, None)
        if granted:
            row["granted_by"] = granted["granted_by"]
    return rows


# ── Usage ─────────────────────────────────────────────────────────────────────────

def load_rows(paths):
    for path in paths:
        opener = __import__("gzip").open if path.endswith(".gz") else open
        with opener(path, "rt", encoding="utf-8") as source:
            for line in source:
                if line.strip():
                    yield json.loads(line)


def usage(faction, rows):
    """Per piece: produced, matches present, considered/chosen/score ratio, actions, casts."""
    stats = {}
    slots = 0
    with_ledger = 0
    def row(pid):
        return stats.setdefault(pid, {"produced": 0, "present_in": 0, "considered": 0, "chosen": 0,
                                      "score_sum": 0.0, "best_sum": 0.0, "actions": {}, "casts": [],
                                      "aim": {}})
    for result in rows:
        if not result.get("ok"):
            continue
        for i, slot in enumerate(result.get("slots", [])):
            if slot.get("faction", faction) != faction:
                continue
            slots += 1
            present = set()
            for sample in result.get("samples", []):
                s = sample["slots"][i]
                present |= set((s.get("units_by_id") or {}) | (s.get("structures_by_id") or {}))
            for pid in present:
                row(pid)["present_in"] += 1
            for pid, n in (slot.get("produced_by_id") or {}).items():
                row(pid)["produced"] += n
            ledger = slot.get("usage") or {}
            if ledger:
                with_ledger += 1
            for domain, pieces in ledger.get("choices", {}).items():
                for pid, c in pieces.items():
                    r = row(pid)
                    for k in ("considered", "chosen", "score_sum", "best_sum"):
                        r[k] += c[k]
            # Only the orders that ACQUIRE a piece count toward it: a rally recorded against
            # the structure it was set on, or an attack-move against the unit sent, says
            # nothing about whether the bot fields that piece.
            for kind, pieces in ledger.get("actions", {}).items():
                for pid, outcomes in pieces.items():
                    if kind == "sanction_aim":
                        aim = row("sanction:" + pid)["aim"]
                        for o, n in outcomes.items():
                            aim[o] = aim.get(o, 0) + n
                        continue
                    if kind not in ACTION_KINDS.values():
                        continue
                    if kind == "use_sanction":
                        key = "sanction:" + pid
                    elif kind in ("use_ability", "spot"):
                        key = "ability:" + pid
                    else:
                        key = pid
                    acts = row(key)["actions"].setdefault(kind, {})
                    for o, n in outcomes.items():
                        acts[o] = acts.get(o, 0) + n
            for pid, positions in ledger.get("cast_positions", {}).items():
                # A sanction's casts and a unit ability's are keyed by the ability id alike;
                # the one that exists in the catalogue is the one they belong to.
                key = "sanction:" + pid if ("sanction:" + pid) in stats or ("ability:" + pid) not in stats else "ability:" + pid
                row(key)["casts"].extend(positions)
    return stats, slots, with_ledger


def repeat_fraction(casts):
    """Share of casts landing within REPEAT_RADIUS of an earlier cast."""
    if len(casts) < 2:
        return None
    repeats = 0
    for i, (x, z) in enumerate(casts):
        if any(math.hypot(x - px, z - pz) < REPEAT_RADIUS for px, pz in casts[:i]):
            repeats += 1
    return repeats / (len(casts) - 1)


def verdict(cat, use, has_ledger):
    if cat.get("stub"):
        return "STUB"
    if not cat["reachable"]:
        return "UNREACHABLE"
    if cat.get("passive"):
        return "PASSIVE"
    if not cat["actuable"]:
        return "NO_ACTUATION"
    if use is None:
        return "NO_DATA" if not has_ledger else "NEVER_CONSIDERED"
    issued = sum(o.get("issued", 0) for o in use["actions"].values())
    refused = {o: n for acts in use["actions"].values() for o, n in acts.items() if o.startswith("refused:")}
    if use["produced"] or use["present_in"] or issued:
        return "USED"
    if refused:
        return "REFUSED"
    if use["chosen"]:
        return "CHOSEN_NOT_ORDERED"
    if use["considered"]:
        return "CONSIDERED_NOT_CHOSEN"
    if use["aim"] and not use["aim"].get("aimed"):
        return "NEVER_AIMED"
    return "NO_DATA" if not has_ledger else "NEVER_CONSIDERED"


def report(faction, cat, stats, slots, with_ledger):
    has_ledger = with_ledger > 0
    lines = ["# Piece usage: %s" % faction, "",
             "%d faction slots read, %d with a usage ledger." % (slots, with_ledger), "",
             "| piece | route | verdict | produced | in slots | considered | chosen | score/best | orders | refused | detail |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    order = {"USED": 0, "PASSIVE": 1, "REFUSED": 2, "CHOSEN_NOT_ORDERED": 3, "CONSIDERED_NOT_CHOSEN": 4,
             "NEVER_AIMED": 5, "NEVER_CONSIDERED": 6, "NO_ACTUATION": 7, "UNREACHABLE": 8, "STUB": 9,
             "NO_DATA": 10}
    rows = []
    for key, c in cat.items():
        use = stats.get(key)
        v = verdict(c, use, has_ledger)
        detail = []
        if c["route"] == "unit_ability":
            detail.append("granted by %s; cast by %s" % (", ".join(c["granted_by"]), c.get("command")))
        if c["route"] == "sanction":
            detail.append("tiers %s" % ",".join(str(l["tier"]) for l in c["levels"]))
        if c["route"] in ("build", "train", "research") and c["requires"] and (not c["reachable"] or (use and use["chosen"] and not use["produced"])):
            detail.append("requires %s" % ", ".join(c["requires"]))
        issued = refused = ""
        ratio = ""
        if use:
            issued = sum(o.get("issued", 0) for o in use["actions"].values()) or ""
            refused = "; ".join("%s×%d" % (o.replace("refused:", ""), n) for acts in use["actions"].values()
                                for o, n in acts.items() if o.startswith("refused:"))
            if use["considered"] and use["best_sum"] > 0:
                ratio = "%.2f" % (use["score_sum"] / use["best_sum"])
            if use["casts"]:
                rf = repeat_fraction(use["casts"])
                if rf is not None:
                    detail.append("%d casts, repeat fraction %.2f" % (len(use["casts"]), rf))
            if use["aim"]:
                detail.append("aim: %s" % ", ".join("%s×%d" % kv for kv in sorted(use["aim"].items())))
        rows.append((order.get(v, 9), c["route"], key, "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            c["piece"], c["route"], v, use["produced"] if use else "", use["present_in"] if use else "",
            use["considered"] if use else "", use["chosen"] if use else "", ratio, issued, refused,
            "; ".join(detail))))
    rows.sort()
    lines += [r[3] for r in rows]
    counts = {}
    for r in rows:
        v = r[3].split("|")[3].strip()
        counts[v] = counts.get(v, 0) + 1
    lines += ["", "## Verdicts", ""] + ["- %s: %d" % kv for kv in sorted(counts.items(), key=lambda kv: order.get(kv[0], 9))]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("faction", help="faction scene name, e.g. colonial")
    parser.add_argument("results", nargs="*", help="run_match result JSONL files (.gz accepted)")
    parser.add_argument("--catalogue", action="store_true", help="print the roster as JSON and stop")
    parser.add_argument("--json", help="also write the joined catalogue + usage here")
    args = parser.parse_args()
    cat = catalogue(args.faction)
    if args.catalogue:
        print(json.dumps(cat, indent=1, sort_keys=True))
        return
    stats, slots, with_ledger = usage(args.faction, load_rows(args.results))
    print(report(args.faction, cat, stats, slots, with_ledger))
    if args.json:
        json.dump({"catalogue": cat, "usage": stats, "slots": slots, "slots_with_ledger": with_ledger},
                  open(args.json, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
