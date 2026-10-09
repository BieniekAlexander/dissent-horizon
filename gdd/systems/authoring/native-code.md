---
title: Native code
type: system-note
---

# Native code

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

The game is GDScript except for a handful of hot loops, which live in one C++ GDExtension,
`dissent_native` (`native/src`). Each native class is the whole implementation of its job —
there is no GDScript fallback — and a script node owns one and keeps the scene-facing parts.

| Native class | Owned by | Holds |
|---|---|---|
| `TerrainCells` | `TerrainGrid` | per-cell passability reasons, clearance / obstacle-distance / region fields, the navigability and segment-walk queries |
| `FogRaster` | `Fog` | sight counts, stamps, display and explored bytes, every per-pixel fog lookup |
| `MinimapCompositor` | `Minimap` | the per-pixel draw of the map layer through the fog |

## What earns a native port

A loop whose cost is GDScript's per-call and per-element overhead rather than the work itself:
a pass over every cell or pixel, called every tick or every frame. Each port above replaced a
loop of that kind, found by profiling a full bot match
([ai/bot-performance](../ai/bot-performance.md) §Native ports, measured 2026-10-09).

Gameplay logic is not a candidate, even when it is hot: the per-actor order and command code
is mostly calls into the engine, so a port would buy a small factor for a large, constantly
changing rewrite. The answer there is to run it less often.

## The game does not run without the library

Scripts name the native classes, so an unbuilt library fails every script that touches one at
parse time. The libraries are build output and git-ignored, per the generated-artifact rule:

- **Build:** `tools/build_native.sh` (`--release` for the export library too). Needs SCons and a
  C++17 compiler; on macOS the Xcode command-line tools. Rebuild after pulling a change to
  `native/`.
- **Cloud sessions** build it in the session-start hook, before the import.
- **The engine API** it builds against is read from `project.godot`'s engine version; bumping
  Godot past what the pinned `native/godot-cpp` submodule supports means bumping the submodule.
- **`native/build_profile.json`** limits godot-cpp to the engine classes `native/src` uses, which
  takes a clean build from minutes to seconds. A class used in `native/src` without being
  listed there fails to compile, which is the reminder to add it.
- `native/.gdignore` keeps Godot from scanning the sources and godot-cpp's own test project; the
  manifest Godot does read is `extension/dissent_native.gdextension`.

## Conventions in C++

The C++ follows Godot's engine conventions rather than the GDScript ones (CLAUDE.md §12's
language exception): `p_` parameters, unprefixed members, tabs, and godot-cpp's clang-format
style, checked by `tools/lint.sh`.

**A port must reproduce the script it replaces exactly**, down to float precision, because
replays and seeded sims depend on identical results. GDScript keeps `Vector2` components in
single precision and script-level float expressions in double, and the ports mirror that mix
where a branch depends on it (the segment walk's corner test, the fog's pixel mapping). Each
port was checked against the original script on randomized inputs before the original was
deleted, and a match replayed with the ports reached the same unit counts minute by minute.
