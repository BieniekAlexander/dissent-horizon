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
| `DMath` | every simulation script | maths that rounds the same on every platform (§Maths that rounds the same everywhere) |

## What earns a native port

A loop whose cost is GDScript's per-call and per-element overhead rather than the work itself:
a pass over every cell or pixel, called every tick or every frame. Each port above replaced a
loop of that kind, found by profiling a full bot match
([ai/bot-performance](../ai/bot-performance.md) §Native ports, measured 2026-10-09).

Gameplay logic is not a candidate, even when it is hot: the per-actor order and command code
is mostly calls into the engine, so a port would buy a small factor for a large, constantly
changing rewrite. The answer there is to run it less often, or to split it into a read-only
phase that threads can share (PLANNED, [commands/the-simulation-step](../commands/the-simulation-step.md)).

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
style, checked by `tools/lint.sh` with a pinned `clang-format` ([linting](linting.md)).

**A port must reproduce the script it replaces exactly**, down to float precision, because
replays and seeded sims depend on identical results. GDScript keeps `Vector2` components in
single precision and script-level float expressions in double, and the ports mirror that mix
where a branch depends on it (the segment walk's corner test, the fog's pixel mapping). Each
port was checked against the original script on randomized inputs before the original was
deleted, and a match replayed with the ports reached the same unit counts minute by minute.

## Maths that rounds the same everywhere

`DMath` is the one native class that is not a hot loop. GDScript's `sin`, `cos`, `tan`, `asin`,
`acos`, `atan`, `atan2`, `exp`, `log`, `pow` and `tanh` call the platform's C library, and the
platforms' libraries round differently in the last bit (macOS/arm64 and Windows/x86_64 measured
2026-10-14). So do the engine methods built on them: `Vector2.angle_to`, `rotated`, `slerp` and
`from_angle`, `Vector3.rotated`, `angle_to` and `slerp`, `RandomNumberGenerator.randfn`, and a
node's `global_rotation` and `global_basis`, which the engine rebuilds from its yaw. A networked
match between two platforms drifts apart on the first such bit
([netplay](../commands/netplay.md) §Decisions, platforms).

- **Simulation code calls `DMath` instead**, and `VU.slerp_3d`, `VU.yaw_of` and `VU.yaw_basis` for
  what is built from it. `tests/test_DMath.gd` scans `scripts/` for the builtins and lists the
  presentation-only scripts allowed them — the camera, HUD dials, highlight pulses, decoration.
- **The implementations are musl's** (v1.1.19, the last release whose `exp`, `log` and `pow` are
  self-contained), vendored in `native/src/dmath/musl/` with its licence, unedited but for one
  marked line, and compiled as C++ inside a namespace so they can never resolve to the platform's
  own. One file per translation unit, as they share static constant names.
- **No floating-point contraction**: `SConstruct` builds the whole library with
  `-ffp-contract=off` (`/fp:precise` under MSVC). Clang fuses a multiply and an add into one
  rounding on arm64 by default, which is the same divergence by another route.
- **A const cannot call DMath**, so a constant derived through a transcendental function is
  written out, and a test holds it to the DMath derivation (`TerrainGrid.MAX_SLOPE_DIFF`).
- `test_DMath` also pins a hash of DMath's output bits over fixed inputs; the same hash on every
  platform the suite runs on is the cross-platform check.
- **A piece's facing is `Entity.yaw`, never `rotation.y`.** Writing a node's transform — every
  `move_and_slide()`, the terrain height snap — drops its cached Euler rotation, and the next
  `rotation.y` read re-derives it from the basis with the platform's `atan2`; a mech's yaw parted
  by one bit on its first turn that way (measured 2026-10-14). `yaw` is script state; setting it
  writes the piece's basis built with DMath (keeping the root's scale), so the engine derives
  every child's world placement — launch points, shapes, their scale — by plain arithmetic on the
  same bits everywhere. Its first value is read from the basis the piece was given, with
  `DMath.atan2`. `VU.yaw_of` reads it; `test_DMath` scans for `rotation.y`, and
  `test_EntityYaw` holds a yaw exact across a move.
- **A digest writes numbers by arithmetic** (`SimulationDigest.fixed`), never with `"%.3f"`: the
  platform's string formatting rounds an exact tie (-39.5625) to even on macOS and away from zero
  on Windows, which made a one-tick digest mismatch where the simulation agreed.
- **Every basis the game turns at run time is written with DMath**, so the engine's global
  transforms — composed by plain arithmetic — are the same everywhere, and a launch point is
  read straight off them (`Weapon.launch_frame`). The piece's own is `Entity.yaw`; the model's is
  `MeshVisual.attitude` (an aircraft's pitch and roll, the model's facing); a turret model's is
  written from its authored basis by `VU.with_yaw`. `VU.euler_basis` and `VU.euler_of` are
  Godot's YXZ Euler order in DMath. `test_DMath` scans simulation scripts for `rotation.x`,
  `.y` and `.z`.
- TODO: an `AnimationPlayer` track that turns a node interpolates with the engine's own maths.
  No model animates today ([ux/unit-animation](../ux/unit-animation.md)); a launch point under an
  animated node would need its frame taken from the piece rather than the node.
