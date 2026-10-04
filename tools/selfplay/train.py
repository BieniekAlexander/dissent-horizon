#!/usr/bin/env python3
"""Population training for the bot: an adversarial quality-diversity search over
BotDifficulty vectors, played out through the self-play harness.

    python3 tools/selfplay/train.py seed                 # roster of seed personalities, round-robin
    python3 tools/selfplay/train.py step --children 4    # one generation
    python3 tools/selfplay/train.py report               # ratings, win matrix, equilibrium

WHAT IT OPTIMISES. Not a champion: a ROSTER. The archive is a MAP-Elites grid keyed by two
behaviour descriptors measured from play (aggression = simulated seconds to the first ATTACK
posture; greed = peak structure count), one incumbent per cell. A child replaces its cell's
incumbent only by out-rating it, so the archive fills outward with distinct personalities
rather than collapsing onto one line. gdd/systems/ai/bot-randomness.md §Strength is a search.

WHAT A MEMBER IS. A tier name (the periods, which are the tier's identity and are never
searched) plus a vector over BotDifficulty.SEARCH_RANGES, read from the GDScript so the
search space and the personality draw can never disagree. Every match pins
personality_spread and decision_temperature to 0, so the ledger measures the vector, not
the dice.

HOW IT SCORES. Every match ever played is kept in one ledger and ratings are refitted from
it (Bradley-Terry on the soft score analyze.score gives: a win beats any stalemate beats
any loss, sooner is better). A child is rated against the roster it actually played, both
start assignments always (the start-position bias would otherwise be learned as "play from
the good corner"). Opponents are drawn with weight toward the ones the parent loses to
(prioritised fictitious self-play) over a uniform floor, so counters get found and old
counters are not forgotten.

EXPLORATION. Parents are chosen by an upper-confidence rule over cells (rating plus a bonus
for few evaluations), mutation scale is self-adaptive per lineage with occasional large
jumps and crossover, and when no cell changes for a generation the next one mutates wider.

THE REPORT is the point: the roster's pairwise score matrix, its mixed equilibrium (how many
bots the mixture plays, and how much the best single bot gains over it). A dominant bot is a
balance finding about the GAME, not a failure of the trainer.

State lives in one directory (--state, default tools/selfplay/results/train/):
    archive.json      the live roster and every retired member (ratings need them all)
    ledger.jsonl      every result row, with the member ids it was between
    gen_NNN.json      the match list each generation ran
    report.md         the last report

Needs no third-party packages. Never run alongside another Godot process (see the memory
on vision shapes being rewritten under a running match).
"""

import argparse
import json
import math
import os
import random
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "results"))
import analyze  # noqa: E402  (tools/selfplay/results/analyze.py: the shared scoring)

DIFFICULTY_SCRIPT = os.path.join(PROJECT, "scripts/interface/commander/bot_difficulty.gd")
RUN_BATCH = os.path.join(HERE, "run_batch.py")
DEFAULT_STATE = os.path.join(HERE, "results", "train")

# Fields searched as "unset" as well as across their range: the value that means it.
SENTINELS = {"production_structure_cap": -1, "build_concurrency": -1, "preserve_min_cost": -1}
# Pinned in every match so the ledger measures the vector and not the per-match draw.
PINS = {"personality_spread": 0.0, "decision_temperature": 0.0}
TIER = "HARD"  # the periods every member plays with; reaction time is not personality

# Behaviour descriptor bins. Aggression: simulated seconds to the first ATTACK posture; the
# last bin is "never, within the cap". Greed: structures BUILT (peak count less the opening
# deployment's), since the roster already stands a dozen at deploy. Edges are read at every
# refresh, so recalibrating them re-bins the archive without replaying anything.
AGGRESSION_EDGES = [90.0, 180.0, 300.0, 450.0]
GREED_EDGES = [16, 18, 21, 24]  # seed round: 15.5 (rusher) to 25.4 (economist)

