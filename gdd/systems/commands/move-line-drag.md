---
title: Move-line drag
type: system-note
---

# Move-line drag

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Hold `modifier_broaden` (Ctrl; Option on macOS), press the default-order button (RMB), drag, release: the selection spreads along the line drawn
instead of fanning out around one point. Modelled on the behaviour of Beyond All Reason's
`cmd_customformations2` widget — reimplemented from that behaviour, not from its code, which is
GPL.

## The gesture

- **`modifier_broaden` must be held at the press.** Without it a right click and a right drag are
  exactly what they always were. With it, a click that never drags still issues the plain order,
  broaden's own behaviour included. Releasing Ctrl mid-drag does not cancel the line. Broaden was
  chosen because for these four orders it already does nothing: none has a precondition, so
  "everyone not carrying it out gets a plain Move" has nobody to apply to
  (`assign_command_to_units`, `_order_bystanders_to_move`).
- The press of `command_issue` that could become a line is **held back, not issued**: only the
  release says whether it was a click or a drag. Within `CLICK_SLOP_PX` (the box-select
  threshold) the release issues the order the press would have, exactly as before.
- Mouse press only. `M` issues at once and cannot drag.
- **macOS** turns Ctrl + left click into a right click, so there `modifier_broaden` is on Option (`PlatformModifiers`, `ux/ui/interface-idioms.md` constraint 1). The line gesture is Option + right drag. Not tried on a Mac.
- **A press starts a line only when** nothing is armed (armed orders are out of scope for now),
  no structure is being placed, the cursor is over **ground** rather than an entity, and it is
  not over the HUD. A press on a unit stays an order *at* that unit — Attack, Embark, Interact.
- The order is fixed at the press. A cursor that crosses a unit mid-drag cannot change it.
- Shift is not part of it. A line replaces the queue (or appends, as `modifier_additive` already
  means) exactly as a click does; there is no waypoint path for one actor.

## Which orders

`RTSController.line_capable`: a plain move, AttackMove, Patrol and Defend. Not Build, FocusFire,
abilities, Train or anything aimed at a thing. Compared by identity, so a subclass of
`MoveCommand` does not inherit a line it was not written for.

Defend's region is centred on the **middle of the line**, which is also the message position that
anything without a slot of its own points at.

## Who stands where

- **Immobile actors take no slot and are given no order.** A line is for what can stand on it.
- **One mover** goes to the end of the line.
- Otherwise `LineSlots.slots`: if the line is long enough for everyone at the spacing, equal
  intervals end to end; if not, **rows** — as many per row as the line holds, each further row one
  spacing back on the side the group came from, a short last row spread across the line.
- **Spacing** is set by the *largest* radius in the selection (`LineSlots.spacing_for_radius`),
  one number for everyone, never a per-actor sum.
- **Ground units and aircraft are laid out separately**, each group as if it were alone on the
  line. The line is reused, not shared, so aircraft do not take slots the ground group then
  leaves gaps beside. Fixed-wing aircraft that cannot hold a slot orbit it, as they do any post.
- **Assignment is deliberately cheap and makes no promise.** `LineSlots.assign` sorts actors and
  slots along the line's axis and zips them. Actors are interchangeable; nobody is guaranteed a
  place, and no optimal matching is attempted.

It is deterministic — no RNG — so a replay can record either the line or the issued destinations.
The rest of the order goes through `assign_command_to_units` unchanged: the line is only a
different producer for the `_fanned_destinations` map.

## Preview

`LineIndicator` draws the line and a marker per actor while the button is held, once the cursor is
past the click slop.

## Not built

- **TODO** Minimap drag: the minimap issues a point only (`issue_command_at_world_position`).
- **TODO** Armed orders (attack-move armed from the grid, etc.) do not draw lines yet; the owner
  has not decided whether they should.
- **TODO** Slots are not snapped to the navmesh, so a slot on a cliff or inside a wall is
  unreachable; the unit goes as near as it can.
- **TODO** The destination swap in `MoveCommand._resolve_destination_swap` may reorder a line's
  slots once a second. Harmless given interchangeable actors.
- **TODO** Recording: when the replay stream lands (`recording-and-replay.md`), record the issued
  destinations, not the drag.
- **TODO** Cursor art while dragging; the existing resolved-command cursor shows.
