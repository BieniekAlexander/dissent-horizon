---
title: Control matrices
type: system-note
---

# Control matrices

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Every place a pointer button can be pressed, crossed with every modifier, and what each
cell does **today**. The point of writing it as a matrix is the empty cells: an unused cell
is a control the game already has and has not spent, and the only way to see one is to draw
the grid.

Derived from the code, not from intent. Where the table says *unused*, nothing reads that
combination; where it says *leaks*, something else reads it that probably should not.

## The axes

**Buttons.** Four pointer inputs are bound, and only three of them are modifiable:

| Action                              | Binding          | Owner                                                                                    |
| ----------------------------------- | ---------------- | ---------------------------------------------------------------------------------------- |
| `world_select`                      | LMB              | `RTSController` only — it was `isometric_camera_select`, and `RTSCamera3D` never read it |
| `command_issue`                     | RMB, and `M`     | `RTSController._unhandled_input`, `Minimap._gui_input`                                   |
| `isometric_camera_drag`             | MMB              | `RTSCamera3D._input`                                                                     |
| `isometric_camera_zoom_in` / `_out` | wheel, `=` / `-` | `RTSCamera3D`                                                                            |

**Armed-order scheme.** Unarmed, the two buttons never change: `world_select` selects and
`command_issue` gives the default order. What they mean once an order is ARMED is a setting,
`ControlScheme.Kind`, read through two actions the code uses instead of the buttons:

| Action | `CLASSIC` sources it from | `ARMED_SWAP` sources it from |
|---|---|---|
| `command_armed_issue` — carry out the armed order | `command_issue` (RMB, `M`) | `world_select` (LMB) |
| `command_armed_cancel` — put it down | `world_select` (LMB) | `command_issue` (RMB, `M`) |

`ARMED_SWAP` is the scheme most RTS games use and is faster for players who know it; `CLASSIC` is
the one this game shipped with and reads more naturally to a newcomer, so both stay. The default is
hardcoded to `ARMED_SWAP` (`ControlScheme.active`); **TODO — read it from settings and expose it in
the options menu**, when the game has either. `ControlScheme.apply` copies the source button's events
onto the armed actions at startup and whenever `active` changes, so a rebinding of a button carries
through. The armed actions ARE named `command_*`, so like `command_issue` they are handled in
`RTSController._unhandled_input` ahead of the grid hotkey dispatcher. The minimap follows it too: while an order is armed, its
armed-issue press orders at the clicked world point and its armed-cancel press puts the order
down (`Minimap._handle_armed_press`); unarmed it keeps right click = order, left drag = box-select.
Tests: `tests/test_ControlScheme.gd`, `tests/test_MinimapArmedClicks.gd`.

**Placement rotation.** Two keys, only meaningful while a Build tool is armed:

| Action | Key | Effect |
|---|---|---|
| `rotate_left` | `[` | turn the structure being placed a quarter turn counter-clockwise (seen from above) |
| `rotate_right` | `]` | a quarter turn clockwise |

Neither is named `command_*`: they turn a placement rather than order anything, so they stay out of
the grid hotkey dispatcher, for the reason `modifier_narrow` does. With a tool armed `command_armed_issue`
is also a GESTURE — press sets the structure down, drag turns it, release orders it — described in
[construction](../../commands/construction.md) §Placing and turning a structure.

**Modifiers.** Three, all held rather than latched as gestures:

| Action | Key | How it is read |
|---|---|---|
| `modifier_additive` | Shift | LATCHED in `_unhandled_input` (`additive_latched`) **and** polled in `_purchase_defers` |
| `modifier_narrow` | Alt / Option | polled only |
| `modifier_broaden` | Ctrl | polled only |

**Latched versus polled is load-bearing and is a live inconsistency.** A modifier keypress
that happens while a HUD Control has focus goes to that Control, not to
`_unhandled_input`, so a latch can miss it — which is why `_purchase_defers`,
`_run_selector` and `_narrowed_actors` all poll `Input.is_action_pressed` instead. The
Shift latch (`additive_latched`) is the one modifier read both ways, and every cell
below that names it is really naming whichever of the two the call site happens to use.