SIGMA_INITIAL = 0.20  # of each field's range
SIGMA_MIN, SIGMA_MAX = 0.05, 0.50
SIGMA_LEARNING_RATE = 0.3  # self-adaptation step, log-normal
JUMP_PROBABILITY = 0.15  # a child mutated at SIGMA_MAX regardless of its lineage
CROSSOVER_PROBABILITY = 0.20
SENTINEL_TOGGLE_PROBABILITY = 0.15
UCB_EXPLORATION = 0.5  # in rating units (log-odds) per sqrt(log N / n)
UNIFORM_OPPONENT_FLOOR = 0.4  # share of opponent weight that ignores the loss record
BRADLEY_TERRY_ITERATIONS = 300
PRIOR_MATCHES = 1.0  # virtual draws against the field, so a new member's rating is finite
EQUILIBRIUM_ITERATIONS = 4000
SUPPORT_THRESHOLD = 0.05

# Seed personalities: overrides on the tier's own vector, searchable fields only. These are
# starting points, not claims about what is strong; the first round-robin rates them.
SEED_PERSONALITIES = {
    "tier": {},
    "rusher": {"army_commit_threshold": 1, "economy_reserve": 0, "attack_value_ratio": 0.8,
               "assumed_enemy_parity": 0.0, "wave_abort_fraction": 0.0,
               "reinforce_fraction": 0.0, "utility_unit_cap": 1},
    "economist": {"economy_reserve": 1200, "build_concurrency": 4, "utility_unit_cap": 6,
                  "income_structure_target": 4, "attack_value_ratio": 2.0,
                  "assumed_enemy_parity": 1.2, "army_commit_threshold": 8},
    "turtle": {"army_commit_threshold": 12, "scout_unit_budget": 0, "economy_reserve": 900,
               "attack_value_ratio": 2.5, "wave_abort_fraction": 1.0,
               "defend_threat_radius": 30.0, "place_frontage_bias": 1.5},
    "skirmisher": {"retarget_switch_margin": 1.0, "scout_unit_budget": 4,
                   "production_structure_cap": 3, "attack_value_ratio": 1.1,
                   "retarget_weight_effectiveness": 3.0, "retarget_weight_finishability": 3.0,
                   "retarget_weight_proximity": 0.0, "reinforce_fraction": 1.0},
}


# ── The search space, read from the GDScript ─────────────────────────────────────────

def read_space():
    """(ranges, base) from bot_difficulty.gd: `ranges[field] = (lo, hi, is_int)` from
    SEARCH_RANGES, `base` the tier's value of each searchable field (declared default,
    overridden by the tier table). Parsed from source so the search cannot drift from the
    personality draw's own bounds."""
    text = open(DIFFICULTY_SCRIPT, encoding="utf-8").read()
    block = re.search(r"const SEARCH_RANGES: Dictionary = \{(.*?)\n\}", text, re.S).group(1)
    ranges = {}
    for name, lo, hi in re.findall(r'"(\w+)": \[([-\d.]+), ([-\d.]+)\]', block):
        is_int = "." not in lo and "." not in hi
        ranges[name] = (int(lo) if is_int else float(lo), int(hi) if is_int else float(hi), is_int)
    defaults = {}
    for name, kind, value in re.findall(r"^var (\w+): (int|float|bool) = (.+)$", text, re.M):
        if name in ranges:
            defaults[name] = int(value) if kind == "int" else float(value)
    tier_block = re.search(r"PlayerSlot\.Difficulty\.%s:(.*?)PlayerSlot\.Difficulty\." % TIER,
                           text, re.S).group(1)
    for name, value in re.findall(r"config\.(\w+) = ([-\d.]+)", tier_block):
        if name in ranges:
            defaults[name] = int(value) if ranges[name][2] else float(value)
    missing = [f for f in ranges if f not in defaults]
    assert not missing, "no default parsed for %s" % missing
    return ranges, {f: defaults[f] for f in ranges}


