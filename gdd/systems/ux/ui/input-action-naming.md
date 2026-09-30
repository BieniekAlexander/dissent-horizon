---
title: Input action naming
type: system-note
---

# Input action naming

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**DONE.** `command_additive` → `modifier_additive`, `isometric_camera_select` →
`world_select`, `move` → `command_issue`, and `purchase_requisition` removed outright (the
modifier replaces it — see
[macroeconomics/requisition-as-a-modifier](../../macroeconomics/requisition-as-a-modifier.md)).
The rule below is what the names now follow; the exception near the end is the one place
they do not. Guarded by `tests/test_InputActions.gd`. Current control surface:
[control-matrices](control-matrices.md).

## The rule the names should follow: a prefix names the ROUTE, not the topic

The project already behaves this way; it has just never been written down, which is how
two actions ended up misfiled.

| Prefix | Means | Enforced by |
|---|---|---|
| `command_*` | goes to the command dispatcher | `RTSController._unhandled_input` routes every action with this prefix to `_dispatch_command_hotkey` |
| `command_cell_*` | a POSITIONAL grid key: runs whatever is drawn in that cell | `ControlBinding.CELL_ACTION_PREFIX` |
| `modifier_*` | POLLED at use time, never dispatched | convention only |
| `isometric_camera_*` | consumed by `RTSCamera3D` | convention only |
| everything else | one-off, handled by an explicit branch | — |

`RTSController.MODIFIER_ADDITIVE` now exists beside `MODIFIER_NARROW` and
`MODIFIER_BROADEN`. That, rather than the rename, was the actual defect: the string had
been written as a literal in seven files, which is what made a rename a text sweep instead
of one edit. The latch member is `additive_latched` — named apart from the POLLED read in
`_purchase_defers()`, a distinction the old single name hid.

`card_toggle_family` documents this rule in a comment already — it is deliberately not
`command_*` because the dispatcher would swallow it. `modifier_narrow` and
`modifier_broaden` avoid the prefix for the same reason. Under that rule exactly two names
are wrong.

## What was renamed, and why each was wrong

**`command_additive` → `modifier_additive`.** Misfiled by the rule above: it is a
polled/latched modifier, not a command, and it was caught only by an explicit branch
sitting *above* the `command_*` dispatcher — luck of ordering rather than design. Its two
siblings already avoided the prefix for that exact reason. The second argument is the
user's: not everything it modifies is a command, since selection is additive too.

**`isometric_camera_select` → `world_select`.** `RTSCamera3D` never read this action at
all. Its only readers were `RTSController` (the box-drag press, release and per-frame
release poll) and player-facing copy. The camera owns
`isometric_camera_left/right/up/down`, `_rotate_*`, `_zoom_*` and `_drag`; `_select` sat in
that namespace by accident of history and implied a reader that did not exist.

**`move` → `command_issue`.** It was never a move: the action resolves to Attack,
AttackMove, Interact, Occupy, a build placement or a sanction cast at least as often. It
is also the one name that breaks the prefix rule — see §The exception below.

**`purchase_requisition` — removed, not renamed.** The additive modifier replaces the mode
it toggled.

**The `{{ }}` placeholders in scene-authored copy were safe to move** because
`test_ControlBinding` fails on a placeholder naming an action that does not exist; a missed
one is caught by the suite rather than shipping as literal braces in a dialog.

## The UI-click question is answered by the code, differently than expected — and is STILL OPEN

The framing was: *maybe clicks on command cards should be governed by a different action
than the world's left-click.* **They already are — but by nothing.**

No HUD control reads an InputMap action for its clicks. `BaseButton` reacts to
`MOUSE_BUTTON_LEFT` internally; `ButtonSpec` wires its alternate handler to
`MOUSE_BUTTON_RIGHT` directly; `CommandableCard._gui_input` and `Minimap._gui_input` match
raw `MOUSE_BUTTON_*` indices. So the split the user wants exists in behaviour and is
expressed as a hardcoded button index in five files, which is the actual problem: **the UI
half of the pointer has no name at all**, and cannot be rebound. Option 1 is what shipped.

That leaves three genuinely different destinations, and the choice is a scope decision
rather than a naming one:

1. **Name the world half only.** `world_select`, as now; the HUD keeps
   raw button indices. Smallest change, and honest — the two halves *are* different
   mechanisms, and pretending otherwise is what the current shared name does.
2. **Name both halves, constants only.** Add `ui_primary` / `ui_alternate` as constants
   next to the raw indices (not InputMap actions), so the HUD's button choice is written
   once. Rebinding still impossible, but the code stops repeating `MOUSE_BUTTON_LEFT`.
3. **Name both halves as real actions.** `world_select` and `ui_primary` /
   `ui_alternate` in the InputMap, with the HUD refactored to test
   `event.is_action_pressed(...)` instead of button indices. This is the only version
   where a rebinding screen can reach HUD clicks — but `BaseButton`'s own press handling
   cannot be driven by an action without giving every button a `Shortcut`, so it is
   substantially more work than it sounds.

**Recommended: 1 now, 2 alongside it, 3 only if a rebinding screen is actually built.**
The game has no settings system at all yet (`RTSController.camera_follow_selection` is
noted as a preference with nowhere to live), so option 3 buys a capability nothing can
currently expose.

## The exception the prefix rule now carries

`command_issue` breaks the rule stated above, knowingly. `command_*` means *routed to the
grid hotkey dispatcher*, and `command_issue` is a pointer button — it is handled by an
explicit branch placed **above** the prefix test in `RTSController._unhandled_input`.

Move that branch below the prefix test and right-click silently stops issuing orders and
starts pressing whatever sits in a command cell: both are legal code and neither errors.
`tests/test_InputActions.gd::test_command_issue_is_handled_before_the_prefix_branch` pins
the ordering for exactly that reason.

The name was chosen anyway because it is accurate where `move` was not: the action resolves
to Attack, AttackMove, Interact, Occupy, a build placement or a sanction cast at least as
often as it resolves to a move. The alternative — reading the prefix as a topic rather than
a route — would have cost the rule that keeps modifiers out of the dispatcher, which is
worth more.

## `command_armed_issue` and `command_armed_cancel`

Two more names that begin `command_` and are not grid commands. They are what the controller reads
for "carry out / put down the armed order", sourced at runtime from `world_select` and `command_issue`
by the control scheme ([control-matrices](control-matrices.md) §Armed-order scheme). They are handled
above the prefix dispatcher for the same reason `command_issue` is.

## What is still open

The UI-click question above is **unanswered and unbuilt**. `world_select` names the world
half; the HUD half still matches raw `MOUSE_BUTTON_*` indices in five files and has no name.
Option 2 (constants beside the raw indices) remains the cheap recommendation; option 3 waits
on a rebinding screen the project has no settings system for.

