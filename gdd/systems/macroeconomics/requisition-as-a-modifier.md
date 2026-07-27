---
title: Requisition by modifier
type: system-note
---

# Requisition by modifier

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

This replaced the requisition TOGGLE. The queue mechanics it rides on are
[production-and-economy](production-and-economy.md); the full control surface is
[ui/control-matrices](../ux/ui/control-matrices.md); the charge half is
[commands/cooldowns-and-preconditions](../commands/cooldowns-and-preconditions.md).

## The rule

**`modifier_additive` means "add this to what I have already asked for, and address it when
you are free to."** One idea, three surfaces:

| Held while… | Effect |
|---|---|
| clicking a unit, dragging a box, pressing a selector | ADD to the selection rather than replace it |
| issuing an order | APPEND to the actor's command queue rather than replace what it was doing |
| issuing a purchase or an ability | QUEUE it when it cannot be afforded, rather than refusing it |

Those are not three features sharing a key; they are one sentence. **Being free to pursue a
command spans three conditions and the player does not have to distinguish them:** the
actor is not busy with prior orders, the actor has the charge, and the commander has the
money. Without the modifier, any of the three is a refusal at order time.

`RTSController._purchase_defers()` is the single reading, POLLED from the live input state
(`Input.is_action_pressed`) rather than read off the `additive_latched` latch. A purchase is
usually issued by CLICKING a HUD button, and the modifier keydown before that click goes to
the focused Control — a latch can miss it entirely. The reading is stamped onto
`CommandMessage.defer_if_unaffordable`, which **defaults to true**, so scenario events, the
bot's actuator and the tests keep the original always-defer behaviour without opting in.

## Resources are committed in the order the player asked

**Submission order is commitment order, globally, across every purchase the commander has
made.** If unit 1 is requisitioned to build A and then unit 2 to build B, unit 2 may be
standing on its site and ready to start — B still cannot take money before A has.

**It is a queue over COMMITMENT, not over construction.** B waits for A's *turn at the
purse*, not for A's structure to be finished. The moment A is funded, B is funded, and both
builders work in parallel.

Two mechanisms enforce it, and they are the two ends of the same rule:

- `ProductionQueue.tick()` returns on the first `DispatchResult.WAIT_FUNDS`, so an entry
  that cannot be paid for stops the pass rather than being skipped. (`WAIT_PRODUCER` is
  deliberately different and does not block — a barracks being busy is not a claim on the
  purse.)
- `_charge_on_submit` skips the debit when `_unfunded_entry_ahead_of` finds any pending
  entry ahead, so a purchase made *later* cannot quietly pay for itself first.

**Retiring front-of-tier insertion is what completed this.** While a purchase could ask to
jump its tier, "the order the player asked" was not a property the queue had — it was a
default that one modifier could override. There is now nothing that can jump the funding
queue, which is why the rule can be stated absolutely. Tests: `tests/test_ProductionQueue.gd`,
§the global commitment order.

## The HUD says it on demand instead of remembering it

The toggle, its `purchase_requisition` key and `EconomyStack`'s indicator are all gone. A
held key leaves no persistent state to display, so the answer is shown **while you ask for
it**: holding the modifier restyles the command grid, and every piece that is unaffordable
*but queueable* lights amber (`TOOL_TINT_REQUISITIONABLE`) instead of red. Still gated by
technology — a piece whose prerequisite is not even on its way stays `LOCKED`, since waiting
cannot resolve that.

`RTSController._unhandled_input` calls `_refresh_tool_affordability()` on the modifier's
keydown AND its keyup. That is the one place in the HUD where a bare modifier repaints
anything, and it is deliberate: the tint is the whole replacement for the indicator.

## What this superseded

`RTSController.requisition_mode` was a sticky toggle on `purchase_requisition` (Backspace),
with its state carried by a combined toggle-and-indicator button on the economy panel. It
was a toggle because *no modifier was left*: Shift sent a purchase to the front of its tier,
Alt and Ctrl were spent on the selector matrix, and macOS turns a Ctrl+left-click into a
right-click before the engine sees it, so Ctrl can never modify a button press. Anno 1800's
blueprint mode was the borrowed shape.

That reasoning was not wrong; one of its premises was withdrawn on purpose. Front-of-tier
was given up, which freed Shift. What was gained is that requisition stopped being a mode
you can forget you are in. What was accepted is that it is now invisible until you reach for
it — see the sacrifices below, which were all made knowingly.

## What was given up to free the modifier

Nine behaviours read the modifier before this change. All of the hard conflicts below were accepted and removed; the soft ones survive with a changed meaning.

### Hard conflicts — the same gesture, on the same click, meaning two things

**1. Train purchase → front of its tier.** `_purchase_to_front()` polls the modifier at
`submit_train`. **Removed.**

**2. Build purchase → front of its tier.** The same call on the build side, reached from
the world placement click rather than a HUD button. **Removed.** Worth stating separately
because the gesture differs: on the build side the key is held during a *world
right-click*, which is also the key that queued the order and kept the tool armed (3 and
4) — one key, four meanings, on one click.

