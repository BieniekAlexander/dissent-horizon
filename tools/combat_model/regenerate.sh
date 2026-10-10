#!/usr/bin/env bash
# Regenerate the bot's combat model from scratch and leave the result beside the shipped one.
#
#   tools/combat_model/regenerate.sh [--count 2000] [--shards 3] [--out DIR] [--committed-only]
#                                    [--root DIR] [--prefixes cl_,an_,tc_] [--seed-base 0]
#                                    [--no-train]
#
# --prefixes narrows the piece pool the fights draw from (the generator's own `prefixes`
# argument): `--prefixes cl_` is a Colonial-only corpus, every fight a Colonial mirror, which is
# how a matchup's pairs are made dense without a stratified sampler. --seed-base offsets every
# shard's seeds, so a second corpus beside an earlier one repeats none of its fights; train on
# both by handing train.py both directories' fights. --no-train stops after the fights, for a
# corpus that is trained together with others.
#
# --root names the checkout whose HEAD and working tree the fights are built from (default: the
# one this script lives in), for running one checkout's generator against another's pieces.
#
# What it does, in order (gdd/systems/ai/macro-learning.md §1):
#   1. makes a DETACHED WORKTREE of HEAD under .claude/worktrees/, so the fights run on a tree
#      nothing else writes to — a GUT run or an import on the working tree while a match runs
#      zeroes its vision shapes — and the working tree stays free for other work;
#   2. applies the working tree's UNCOMMITTED changes to it (the corpus should price the pieces
#      you are playing, not the ones you committed yesterday); --committed-only skips this;
#   3. gives it the native library and the imported assets, and imports it;
#   4. runs the fight generator in parallel shards (count fights each, disjoint seeds);
#   5. trains the model (tools/combat_model/train.py, needs the .venv — see requirements.txt);
#   6. prints the comparison against resources/bots/combat_model.json and removes the worktree.
#
# It never replaces the shipped model: read the comparison, then
#   cp <out>/combat_model.json resources/bots/combat_model.json
# and run sims/bot/production. About 70 minutes for 3 × 2000 on this machine.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT_ROOT="$ROOT"
COUNT=2000
SHARDS=3
INCLUDE_UNCOMMITTED=1
STAMP=$(date +%Y-%m-%d_%H%M)
OUT=""
PREFIXES="cl_,an_,tc_"
SEED_BASE=0
TRAIN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --count) COUNT="$2"; shift 2 ;;
    --shards) SHARDS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --committed-only) INCLUDE_UNCOMMITTED=0; shift ;;
    --root) ROOT=$(cd "$2" && pwd); shift 2 ;;
    --prefixes) PREFIXES="$2"; shift 2 ;;
    --seed-base) SEED_BASE="$2"; shift 2 ;;
    --no-train) TRAIN=0; shift ;;
    *) echo "regenerate: unknown argument $1" >&2; exit 2 ;;
  esac
done

[ -n "$OUT" ] || OUT="$ROOT/tools/combat_model/out/$STAMP"
PYTHON="$ROOT/tools/combat_model/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON="$SCRIPT_ROOT/tools/combat_model/.venv/bin/python"
if [ ! -x "$PYTHON" ]; then
  echo "regenerate: no trainer environment at tools/combat_model/.venv — create it with" >&2
  echo "  python3 -m venv tools/combat_model/.venv && tools/combat_model/.venv/bin/pip install --require-hashes -r tools/combat_model/requirements.txt" >&2
  exit 1
fi
command -v godot >/dev/null || { echo "regenerate: godot is not on PATH" >&2; exit 1; }
DYLIB=$(ls "$ROOT"/bin/libdissent_native*.dylib 2>/dev/null | head -1)
[ -n "$DYLIB" ] || { echo "regenerate: no native library in bin/ — run tools/build_native.sh" >&2; exit 1; }

WT="$ROOT/.claude/worktrees/fights-regen-$STAMP"
mkdir -p "$OUT"
cleanup() { git -C "$ROOT" worktree remove --force "$WT" 2>/dev/null || true; }
trap cleanup EXIT

git -C "$ROOT" worktree add --detach "$WT" HEAD >/dev/null
{
  echo "head: $(git -C "$ROOT" rev-parse --short HEAD)"
  echo "count per shard: $COUNT, shards: $SHARDS"
  echo "prefixes: $PREFIXES, seed base: $SEED_BASE"
} > "$OUT/source.txt"
if [ "$INCLUDE_UNCOMMITTED" = 1 ]; then
  CHANGED=$(git -C "$ROOT" status --short -- gdd scenes resources scripts tools | grep -v "gdd/tasks.md" || true)
  if [ -n "$CHANGED" ]; then
    echo "uncommitted changes included:" >> "$OUT/source.txt"
    echo "$CHANGED" >> "$OUT/source.txt"
    git -C "$ROOT" diff --binary HEAD -- gdd scenes resources scripts tools ':!gdd/tasks.md' | git -C "$WT" apply --allow-empty
    git -C "$ROOT" ls-files --others --exclude-standard -- gdd scenes resources scripts tools | while read -r f; do
      mkdir -p "$WT/$(dirname "$f")" && cp "$ROOT/$f" "$WT/$f"
    done
  fi
fi

mkdir -p "$WT/bin" "$WT/.godot"
cp "$ROOT"/bin/libdissent_native*.dylib "$WT/bin/"
cp -r "$ROOT/.godot/imported" "$WT/.godot/"
echo "regenerate: importing $WT"
(cd "$WT" && godot --headless --path . --import > "$OUT/import.log" 2>&1) || { echo "regenerate: import failed, see $OUT/import.log" >&2; exit 1; }

echo "regenerate: $SHARDS shards of $COUNT fights → $OUT"
for k in $(seq 0 $((SHARDS - 1))); do
  (cd "$WT" && godot --headless --path . --fixed-fps 30 tools/combat_model/generate_fights.tscn -- \
    "out=$OUT/fights_$k.jsonl" "count=$COUNT" "seed=$((SEED_BASE + k * COUNT + 1))" \
    "prefixes=$PREFIXES" > "$OUT/gen_$k.log" 2>&1) &
done
wait
TOTAL=$(cat "$OUT"/fights_*.jsonl | wc -l | tr -d ' ')
echo "regenerate: $TOTAL fights"
if [ "$TRAIN" = 0 ]; then
  echo "regenerate: --no-train, corpus left at $OUT"
  exit 0
fi

"$PYTHON" "$ROOT/tools/combat_model/train.py" "$OUT"/fights_*.jsonl --out "$OUT/combat_model.json" | tee "$OUT/train.log"
python3 "$SCRIPT_ROOT/tools/combat_model/compare_models.py" "$ROOT/resources/bots/combat_model.json" "$OUT/combat_model.json" \
  --technology "$WT/resources/generated/technology.json" | tee "$OUT/compare.log"
echo
echo "regenerate: candidate at $OUT/combat_model.json — to ship it:"
echo "  cp $OUT/combat_model.json resources/bots/combat_model.json"
echo "  then run the production sims (gdd/systems/ai/decision-sims.md) and commit both."
