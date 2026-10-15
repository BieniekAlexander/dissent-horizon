#!/usr/bin/env python3
"""Compare two determinism_probe output directories and say where they first part.

    python3 tools/netplay/compare_determinism.py <dir A> <dir B>

Reports, in order: whether the builds and map digests agree; the first tick whose exact floats
differ (raw.txt — finer than the digest); the first tick whose digest differs; and, for that
tick, which pieces' state lines differ. Exits 0 only when every compared tick agrees.
"""

import json
import sys
from pathlib import Path


def ticked(path: Path, sep: str | None = None) -> dict[int, str]:
    out = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        if not line:
            continue
        tick, rest = line.split(sep, 1) if sep else line.split(None, 1)
        out[int(tick)] = rest
    return out


def first_difference(a: dict[int, str], b: dict[int, str]) -> int | None:
    return next((t for t in sorted(a.keys() & b.keys()) if a[t] != b[t]), None)


def raw_pieces(line: str) -> dict[str, str]:
    return dict(item.split(":", 1) for item in line.split())


def state_entities(state: str) -> dict[str, str]:
    # Entity lines lead with their spawn serial; anything else is keyed by its own text.
    return {part.split(",", 1)[0]: part for part in state.replace("|", ";").split(";")}


def main() -> int:
    a_dir, b_dir = Path(sys.argv[1]), Path(sys.argv[2])
    a_sum = json.loads((a_dir / "summary.json").read_text())
    b_sum = json.loads((b_dir / "summary.json").read_text())
    for key in ("platform", "engine", "build", "map_seed_played", "map_digest", "tick_reached", "error"):
        mark = "  " if a_sum.get(key) == b_sum.get(key) else "!!"
        print(f"{mark} {key}: {a_sum.get(key)!r} | {b_sum.get(key)!r}")
    print(f"   wall_seconds: {a_sum.get('wall_seconds')} | {b_sum.get('wall_seconds')}")
    agreed = a_sum.get("build") == b_sum.get("build") and a_sum.get("map_digest") == b_sum.get("map_digest")

    a_raw, b_raw = ticked(a_dir / "raw.txt"), ticked(b_dir / "raw.txt")
    raw_tick = first_difference(a_raw, b_raw)
    if raw_tick is None:
        print(f"exact floats agree on all {len(a_raw.keys() & b_raw.keys())} sampled ticks")
    else:
        pa, pb = raw_pieces(a_raw[raw_tick]), raw_pieces(b_raw[raw_tick])
        drifted = sorted((s for s in pa.keys() | pb.keys() if pa.get(s) != pb.get(s)), key=int)
        print(f"!! exact floats first differ at tick {raw_tick}: serials {drifted[:20]}")
        agreed = False

    a_dig, b_dig = ticked(a_dir / "digests.txt"), ticked(b_dir / "digests.txt")
    dig_tick = first_difference(a_dig, b_dig)
    if dig_tick is None:
        print(f"digests agree on all {len(a_dig.keys() & b_dig.keys())} ticks")
        return 0 if agreed else 1
    print(f"!! digests first differ at tick {dig_tick}")
    a_st, b_st = ticked(a_dir / "states.txt", "\t"), ticked(b_dir / "states.txt", "\t")
    state_tick = next((t for t in sorted(a_st.keys() & b_st.keys()) if t >= dig_tick and a_st[t] != b_st[t]), None)
    if state_tick is not None:
        ea, eb = state_entities(a_st[state_tick]), state_entities(b_st[state_tick])
        print(f"   state at tick {state_tick} (first sampled at or after):")
        for key in sorted(ea.keys() | eb.keys()):
            if ea.get(key) != eb.get(key):
                print(f"   A {ea.get(key)}\n   B {eb.get(key)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
