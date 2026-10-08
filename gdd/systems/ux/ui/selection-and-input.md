---
title: Selection and input
type: system-note
---

# Selection and input

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*


`RTSController` is a `CanvasLayer` in `scenes/player.tscn`. It owns:
- **Selection**: box-select (drag) or click; selection stored as `Array[Node]` (Actor instances). See §Box-select drags below for the drag lifecycle — it is driven per-frame from the live cursor, not from MouseMotion events
- **`pending_command_name`**: arms a sub-mode (e.g., `"command_attack_move"` → next right-click resolves to `AttackMove`/`Attack`)
- **`_available_commands`**: recomputed via `CommandContextParser.commands_for_selection()` on every selection change; HUD button visibility and hotkey gate read from this
- **Build preview ghost**: a translucent copy of the structure's `MeshVisual` (or its `Sprite3D`, for billboard art) duplicated from `Commander.get_build_preview_instance(tool)`; snapped to the footprint centre each frame, tinted red on invalid placement
- **Blueprints**: issuing a build order raises one, via `Build.plan_structure` right after `Build.submit_purchase` — see §Planned structures. Like the purchase, it is stamped on the order's `CommandMessage` and shared by every builder's snapshot. Build orders are also the one command type EXCLUDED from the per-unit destination spread (`assign_command_to_units`): a build has a single destination — the one site — so fanning the selection out made each builder target a different cell
- **Waypoint indicators**: pooled `WaypointIndicator` nodes under Map; shown for active `CommandMessage` snapshots in selected units' command chains

`_resolve_command_class()` (static) is the central command resolution function — replaces the old `CommandContext` + `Pattern` machinery.

## Box-select drags


A drag has three moments, and only the first two are events: `begin_drag_at` on the press (over the world — a press on a HUD panel belongs to that panel), `update_drag_to` **every frame from `_process`**, and `end_drag_at` on the release.

The per-frame middle is the whole point. The bottom panels' Controls are `MOUSE_FILTER_STOP`, so a drag that crosses into the HUD stops producing `InputEventMouseMotion` at `_unhandled_input` entirely — the box used to freeze at the panel's top edge. `_update_drag` reads `get_viewport().get_mouse_position()` instead (clamped to the visible rect), which is the same reason `_pointer_over_blocking_ui` can't use the cached `mouse_position`. It also polls the action, as a backstop for a release the panel consumed before we saw it — without it the box could stay up forever.

**A drag resolves wherever it ends, the HUD included**, so a box dragged down over the command panels takes the units drawn behind them: they are under the camera, merely hidden by the overlay (`query_box_collisions` unprojects world positions, so they were always inside the rect). **A click over the HUD still resolves nothing** — that press is the panel's, and letting it through would clear the world selection on the button-up of every info-panel card.

Click vs. drag is `is_click_gesture` (`CLICK_SLOP_PX` on **both** axes). Compare per-axis, never `delta < Vector2(10, 10)`: Vector2's `<` is lexicographic, so x alone decided it, and a tall narrow drag registered as a click.

## HUD tooltips are two-tier


Every HUD button is a `VerboseTooltipButton` carrying a `simple_tooltip` and an optional `verbose_tooltip`. It renders its OWN popup rather than Godot's built-in one, precisely so it can swap tiers mid-hover: holding `ui_verbose` (/) while the popup is open re-renders it into the long version. Same hold-to-reveal idiom as `HelpOverlay` (`show_help`).

**Only the simple tier is mandatory, and it is enforced at runtime**: assigning `""`, or entering the tree never having been given one, pushes an error naming the button and substitutes `MISSING_TOOLTIP` ("TODO fill out this tooltip"). An undescribed button is therefore loud in the error panel and visibly unfinished in-game, never silently featureless. Name the button BEFORE assigning tooltips so the error identifies it.

Where the copy comes from:

| Buttons | Source |
| --- | --- |
| Verb + selector commands | authored on the `ControlBinding`s in `command_grid.gd` |
| Build/train tools | SYNTHESIZED from the piece's gdd doc into `tools.json` (§Tool wiring) |
| Ability bar | the ability's own copy (`AbilityCatalog`), or — for a dominion-unlocked one — the CELL in play: `Sanction.description` plus numbers off its sanction grid entry |
| Info-panel queue controls, dialog nav/help glyphs | authored at the call site |