def coerce(ranges, vector):
    """Ints as ints, floats rounded, nothing outside its range unless it is a sentinel."""
    out = {}
    for field, (lo, hi, is_int) in ranges.items():
        value = vector[field]
        if field in SENTINELS and value == SENTINELS[field]:
            out[field] = value
            continue
        value = min(hi, max(lo, value))
        out[field] = int(round(value)) if is_int else round(float(value), 3)
    return out


# ── Mutation ────────────────────────────────────────────────────────────────────────

def mutate(ranges, parent_vector, sigma, rng):
    child = dict(parent_vector)
    for field, (lo, hi, is_int) in ranges.items():
        sentinel = SENTINELS.get(field)
        if sentinel is not None and rng.random() < SENTINEL_TOGGLE_PROBABILITY:
            child[field] = sentinel if child[field] != sentinel else rng.uniform(lo, hi)
            continue
        if sentinel is not None and child[field] == sentinel:
            continue
        child[field] = child[field] + rng.gauss(0.0, sigma * (hi - lo))
    return coerce(ranges, child)


def crossover(ranges, a, b, rng):
    return coerce(ranges, {f: (a[f] if rng.random() < 0.5 else b[f]) for f in ranges})


def adapted_sigma(parent_sigma, rng):
    """Log-normal self-adaptation: lineages that keep winning with small steps keep them."""
    return min(SIGMA_MAX, max(SIGMA_MIN, parent_sigma * math.exp(SIGMA_LEARNING_RATE * rng.gauss(0, 1))))


# ── Descriptors: what a match says about how a slot played ───────────────────────────

def descriptors(row, slot, cap):
    """(aggression_seconds, structures_built, mech_fraction) for `slot` in one result row.
    Aggression is the cap when the bot never attacked. Mech fraction is over unit-samples,
    read from the unit ids, whose frame token is their second segment."""
    samples = row.get("samples") or []
    first_attack = cap
    peak_structures = 0
    # The opening deployment lands after the first sample, so the opening count is the first
    # sample that saw any structure at all.
    opening_structures = next((s["slots"][slot]["structure_count"] for s in samples
                               if s["slots"][slot].get("structure_count", 0) > 0), 0)
    mech = total = 0
    for sample in samples:
        s = sample["slots"][slot]
        if s.get("brain", {}).get("posture") == "ATTACK" and first_attack == cap:
            first_attack = min(first_attack, sample["simulated_seconds"])
        peak_structures = max(peak_structures, s.get("structure_count", 0))
        for unit_id, count in (s.get("units_by_id") or {}).items():
            total += count
            if "_mech" in unit_id:
                mech += count
    return (first_attack, peak_structures - opening_structures, (mech / total) if total else 0.0)


def bin_index(value, edges):
    return sum(1 for edge in edges if value >= edge)


def cell_of(aggression, greed):
    return "a%d_g%d" % (bin_index(aggression, AGGRESSION_EDGES), bin_index(greed, GREED_EDGES))


# ── Ratings from the ledger ─────────────────────────────────────────────────────────

def pair_results(ledger, cap):
    """[(member_a, member_b, score_for_a)] over every ok row; score in [0,1]."""
    out = []
    for row in ledger:
        if not row.get("ok"):
            continue
        a, b = row["members"]
        s = analyze.score(row, 0, cap=cap)
        if s is not None:
            out.append((a, b, s))
    return out


def bradley_terry(members, pairs):
    """log-strength per member from soft pairwise outcomes, by the MM iteration with a weak
    prior (each member plays PRIOR_MATCHES virtual draws against a strength-1 field)."""
    strength = {m: 1.0 for m in members}
    for _ in range(BRADLEY_TERRY_ITERATIONS):
        wins = {m: PRIOR_MATCHES * 0.5 for m in members}
        denom = {m: PRIOR_MATCHES / (strength[m] + 1.0) for m in members}
        for a, b, s in pairs:
            wins[a] += s
            wins[b] += 1.0 - s
            d = 1.0 / (strength[a] + strength[b])
            denom[a] += d
            denom[b] += d
        strength = {m: wins[m] / denom[m] for m in members}
        mean_log = sum(math.log(v) for v in strength.values()) / len(strength)
        strength = {m: v / math.exp(mean_log) for m, v in strength.items()}
    return {m: math.log(v) for m, v in strength.items()}


