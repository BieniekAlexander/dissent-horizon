"""Colonial recalibration sweep: how sentence length, Compound capacity and deposit time trade
against dominion per captive, with the Stock Truck side unchanged and Work Detail ignored.

Every Colonial route's dominion is linear in the rate per captive R, and no strategy choice
depends on R, so each configuration is run once at R = 1/s and the R that puts 10-minute dominion
at 1x the Technocratic route is solved for afterwards.

  python3 tools/dominion_analysis/sweep_colonial.py [workers] [simultaneous|queue]
Writes out/colonial_sweep[_queue].json and .md (gitignored). `queue` models one-at-a-time
processing: a Compound serves one captive's sentence while the rest of its places wait unpaid.
"""

from __future__ import annotations

import glob
import itertools
import json
import os
import statistics
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(__file__))
import facts as facts_mod  # noqa: E402
import mapdata  # noqa: E402
import sim  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

MODE = sys.argv[2] if len(sys.argv) > 2 else "simultaneous"
if MODE == "queue":
    SENTENCES = (15, 30, 60, 120)
    CAPACITIES = (3, 6)
    COMPOUNDS = (2, 4, 8, 12, 18, 24, 36)
    TRUCKS = (2, 4, 6, 8)
else:
    SENTENCES = (30, 60, 120, 240)
    CAPACITIES = (2, 3, 6)
    COMPOUNDS = (2, 4, 8, 12, 18, 24)
    TRUCKS = (2, 4, 6)
DEPOSIT_PER_CAPTIVE = (0.0, 5.0)  # on top of the shipped 0.5 s per deposit
SERVANT_PRICES = (150, 300)
POLICIES = [{"compounds": c, "trucks": t, "compound_at": at, "energy": 0}
            for c in COMPOUNDS for t in TRUCKS for at in ("base", "shelter")]
SUFFIX = "_queue" if MODE == "queue" else ""


def run_config(args):
    path, sentence, capacity, per_captive = args
    f = facts_mod.load()
    f["rates"]["compound_per_captive_per_second"] = 1.0
    f["colonial"]["sentence_seconds"] = sentence
    f["colonial"]["compound_capacity"] = capacity
    f["colonial"]["deposit_seconds_per_captive"] = per_captive
    f["colonial"]["processing"] = MODE
    m = mapdata.MapData(path)
    best = None
    for pol in POLICIES:
        w = sim.Colonial(f, m, "colonial", pol).run()
        cp = w.checkpoints()
        if best is None or cp[600] > best["cp"][600]:
            best = {"cp": cp, "policy": pol, "rate_end": w.rate_series[-1]}
    return (m.name, sentence, capacity, per_captive, best)


def main() -> None:
    workers = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    maps = sorted(glob.glob(os.path.join(OUT, "maps", "*.json")))
    results = json.load(open(os.path.join(OUT, "results.json")))
    tc = {r["map"]: r["factions"]["technocratic"]["best"]["checkpoints"] for r in results}
    jobs = [(p, s, c, d) for p in maps for s, c, d in
            itertools.product(SENTENCES, CAPACITIES, DEPOSIT_PER_CAPTIVE)]
    with ProcessPoolExecutor(workers) as pool:
        rows = list(pool.map(run_config, jobs))
    json.dump(rows, open(os.path.join(OUT, "colonial_sweep%s.json" % SUFFIX), "w"), indent=1)

    lines = ["# Colonial sweep (%s processing)" % MODE, "",
             "R = the rate per captive that puts 10-minute dominion at 1x Technocratic (median "
             "over maps); V = R x sentence, dominion per captive. Servant energy per dominion at "
             "the two ends of the 150-300 price range.", "",
             "| sentence s | capacity | deposit s/captive | R (/s) | R per 5 s | V | "
             "15-min ratio | Compounds chosen | trucks chosen | Servant e/dom @150 | @300 |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for s, c, d in itertools.product(SENTENCES, CAPACITIES, DEPOSIT_PER_CAPTIVE):
        mine = [r for r in rows if r[1] == s and r[2] == c and r[3] == d]
        rs = [tc[r[0]]["600"] / r[4]["cp"][600] for r in mine if r[4]["cp"][600] > 0]
        if not rs:
            continue
        R = statistics.median(rs)
        r900 = statistics.median(R * r[4]["cp"][900] / tc[r[0]]["900"] for r in mine)
        comps = sorted(r[4]["policy"]["compounds"] for r in mine)
        trucks = sorted(r[4]["policy"]["trucks"] for r in mine)
        V = R * s
        lines.append("| %d | %d | %.0f | %.2f | %.1f | %.0f | %.2fx | %d–%d | %d–%d | %.1f | %.1f |" % (
            s, c, d, R, 5 * R, V, r900, comps[0], comps[-1], trucks[0], trucks[-1],
            SERVANT_PRICES[0] / V, SERVANT_PRICES[1] / V))
    text = "\n".join(lines) + "\n"
    open(os.path.join(OUT, "colonial_sweep%s.md" % SUFFIX), "w").write(text)
    print(text)


if __name__ == "__main__":
    main()