**The modifiers span three key spaces, not one.** They cross a POINTER button (the
contexts below), a SELECTOR F-key (Context 4), and now a CONTROL-GROUP number key
(Context 10). Nothing is shared between the three but the modifiers themselves, and the
direction each one means is what has to agree across them: `modifier_broaden` always takes
the wider action and `modifier_narrow` always restricts. What is widened or restricted
differs per space; that it widens or restricts never does.

**Only LMB and RMB reach the HUD at all.** Godot Controls consume the mouse buttons they
handle, and every HUD control handles LMB (`BaseButton.pressed`,
`CommandableCard._gui_input`). RMB reaches exactly one kind of HUD control — a grid
button, through the `gui_input` signal `ButtonSpec` wires by hand. MMB reaches none of
them, so it falls through to `RTSCamera3D._input` and starts a camera pan **from wherever
the cursor is, HUD included**. That is the one cell that is worse than unused.

---

## Context 1 — game space, nothing armed

The default state: own units selected, no tool and no sanction armed.

|                    | `world_select` (LMB)                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `isometric_camera_drag` (MMB)                                                                                                                                        | `command_issue` (RMB)                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| *none*             | press starts a box-drag; release click-selects or box-selects, **replacing** the selection. Double-click selects every on-screen unit of that type                                                                                                                                                                                                                                                                                                                                               | pan the camera while held                                                                                                                                            | issue the resolved command at the cursor (Move / Attack / AttackMove / Interact / Occupy / **Embark**…), **replacing** the unit's orders     |
| `modifier_additive` | keep the current selection and add; clicking an already-selected own unit **removes** it; a shift-click on an enemy/neutral is ignored outright                                                                                                                                                                                                                                                                                                                                                  | *unused* (pans)                                                                                                                                                      | append the command to each unit's queue **and** keep the armed sub-mode (`_reset_pending_state` is skipped)                     |
| `modifier_narrow`  | **SET DIFFERENCE.** Whatever the click or the box caught comes OUT of the selection; everything else stays. Ten selected and a box over three leaves seven | pan at `precise_pan_factor` (0.5) | assign to ONE actor — the nearest **idle** capable actor to the target |
| `modifier_broaden` | **select every on-screen unit of the clicked type** — the double-click's reach without the timing. On a DRAG it means nothing and the box runs unmodified | pan at `fast_pan_factor` (2.0) | **the units that cannot carry the order out get a plain Move to the same point** (see below) |

Two things worth naming because they are not obvious from either the key or the tooltip:

- **Shift on a command carries a second, unnamed meaning.** `assign_command_to_units`
  skips `_reset_pending_state()` and `command_message.clear()`, so holding Shift is also what
  keeps a tool or sub-mode armed for the next click. Repeat-placement is a side effect of the
  queueing flag, not a control of its own — **and only for an order that WAITS for a click.**
  One that fires on the press (`requires_position()` false — Stop, Evacuate, Train) disarms
  either way, because it has nothing to stay armed for. See
  [commands/the-command-tick](../../commands/the-command-tick.md) §A command that fires on the
  press.
- **A few orders INTERRUPT rather than replace.** Given without the modifier, an
  `is_interrupt()` command takes over now and pushes what was running to the FRONT of the
  queue instead of clearing it — `Evacuate` is the one today. Same note, §An INTERRUPT keeps
  the queue.
- **`modifier_broaden` on a command now means "and the rest of you go there anyway".** The
  standing rule is that only units which can carry an order out receive it — right for an
  order aimed at a THING, and often not what a player means when they have told everything
  they own to go and deal with something. Holding broaden gives every other selected unit a
  plain `MoveCommand` to the same point, for ANY command rather than only the ones that opt
  in through `MoveCommand.bystanders_move()`. See
  [commands/the-click-ladder](../../commands/the-click-ladder.md) §What the members that do NOT
  receive the order do.
- **Narrow takes the whole LMB gesture rather than modifying it**, which is why it ignores
  `modifier_additive`: "remove these" has no additive reading. It overlaps with shift-clicking
  a selected unit to drop it, and that is accepted — one gesture drops one unit, the other
  drops a group.