def score_matrix(members, pairs, ratings):
    """Mean score of row vs column; unplayed pairs filled from the ratings' prediction."""
    sums, counts = {}, {}
    for a, b, s in pairs:
        sums[(a, b)] = sums.get((a, b), 0.0) + s
        counts[(a, b)] = counts.get((a, b), 0) + 1
        sums[(b, a)] = sums.get((b, a), 0.0) + 1.0 - s
        counts[(b, a)] = counts.get((b, a), 0) + 1
    matrix = {}
    for a in members:
        for b in members:
            if a == b:
                matrix[(a, b)] = 0.5
            elif (a, b) in counts:
                matrix[(a, b)] = sums[(a, b)] / counts[(a, b)]
            else:
                matrix[(a, b)] = 1.0 / (1.0 + math.exp(ratings[b] - ratings[a]))
    return matrix, counts


def equilibrium(members, matrix):
    """Mixed equilibrium of the symmetric zero-sum game with payoff score-0.5, by fictitious
    play; returns (mixture, exploitability = best pure reply's gain over the mixture)."""
    n = len(members)
    counts = [1.0] * n
    for _ in range(EQUILIBRIUM_ITERATIONS):
        total = sum(counts)
        best, best_value = 0, -1e9
        for i in range(n):
            value = sum((matrix[(members[i], members[j])] - 0.5) * counts[j] for j in range(n)) / total
            if value > best_value:
                best, best_value = i, value
        counts[best] += 1.0
    total = sum(counts)
    mixture = {members[i]: counts[i] / total for i in range(n)}
    exploitability = max(
        sum((matrix[(members[i], members[j])] - 0.5) * mixture[members[j]] for j in range(n))
        for i in range(n))
    return mixture, exploitability


# ── State ──────────────────────────────────────────────────────────────────────────

class State:
    def __init__(self, directory):
        self.directory = directory
        os.makedirs(directory, exist_ok=True)
        self.archive_path = os.path.join(directory, "archive.json")
        self.ledger_path = os.path.join(directory, "ledger.jsonl")
        self.archive = json.load(open(self.archive_path)) if os.path.exists(self.archive_path) else {
            "generation": 0, "cap": None, "members": {}, "cells": {}, "log": []}
        self.ledger = analyze.load(self.ledger_path) if os.path.exists(self.ledger_path) else []

    def save(self):
        json.dump(self.archive, open(self.archive_path, "w"), indent=1, sort_keys=True)

    def append_ledger(self, rows):
        with open(self.ledger_path, "a", encoding="utf-8") as sink:
            for row in rows:
                sink.write(json.dumps(row) + "\n")
        self.ledger.extend(rows)

    @property
    def members(self):
        return self.archive["members"]

    def live_ids(self):
        return list(self.archive["cells"].values())

    def refresh(self):
        """Recompute every member's rating, descriptors and match count from the ledger."""
        cap = self.archive["cap"]
        pairs = pair_results(self.ledger, cap)
        ratings = bradley_terry(list(self.members), pairs) if pairs else {m: 0.0 for m in self.members}
        played = {m: [] for m in self.members}
        for row in self.ledger:
            if not row.get("ok"):
                continue
            for slot, member in enumerate(row["members"]):
                played[member].append(descriptors(row, slot, cap))
        for member_id, member in self.members.items():
            member["rating"] = round(ratings[member_id], 4)
            member["matches"] = len(played[member_id])
            if played[member_id]:
                columns = list(zip(*played[member_id]))
                member["descriptors"] = [round(sum(c) / len(c), 3) for c in columns]
                member["cell"] = cell_of(member["descriptors"][0], member["descriptors"][1])
        return pairs

    def place(self, member_id):
        """MAP-Elites insertion: the member takes its cell if empty or if it out-rates the
        incumbent, who is retired (kept for the ratings, dropped from the roster)."""
        member = self.members[member_id]
        cell = member.get("cell")
        if cell is None:
            return "unrated"
        incumbent = self.archive["cells"].get(cell)
        if incumbent is None:
            self.archive["cells"][cell] = member_id
            return "new cell %s" % cell
        if incumbent == member_id:
            return "holds %s" % cell
        if member["rating"] > self.members[incumbent]["rating"]:
            self.archive["cells"][cell] = member_id
            self.members[incumbent]["retired"] = True
            return "takes %s from %s" % (cell, incumbent)
        member["retired"] = True
        return "loses %s to %s" % (cell, incumbent)

    def recell(self, candidate_ids):
        """Rebuild the roster from `candidate_ids` by MAP-Elites insertion in rating order:
        descriptors move as a member plays more, so every live member is re-placed, and a
        cell with two claimants keeps the better rated. Returns {id: placement text}."""
        ranked = sorted(candidate_ids, key=lambda m: -self.members[m]["rating"])
        self.archive["cells"] = {}
        for member_id in ranked:
            self.members[member_id]["retired"] = False
        return {m: self.place(m) for m in ranked}


