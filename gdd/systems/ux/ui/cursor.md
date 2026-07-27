---
title: Cursor
type: system-note
---

# Cursor

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PARTLY DESIGNED.** The delivery half is written up because it has been debugged twice, and
is still the open problem — §Open item 1 carries the current hypothesis and the experiment
that settles it. The state half is transcribed from the code; one of its four questions has
been answered and built, and the rest are marked in §Open.

The cursor is game art, not the OS pointer. Five images live in `assets/interface/`, are
preloaded as constants on `RTSController`, and are swapped by `_apply_cursor`.

---

## Which cursor shows — as the code has it today

Two layers, and the outer one wins.

**1. The precondition of the armed command**, checked every frame in `_process` against the
whole selection (`selection_precondition`):

| `PreconditionFailureCause` | cursor |
| --- | --- |
| `NONE` | whatever the table below says |
| `COMMAND_PENDING_TOOL` | `cursor_free` — not a failure, the player has yet to pick a tool |
| positional (`INVALID_PLACEMENT`, `TARGET_NOT_SPOTTED`) | `cursor_unknown` — keep looking, this SPOT is wrong |
| anything else | `cursor_invalid` — refused wherever you point it |

The split is `MoveCommand.is_positional_failure`, read by
`RTSController._cursor_for_precondition`. See §Open item 3 for why it is one question and not
two, and why `cursor_unknown` is standing in.

**2. `cursor_evaluator(command_type, message)`**, when the precondition passed:

| armed command                         | under the pointer              | cursor             |
| ------------------------------------- | ------------------------------ | ------------------ |
| none / `MoveCommand`                  | nothing                        | `cursor_free`      |
| none / `MoveCommand`                  | a player-owned entity          | `cursor_selection` |
| none / `MoveCommand`                  | anything else (enemy, neutral) | `cursor_free`      |
| `Attack` / `AttackMove` / `FocusFire` | anything                       | `cursor_attack`    |
| `Embark`                              | anything                       | `cursor_selection` |
| any other command                     | anything                       | `cursor_unknown`   |

**The cursor follows the RESOLVED command, never a re-derived guess about the thing under the
pointer.** A click that resolved to `MoveCommand` shows a move cursor even with an entity
underneath — notably a NEUTRAL one, which `_resolve_command_class` deliberately does not turn
into an Attack. The branch used to answer `cursor_attack` for anything not player-owned, which
promised an attack the click would not issue.

`cursor_unknown` is the fallback and is doing real work by accident: every command without a
row above lands on it — `Occupy`, `Repair`, `Build`, `Assemble`, `Land`, `Rearm`, `Spot`,
`Bombard`, every sanction. See §Open.

---

## Whether the OS keeps showing it

This half has bitten twice and the mechanism is worth stating plainly.

**`Input.set_custom_mouse_cursor` looks idempotent and is not, in the wrong direction.** The
DisplayServer caches the image per cursor SHAPE. A call naming the same image for the same
shape short-circuits before reaching the platform: on macOS `cursor_set_custom_image` hits its
`cursors_cache` and defers to `cursor_set_shape`, which returns immediately because the shape
did not change. No `[NSCursor set]` happens. **Calling it every frame does not keep the cursor
asserted** — it is a no-op from the second frame onward.

