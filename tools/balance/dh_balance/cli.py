"""Command-line entry point.

    python -m dh_balance obsolete <faction>
    python -m dh_balance unanswered <attacker> <defender>
    python -m dh_balance tier-gap <low_faction> <low_tier> <high_faction> <high_tier>
    python -m dh_balance tiers <faction>
    python -m dh_balance list
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from . import graph, queries
from .loader import load_world


def _fmt_xc(xc: float) -> str:
    return "INF (cannot hit)" if math.isinf(xc) else f"{xc:.0f}"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="dh_balance", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data-dir", type=Path, default=None,
                   help="data directory to load (default: bundled data/; "
                        "use data_exported/ for a fresh Godot export)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("list", help="list factions and units")
    sp = sub.add_parser("tiers", help="show tech tiers for a faction")
    sp.add_argument("faction")
    sp = sub.add_parser("obsolete", help="units off the Pareto frontier")
    sp.add_argument("faction")
    sp = sub.add_parser("unanswered", help="threats A has that B can't answer")
    sp.add_argument("attacker")
    sp.add_argument("defender")
    sp = sub.add_parser("tier-gap", help="tech-tier asymmetry")
    sp.add_argument("low_faction")
    sp.add_argument("low_tier", type=int)
    sp.add_argument("high_faction")
    sp.add_argument("high_tier", type=int)
    sp = sub.add_parser("import", help="dry-run: preview YAML -> Godot changes")
    sp.add_argument("--current", type=Path, required=True,
                    help="current Godot state (a fresh data_exported/)")
    sp.add_argument("--desired", type=Path, required=True,
                    help="edited YAML to push back")
    sp.add_argument("--manifest", type=Path,
                    default=Path(__file__).resolve().parents[2] / "balance_export" / "manifest.json",
                    help="export manifest, for annotating owning scenes")
    sp.add_argument("--apply", action="store_true",
                    help="actually write the changes (default: dry run). "
                         "Mutates game scene files + manifest.json — commit/stash first.")

    args = p.parse_args(argv)

    if args.cmd == "import":
        from . import importer
        current = load_world(args.current)
        desired = load_world(args.desired)
        scene_for = {}
        if args.manifest and args.manifest.exists():
            scene_for = importer.scene_map_from_manifest(args.manifest, current)
        changes, added, removed = importer.diff_worlds(current, desired, scene_for)
        edits = importer.plan(changes, desired)
        importer.apply(edits, args.manifest, dry_run=not args.apply)

        mode = "APPLIED" if args.apply else "DRY RUN (no files modified — pass --apply to write)"
        applied = [e for e in edits if e.applied]
        skipped = [e for e in edits if e.scope != "skip" and not e.applied]
        manual = [e for e in edits if e.scope == "skip"]
        print(f"{mode}\n{len(changes)} change(s): {len(applied)} writable, "
              f"{len(skipped)} unwritable, {len(manual)} structural; "
              f"{len(added)} added, {len(removed)} removed.\n")
        for e in applied:
            if e.created:
                prefix = "CREATED " if args.apply else "WOULD CREATE "
            else:
                prefix = "WROTE " if args.apply else "WOULD "
            print("  ", prefix + e.describe()[5:])
        for e in skipped:
            print(f"   UNWRITABLE  {e.change.kind} {e.change.id}.{e.change.field}  ({e.skip_reason})")
        for e in manual:
            print("  ", e.describe())
        for a in added:
            print(f"   + NEW {a.kind} {a.id} (in desired only — create it in Godot)")
        for r in removed:
            print(f"   - GONE {r.kind} {r.id} (in current only)")
        return 0

    world = load_world(args.data_dir)

    if args.cmd == "list":
        for f in world.factions.values():
            print(f"\n{f.id}  ({f.name}) — {f.description.strip()}")
            tiers = graph.tech_tiers(f)
            for b in f.buildables.values():
                tag = "unit" if b.is_unit else "bldg"
                wpns = ", ".join(w.name for w in b.weapons) or "-"
                print(f"  [T{tiers.get(b.id,1)}] {tag} {b.id:12} ore={b.cost.ore:<4} "
                      f"hp={b.hp:<6g} armour={b.armour.value if b.armour else '-':9} weapons={wpns}")

    elif args.cmd == "tiers":
        for uid, tier in sorted(graph.tech_tiers(world.factions[args.faction]).items(),
                                key=lambda kv: kv[1]):
            print(f"T{tier}  {uid}")

    elif args.cmd == "obsolete":
        res = queries.obsolete_units(world, args.faction)
        if not res:
            print(f"No obsolete units in {args.faction}: every unit is on the Pareto frontier.")
        for d in res:
            print(f"OBSOLETE  {d.unit}  — dominated by {d.dominated_by}")

    elif args.cmd == "unanswered":
        res = queries.unanswered_threats(world, args.attacker, args.defender)
        if not res:
            print(f"{args.defender} has a favorable answer to every {args.attacker} threat.")
        for u in res:
            best = u.best_response or "—"
            print(f"UNANSWERED  {u.threat} (ore {u.threat_cost:.0f})  "
                  f"best {args.defender} response: {best} "
                  f"[exchange_cost={_fmt_xc(u.best_exchange_cost)}]  ({u.reason})")

    elif args.cmd == "tier-gap":
        r = queries.tech_tier_gap(world, args.low_faction, args.low_tier,
                                  args.high_faction, args.high_tier)
        print(f"{r.low_faction} @T{r.low_tier} vs {r.high_faction} @T{r.high_tier}:")
        if not r.struggles_against:
            print("  no unanswered threats at this tier gap.")
        for u in r.struggles_against:
            best = u.best_response or "—"
            print(f"  STRUGGLES vs {u.threat} (ore {u.threat_cost:.0f})  "
                  f"best response: {best} [exchange_cost={_fmt_xc(u.best_exchange_cost)}]  ({u.reason})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
