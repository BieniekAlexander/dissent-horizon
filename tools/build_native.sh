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

# macOS: build against the SDK the installed toolchain designates, not whichever xcrun finds
# newest. A Command Line Tools install can carry a newer SDK (a beta left behind by an update)
# whose text stubs the installed linker cannot read, and the link then fails with "unknown
# architecture ... malformed file" after a clean compile. $SDKROOT wins when set (SCons does not
# forward it to the compiler, so it is passed as macos_sdk_path); otherwise the Command Line
# Tools' own MacOSX.sdk link; with full Xcode that link is absent and xcrun's choice stands.
sdk_args=()
if [ "$(uname -s)" = "Darwin" ]; then
  sdk_path="${SDKROOT:-$(xcode-select -p)/SDKs/MacOSX.sdk}"
  if [ -d "$sdk_path" ]; then
    sdk_args=(macos_sdk_path="$(cd "$sdk_path" && pwd -P)")
  fi
fi

for target in "${targets[@]}"; do
  # The profile limits godot-cpp to the engine classes native/src uses, which is most of
  # what a first build costs; a class used without being listed there fails to compile.
  scons -C "$ROOT/native" -j "$jobs" target="$target" api_version="$api_version" \
    build_profile="$ROOT/native/build_profile.json" ${sdk_args[@]+"${sdk_args[@]}"}
done
