# Animation Approach

## TL;DR

The hookup is already in place. `MeshVisual.set_animation_state()` is called every frame from `Commandable._process` with the correct state (IDLE / MOVE / ATTACK). The body of that method is a no-op stub with a TODO comment pointing exactly at what to do. The work is: (1) author skeletal animations in the `.blend` files, (2) wire up an `AnimationTree` in each unit scene, (3) fill in the TODO.

---

## What already exists

### `MeshVisual` component (`scripts/entities/components/mesh_visual.gd`)

The designated owner of everything visual on a mesh-based entity. Already handles:
- Team colour tinting (non-destructive, per-surface)
- Construction opacity fade
- Shadow toggling during transparency
- A `turn_speed` parameter for smooth yaw interpolation
- **`AnimationState` enum** — IDLE, MOVE, ATTACK, DIE
- **`set_animation_state(state)`** — the single call site for animation; currently records the state but does nothing else

### `Commandable._drive_mesh_visual()` (`scripts/entities/commandable.gd:646`)

Called every `_process` frame for any entity that has a `MeshVisual` child. Maps:

| Situation | AnimationState |
|---|---|
| Current command is `Attack` | ATTACK |
| Velocity > 0 on XZ | MOVE |
| Otherwise | IDLE |

DIE is not yet driven — `_on_death()` exists but doesn't push the DIE state.

### Node structure in unit scenes

```
Commandable (root, CharacterBody3D)
  └── MeshVisual (Node3D, mesh_visual.gd)
        └── <model> (instanced .blend — e.g. irregular, hexagonal_prism)
```

Some older units still have a `Sprite3D` child instead of `MeshVisual`; see the sprite section below.

---

## Approach for mesh-based units

### 1. Author skeletal animations in Blender

Add an **Armature** to each `.blend` model and key the following clips:

| Clip name | Loop | Notes |
|---|---|---|
| `idle` | yes | Subtle breathing / weight shift |
| `move` | yes | Walk/run cycle |
| `attack` | yes | Looping attack wind-up; see "firing" below |
| `die` | no | One-shot; ends on final frame |

Blender exports the armature + clips directly via Godot's `.blend` importer (Blender must be configured in Editor → Settings → FileSystem → Import). The import `.import` file can mark specific clips as looping.

For the **generic placeholder meshes** (hexagonal_prism, cone, etc.) used by units like the warlord, it's reasonable to skip a skeleton and use `AnimationPlayer` keyframing on `Node3D` properties instead (scale pulse for idle, position bounce for move). This avoids rigging cost on meshes that will eventually be replaced.

### 2. Add `AnimationPlayer` + `AnimationTree` under `MeshVisual`

In each unit scene, add two children to `MeshVisual`:

```
MeshVisual
  ├── <model instance>
  ├── AnimationPlayer       ← plays clips from the model's library
  └── AnimationTree         ← state machine on top of AnimationPlayer
        root: AnimationNodeStateMachine
          states: idle, move, attack, die
          transitions: (see below)
```

State machine transitions:

```
idle  ←→  move     (bidirectional, immediate)
idle  →   attack   (immediate)
attack →  idle     (at-end of clip, or immediate if target lost)
any   →   die      (immediate, one-shot)
```

`AnimationTree.active = true` at runtime; the `AnimationPlayer` is controlled only through the tree.

### 3. Fill in `MeshVisual.set_animation_state()`

Replace the TODO stub:

```gdscript
const _STATE_NAMES := {
    AnimationState.IDLE:   "idle",
    AnimationState.MOVE:   "move",
    AnimationState.ATTACK: "attack",
    AnimationState.DIE:    "die",
}

@onready var _anim_tree: AnimationTree = get_node_or_null("AnimationTree")

func set_animation_state(state: AnimationState) -> void:
    if state == _anim_state:
        return
    _anim_state = state
    if _anim_tree == null:
        return
    var pb := _anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
    pb.travel(_STATE_NAMES[state])
```

`get_node_or_null` keeps this safe for entities that have `MeshVisual` but no `AnimationTree` yet (static structures, placeholder meshes during development).

### 4. Wire the DIE state

In `Commandable._on_death()`, push the DIE state before `super()` frees the node:

```gdscript
var mesh_visual := get_node_or_null("MeshVisual") as MeshVisual
if mesh_visual != null:
    mesh_visual.set_animation_state(MeshVisual.AnimationState.DIE)
    # Delay queue_free until the death animation finishes.
    # AnimationPlayer emits animation_finished; connect once:
    var ap := mesh_visual.get_node_or_null("AnimationPlayer") as AnimationPlayer
    if ap != null:
        await ap.animation_finished
```

This requires `_on_death()` to be `async` (add `await`). For entities with no death animation, `get_node_or_null` returning null means the existing `super()` path runs immediately as before.

---

## Approach for sprite-based units (`Sprite3D` billboards)

Several older units (vanguard, technician, etc.) use a `Sprite3D` child rather than `MeshVisual`. The flip path in `Commandable._process` already handles left/right mirroring. Two options:

**Option A — `AnimatedSprite3D` (preferred for sprites)**

Replace `Sprite3D` with `AnimatedSprite3D` and attach a `SpriteFrames` resource. Name frame groups `idle`, `move`, `attack`, `die`. Drive it from a **parallel to `_drive_mesh_visual`** — either a `SpriteVisual` component with the same `AnimationState` enum, or a conditional branch in the existing `_process` block.

**Option B — `AnimationPlayer` on the `Sprite3D`**

Keep `Sprite3D` and animate `frame` via `AnimationPlayer` clips. Simpler to set up but a worse long-term fit as clip names drift from `MeshVisual`'s enum.

Option A is the better path because it unifies the interface: `SpriteVisual` would expose `set_animation_state()` identically to `MeshVisual`, so `_drive_mesh_visual` can be renamed `_drive_visual` and dispatch to whichever component the entity has. The existing enum and call site don't change.

---

## Facing

Do **not** drive facing from animation. `Movement` already rotates the root `CharacterBody3D`'s `rotation.y` toward the travel direction every physics tick, and `MeshVisual` is a child that inherits that. `MeshVisual.turn_speed` provides smoothed interpolation if desired. Adding facing keyframes in animation clips would compound with the root rotation and produce doubled/wrong yaw.

For attacks where the unit should snap to face the target, drive `Movement`'s facing directly (already possible via its `get_facing` / `set_facing` interface) rather than keying it in the clip.

---

## Projectile and effect animations

Projectiles (`scenes/entities/projectiles/`) use `Sprite3D` or `MeshInstance3D` already — a short `AnimationPlayer` on each projectile scene for muzzle flash / impact is self-contained and doesn't touch this system.

Status-effect visuals (scenes/entities/status_effects/) follow the same pattern.

---

## Phasing

A practical order given the current state of the art assets:

1. **Fill in `MeshVisual.set_animation_state()`** with the `get_node_or_null` guard (no-op if no `AnimationTree`). Zero risk, unblocks everything else.
2. **Wire the DIE state** in `_on_death()` (make async, add the await). Can be done before any animation clip exists.
3. **Rig and animate one unit** end-to-end (irregular or warlord) as the reference. Verify the import → AnimationTree → state machine path works in-editor.
4. **Roll out** to remaining mesh units.
5. **Sprite units**: add `AnimatedSprite3D` + `SpriteVisual` component in parallel; unify `_drive_mesh_visual` to `_drive_visual`.