- **The two pan factors MULTIPLY, so holding both cancels to 1.0.** That is the honest
  arithmetic for two opposite scalars, and it is why panning needs no precedence rule where
  the control-group table needs one: there, narrow and broaden name opposite WRITES and
  exactly one has to happen. A scalar can simply be 1. Both are `@export`s on `RTSCamera3D`,
  so an options-menu sensitivity setting can reach them later without moving the rule.

## Context 1a — game space, a BUILD tool armed

|                     | LMB                                     | MMB      | RMB                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------- | --------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *none*              | **CANCEL** — puts the tool down and changes the selection not at all | pan      | place the structure: submit the purchase, raise the blueprint, order ONE builder (see §Cast arity). Tool disarms                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `modifier_additive` | cancel (the modifier is not read)       | *unused* | place, REQUISITIONING an unaffordable site rather than refusing it, **and** queue the Build behind the builder's orders, **and** keep the tool armed for the next placement. Front-of-tier is retired; the rest are one idea — see [requisition-as-a-modifier](../../macroeconomics/requisition-as-a-modifier.md)                                                                                                                                                                                                                                                                                                                                                         |
| `modifier_narrow`   | cancel                                  | *unused* | send the build to one builder — nearest idle to the site |
| `modifier_broaden`  | cancel                                  | *unused* | the builders build; every other selected unit gets a plain Move to the site (Context 1) |

**A debug piece armed** arms the same way and reads the same table, minus everything about
builders, purchases and requisition: the world command places the piece directly. See [debug-mode](debug-mode.md) §The piece spawner.

### Cast arity: how many of the selection carry an order out

**The modifiers were always ABSOLUTE and the default was always meant to vary.** The axes
table above has said "whichever way the command's own default falls" since the modifiers were
written; what was missing was any command whose default was not ALL.

Every command now answers `MoveCommand.default_cast_arity(message)`, and the controller
applies the modifiers to it (`RTSController.cast_arity_for`, whose modifier step is the one
statement of the rule):

|                | no modifier | `modifier_narrow` | `modifier_broaden` |
| -------------- | ----------- | ----------------- | ------------------ |
| default **ALL**    | all     | one               | all *(no-op)*      |
| default **SINGLE** | one     | one *(no-op)*     | all                |

- **ALL** is every ordinary verb — a move, an attack, a stop. Telling a squad to advance and
  having one of them go would be absurd.
- **SINGLE** is an order that is a JOB, where giving it to the whole selection wastes the
  rest. `Build` is the shipped command case: five builders converging on one site is four
  builders not building anything else, and the co-build path exists for when the player
  genuinely wants several — by ordering them each in turn, not by one click meaning all.
- **An ABILITY defaults to SINGLE**, and that is authored per ability rather than fixed in
  code: `cast_by: SINGLE | ALL` on its `kind: AbilityDefinition` doc, read through
  `AbilityCatalog.cast_arity_of`. The default is SINGLE because the whole selection firing at
  one point spends every caster's charge on it, and a charge pool is the scarce thing an
  ability is balanced around. `spot` is the roster's one `cast_by: ALL` — a second firing
  solution on the same ground is worth having.

**Narrow is checked FIRST, so holding both keys still narrows.** Broaden then keeps the
meaning it already had in that pair — it drops the idle preference, so the nearest actor is
taken rather than the nearest idle one (see
[selection-and-input](selection-and-input.md) §The narrow modifier picks the nearest IDLE
actor). That composition predates arity and is the only way to say "that one, right there".

`Train` is exempt: a purchase is commander-global, so there is only ever one actor from the
commander's point of view and there is nothing to narrow.

**The aiming preview asks the same question.** `RTSController.armed_ability_casters` draws a
reach ring per piece that would actually fire — one when the click is SINGLE, all of the
charged casters when it is ALL — so the rings and the order cannot come to disagree. Tests:
`tests/test_CastArity.gd`.

### Left click is the universal CANCEL, and the card has three states

*Under the default `ARMED_SWAP` scheme (§Armed-order scheme) the two buttons trade places while an
order is armed: the RIGHT click is the cancel and the left issues. What follows describes
`CLASSIC`, and every other reference in this note to a click that cancels or issues an armed order
means the button its scheme sources.*

**A left click anywhere on the map puts the armed order down** — the sub-mode, the tool and
the sanction together (`RTSController.disarm_command`) — and does nothing else. It does not
box-select, and it does not touch the selection: cancelling an order is not a statement about
what you have selected. Every RTS spends the left button this way, and making a player find
the right key first is friction with nothing to recommend it.

