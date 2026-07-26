"""Command-line entry point.

    python -m dh_balance obsolete <faction>
    python -m dh_balance unanswered <attacker> <defender>
    python -m dh_balance tier-gap <low_faction> <low_tier> <high_faction> <high_tier>
    python -m dh_balance tiers <faction>
    python -m dh_balance mermaid <faction>
    python -m dh_balance list
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from . import combat, effectiveness, graph, queries
from .loader import load_world


def _fmt_xc(xc: float) -> str:
    return "INF (cannot hit)" if math.isinf(xc) else f"{xc:.0f}"


def _mermaid_placeholder(label: str, why: str) -> str:
    """A one-node stand-in for a graph that cannot be drawn. A bodyless
    flowchart renders as an unexplained blank box, so state the reason."""
    return f'flowchart LR\n    empty["{label}: {why}"]'


def _mermaid(faction, reachable_only: bool) -> str:
    """A ``flowchart LR`` rendering of ``faction``'s tech DAG (graph.tech_graph),
    one node per buildable and one edge per requires-link. Units render as
    stadium shapes, structures as rectangles. ``reachable_only`` restricts to
    graph.reachable_from(faction), matching the balance queries' default."""
    g = graph.tech_graph(faction)
    nodes = set(g.nodes)
    if reachable_only:
        nodes &= graph.reachable_from(faction)

    if not nodes:
        return _mermaid_placeholder(
            faction.id,
            "no starts_with in the faction doc, so nothing is reachable"
            if not faction.starts_with else "nothing reachable from starts_with")

    lines = ["flowchart LR"]
    for node in sorted(nodes):
        b = faction.buildables[node]
        open_b, close_b = ("([", "])") if b.is_unit else ("[", "]")
        lines.append(f'    {node}{open_b}"{b.name}"{close_b}')
    for u, v in sorted(e for e in g.edges if e[0] in nodes and e[1] in nodes):
        lines.append(f"    {u} --> {v}")
    return "\n".join(lines)


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
    sp = sub.add_parser("mermaid", help="tech DAG as a Mermaid flowchart (for Obsidian/docs embedding)")
    sp.add_argument("faction", nargs="?", help="omit with --all for every faction")
    sp.add_argument("--all", action="store_true", help="emit one flowchart per faction")
    sp.add_argument("--full", action="store_true",
                    help="include buildables unreachable from starts_with too (default: reachable-only)")
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
    sp = sub.add_parser("matchup", help="emergent-factor breakdown for an attacker vs target")
    sp.add_argument("attacker", help="uid faction:id")
    sp.add_argument("target", help="uid faction:id")
    sp = sub.add_parser("distinctness",
                        help="faction roster distinctness: matrix, or detail for one pair")
    sp.add_argument("faction_a", nargs="?", help="omit both for the all-pairs matrix")
    sp.add_argument("faction_b", nargs="?")
    sp.add_argument("--tier", type=int, action="append",
                    help="restrict to these tech tiers (repeatable, e.g. --tier 1 --tier 2)")
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
        # Entities described in the flat files but absent from the Godot export
        # (`current`) have no scene to write to. This is a non-fatal WARNING, not
        # an error — you may be sketching a unit in YAML before authoring it.
        print(f"{mode}\n{len(changes)} change(s): {len(applied)} writable, "
              f"{len(skipped)} unwritable, {len(manual)} structural; "
              f"{len(added)} not in Godot, {len(removed)} removed.\n")
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
            print(f"   WARNING  {a.kind} '{a.id}' is described in the flat files but "
                  f"not found in the Godot files (no scene) — skipped, not applied")
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

    elif args.cmd == "mermaid":
        if not args.all and not args.faction:
            print("provide a faction, or --all for every faction.")
            return 2
        fids = list(world.factions) if args.all else [args.faction]
        for fid in fids:
            if args.all:
                print(f"## {fid}\n")
            faction = world.factions.get(fid)
            print("```mermaid")
            if faction is None:
                # A faction with no unit/structure docs yet — it never reaches
                # the export at all. Draw the moot graph rather than failing.
                print(_mermaid_placeholder(fid, "no pieces authored yet"))
            else:
                faction = graph.with_external_buildables(world, faction)
                print(_mermaid(faction, reachable_only=not args.full))
            print("```")
            if args.all:
                print()

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

    elif args.cmd == "matchup":
        a = world.get(args.attacker)
        t = world.get(args.target)
        d = world.damage
        print(f"{a.uid}  ->  {t.uid}")
        print(f"  base dps        {combat.dps(d, a, t):.2f}")
        for name, v in effectiveness.matchup_factors(d, a, t).items():
            print(f"    x {name:9}   {v:.3f}")
        print(f"  combined factor {effectiveness.combined_factor(d, a, t):.3f}")
        print(f"  effective dps   {effectiveness.effective_dps(d, a, t):.2f}")
        print(f"  exchange_cost   base={_fmt_xc(combat.exchange_cost(d, a, t))}  "
              f"effective={_fmt_xc(effectiveness.effective_exchange_cost(d, a, t))}")

    elif args.cmd == "distinctness":
        tiers = set(args.tier) if args.tier else None
        suffix = f"  (tiers {sorted(tiers)})" if tiers else ""
        if args.faction_a and args.faction_b:
            r = queries.faction_distinctness(world, args.faction_a, args.faction_b, tiers)
            print(f"{r.faction_a} vs {r.faction_b}{suffix}")
            print(f"  {r.faction_a:>12} -> {r.faction_b:<12}  {r.a_to_b:.2f}  (how poorly {r.faction_b} shadows {r.faction_a})")
            print(f"  {r.faction_b:>12} -> {r.faction_a:<12}  {r.b_to_a:.2f}")
            if r.most_similar:
                ms = r.most_similar
                print(f"  most similar: {ms.unit_a} ~ {ms.unit_b}  (distinctness {ms.distinctness:.2f})")
        elif args.faction_a:
            print("provide BOTH factions for a pair, or NEITHER for the matrix.")
            return 2
        else:
            m = queries.distinctness_matrix(world, tiers)
            fids = list(world.factions)
            print(f"set_distinctness  (row shadowed by col; higher = more distinct){suffix}")
            print("            " + "".join(f"{c[:11]:>13}" for c in fids))
            for a in fids:
                cells = "".join("-".rjust(13) if a == b else f"{m[(a, b)]:>13.1f}"
                                for b in fids)
                print(f"{a[:11]:>12}" + cells)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