**3. Keeping a tool or sub-mode ARMED between clicks.** `assign_command_to_units` skips
`_reset_pending_state()` and `command_message.clear()` when `add_to_queue` is true. This
is what makes shift-placement of several structures in a row work, and shift-issuing a
run of attack-moves without re-arming. **It has no name, no tooltip and no documentation**
— it is a side effect of the queue flag, and it is the sacrifice most likely to be missed
until it is gone. **Kept, but now welded to requisition:** you cannot place five affordable
structures in a row without also declaring every one of them requisitionable, and you
cannot requisition a single structure without leaving the tool armed afterwards. Accepted
knowingly — see §Known costs.

**4. Standing order + front-of-tier, together.** Right-clicking a TRAIN tool with the
modifier held gives a standing order that is *also* inserted at the front. Nothing
documents this cell; it falls out of `_on_control_button_alternate_pressed` calling
`process_command`, which reaches `_purchase_to_front` anyway. **Removed** with 1.

### Soft conflicts — survive, but change meaning

**5. Queueing a command behind existing orders.** `c.update_commands(new_cmd, add_to_queue)`
— waypoints, queued attack-moves, a build ordered after the builder's current job. Survives
*mechanically*, because deferral only bites on an order the commander cannot afford. The
two are now welded: there is no way to queue a build behind a builder's current order
**without** also opting that purchase into deferral, and no way to requisition a purchase
as the actor's **first** order. That welding is the intended reading, not a side effect —
see §The rule.

**6. Queueing a sanction cast.** `_issue_sanction` passes the same latch. Same analysis
as 5, and the same welding.

### Not in conflict — but they make the modifier mean three things at once

**7–9. Selection.** Add-to-selection on a click, on a box-drag and on a minimap
world-rect drag; toggle-remove when clicking an already-selected own unit; add rather than
replace on every selector press; and add on a double-click type-select. None of these
touch a purchase, so nothing broke. The one that commits resources is also the least
visible — a held key leaves no HUD state behind, where the toggle's whole justification was
that an amber indicator told you what mode you were in. That is the trade §The HUD says it
on demand covers.

**One behaviour reads Shift and did NOT follow the rename**, because it does not read the
action at all: the info-panel summary card's shift-to-deselect reads
`InputEventMouseButton.shift_pressed` off the event. It still works and has silently
stopped being the same control as everything else.

---

## What moved

| Was | Is |
|---|---|
| `RTSController.requisition_mode`, `set_requisition_mode`, `requisition_mode_changed` | gone; `_purchase_defers()` polls the modifier |
| `purchase_requisition` input action | gone |
| `EconomyStack._make_requisition_button`, `set_requisition_state`, `requisition_toggle_requested` | gone; the panel is readouts only |
| `_purchase_to_front()` and `PurchaseTransaction.to_front` | gone; see §Resources are committed in the order the player asked |
| `defer_if_unaffordable` stamped from a mode in `_process` | polled at the same three sites (`_process`, `process_command`, `issue_command_at_world_position`) |
| grid restyled on `set_requisition_mode` | restyled on the modifier's keydown and keyup |

**Nothing outside the HUD changed.** `CommandMessage.defer_if_unaffordable` still defaults
to `true`, and scenario events, the bot's actuator and the tests all rely on that default.
The controller is still the only thing that sets it false.

---

## The ability-charge half

Extended past money: an ability with no charge left is **refused** without the modifier and
**queued** with it. The rule and what it superseded live in
[commands/cooldowns-and-preconditions](../commands/cooldowns-and-preconditions.md); only
what is specific to this change is here.

- `Ability`, `Bombard` and `UseSanction` gate their readiness test on
  `not a_message.defer_if_unaffordable`, mirroring exactly how `Train` gates affordability
  through `Commander.get_blocking_need(type, allow_deferral)`. `PreconditionFailureCause`
  already carried `ABILITY_NO_CHARGES`, so no new vocabulary was needed.
- **The queue of ability orders needed no new machinery.** One order is one casting —
  `fulfill_action` returns null after a single shell, deliberately — so "hold a run of
  orders and fire them as charges come up" is just several queued commands, which the
  command queue has always supported. What was missing was one gate: `Ability.can_act`
  tested range alone, so a queued cast with an empty pool was DROPPED on arrival rather
  than held. `Bombard` and `UseSanction` were already correct.
- **BUILD is the same shape and was already right.** The Build verb is always available;
  what gets gated is arming a particular STRUCTURE, through
  `Build.meets_precondition` → `get_blocking_need(tool.type, message.defer_if_unaffordable)`.
  The tool button carries the gate, the verb does not.

---

## Known costs, accepted

- **Arm-repeat and requisition are welded.** Holding the modifier to place five structures
  in a row also declares every one of them requisitionable, and requisitioning a single
  structure leaves the tool armed afterwards. Accepted rather than fixed: giving arm-repeat
  its own control is a separate change and is not blocked by this one. An armed tool or
  ability is dismissed the standard way — release the modifier and left-click — the same
  gesture that dismisses an armed attack-move.
- **Requisition has no resting indicator.** You find out what is queueable by holding the
  key, not by looking. That is the trade for not being able to forget which mode you are in.
- **The Bombard's idiom now needs a held key.** Its whole design was ordering the next shell
  during the reload; that is now the modified click. See
  [cooldowns-and-preconditions §What this superseded](../commands/cooldowns-and-preconditions.md).
- **One reader does not follow the rename.** The info-panel summary card reads
  `InputEventMouseButton.shift_pressed` off the event rather than the InputMap action, so
  its shift-to-deselect is hard-wired to the Shift KEY and would not follow a rebinding. It
  is the only place in the HUD that does this. Known, not fixed.