# ── Match generation ───────────────────────────────────────────────────────────────

def slot_config(member):
    config = dict(member["vector"])
    config.update(PINS)
    return {"difficulty": member["tier"], "config": config}


def pairing_matches(state, prefix, a, b, seed, cap):
    """Both start assignments of one pairing, as run_batch configs tagged with members."""
    common = {"seed": seed, "max_simulated_seconds": cap, "max_wall_seconds": 900,
              "sample_interval_seconds": 5.0, "deterministic_navigation": True,
              "slots": [slot_config(state.members[a]), slot_config(state.members[b])]}
    return [dict(common, id="%s__%s_v_%s__s%d_p0" % (prefix, a, b, seed), members=[a, b]),
            dict(common, id="%s__%s_v_%s__s%d_p1" % (prefix, a, b, seed), members=[a, b],
                 swap_start_points=True)]


def run_matches(state, matches, generation, jobs):
    """Run a match list through run_batch.py and ingest the rows into the ledger."""
    list_path = os.path.join(state.directory, "gen_%03d.json" % generation)
    out_path = os.path.join(state.directory, "gen_%03d_results.jsonl" % generation)
    members_by_id = {m["id"]: m["members"] for m in matches}
    for m in matches:
        m.pop("members")  # run_match ignores unknown keys, but keep its document clean
    json.dump(matches, open(list_path, "w"), indent=1)
    command = [sys.executable, RUN_BATCH, list_path, "--out", out_path, "--jobs", str(jobs),
               "--project", PROJECT, "--resume"]
    print("running %d matches (jobs=%d) -> %s" % (len(matches), jobs, out_path), file=sys.stderr)
    started = time.time()
    subprocess.run(command, cwd=PROJECT, check=True)
    rows = []
    for row in analyze.load(out_path):
        row["members"] = members_by_id[row["id"]]
        row["generation"] = generation
        rows.append(row)
    state.append_ledger(rows)
    ok = sum(1 for r in rows if r.get("ok"))
    print("ingested %d rows (%d ok) in %.0f s" % (len(rows), ok, time.time() - started), file=sys.stderr)
    os.remove(out_path)
    return rows