Tooltip copy names keys with `{{ action }}` placeholders, resolved by `InputPrompt` when the button is built (`ButtonSpec.create_button_from_spec`) — same treatment dialog pages get, so a rebinding re-words the tooltip. `test_ControlBinding` fails on a placeholder naming an action that doesn't exist. A command has no action of its own — the CELL carries the key — so a placeholder resolves only while its command has a button, and copy naming a command that has no cell (`command_land` today) has to name none.

The labelled dialog buttons ("Continue", "Close") stay plain `Button`s: their own text is the explanation. `CommandableCard`s are Controls rather than Buttons and still use Godot's built-in `tooltip_text`.

## Cursor picking: a UNIT outranks a structure, whatever is in front

The cursor raycast used to take the nearest hit on the SELECTION layer. That is the wrong
question here: the camera looks down at an angle and structure selection shapes are tall, so a
structure routinely covers units standing behind it and made them **unclickable**.

`RTSController.preferred_cursor_entity` takes the candidates in ray order (nearest first) and
returns the first one in the `"unit"` group, falling back to the nearest non-unit. The rule is
separated from the raycast precisely so it is testable without a physics server
(`tests/test_CursorPickingAndPrune.gd`); `Map.line_hits` supplies the ordered candidates by
re-running Godot's single-result ray query with a growing `exclude` list.

**The reverse case is deliberately NOT handled.** A structure buried behind units stays
unpickable, and that is accepted: it does not happen in play, because units do not stack over a
building the way a building covers units. Do not "fix" the asymmetry — it is the whole point.

**Perceptibility filters candidates, it no longer ends the search.** A fogged or stealthed
enemy is skipped and the scan continues, so a visible unit behind an unseen one is still
pickable. With nothing perceptible along the ray the caller falls through to the terrain hit,
so a right-click resolves to a move rather than an attack on something the player cannot see.

## Selecting a piece you do not own

A plain click on an enemy's or the world's piece selects it — ALONE, for inspection. Selecting
one of your own drops it again. A box and `modifier_additive` only ever take your own pieces,
so another commander's pieces are never part of a selection you command.

TODO: outside the debug view, selecting several pieces you do not own is not supported. The
debug view allows it: see [debug-mode](debug-mode.md) §Commanding any piece.

## The narrow modifier picks the nearest IDLE actor

*Moved out of `rts_controller.gd::_narrowed_actors`.*

Which one: the NEAREST IDLE actor to the order's target, falling back to the nearest
outright when every candidate is busy. A command that goes to ONE actor by default (Build,
Spot, an ability) defines "free" as "not already on this job" rather than idle — see
[control-matrices](control-matrices.md) §Cast arity. Idle-first is what makes narrowing useful for the
case it exists to serve — keeping one builder free while the rest work — without ever
refusing the order when nothing is idle.