**Arming an order takes the card over**, ahead of everything including the commander's
ORDNANCE card: every other button is something the player would have to un-arm to reach.
What the card holds while armed is **that order's own menu, plus Cancel**:

| State | Card shows | Banner |
|---|---|---|
| nothing armed | the ordinary command card | the card's own name |
| armed, still choosing | the builder's structures or the sanction's cargo, **and Cancel** | `PENDING` |
| armed and answered (`is_command_ready`) | the same menu, still on screen, **and Cancel** | `READY` |

**The menu does not close when it is answered, and that is the rule worth stating.** Picking
the wrong structure used to leave the card holding one Cancel button, so changing your mind
meant cancelling and re-opening the list. The pick is a radio button, not a door — the list
stays up and a second pick replaces the first. An order that asks nothing (every plain verb)
has no menu, so its card really is one Cancel button, which is what the old behaviour was
generalising from.

**PENDING and READY are two readings of ONE state, not two cards.** The card's contents
follow the same rule either way; what differs is where the player's next click goes — on the
CARD while it is still asking, on the MAP once it is not. That is what the banner is telling
them, and it is the whole reason the distinction is drawn at all.

**Cancel is offered while ARMED, never only once answered.** Requiring a player to finish
choosing a structure before they are allowed to cancel is absurd, and gating it on
`is_command_ready()` used to do exactly that.

**The Cancel button sits bottom-right at (5, 2), and its positional hotkey is already `N`.**
That fell out of the grid being positionally keyed — the cell's action `command_cell_5_2` is
bound to N and needed no new action at all. It is exempt from the collision review
(`ControlBinding.wins_its_cell`) because it is placed ahead of every tool and so takes its
cell whatever else claims it. Nothing does: no tool is laid out in column 5 at all.

> **TODO — the armed card's visuals.** The banner shows one word and the card shows the menu
> it already had. Alex flagged this for a later pass with elements naming the armed command
> and its tool; `CardModeBanner.ARMED_TITLES` is the stand-in.

Tests: `tests/test_ArmedCommandCard.gd`.
## Context 1b — game space, a sanction armed

|  | LMB | MMB | RMB |
|---|---|---|---|
| *none* | box-select (does not cancel the arm) | pan | fire at the clicked point (`UseSanction` to every selected caster). REFUSED while the pool is empty |
| `modifier_additive` | additive select | *unused* | queue the cast behind the caster's existing orders, **and** accept it on an empty pool — it fires when the charge returns |
| `modifier_narrow` | *unused* | *unused* | one caster only |
| `modifier_broaden` | *unused* | *unused* | no-op alone |

## Context 2 — the minimap

`Minimap._gui_input`, which matches raw `MOUSE_BUTTON_*` indices rather than InputMap
actions.

