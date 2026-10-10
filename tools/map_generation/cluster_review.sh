#!/usr/bin/env bash
# Generate the cluster review set and render each cluster at the game camera's angle.
# Usage: tools/map_generation/cluster_review.sh [count=12] [seed=4000]
# Writes plan_NN.png (top-down cells, one colour per grouping), cluster_NN.png (in game) and
# rules.md under scenes/scenarios/generated/cluster_review/ (gitignored). Needs a display: on a
# machine without one, prefix the render with xvfb-run as tools/terrain_visuals/render.sh does.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="res://scenes/scenarios/generated/cluster_review"
"${GODOT:-godot}" --headless --path . res://tools/map_generation/cluster_review.tscn -- "out=$out" "$@" 2>&1 \
  | grep -E "cluster_review|SCRIPT ERROR|Parse Error" || true
tsv="scenes/scenarios/generated/cluster_review/shots.tsv"
for scene in $(cut -f1 "$tsv" | sort -u); do
  shots=$(awk -F'\t' -v s="$scene" '$1 == s { printf "%s;", $2 }' "$tsv")
  "${GODOT:-godot}" --path . --audio-driver Dummy --resolution 1400x900 \
    res://tools/terrain_visuals/visual_preview.tscn -- "scene=$scene" "out=$out" "shots=$shots" 2>&1 \
    | grep -E "visual_preview: wrote|SCRIPT ERROR|Parse Error" || true
done