Holding BROADEN as well drops the idle preference and takes the nearest outright. That
is the same axis broaden means on the selector side ("all of them, not just the idle
one"), so the two modifiers compose here the way they do there rather than cancelling.
**Narrow is checked first**, which is what keeps that composition alive now that broaden on
its own means ALL — see [control-matrices](control-matrices.md) §Cast arity for the whole
table, and for the per-command DEFAULT that decides what happens with neither held.

Distance is measured to the order's target position on XZ; an order with no meaningful
position (Stop) falls back to the actors' own positions, which leaves the lead unit —
the answer being asked for is "which one", and for a positionless order any consistent
one will do.

## How a selector resolves its candidate set

*Moved out of `rts_controller.gd::_run_selector`.*

|            | cycle ONE (default)          | take ALL (MODIFIER_BROADEN) |
  | any (def)  | cycle every one you own      | every one you own           |
  | idle only  | cycle the idle ones          | every idle one you own      |

Shift (next_command_additive) adds to the selection instead of replacing it, on every
cell — a third axis, orthogonal to both.

**Every selector is GLOBAL.** Scope used to be a third axis (on screen / everywhere) and
it was dropped, because the on-screen half already has a gesture: box-select resolves
wherever the drag ends, HUD included, so "select what I can see" is a drag. That freed the
modifier this design needed, and it is what makes the camera jump load-bearing rather than
a convenience — see _look_at_selection.

The unmodified cycle takes ANY member, in least-recently-selected order — not idle-first.
Preferring idle members sounds free and is not: the precedence would be absolute, so the
cycle would never leave the idle set while one existed, making the unmodified press
identical to MODIFIER_NARROW exactly whenever that modifier would have mattered. Keeping
the filter strictly on the modifier is what keeps all four cells distinct — and it removes
any need for per-family defaults, which is what used to force the absolute-vs-relative
question here.

This retires the "recorded inconsistency" (Alt narrowing on the command side and
broadening here). The two modifiers now agree in DIRECTION across both key spaces:
MODIFIER_BROADEN means "take all" (all actors / all members) and MODIFIER_NARROW means
"restrict" (to one actor / to idle only). What is restricted differs; that it restricts
never does, which is what a player needs in order to predict either side from the other.

## Control groups

Ten remembered selections, addressed by `control_group_1` … `control_group_10`. The number
row is the DEFAULT and nothing more — **the action is the binding**, exactly as it is for the
positional command cells (`ControlBinding.CELL_ACTION_PREFIX`), and nothing outside
`project.godot` names a digit. A rebinding screen moves any of the ten without touching code.

`0` addresses group 10, so the player-facing numbering is 1–10 and the storage index is one
less. That is the only place the two disagree, and `control_group_index_from_action` is
where the conversion lives.

### The gesture is the modifiers, not the key

|                     | *no* `modifier_additive`                    | `modifier_additive`                      |
| ------------------- | ------------------------------------------- | ---------------------------------------- |
| *none*              | select the group, replacing the selection   | add the group to the selection           |
| `modifier_narrow`   | remove the current selection from the group | *unused*                                 |
| `modifier_broaden`  | set the group to the current selection      | add the current selection to the group   |

This differs from the usual RTS convention, where assigning is one fixed chord (Ctrl+N) and
adding is another (Shift+N), and the difference is deliberate: the game already has three
modifiers that mean something everywhere, so a control group reads them the way everything
else does rather than inventing a fourth idiom. **`broaden` / `narrow` decide whether the
press READS the group or WRITES it; `additive` decides whether the operation replaces or
extends.** Each of the three then carries the same direction it carries on a command and on
a selector — broaden takes the wider action, narrow restricts, additive adds to what is
already there — so the table can be predicted from the other two key spaces instead of
memorised.

Consequences worth stating:

- **Narrow wins when both write modifiers are held.** They name opposite writes, so unlike a
  selector's two they cannot compose; one has to take precedence and it is the table's own
  row order. `additive` is simply not read on that row, which is the honest way to spend a
  cell the table marks unused — better than refusing the press.
- **The modifiers are POLLED, not latched.** A modifier keydown that lands while a HUD
  Control has focus never reaches `_unhandled_input`, so the Shift latch can miss it. A
  control-group press is a keyboard press exactly as a selector's F-key is, and reads them
  the same way for the same reason (see §The axes in
  [control-matrices](control-matrices.md)).
- **A bare press on an empty group still clears the selection.** Pressing a group is a
  statement about what you want selected, and "nothing, yet" is an answer to it.
- **Only a double tap moves the camera.** One press reads the group into the selection and
  leaves the view where it is; a second press of the SAME group within `DOUBLE_CLICK_SECONDS`
  centres the camera on it, whatever was already on screen (`RTSController.is_double_tap`).
  That holds for both reading gestures and for the panel's buttons, which apply the same
  gestures. A write between the two presses breaks the pair. Before 2026-10-08 a single
  press moved the camera on the selectors' rule (only when nothing selected was visible),
  which pulled the view away on every routine recall.
- **Membership is pruned on READ, not watched for.** A group is only ever consulted on a
  keypress, so hooking every member's `tree_exiting` to keep ten arrays exact would be a lot
  of bookkeeping for a filter. A group that has lost members to the fighting is corrected by
  being used.
- **Adding is de-duplicating and order-preserving**, so a unit added to a group twice is in
  it once and the group keeps the order it was assembled in.

The gestures, the action naming and the set arithmetic are static or touch nothing but
`selection` and the ten arrays, which is what lets them be tested on a controller that was
never put in a scene tree. Tests: `tests/test_ControlGroups.gd`.

### The control-group panel

`ControlGroupPanel` draws the ten groups as a row of numbered buttons carrying a HEAD COUNT.
It is **persistent**, not selection-owned: "what have I got squadded up" is a question you
ask with nothing selected, and reaching for a group is something you do precisely because the
current selection is wrong — the same reasoning that moved `SelectorPanel` out of the command
grid.

**The panel never re-implements the group rules.** Membership, pruning and every gesture stay
on `RTSController`; the panel reads `control_group()` for the count and calls
`apply_control_group_gesture()` for a press, so a button and a number key cannot come to
disagree about what a group holds.

**Which buttons are on screen — the populated run, plus the next empty slot.** Three rules
compose into it:

1. **Group 1 is always shown**, empty or not. AUTHORED, not derived: it is the base case rule
   3 chains from, and an untouched game that shows no panel teaches the player nothing.
2. A group with members is always shown.
3. The group AFTER a populated one is shown, so there is always somewhere to assign to.

An emptied group is not remembered as having existed: when its last member dies the row
shrinks back, which is why visibility is computed from live counts every frame rather than
from a "has ever been used" flag.

**The two mouse buttons ARE the read/write axis**, which is what `modifier_broaden` spends on
the number row — so the panel does not read `broaden` at all and gets a whole modifier back:

|                     | LEFT — reads the group, acts on the selection | RIGHT — writes the group |
| ------------------- | --------------------------------------------- | ------------------------ |
| *none*              | recall: the group replaces the selection       | set the group to the selection |
| `modifier_additive` | add the group to the selection                 | add the selection to the group |
| `modifier_narrow`   | remove the group's members from the selection  | remove the selection from the group |

Every modifier keeps the direction it carries everywhere else, so the table is predictable
rather than memorised — the same claim the keyboard table makes. Narrow beats additive for
the same reason it does there: the two writes are opposites and cannot compose.

What the extra modifier BUYS is the one cell the number row has nowhere to put:
**`REMOVE_FROM_SELECTION`**, the mirror of `REMOVE_FROM_GROUP`. It edits the selection and
leaves the group alone, and it moves no camera — the player is narrowing what they already
have in hand, so nothing new has been picked to look at.

Tests: `tests/test_ControlGroupPanel.gd`. Rendered by
`tools/hud_panels_preview.tscn`, because a populated row is a state an offscreen render of a
scenario cannot reach (it needs input).

## Group destinations fan out

*Moved out of `rts_controller.gd::_fanned_destinations`.*

A right-click **drag with `modifier_broaden` held** replaces this fan-out with a line: [commands/move-line-drag](../../commands/move-line-drag.md).

A multi-unit position order gives each unit its own point scattered around the click,
rather than sending everyone to one spot. Destinations are sorted by angle around the click
point and units by angle around the group's own centroid, then zipped: two sequences swept
in the same rotational order cannot cross, so the assignment is non-crossing and
formation-preserving **by construction**. That replaced an O(N²) greedy
nearest-free-destination search, which assigned in whatever order the BFS scatter returned
and produced crossing paths.

The scatter radius is `max(MIN_FAN_OUT_RADIUS, body_radius × FAN_OUT_RADIUS_PER_UNIT × N)`.
When the scatter finds fewer points than units, the surplus units are absent from the map
and fall back to the raw click point.

**Build is excluded.** A build order has one destination by definition — the site of the one
structure being placed. Fanning it out gave each builder a different target cell, so they
raced to lay foundations a cell or two apart instead of co-building the one the player
clicked.

**FocusFire is excluded too, for a reason that only looks the same.** An order aimed at an
ENTITY keeps aiming at the entity however the destinations are scattered — `CommandMessage
.position` prefers the target over `world_position` — so fanning an Attack moves only where
the shooters stand. `FocusFire` has no target, so its aim point *is* `world_position`, and
fanning it would have each unit shell a slightly different patch of ground rather than the
one the player clicked. Nothing is lost by excluding it: the actors stop as soon as they are
in range, which is a long way short of the point they are shooting at, so they never stack.
