#!/usr/bin/env python3
"""Whole-corpus health check: the numbers the 2026-09-05 note called bugs, re-measured.

Reads every JSONL given and reports, over all slot-trajectories: how often a commander is
broke, whether it owns income, how many units stand idle, how far its scouts see, how often
its posture oscillates (an A->B->A reversal inside three samples), and how the matches ended.

    python3 tools/selfplay/results/corpus.py selfplay-2026-09-06-*.jsonl
"""
import json, sys
from collections import Counter


def main(paths):
    rows = []
    for p in paths:
        for line in open(p, encoding="utf-8"):
            if line.strip():
                rows.append(json.loads(line))
    ok = [r for r in rows if r.get("ok")]
    print("matches %d (ok %d)   wall %.1f h   simulated %.1f h"
          % (len(rows), len(ok),
             sum(r.get("wall_seconds", 0) for r in ok) / 3600.0,
             sum(r.get("simulated_seconds", 0) for r in ok) / 3600.0))
    print("outcomes: %s" % dict(Counter(r.get("outcome", r.get("batch_status")) for r in rows)))
    tps = sorted(r["ticks_per_wall_second"] for r in ok)
    print("ticks per wall second: min %.0f  median %.0f  max %.0f"
          % (tps[0], tps[len(tps) // 2], tps[-1]))

    samples = zero = 0
    traj = 0
    zero_extractor = 0
    idle_peaks, scout_peaks, structure_finals = [], [], []
    osc = Counter()
    postures = Counter()
    no_structure_alive = 0
    for r in ok:
        for slot in (0, 1):
            traj += 1
            seq, idle, scout, ext = [], 0, 0.0, 0
            for s in r["samples"]:
                sl = s["slots"][slot]
                if not sl:
                    continue
                samples += 1
                if sl["energy"] == 0:
                    zero += 1
                idle = max(idle, sl["brain"].get("idle_units", 0))
                scout = max(scout, sl["brain"].get("scout_observed_fraction", 0.0))
                ext = max(ext, sl["extractor_count"])
                p = sl["brain"].get("posture", "")
                if p:
                    postures[p] += 1
                    if not seq or seq[-1] != p:
                        seq.append(p)
            if ext == 0:
                zero_extractor += 1
            idle_peaks.append(idle)
            scout_peaks.append(scout)
            last = r["samples"][-1]["slots"][slot]
            structure_finals.append(last["structure_count"])
            if last["structure_count"] == 0:
                no_structure_alive += 1
            for i in range(len(seq) - 2):
                if seq[i] == seq[i + 2]:
                    osc["%s<->%s" % tuple(sorted((seq[i], seq[i + 1])))] += 1

    def med(v):
        v = sorted(v)
        return v[len(v) // 2]

    print("\nslot-trajectories %d, slot-samples %d" % (traj, samples))
    print("  banked energy exactly zero: %.1f%% of samples  (2026-09-05: 71.1%%)"
          % (100.0 * zero / samples))
    print("  finished owning ZERO extractors: %d/%d  (2026-09-05: 145/170)"
          % (zero_extractor, traj))
    print("  final structure count: median %d, min %d   (zero structures and still alive: %d)"
          % (med(structure_finals), min(structure_finals), no_structure_alive))
    print("  idle units, peak per trajectory: median %d, max %d" % (med(idle_peaks), max(idle_peaks)))
    print("  scout observed fraction, peak: min %.2f median %.2f max %.2f"
          % (min(scout_peaks), med(scout_peaks), max(scout_peaks)))
    print("  posture samples: %s" % dict(postures))
    print("  posture A->B->A reversals within three transitions: %s (total %d)"
          % (dict(osc), sum(osc.values())))


if __name__ == "__main__":
    main(sys.argv[1:])