def opponents_for(state, parent_id, k, rng):
    """k live opponents, weighted toward the ones the parent scores worst against."""
    cap = state.archive["cap"]
    candidates = [m for m in state.live_ids() if m != parent_id]
    if not candidates:
        return []
    loss = {}
    for a, b, s in pair_results(state.ledger, cap):
        if a == parent_id and b in candidates:
            loss.setdefault(b, []).append(1.0 - s)
        elif b == parent_id and a in candidates:
            loss.setdefault(a, []).append(s)
    weights = []
    for c in candidates:
        record = loss.get(c)
        prioritised = (sum(record) / len(record)) if record else 0.5
        weights.append(UNIFORM_OPPONENT_FLOOR + (1.0 - UNIFORM_OPPONENT_FLOOR) * prioritised)
    chosen = []
    pool = list(zip(candidates, weights))
    while pool and len(chosen) < k:
        total = sum(w for _, w in pool)
        r = rng.uniform(0, total)
        for i, (c, w) in enumerate(pool):
            r -= w
            if r <= 0:
                chosen.append(c)
                pool.pop(i)
                break
    return chosen


def choose_parents(state, n, rng):
    """Upper-confidence selection over live cells: strong cells are exploited, thinly played
    ones explored. Sampled without replacement by UCB rank, so n parents span n cells."""
    live = state.live_ids()
    total = sum(state.members[m]["matches"] for m in live) + 1
    ucb = {m: state.members[m]["rating"]
           + UCB_EXPLORATION * math.sqrt(math.log(total) / (state.members[m]["matches"] + 1))
           for m in live}
    ranked = sorted(live, key=lambda m: -ucb[m])
    return [ranked[i % len(ranked)] for i in range(n)]


# ── Commands ─────────────────────────────────────────────────────────────────────────

def cmd_seed(state, args):
    ranges, base = read_space()
    if state.members:
        sys.exit("archive already seeded at %s" % state.archive_path)
    state.archive["cap"] = args.cap
    for name, overrides in SEED_PERSONALITIES.items():
        member_id = "s_%s" % name
        vector = coerce(ranges, dict(base, **overrides))
        state.members[member_id] = {"tier": TIER, "vector": vector, "sigma": SIGMA_INITIAL,
                                    "parent": None, "generation": 0, "retired": False}
    ids = list(state.members)
    rng = random.Random(args.seed)
    matches = []
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            matches += pairing_matches(state, "g000", a, b, rng.randrange(1, 10 ** 6), args.cap)
    if args.dry_run:
        print(json.dumps(matches, indent=1))
        return
    state.save()
    run_matches(state, matches, 0, args.jobs)
    state.refresh()
    placements = state.recell(list(state.members))
    state.archive["log"].append({"generation": 0, "matches": len(matches),
                                 "placements": placements, "changed": True,
                                 "cells": dict(state.archive["cells"])})
    state.save()
    cmd_report(state, args)


def cmd_step(state, args):
    ranges, _ = read_space()
    if not state.members:
        sys.exit("seed the archive first")
    generation = state.archive["generation"] + 1
    rng = random.Random(args.seed + generation)
    state.refresh()
    stagnant = state.archive["log"] and not state.archive["log"][-1].get("changed", True)
    parents = choose_parents(state, args.children, rng)
    children = []
    for k, parent_id in enumerate(parents):
        parent = state.members[parent_id]
        sigma = SIGMA_MAX if (stagnant or rng.random() < JUMP_PROBABILITY) else adapted_sigma(parent["sigma"], rng)
        vector = parent["vector"]
        other = rng.choice(state.live_ids())
        if other != parent_id and rng.random() < CROSSOVER_PROBABILITY:
            vector = crossover(ranges, vector, state.members[other]["vector"], rng)
        child_id = "g%03d_c%d" % (generation, k)
        state.members[child_id] = {"tier": TIER, "vector": mutate(ranges, vector, sigma, rng),
                                   "sigma": round(sigma, 3), "parent": parent_id,
                                   "generation": generation, "retired": False}
        children.append(child_id)
    matches = []
    for child_id in children:
        for opponent in opponents_for(state, state.members[child_id]["parent"], args.opponents, rng):
            matches += pairing_matches(state, "g%03d" % generation, child_id, opponent,
                                       rng.randrange(1, 10 ** 6), state.archive["cap"])
    if args.dry_run:
        print(json.dumps(matches, indent=1))
        return
    state.save()
    run_matches(state, matches, generation, args.jobs)
    state.refresh()
    placements = state.recell(state.live_ids() + children)
    placements = {c: placements[c] for c in children}
    changed = any(not p.startswith("loses") for p in placements.values())
    state.archive["generation"] = generation
    state.archive["log"].append({"generation": generation, "matches": len(matches),
                                 "placements": placements, "changed": changed,
                                 "cells": dict(state.archive["cells"])})
    state.save()
    for c, p in placements.items():
        print("%-10s %s" % (c, p), file=sys.stderr)
    cmd_report(state, args)


