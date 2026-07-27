#!/usr/bin/env python3
"""One-at-a-time perturbation screen: does a parameter change the simulation AT ALL?

Each row is one match whose slot 0 carries a single changed field against an unchanged
MEDIUM slot 1, on the seed and cap the BASELINE row used. Two readouts:

  diverge@   the first sampled simulated second at which the state digest differs from the
             baseline match's digest at the same sample. "never" means the perturbation
             produced a BIT-IDENTICAL simulation -- the parameter is not reachable from this
             configuration, and no sample size will make it measurable.
  trajdist   mean |perturbed - baseline| of slot 0's army-energy series, divided by the
             baseline's own mean. Dimensionless, so arms are comparable; it is a distance,
             not an effect on winning.

The verdicts A/B/C are the 2026-09-05 note's, kept so the two screens can be read against
each other: A = bit-identical (not reachable), B = moves less than the replication noise
floor measured in the same run, C = moves more.
"""
import json, sys


def load(path):
    return {json.loads(l)["id"]: json.loads(l) for l in open(path, encoding="utf-8") if l.strip()}


def series(row, slot=0, key="army_energy_value"):
    return [(s["simulated_seconds"], s["slots"][slot][key]) for s in row["samples"]]


def digests(row):
    return [(s["simulated_seconds"], s["digest"]) for s in row["samples"]]


def main(path, baseline_id="screen_BASELINE", noise=None):
    rows = load(path)
    base = rows[baseline_id]
    bd = dict(digests(base))
    bs = dict(series(base))
    out = []
    for rid, row in rows.items():
        if rid == baseline_id or not row.get("ok"):
            continue
        first = None
        for t, d in digests(row):
            if t in bd and bd[t] != d:
                first = t
                break
        pairs = [(bs[t], v) for t, v in series(row) if t in bs]
        denom = sum(a for a, _ in pairs) / max(len(pairs), 1) or 1.0
        dist = sum(abs(a - b) for a, b in pairs) / max(len(pairs), 1) / denom
        out.append((rid.replace("screen_", ""), dist, first))
    out.sort(key=lambda r: (r[2] is not None, r[1]))
    print("baseline %s  (%d samples)" % (baseline_id, len(bd)))
    print("%-30s %10s %10s   %s" % ("arm", "trajdist", "diverge@", "verdict"))
    for name, dist, first in out:
        if first is None:
            verdict = "A - BIT-IDENTICAL (not reachable)"
        elif noise is not None and dist <= noise:
            verdict = "B - wired, effect <= noise floor"
        else:
            verdict = "C - LIVE"
        print("%-30s %10.4f %10s   %s"
              % (name, dist, "never" if first is None else "%.0f s" % first, verdict))


if __name__ == "__main__":
    # screen.py <results.jsonl> [baseline_id] [noise_floor]
    args = sys.argv[1:]
    path = args[0]
    baseline = args[1] if len(args) > 1 else "screen_BASELINE"
    noise = float(args[2]) if len(args) > 2 else None
    main(path, baseline_id=baseline, noise=noise)