|                     | LMB                                                                                      | MMB                                                                                                                                                                                     | RMB                                         |
| ------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| *none*              | drag defines a **world-space** selection rectangle; on release it replaces the selection | centre the camera on the clicked point — **and** the camera's own `_input` starts a pan-drag on the same press, because `_input` runs before `_gui_input` and the accept comes too late | issue the armed command at that world point |
| `modifier_additive` | additive world-rect select (reads the controller's latch)                                | *unused* / leaks as above                                                                                                                                                               | queue the command                           |
| `modifier_narrow`   | **SET DIFFERENCE** over the world rect — the world-space twin of Context 1's | *unused* / leaks as above | one actor (same `_narrowed_actors` path) |
| `modifier_broaden`  | *unused* — see below                                                        | *unused* / leaks as above | the incapable units get a plain Move (Context 1) |

**The minimap runs Context 1's controls, mapped to world space.** That is the rule, and the
one exception is what makes it a mapping rather than a copy: **nothing here may key off "the
unit under the cursor"**, because a minimap pixel covers far too much ground for a click to
mean one unit. So every LMB and RMB control is expressed against world positions — selection
rectangles, command points, and eventually placements on the terrain grid.

Two consequences fall straight out of that:

- **`modifier_broaden` on LMB has nothing to key off** and stays unused here. Its Context 1
  reading is "every on-screen unit of the type you clicked", and there is no clicked type.
- **A plain minimap left-CLICK deselects everything**, because a zero-size rectangle catches
  nothing and a non-additive selection clears first. That is now INTENDED rather than a
  leftover: it is exactly what a left click on empty ground does in the world, which is what
  "the same controls, in world space" has to mean.

## Context 3 — command-grid buttons

`ButtonSpec.create_button_from_spec` gives every grid button two routes: `pressed` (LMB)
and a hand-wired `gui_input` handler that fires only on `MOUSE_BUTTON_RIGHT`. The grid has
four kinds of button and they do **not** behave alike, which is the subdivision the matrix
makes visible.

**The MMB leak through the grid is ACCEPTED, not a bug to fix.** A middle-button press over
a command button starts a camera pan from wherever the cursor is, and that is what it should
do: MMB is the camera's button and nothing else wants it (see §What the grid says). The
*leaks* cells below record the behaviour rather than complaining about it.

### 3a — verb bindings (attack-move, stop, defend, evacuate, land, bombard, abilities)

|                                        | LMB                                                                   | MMB                       | RMB                                                                           |
| -------------------------------------- | --------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------- |
| *none*                                 | run the command (fire now, or arm a sub-mode the next RMB resolves)   | *leaks* — pans the camera | **nothing**: the alternate handler returns early when `Tool.for_name` is null |
| `modifier_additive`                     | *unused* at the press; the latch is consumed later by the world click | *leaks*                   | *unused*                                                                      |
| `modifier_narrow` / `modifier_broaden` | *unused*                                                              | *leaks*                   | *unused*                                                                      |

### 3b — TRAIN tool buttons

|                                        | LMB                                                                                                                                                      | MMB     | RMB                                                            |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------------------------------------------- |
| *none*                                 | buy one, at the back of the one-off tier. REFUSED if unaffordable                                                                                        | *leaks* | buy as a STANDING order (re-issues forever, behind everything) |
| `modifier_additive`                    | buy one; an unaffordable price is REQUISITIONED — queued, funded when its turn comes (`_purchase_defers`, polled). Front-of-tier is retired              | *leaks* | standing, and requisitioned if unaffordable                    |
| `modifier_broaden`                     | **buy `BULK_PURCHASE_COUNT` (5)** in one press, stopping early at the first one the commander cannot afford | *leaks* | *unused* |
| `modifier_broaden` + `modifier_additive` | buy all five: an unaffordable one is REQUISITIONED rather than refused, so the batch lands whole and the treasury funds it in order | *leaks* | *unused* |
| `modifier_narrow`                      | *unused*                                                                                                    | *leaks* | *unused* |

**"As many as you can afford, and requisition the remainder" needed no rule of its own.** The
batch re-checks the precondition between submissions, and each transaction reserves its energy
as it lands — so an unaffordable batch stops partway. With `modifier_additive` also held the
check never fails, because `defer_if_unaffordable` is what turns a refusal into a queued entry.
Both halves are the two existing rules meeting.

### 3c — BUILD tool buttons

|                                        | LMB                                                  | MMB     | RMB                                                                                                                                                                                      |
| -------------------------------------- | ---------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *none*                                 | arm the tool; the placement happens on the world RMB | *leaks* | **identical to LMB.** The standing flag is set and then cleared inside the same call, because a repeating build has no site — so the right-click is a dead cell on this button kind only |
| `modifier_additive`                    | arm (the modifier is read later, at placement)       | *leaks* | as above                                                                                                                                                                                 |
| `modifier_narrow` / `modifier_broaden` | *unused*                                             | *leaks* | *unused*                                                                                                                                                                                 |

### 3d — cell hotkeys (`command_cell_x_y`, Q W E R T Y / A S D F G H / Z X C V B N)

A whole parallel input surface with **no button axis at all**: a key press runs the cell's
LMB behaviour and there is no keyboard equivalent of the right-click. So a standing order
cannot be given from the keyboard, and the modifier rows are exactly the LMB column above.

## Context 4 — selector buttons (`SelectorPanel`, F1 / F2 / F3)

The one context where every modifier row is spent, and the reason Alt and Ctrl are not
free.

|                     | LMB / F-key                                                 | MMB     | RMB                  |
| ------------------- | ----------------------------------------------------------- | ------- | -------------------- |
| *none*              | cycle one, least-recently-selected, replacing the selection | *leaks* | nothing (not a Tool) |
| `modifier_additive` | add to the selection instead of replacing                   | *leaks* | *unused*             |
| `modifier_narrow`   | restrict to IDLE members                                    | *leaks* | *unused*             |
| `modifier_broaden`  | take ALL of them at once                                    | *leaks* | *unused*             |

Narrow and broaden compose (all idle members), and Shift is orthogonal to both — three
axes, eight live cells. See [selection-and-input](selection-and-input.md) for why the
unmodified press is not idle-first.

## Context 5 — production-rail cards and controls

`CommandableCard._gui_input` returns immediately unless the event is
`MOUSE_BUTTON_LEFT`, so the rail has a one-cell control surface.

|                     | LMB                                                                                                                                                                                                                                                 | MMB     | RMB                                                                                                                                                                                                                                                                                                           |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *none*              | cancel the purchase (for a collapsed run, the LAST entry of it) | *leaks* | **select the PENDING unit** — the phantom this purchase will produce |
| `modifier_additive` | ignored                                                          | *leaks* | add it to the pending selection |
| `modifier_narrow`   | ignored                                                          | *leaks* | *unused* |
| `modifier_broaden`  | *unused*                                                         | *leaks* | select every pending purchase of the same piece, across the whole queue |

The rail's "clear queued" / "clear standing" buttons are plain `Button`s: LMB only, no
modifier read anywhere.

### Selecting a unit that does not exist yet

**A pending selection carries AGENCY, not just information.** Right-clicking a queued purchase
selects the unit it will produce; the card wears a green border to say so; and a command
issued while that selection is held is STORED on the purchase and replayed the instant the
unit spawns. Nothing acts on it in the meantime — there is nothing to act — and the
requisition system already carries the intent through the transaction.

**The order is stored on the PURCHASE** (`PurchaseTransaction.player_commands`), not on a
producer, because the purchase does not yet know which structure will build it and the order
was never about a structure anyway. It is read at spawn, alongside the producer's rally:

| the unit was | it does |
|---|---|
| singled out by the player | what the player told it |
| not | its producer's rally, as it stands when the unit appears |

**The player's own wins**, being the more specific statement, and a phantom nobody singled out
still follows the rally — so this is additive to the old behaviour rather than a replacement
for it. Neither is captured at submission; see
[commands/construction](../../commands/construction.md) §The rally is read at SPAWN.

**`pending_selection` is its own channel**, because every consumer of the live selection —
the command card's availability gate, the info panel, every `meets_precondition` — assumes an
entity standing in the world, so a phantom cannot join it.

**But it does NOT clear the live selection**, and that is load-bearing rather than lax. A
phantom is reached through a card drawn only while its PRODUCER (or garrison host) is
selected, so dropping the live selection destroys the card the player just clicked, empties
the panel, and leaves no sign anything was selected — it reads exactly like a dead button.
Both channels are held at once, and the command path is unambiguous about them: a right-click
goes to the phantoms whenever any are selected, which is what clicking their card asked for.
Selecting anything LIVE clears the phantoms again, which is the way back.

**The orderable window runs until the UNIT APPEARS** — PENDING, FUNDED *and* CONSUMED
(`PurchaseTransaction.awaits_its_unit`). Stopping at FUNDED made the unit ACTIVELY BEING
TRAINED the one thing on screen that could not be ordered, which is exactly the one a player
watching the progress bar reaches for. Only a completed or cancelled purchase is refused.

**A unit being trained has left the production queue**, so the rail cannot show it: it is
reached through the info panel's own job card, whose right click raises the same request. Its
orders are read from the transaction AT SPAWN rather than trusted from the copy taken when the
job was enqueued — the same "read it late" rule the rally follows, and what lets an order
given mid-training still arrive.

**The green border is repainted every frame, not on rebuild.** Both panels rebuild their cards
only when the CARD SET changes — the rail off `_build_signature`, the info panel off its own
gate — and selecting a phantom changes no card, so a border painted during a rebuild is a
border that never appears. `ProductionRail._refresh_pending_borders` and
`InfoView._refresh_pending_borders` both run unconditionally instead. **The general rule: HUD
state that follows the SELECTION cannot ride on a signature computed from the CONTENTS.** The
same mistake is available to anything else keyed that way.

Tests: `tests/test_PendingUnitOrders.gd`. Rendered by `tools/hud_panels_preview.tscn`, since a
selected chip needs both a queue and a right click — and a border bug is invisible to any test
that asks the mechanism rather than the pixels. Crop the chip using its own
`get_global_rect()`; a guessed crop proves nothing.

> **TODO — bulk cancel.** `modifier_broaden` + LMB should cancel every queued purchase of that
> type across the selection: two barracks with five recruits between them, one press. Not
> built. It wants the same "which entries match this card" query
> (`ProductionRail._pending_of_type`) that the broaden-select above already uses, so it is a
> small step from here.

**The info panel's production cards want the same treatment**, which is why Context 6 below
carries no separate specification for them: they are the same `CommandableCard` bound the same
way, and whatever the rail does they should do.

## Context 6 — info-panel cards

Three bindings on one card class, and only one of them reads a modifier.

|                            | LMB                                                 | MMB     | RMB      |
| -------------------------- | --------------------------------------------------- | ------- | -------- |
| **summary card**, *none*   | make it the sole selection                          | *leaks* | *unused* |
| **summary card**, Shift    | remove it from the selection                        | *leaks* | *unused* |
| **training-job card**      | cancel that job                                     | *leaks* | *unused* |
| **garrison-occupant card** | evacuate that occupant (inert on a closed garrison) | *leaks* | **select it**, so it can be ordered before it comes out (`modifier_additive` adds) |

**The summary card's Shift is not `modifier_additive`.** It reads
`InputEventMouseButton.shift_pressed` off the event and passes it through the `activated`
signal, so it is hard-wired to the Shift KEY and would not follow a rebinding of the
action. It is the only place in the HUD that reads a modifier from an event flag rather
than from the InputMap, and it is the one thing in this note that is a defect rather than
a gap.

### Right-clicking a garrison occupant SELECTS it

An occupant card's LEFT click evacuates that one occupant; its RIGHT click selects it, so the
player can give it orders it carries out on coming out. `modifier_additive` adds it to the
selection rather than replacing.

**An order does not imply evacuation.** A garrisoned unit is off the tree and processes
nothing, so the orders simply wait; a unit that never comes out never acts on them. On
release, **its own orders win over the host's rally** — the same precedence a trained unit
gets between a player order and its producer's rally.

Why that needed no new storage: the occupant is a real `Commandable` with a real
`CommandReceiver`, which survives being garrisoned. Where a pending unit needed a slot on its
purchase, this one already had somewhere to put orders.

Full rules: [combat/garrison-and-transport](../../combat/garrison-and-transport.md) §An occupant
can be ORDERED. Tests: `tests/test_OccupantOrders.gd`.

## Context 7 — ability bar and unlock menu

The bar is one button per ABILITY that authors `hud_button: true` — not one per sanction grid
cell — so a free ability (the Bombard's battery) sits there beside the dominion-unlocked
ones and behaves identically.

|  | LMB | MMB | RMB |
|---|---|---|---|
| **deploy bar button** | select every piece that can use it and arm the ability (or fire outright when the sanction needs no target) | *leaks* | *unused* |
| **unlock menu button** | attempt the unlock | *leaks* | *unused* |
| any modifier | *unused* on both | *leaks* | *unused* |

## Context 8 — economy stack

|          | LMB      | MMB     | RMB      |
| -------- | -------- | ------- | -------- |
| readouts | *unused* | *leaks* | *unused* |

The requisition toggle that sat here, and its `purchase_requisition` key, are both retired.
Requisition is `modifier_additive` now, and the command grid's amber tint reports it while
the key is held.

## Context 9 — modal surfaces

Scenario dialogs, the help overlay and the pause menu are labelled `Button`s: LMB, no
modifiers, no alternate click. `ui_verbose` (`/`), `show_help`, `show_pause_menu` and
`show_debug_info` (`;`) are hold-or-press keys with no pointer dimension at all.

## Context 10 — control groups (number row)

`RTSController._dispatch_control_group`. Ten remembered selections on `control_group_1` …
`control_group_10` — the number row by default, with `0` standing for the tenth. No pointer
dimension at all and, for now, no HUD: the group panel is deliberately unbuilt.

The one context where a modifier decides whether the press READS or WRITES:

|                     | *no* `modifier_additive`                    | `modifier_additive`                       |
| ------------------- | ------------------------------------------- | ----------------------------------------- |
| *none*              | select the group, replacing the selection   | add the group to the selection            |
| `modifier_narrow`   | remove the current selection from the group | *unused* — reads as the cell to its left  |
| `modifier_broaden`  | set the group to the current selection      | add the current selection to the group    |

Five live cells out of six. Reading it the way the other spaces read: `broaden` takes the
wider action (put the selection INTO the group), `narrow` the restricting one (take it out),
and `additive` extends rather than replaces on every row it is read.

Two things worth naming:

- **Narrow wins when both write modifiers are held.** They name opposite writes rather than
  composing the way they do on a selector, so one has to take precedence; this is the
  table's own row order and nothing deeper.
- **The modifiers are POLLED, not latched**, for the reason the selectors poll them: a
  modifier keydown that lands while a HUD Control has focus never reaches
  `_unhandled_input`, so the Shift latch can miss it. A control-group press is a keyboard
  press like a selector's and reads them the same way.

An empty group still clears the selection on a bare press — pressing a group is a statement
about what you want selected, and "nothing, yet" is an answer. Membership is pruned on READ
rather than watched for: a group is only consulted on a keypress, so hooking every member's
`tree_exiting` would be a lot of bookkeeping for a filter.

Rules and rationale: [selection-and-input](selection-and-input.md) §Control groups.
Tests: `tests/test_ControlGroups.gd`.

---

## Two buttons are SETTLED, and are not unspent controls

The two rules that stop this note being read as a list of things to fill in:

- **MMB and the WHEEL belong to the camera, everywhere.** Neither is ever going to mean
  something else, so a *leaks* cell below is a description and not a defect. Panning from
  wherever the cursor happens to rest — over a panel included — is the correct behaviour, and
  the minimap's middle-click recentre is the one other thing the button does.
- **RMB in the HUD never duplicates LMB.** Where it has nothing of its own to do it is a
  no-op, and that is preferable to giving it the left button's job: a right click that
  sometimes means the same thing and sometimes does not is worse than one that reliably means
  nothing. Cells may be filled in later; none may be filled in with a copy.

The consequence for reading the tables: an *unused* cell on LMB or on a modifier is a control
the game has and has not spent. An *unused* cell on MMB or the wheel is not.

## What the grid says

**By modifier.**

- `modifier_additive` means one idea in three registers: *add to a set*, *append to a queue*,
  *queue a purchase or a cast you cannot yet pay for*. (*Jump a queue* was a fourth and is
  retired.) It is the only modifier read both by latch and by poll.
- `modifier_narrow` restricts, and now does so in four registers: *one actor* for a command,
  *idle only* for a selector, *set difference* for a selection gesture, and *fine control* for
  a camera pan.
- `modifier_broaden` widens, in four: *all of them* for a selector, *every on-screen unit of
  this type* for a click, *a batch of five* for a purchase, *and the rest of you go there
  anyway* for a command. It is no longer a no-op anywhere it is read.
- Every one of the three now spans all three key spaces — pointer, F-key and number row —
  carrying the same direction in each. That was the design goal the matrix was drawn to test,
  and it is met.

**By button.**

- **LMB is the universal CANCEL while an order is armed** (§Context 1a), and otherwise the
  selection button.
- **MMB and the wheel are the camera's**, by the rule above.
- **RMB is unbound almost everywhere in the HUD**, by the rule above. It is spent in exactly
  two places: a grid TRAIN button (a standing order) and a control-group button (write the
  group).

**By surface.** The command grid, the info panel, the sanction bar and the economy stack each
expose a one-button, no-modifier surface. The selector panel, the control-group panel and the
world all use more than one cell.

**Still unspent, and indexed in `gdd/deferred.md`:** pending-unit selection on the production
rail (§Context 5), garrison-occupant selection (§Context 6), and the READY state's visuals
(§Context 1a).
