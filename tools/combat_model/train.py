#!/usr/bin/env python3
"""Fit the bot's combat model on generated fights and export it for the game.

    tools/combat_model/.venv/bin/python tools/combat_model/train.py \
        tools/combat_model/out/fights_*.jsonl --out resources/bots/combat_model.json

THE MODEL. An explainable boosting machine (GA2M: Lou, Caruana, Gehrke & Hooker, KDD 2013):
one shape function per feature plus a few automatically chosen pairwise terms. Features are
each side's piece counts ("own:<id>", "enemy:<id>"); the target is the fight's MARGIN,
own fraction of value left minus enemy fraction left, in [-1, 1]. Every fight is used twice,
once from each side, so the model sees no side as special. gdd/systems/ai/macro-learning.md §1.

THE EXPORT is lookup tables, not the boosting internals: each term evaluated on every count from
0 to CAP (and every pair of counts for a pairwise term), read back through the model's own
eval_terms. The game adds table entries; it never needs the library, and nothing pickled leaves
this process (the note's §The training dependencies).

THE REPORT compares, on held-out fights, the model with its pairwise terms, the same model
without them, and a value-only baseline (the two sides' energy alone). How much the pairs add
over the additive model is a measurement of the game's interaction structure.

Needs the pinned environment in requirements.txt; nothing else in the repo imports it.
"""

import argparse
import datetime
import glob
import json
import math
import random
import sys

import numpy as np
import pandas as pd
from interpret.glassbox import ExplainableBoostingRegressor

# Counts at and above this read as this: the generator never puts more than 16 bodies on a
# side, so a table past it would be extrapolation the model never saw.
CAP = 16
# Pairwise terms the EBM may add, chosen by its own interaction ranking.
INTERACTIONS = 40
# Share of fights (grouped by seed, so a fight and its mirror stay together) held out.
HOLDOUT_FRACTION = 0.2
SPLIT_SEED = 7


def load_rows(paths):
    rows = []
    for pattern in paths:
        for path in sorted(glob.glob(pattern)):
            with open(path) as f:
                rows += [json.loads(line) for line in f if line.strip()]
    return [r for r in rows if "error" not in r and r["a_value"] > 0 and r["b_value"] > 0]


def vocabulary(rows):
    return sorted({t for r in rows for t in list(r["a"]) + list(r["b"])})


def margin(left_own, value_own, left_enemy, value_enemy):
    return left_own / value_own - left_enemy / value_enemy


def mirrored(rows):
    """Each fight from both sides: (own counts, enemy counts, own value, enemy value, margin, seed)."""
    out = []
    for r in rows:
        y = margin(r["a_left"], r["a_value"], r["b_left"], r["b_value"])
        out.append((r["a"], r["b"], r["a_value"], r["b_value"], y, r["seed"]))
        out.append((r["b"], r["a"], r["b_value"], r["a_value"], -y, r["seed"]))
    return out


def design(samples, types):
    columns = [f"own:{t}" for t in types] + [f"enemy:{t}" for t in types]
    data = [
        [min(own.get(t, 0), CAP) for t in types] + [min(enemy.get(t, 0), CAP) for t in types]
        for own, enemy, _, _, _, _ in samples
    ]
    return pd.DataFrame(data, columns=columns, dtype=float)


def split(samples):
    seeds = sorted({s[5] for s in samples})
    random.Random(SPLIT_SEED).shuffle(seeds)
    held = set(seeds[: int(len(seeds) * HOLDOUT_FRACTION)])
    return [s for s in samples if s[5] not in held], [s for s in samples if s[5] in held]


def scores(y_true, y_pred):
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    residual = float(np.sum((y_true - y_pred) ** 2))
    total = float(np.sum((y_true - y_true.mean()) ** 2))
    sign = float(np.mean(np.sign(y_true) == np.sign(y_pred)))
    return {
        "r2": round(1.0 - residual / total, 4),
        "mae": round(float(np.mean(np.abs(y_true - y_pred))), 4),
        "winner_agreement": round(sign, 4),
    }


