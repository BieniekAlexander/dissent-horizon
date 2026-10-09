#!/bin/bash
# Builds the game's native code (native/src, the dissent_native GDExtension) into bin/, where
# extension/dissent_native.gdextension loads it from. The game does not run without it: the
# scripts name its classes, so build before opening the project, and again after pulling a
# change to native/.
#
#   tools/build_native.sh            the debug library the editor and headless runs load
#   tools/build_native.sh --release  also the release library an export ships
#
# Needs a C++17 compiler and SCons (`pip install scons`; on macOS also the Xcode command-line
# tools, `xcode-select --install`). The engine API it builds against is project.godot's engine
# version, so bumping Godot needs no edit here — only a godot-cpp that supports it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v scons >/dev/null 2>&1; then
  echo "build_native: SCons not found — install it with 'pip install scons'" >&2
  exit 1
fi

if [ ! -f "$ROOT/native/godot-cpp/SConstruct" ]; then
  git -C "$ROOT" submodule update --init native/godot-cpp
fi

api_version="$(sed -nE 's/^config\/features=PackedStringArray\("([0-9]+\.[0-9]+)".*/\1/p' "$ROOT/project.godot" | head -n1)"
if [ -z "$api_version" ]; then
  echo "build_native: no engine version in project.godot config/features" >&2
  exit 1
fi

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
targets=(template_debug)
if [ "${1:-}" = "--release" ]; then
  targets+=(template_release)
fi

for target in "${targets[@]}"; do
  # The profile limits godot-cpp to the engine classes native/src uses, which is most of
  # what a first build costs; a class used without being listed there fails to compile.
  scons -C "$ROOT/native" -j "$jobs" target="$target" api_version="$api_version" \
    build_profile="$ROOT/native/build_profile.json"
done
