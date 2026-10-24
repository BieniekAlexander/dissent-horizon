---
title: Screen shake
type: system-note
---

# Screen shake

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Some heavy moments shake the player's screen: a structure slamming down from a deployment drop, a
Bombard shell bursting. This note owns what a shake is, who may raise one, and when the player
feels it.

## A shake is a resource, and a source opts in

A `ScreenShake` (`scripts/interface/screen_shake.gd`) is three numbers, authored as a `.tres`
under `resources/screen_shake/`:

| Field | Meaning |
|---|---|
| `magnitude` | the initial throw, as a **fraction of the visible height** — 0.02 moves the picture by 2% of the screen |
| `duration_seconds` | how long it lasts; the throw falls quadratically to nothing over it |
| `frequency_hz` | how often the lens picks a new direction — low rolls, high rattles |

A shake is a **magnitude, not a flag**, and nothing shakes that does not name one: a source that
should be quiet simply names none, and a source is retuned by editing its resource alone.

**Magnitude is measured against the view, not the world.** The player feels the SCREEN move; a
world-unit throw would all but vanish zoomed out and lurch zoomed in.

## Who raises one

| Source | Where it is configured | Raised when |
|---|---|---|
| A deployment drop | `Deployment.DROP_SHAKES`, by `Drop` | the dropped structure's model touches down (`MeshVisual.play_descent`'s tween finishes), not at the drop — the piece is in play at once, but the thud belongs to the landing |
| An emission phase | `EmissionPhase.screen_shake` | the phase begins (`PhasedLocomotion`: on `ENTERED`, and at launch for the first phase). A shell's burst phase is the impact |

Shipped proof of concept, tuned by eye and expected to move:

| Resource | Used by | Character |
|---|---|---|
| `command_centre_drop.tres` | the command-centre drop | heavy and slow: 3.5%, 0.7 s, 14 Hz |
| `extractor_drop.tres` | the extractor drop | a light thud: 1.5%, 0.35 s, 22 Hz |
| `cannon_shell_impact.tres` | the Bombard's `cannon_shell`, Impact phase | a sharp rattle: 2.5%, 0.45 s, 28 Hz |

The Anarchist `mortar_shell` is a copy of `cannon_shell` and names no shake: the Bombard's is the
one shell asked for.

TODO: no other structure placement shakes. A drop is the only "structure from ordnance" today; a
future one opts in the same way, through its own resource.

## The player feels only what the player can see

`ScreenShake.play(shake, source)` shakes only when **both** hold (`ScreenShake.is_seen`):

- **The source is on screen** — `Camera3D.is_position_in_frustum` on the source's position. A
  shell bursting off-screen says nothing.
- **The source is out of the fog on screen** — judged against the DISPLAYED fog
  (`Fog.get_active_fog`), so a spectator shakes for what they see, and lifted fog (debug view, the
  spectator's toggle) hides nothing. A structure is in sight when any footprint cell is
  (`Fog.structure_in_vision`), as the fog draws it; any other piece by its own pixel and stealth
  (`Entity.is_visible_to`). A shake from something under the fog would tell the player it
  happened.

The judgement is made when the shake is raised — for a drop, at touchdown — so it follows where
the camera and the fog are by then.

## Presentation only

A shake moves the camera's LENS — `Camera3D.h_offset` / `v_offset` — never the camera's
position, a piece, or anything the simulation reads. So:

- `ground_focus`, panning, the map bounds and `center_on` never see a shake. (The cursor's ray
  does: the picture moved, so what is under the cursor moved with it.)
- Two peers, or a replay and its recording, may shake differently — another view, another fog —
  and play the same match. The shake draws its directions from its own `RandomNumberGenerator`,
  never `SU.rng`, for the same reason.
- It runs in real time, like the rest of the camera, so a hold does not freeze a screen mid-throw.

## Several at once

Shakes overlap rather than queue, and the **strongest** throw at each instant is the one shown,
not the sum (`RTSCamera3D.shake_amplitude`): a salvo landing together shakes as hard as its
biggest shell rather than piling into a blur, and a weak long shake outlives a strong short one.

## The player's setting

`RTSCamera3D.shake_scale` multiplies every throw; 0 turns shaking off. TODO: it is an export
only — no options menu wires it yet, and it should be one (it is an accessibility setting).