def value_baseline(train, test):
    """Margin from the energy log-ratio alone: what a pure 'bigger army wins' model gets."""
    x = np.array([math.log(s[2] / s[3]) for s in train])
    y = np.array([s[4] for s in train])
    slope = float(np.sum(x * y) / np.sum(x * x))  # antisymmetric through the origin
    return [float(np.tanh(slope * math.log(s[2] / s[3]))) for s in test], slope


def fit(x, y, interactions):
    model = ExplainableBoostingRegressor(interactions=interactions, random_state=SPLIT_SEED)
    model.fit(x, y)
    return model


def export_tables(model, columns):
    """Every term as a lookup table over counts 0..CAP, via the model's own eval_terms."""
    names = list(columns)
    zero = pd.DataFrame(np.zeros((1, len(names))), columns=names)
    main, pairs = {}, []
    for term_index, features in enumerate(model.term_features_):
        if len(features) == 1:
            grid = pd.concat([zero] * (CAP + 1), ignore_index=True)
            grid[names[features[0]]] = np.arange(CAP + 1, dtype=float)
            main[names[features[0]]] = [
                round(float(v), 6) for v in model.eval_terms(grid)[:, term_index]
            ]
        else:
            i, j = features
            grid = pd.concat([zero] * ((CAP + 1) ** 2), ignore_index=True)
            grid[names[i]] = np.repeat(np.arange(CAP + 1, dtype=float), CAP + 1)
            grid[names[j]] = np.tile(np.arange(CAP + 1, dtype=float), CAP + 1)
            flat = model.eval_terms(grid)[:, term_index]
            pairs.append(
                {
                    "a": names[i],
                    "b": names[j],
                    "grid": [
                        [round(float(v), 6) for v in flat[r * (CAP + 1) : (r + 1) * (CAP + 1)]]
                        for r in range(CAP + 1)
                    ],
                }
            )
    return main, pairs


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("fights", nargs="+", help="JSONL files (globs allowed)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--interactions", type=int, default=INTERACTIONS)
    args = parser.parse_args(argv)

    rows = load_rows(args.fights)
    types = vocabulary(rows)
    train, test = split(mirrored(rows))
    x_train, x_test = design(train, types), design(test, types)
    y_train, y_test = [s[4] for s in train], [s[4] for s in test]
    print(f"{len(rows)} fights, {len(types)} piece types, {len(train)} train / {len(test)} test rows")

    baseline, slope = value_baseline(train, test)
    additive = fit(x_train, y_train, 0)
    paired = fit(x_train, y_train, args.interactions)
    metrics = {
        "value_only": scores(y_test, baseline),
        "additive": scores(y_test, additive.predict(x_test)),
        "with_pairs": scores(y_test, paired.predict(x_test)),
    }
    for name, m in metrics.items():
        print(f"  {name:11s} R² {m['r2']:.3f}  MAE {m['mae']:.3f}  winner agreement {m['winner_agreement']:.3f}")

    # The shipped model is refitted on every fight: the held-out score above is its estimate.
    everything = train + test
    final = fit(design(everything, types), [s[4] for s in everything], args.interactions)
    main_terms, pair_terms = export_tables(final, design(everything, types).columns)
    model = {
        "version": 1,
        "trained": datetime.date.today().isoformat(),
        "fights": len(rows),
        "cap": CAP,
        "target": "own fraction of value left minus enemy fraction left, in [-1, 1]",
        "intercept": round(float(np.ravel(final.intercept_)[0]), 6),
        "types": types,
        "main": main_terms,
        "pairs": pair_terms,
        "metrics": metrics,
        "value_only_slope": round(slope, 6),
    }
    with open(args.out, "w") as f:
        json.dump(model, f, indent=1, sort_keys=True)
        f.write("\n")
    strongest = sorted(
        pair_terms, key=lambda p: -max(abs(v) for row in p["grid"] for v in row)
    )[:10]
    print(f"wrote {args.out}: {len(main_terms)} main terms, {len(pair_terms)} pairs")
    print("strongest pairs (largest table entry):")
    for p in strongest:
        print(f"  {p['a']:34s} × {p['b']:34s} {max(abs(v) for row in p['grid'] for v in row):.3f}")


if __name__ == "__main__":
    main(sys.argv[1:])
