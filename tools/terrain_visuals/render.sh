#!/usr/bin/env bash
# Render preview shots of a map through visual_preview.tscn on a machine with no display.
# Usage: tools/terrain_visuals/render.sh <scene> <out_dir> [extra user args...]
# Needs xvfb-run; uses the Compatibility renderer, which runs on Mesa's software rasteriser.
set -euo pipefail
cd "$(dirname "$0")/../.."
scene="$1"; out="$2"; shift 2
xvfb-run -a -s "-screen 0 1600x900x24" "${GODOT:-godot}" --path . --rendering-driver opengl3 \
  --audio-driver Dummy --resolution 1600x900 res://tools/terrain_visuals/visual_preview.tscn \
  -- "scene=$scene" "out=$out" "$@" 2>&1 | grep -E "visual_preview|SCRIPT ERROR|Parse Error" || true