**The OS reassigns the cursor behind the game's back.** macOS restores the custom one from an
NSTrackingArea registered `NSTrackingActiveWhenFirstResponder`, which is dead whenever the
window is not key. Anything taking the pointer out of the window and back can leave the system
arrow in place with nothing to correct it. On a single display in fullscreen the pointer can
barely leave; with a second monitor it crosses out and back constantly (edge panning walks it
right at the boundary). Godot's own re-application is unreliable here
(godotengine/godot#121474, #104892).

**Two things reach the platform**, and the code now uses both:

1. **A null cycle.** `Input.set_custom_mouse_cursor(null)` is the one path that erases the
   cache entry, so the call after it must rebuild the cursor and push it. `_apply_cursor` does
   this when `_cursor_needs_reassert` is set — armed by `NOTIFICATION_WM_MOUSE_ENTER`,
   `WM_WINDOW_FOCUS_IN` and `APPLICATION_FOCUS_IN`.
2. **A SHAPE change**, which is never short-circuited.

**Every shape the HUD asks for must have art registered.** `_apply_cursor` only ever touches
`CURSOR_ARROW`, so any other shape arrives with nothing behind it and the OS draws its own.
`_register_hud_cursor` gives `CURSOR_POINTING_HAND` the plain game pointer, and that is the
only other shape in use. It is the plain pointer rather than the current world cursor
deliberately: the HUD is not somewhere you attack.

> **The expensive lesson.** The pointing hand on HUD buttons was first read as the *bug* — a
> stock shape with no art, replacing the game cursor whenever the mouse crossed a button — and
> removing it made things much worse. Flipping between two shapes had been re-asserting the
> cursor many times a second during ordinary play, and that accident was the only thing
> repairing what the OS kept stealing. **The pointing hand was load-bearing by accident, and
> the accident was masking the real defect:** nothing in the game re-asserts the cursor on a
> schedule the OS cannot undercut.

`tests/test_CursorArt.gd` holds the shape/art pairing.

---

## Open

### 1. Why it goes plain — the leading hypothesis is a COORDINATE MISMATCH, not the OS

**Answered 2026-08-28, and the answer moved the diagnosis.** Every scenario the macOS
tracking-area story predicted was ruled out: it happens with no second monitor, before any
alt-tab, always fullscreen, and without the pointer leaving the window. What was reported
instead:

> there seems to be a small bounding box at the centre of the screen where the cursor updates
> (hovering a friendly unit changes it); outside that area it goes plain. Worse with an
> external monitor plugged in.

**A bounded region where the cursor works is not what the OS stealing it looks like** — that
would be time-based and total, not positional. It is what a mismatch between two coordinate
spaces looks like, and this project has exactly the setup that produces one:

| setting | value |
| --- | --- |
| `window/size/viewport_width` × `height` | 1920 × 1080 |
| `window/stretch/mode` | `canvas_items` |
| `window/size/mode` | `4` — EXCLUSIVE FULLSCREEN |
| `window/stretch/aspect` | unset, so Godot's default |

The viewport is a fixed 1920×1080 (16:9). The window is whatever the display is — and a
MacBook panel is 16:10, so under a `keep` aspect the rendered content is a CENTRED rectangle
with letterbox bars. A custom cursor applied in one space while the pointer is tracked in the
other gives a centred region where the two agree and everything outside it plain. **Retina
backing scale and an external monitor both change the ratio between the two spaces, which is
exactly why plugging one in makes it worse.**

This is a hypothesis, not a finding. It is testable and the instrument is built:
`CursorDebugReadout` (shown with the debug view, `show_debug_info`) prints the viewport size and mouse, the window size
and mouse, the content-scale settings and the screen. **Walk the pointer to the boundary and
read both position lines:**

- the two positions **agree** at the boundary → not a mismatch; the OS really is dropping the
  cursor, and the re-assert policy below is the problem after all
- they **diverge**, or the viewport mouse stops changing → a mismatch, and the boundary's
  numbers say which pair is wrong

Cheap experiments, in the order worth trying: set `window/stretch/aspect` to `expand`; run
windowed (`window/size/mode = 0`); set `window/stretch/mode = disabled`. Any of the three
making the box vanish identifies the space that is wrong.

**TODO — the re-assert policy is still unsettled** and stays open behind this. Three window
notifications (`WM_MOUSE_ENTER`, `WM_WINDOW_FOCUS_IN`, `APPLICATION_FOCUS_IN`) is a guess at
when the cursor is lost, not a rule. But it is now the SECOND suspect, not the first, and
building a heartbeat before the geometry is understood would paper over the real defect.

### 2. TODO — `cursor_unknown` as a catch-all, deferred deliberately

**Answered: fine for now, to be revisited.** It has since taken on a second job (below), which
is worth knowing when it is revisited: the catch-all and "aim elsewhere" are now the same
image and want separating together.

### 3. Refused versus unaimed — DONE

**Answered: yes, distinguish them.** Built. The classification lives with the enum
(`MoveCommand.POSITIONAL_FAILURE_CAUSES` / `is_positional_failure`) rather than in the HUD,
because it is a fact about the cause; `RTSController._cursor_for_precondition` reads it.

**The rule: does moving the pointer change the answer?**

| cause | cursor | reading |
| --- | --- | --- |
| `NONE` | per the table above | — |
| `COMMAND_PENDING_TOOL` | `cursor_free` | not a failure; the command is waiting on a tool |
| `INVALID_PLACEMENT`, `TARGET_NOT_SPOTTED` | `cursor_unknown` | keep looking — this SPOT is wrong |
| everything else | `cursor_invalid` | give up — no amount of aiming conjures energy, a prerequisite, a charge or a free pad |

That is the only question a player actually asks of a refusal, and both halves used to answer
it with the same red X.

`cursor_unknown` is a **stand-in** here, not a choice: it is a plain pointer in another colour,
which reads as "keep pointing, not here", and it costs no art. "Aim elsewhere" wants its own
image — tracked with item 2, since they are the same picture doing two jobs.

### 4. REJECTED — more than one HUD cursor shape

One cursor serves the whole HUD (answered 2026-09-24); a disabled button, a drag handle and a
resize edge get no shapes of their own.