def cmd_report(state, args):
    pairs = state.refresh()
    live = sorted(state.live_ids(), key=lambda m: -state.members[m]["rating"])
    ratings = {m: state.members[m]["rating"] for m in state.members}
    matrix, counts = score_matrix(live, pairs, ratings)
    mixture, exploitability = equilibrium(live, matrix) if len(live) > 1 else ({live[0]: 1.0}, 0.0)
    lines = ["# Training report", "",
             "Generation %d, %d ledger rows, %d live of %d members, cap %s s." % (
                 state.archive["generation"], len(state.ledger), len(live), len(state.members),
                 state.archive["cap"]), "",
             "## Roster", "",
             "| member | cell | rating | matches | first attack s | structures built | mech | mixture | parent |",
             "|---|---|---|---|---|---|---|---|---|"]
    for m in live:
        d = state.members[m].get("descriptors", [0, 0, 0])
        lines.append("| %s | %s | %+.2f | %d | %.0f | %.1f | %.2f | %.2f | %s |" % (
            m, state.members[m].get("cell"), ratings[m], state.members[m]["matches"],
            d[0], d[1], d[2], mixture[m], state.members[m]["parent"]))
    support = sum(1 for m in live if mixture[m] >= SUPPORT_THRESHOLD)
    lines += ["", "## Equilibrium", "",
              "Support: %d of %d bots play at %.0f%% or more. Exploitability: %+.3f "
              "(best single bot's mean score gain over the mixture; 0 is unexploitable)." % (
                  support, len(live), SUPPORT_THRESHOLD * 100, exploitability), "",
              "## Score matrix (row vs column, mean score; * = predicted, unplayed)", "",
              "| | " + " | ".join(live) + " |", "|---|" + "---|" * len(live)]
    for a in live:
        cells = []
        for b in live:
            if a == b:
                cells.append("·")
            else:
                cells.append("%.2f%s" % (matrix[(a, b)], "" if (a, b) in counts else "*"))
        lines.append("| %s | %s |" % (a, " | ".join(cells)))
    lines += ["", "## Vectors", ""]
    fields = list(read_space()[0])
    lines.append("| field | " + " | ".join(live) + " |")
    lines.append("|---|" + "---|" * len(live))
    for f in fields:
        lines.append("| %s | %s |" % (f, " | ".join(str(state.members[m]["vector"][f]) for m in live)))
    lines += ["", "## Generations", ""]
    for entry in state.archive["log"]:
        lines.append("- g%03d: %d matches; %s" % (
            entry["generation"], entry["matches"],
            "; ".join("%s %s" % kv for kv in entry.get("placements", {}).items())))
    report = "\n".join(lines) + "\n"
    open(os.path.join(state.directory, "report.md"), "w").write(report)
    state.save()
    print(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["seed", "step", "report"])
    parser.add_argument("--state", default=DEFAULT_STATE)
    parser.add_argument("--cap", type=int, default=900, help="simulated seconds per match (seed only)")
    parser.add_argument("--children", type=int, default=4)
    parser.add_argument("--opponents", type=int, default=2)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--seed", type=int, default=20261004)
    parser.add_argument("--dry-run", action="store_true", help="write and print the match list only")
    args = parser.parse_args()
    state = State(args.state)
    {"seed": cmd_seed, "step": cmd_step, "report": cmd_report}[args.command](state, args)


if __name__ == "__main__":
    main()
