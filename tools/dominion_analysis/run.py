"""Run the dominion model over every exported map, faction and policy; keep the best policy per
map and faction; write results JSON, a markdown summary and a chart.

  python3 tools/dominion_analysis/run.py            # all maps in out/maps
Outputs land in tools/dominion_analysis/out/ (gitignored); the write-up quotes them.
"""

from __future__ import annotations

import glob
import json
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import facts as facts_mod  # noqa: E402
import mapdata  # noqa: E402
import sim  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
RANK_AT = 600  # the policy kept is the one with the most dominion banked by 10 minutes
SENSITIVITY_FOLLOWERS = (12, 25, 50)


def run_map(facts: dict, path: str) -> dict:
    m = mapdata.MapData(path)
    result = {"map": m.name, "seed": m.seed, "shelters": len(m.shelters),
              "sites": len(m.sites), "ponds": len(m.ponds), "factions": {}}
    for faction, cls in sim.FACTIONS.items():
        runs = []
        for pol in sim.POLICIES[faction]:
            w = cls(facts, m, faction, pol).run()
            runs.append({"policy": pol, "checkpoints": w.checkpoints(),
                         "series": [round(x, 1) for x in w.series[9::10]],
                         "rate_at_end": round(w.rate_series[-1], 2),
                         "first_dominion_s": next((i + 1 for i, r in enumerate(w.rate_series)
                                                   if r > 0), None)})
        best = max(runs, key=lambda r: r["checkpoints"][RANK_AT])
        best_each = {t: max(runs, key=lambda r: r["checkpoints"][t])["checkpoints"][t]
                     for t in sim.CHECKPOINTS}
        result["factions"][faction] = {"best": best, "best_at_each_checkpoint": best_each,
                                       "policies_tried": len(runs)}
    # Sensitivity: the one assumed number the Anarchist curve leans on.
    sens = {}
    for cap in SENSITIVITY_FOLLOWERS:
        f2 = json.loads(json.dumps(facts))
        f2["assumptions"]["followers_per_warlord"] = cap
        best = max((sim.Anarchical(f2, m, "anarchical", pol).run().checkpoints()
                    for pol in sim.POLICIES["anarchical"]), key=lambda c: c[RANK_AT])
        sens[cap] = best
    result["anarchical_follower_cap_sensitivity"] = sens
    return result


def summarise(results: list[dict], facts: dict) -> str:
    lines = ["# Dominion model — step 2 results", ""]
    lines.append("Best policy per map and faction, ranked by dominion banked at %d s. "
                 "Dominion EARNED (the starting 100 is not counted)." % RANK_AT)
    lines.append("")
    header = "| Faction | " + " | ".join("D(%d s)" % t for t in sim.CHECKPOINTS) + \
        " | avg rate 0-10 min | rate at 15 min | first dominion |"
    lines += [header, "|" + "---|" * (len(sim.CHECKPOINTS) + 4)]
    for faction in sim.FACTIONS:
        cps = {t: [r["factions"][faction]["best"]["checkpoints"][t] for r in results]
               for t in sim.CHECKPOINTS}
        cell = lambda xs: "%s (%s–%s)" % (_fmt(statistics.median(xs)), _fmt(min(xs)),
                                         _fmt(max(xs)))
        rates = [r["factions"][faction]["best"]["rate_at_end"] for r in results]
        firsts = [r["factions"][faction]["best"]["first_dominion_s"] or 0 for r in results]
        lines.append("| %s | %s | %s | %s | %s s |" % (
            faction, " | ".join(cell(cps[t]) for t in sim.CHECKPOINTS),
            _fmt(statistics.median(cps[600]) / 600), cell(rates),
            _fmt(statistics.median(firsts))))
    lines += ["", "Cells: median over the maps, (min–max).", ""]
    lines.append("## Per map (D at 600 s, best policy)")
    lines.append("")
    lines.append("| Map | seed | shelters | sites | ponds | " +
                 " | ".join(sim.FACTIONS) + " |")
    lines.append("|" + "---|" * (5 + len(sim.FACTIONS)))
    for r in results:
        lines.append("| %s | %d | %d | %d | %d | %s |" % (
            r["map"], r["seed"], r["shelters"], r["sites"], r["ponds"],
            " | ".join(_fmt(r["factions"][f]["best"]["checkpoints"][600]) for f in sim.FACTIONS)))
    lines += ["", "## Best policies chosen", ""]
    for faction in sim.FACTIONS:
        pols = [json.dumps(r["factions"][faction]["best"]["policy"], sort_keys=True)
                for r in results]
        counts = {p: pols.count(p) for p in set(pols)}
        lines.append("- **%s**: " % faction + "; ".join(
            "%s ×%d" % (p, n) for p, n in sorted(counts.items(), key=lambda kv: -kv[1])))
    lines += ["", "## Anarchist sensitivity to followers per Warlord (assumed 25)", ""]
    lines.append("| cap | D(300) | D(600) | D(900) |")
    lines.append("|---|---|---|---|")
    for cap in SENSITIVITY_FOLLOWERS:
        xs = {t: statistics.median(r["anarchical_follower_cap_sensitivity"][cap][t]
                                   for r in results) for t in (300, 600, 900)}
        lines.append("| %d | %s | %s | %s |" % (cap, _fmt(xs[300]), _fmt(xs[600]), _fmt(xs[900])))
    lines += ["", "## Facts and assumptions used", "", "```",
              json.dumps({k: v for k, v in facts.items() if k != "pieces"}, indent=1), "```"]
    return "\n".join(lines) + "\n"


def _fmt(x) -> str:
    return "%.0f" % x if abs(x) >= 10 else "%.1f" % x


def chart(results: list[dict]) -> str:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    colors = {"technocratic": "#2a78d6", "colonial": "#d4552b", "anarchical": "#3a9b5c",
              "libertarian": "#8a5cc7"}
    fig, ax = plt.subplots(figsize=(8, 5), dpi=120)
    ts = [10 * (i + 1) for i in range(len(results[0]["factions"]["technocratic"]["best"]["series"]))]
    for faction in sim.FACTIONS:
        series = [r["factions"][faction]["best"]["series"] for r in results]
        med = [statistics.median(col) for col in zip(*series)]
        lo = [min(col) for col in zip(*series)]
        hi = [max(col) for col in zip(*series)]
        ax.fill_between([t / 60 for t in ts], lo, hi, color=colors[faction], alpha=0.15, lw=0)
        ax.plot([t / 60 for t in ts], med, color=colors[faction], lw=2, label=faction)
    ax.set_xlabel("minutes")
    ax.set_ylabel("dominion earned")
    ax.set_title("Dominion earned alone, best policy per map (median, min–max band)")
    ax.legend(frameon=False)
    ax.grid(alpha=0.25)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    path = os.path.join(OUT, "dominion_curves.png")
    fig.tight_layout()
    fig.savefig(path)
    return path


def main() -> None:
    facts = facts_mod.load()
    maps = sorted(glob.glob(os.path.join(OUT, "maps", "*.json")))
    results = []
    t0 = time.time()
    for path in maps:
        results.append(run_map(facts, path))
        print("%s done (%.0fs)" % (os.path.basename(path), time.time() - t0), flush=True)
    json.dump(results, open(os.path.join(OUT, "results.json"), "w"), indent=1)
    summary = summarise(results, facts)
    open(os.path.join(OUT, "summary.md"), "w").write(summary)
    print(chart(results))
    print(summary)


if __name__ == "__main__":
    main()
