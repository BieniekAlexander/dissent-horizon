#!/usr/bin/env python3
"""Compare two exported combat models: a candidate against the one the game ships.

    python3 tools/combat_model/compare_models.py resources/bots/combat_model.json \
        tools/combat_model/out/<run>/combat_model.json [--prefix cl_]

Prints the held-out metrics side by side, the piece types one model knows and the other does
not, each own-side table at counts 1..5, and the first unit's marginal per 100 energy (the
figure the bot's unit choice ranks by, Bot.purchase_values_per_energy). Read it before
accepting a regenerated model: a change that moves a table is a finding about the game or the
fight conditions, and a metric that fell is a reason to look at the corpus. Stdlib only.
gdd/systems/ai/macro-learning.md §1.
"""

import argparse
import json
import sys

TECHNOLOGY_JSON = "resources/generated/technology.json"
COUNTS_SHOWN = 5


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("shipped")
    parser.add_argument("candidate")
    parser.add_argument("--prefix", default="", help="only own-side tables of ids with this prefix")
    parser.add_argument("--technology", default=TECHNOLOGY_JSON, help="prices for the per-energy line")
    args = parser.parse_args(argv)
    old = json.load(open(args.shipped))
    new = json.load(open(args.candidate))
    try:
        prices = {k: v["cost"]["energy"] for k, v in json.load(open(args.technology)).items()}
    except (OSError, KeyError, TypeError):
        prices = {}

    print(f"shipped:   trained {old.get('trained')}  fights {old.get('fights')}")
    print(f"candidate: trained {new.get('trained')}  fights {new.get('fights')}")
    for name in ("additive", "with_pairs"):
        o = old.get("metrics", {}).get(name, {})
        n = new.get("metrics", {}).get(name, {})
        print(
            f"  {name:11s} R² {o.get('r2', 0):.3f} → {n.get('r2', 0):.3f}   "
            f"winner {o.get('winner_agreement', 0):.3f} → {n.get('winner_agreement', 0):.3f}   "
            f"MAE {o.get('mae', 0):.3f} → {n.get('mae', 0):.3f}"
        )
    only_old = sorted(set(old.get("types", [])) - set(new.get("types", [])))
    only_new = sorted(set(new.get("types", [])) - set(old.get("types", [])))
    if only_new:
        print("newly known:   " + ", ".join(only_new))
    if only_old:
        print("no longer known: " + ", ".join(only_old))

    keys = sorted(
        k for k in set(old["main"]) | set(new["main"])
        if k.startswith("own:") and k[4:].startswith(args.prefix)
    )
    width = 6 * COUNTS_SHOWN
    print(f"\n{'own-side table, counts 1..' + str(COUNTS_SHOWN):34s} {'shipped':>{width}s}   {'candidate':>{width}s}")
    for k in keys:
        o = old["main"].get(k, [])
        n = new["main"].get(k, [])
        fo = " ".join(f"{x:5.2f}" for x in o[1 : COUNTS_SHOWN + 1]) or "(unknown)"
        fn = " ".join(f"{x:5.2f}" for x in n[1 : COUNTS_SHOWN + 1]) or "(unknown)"
        print(f"{k:34s} {fo:>{width}s}   {fn:>{width}s}")

    print(f"\n{'first unit, marginal per 100 energy':34s} {'shipped':>8s} {'candidate':>10s}")
    for k in keys:
        piece = k[4:]
        cost = prices.get(piece)
        if not cost:
            continue
        o = old["main"].get(k, [0.0, 0.0])
        n = new["main"].get(k, [0.0, 0.0])
        fo = f"{100 * o[1] / cost:8.3f}" if len(o) > 1 else "   -    "
        fn = f"{100 * n[1] / cost:10.3f}" if len(n) > 1 else "     -    "
        print(f"{piece:34s} {fo} {fn}")
    print(f"\npairs: shipped {len(old.get('pairs', []))}, candidate {len(new.get('pairs', []))}")


if __name__ == "__main__":
    main(sys.argv[1:])
