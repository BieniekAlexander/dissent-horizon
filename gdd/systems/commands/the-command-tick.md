---
title: The command tick
type: system-note
---

# The command tick

`CommandReceiver._process_commands` is one tick of the active order. The five-step lifecycle
itself is in `CLAUDE.md` §Command system, which is load-bearing enough to stay there; this
note is what that summary leaves out.

**The command decides WHERE; locomotion decides HOW.** Each tick the receiver sets the actor's
goal — the place, whether to stop there or pass through (only the final queued destination of
a non-attack, non-patrol order stops), and the unit being followed — and `Locomotion.tick`
steers, brakes, or holds against a followed unit. What the ORDER does on arriving (end, keep a
follow, chain the next waypoint) stays here; what the BODY does with nothing left to do is
`Locomotion.settle` — stop, or for a unit that cannot stop, circle the last goal. See
[authoring/composition-rework](../authoring/composition-rework.md) §Locomotion is bigger than
`Movement`.

---

## Three things suspend command processing entirely

Before anything else, `_process_commands` may stop the unit dead and return. Three states do
it, and they are the same rule three times: **the order is KEPT, not refused.**

| State | Why it stops |
|---|---|
| **Stunned** (`Commandable.is_stunned`) | a total stop — no reactive `get_updated_state` swap, no `can_act`/`fulfill_action`, no movement. Unlike stagger, which blocks only opt-in actions and never movement |
| **Still under construction** (`not is_built`) | a half-built barracks trains nothing; the same rule for every other command |
| **Still under a canopy** (`Movement.is_parachuting`) | tipped out of an air transport and floating down, with no say in where it goes |

Keeping the orders is the point in all three. A player queueing work at a building while it
goes up gets exactly what they asked for the moment it finishes — which is already how
training behaves, since `Production.tick` is gated on `is_built`. A squad dropped onto a
rally point walks off the instant it lands rather than standing about waiting to be told
again.

**Without the `is_built` gate a defensive structure opened fire while it was still a
foundation** — a SAM shooting down aircraft at 10% health was the case that surfaced it.

---

## A fixed wing does not stop when it acts

Every other actor zeroes its velocity when it acts. An aeroplane cannot
(`Movement.can_hold_still()` is false for FLYING), so the ACT branch has three outcomes
rather than one:

1. **`can_hold_still()`** — stop. The ordinary case.
2. **The command still wants movement** — keep driving it. It flies at its target, fires as
   it closes, passes over and comes around; that overshoot IS the attack run. Without it the
   Drake halted in mid-air the instant its rockets came into range. Still gated on the
   command WANTING movement: a rearm taxiing to its pad acts every tick and must not be
   driven anywhere, or the aircraft goes straight back off the deck it is parking on.
3. **Acting with nowhere to go** — fly a circuit over the spot. This is what a plain move
   does on arrival; the difference is that this order STAYS, so it never reaches the arrival
   branch that sets the orbit up. **`Defend` is what exposed the gap**: its `can_act` goes
   true the moment the unit reaches its post, and `can_act` is tested BEFORE `should_move`,
   so an aircraft on station fell between the two and coasted to a halt in mid-air — while
   the same aircraft given a plain move to the same point orbited correctly.

Outcome 3 is safe for the docking states, which also act without wanting movement: orbiting
is suppressed outright while a unit is not AIRBORNE (`compute_orbit_velocity`), and
`set_velocity` is ignored while it is landing or parked.

---

## A target that LEAVES THE PLAY SPACE takes its order with it

**A command whose target still exists but no longer has a place in the world is dropped,
before anything else in the tick looks at it** (`CommandReceiver._target_has_left_play`).

Garrisoning is the case that matters. `Garrison.garrison()` removes the occupant from the
scene tree outright, so nothing can *acquire* it — but an order issued BEFORE it boarded still
holds the reference, and an off-tree node reports `global_position` (0, 0, 0). Since
`CommandMessage.position` reads the target's position whenever a target is set, the order
silently becomes **"go to the world origin"**.

That is not hypothetical: the Colonial stock truck captures infantry by running them over, so a
truck ordered at a trooper ran it down, took it aboard, and then set off for the middle of the
map with an order that still looked perfectly valid.

**This is the missing half of `_end_after_follow_target_died`**, which is the same rule for a
target that DIED. Taken alive looks identical from the outside and is just as un-actionable,
and the two had drifted apart because only one of them had ever happened.

Two deliberate limits:

- **Death is left to the paths that already handle it.** Every command handles a freed target,
  and a flying actor's orbit-on-death anchoring lives in that path; reporting death here too
  would change how a death is handled, which is a different behaviour.
- **Only a `Commandable` can be off the field.** A non-Commandable `Entity` target — an
  extraction site, say — has no such state and always reads as in play.

The queue is not disturbed: `_drop_command` clears the current order and `_update_state`
promotes the next one on the following tick, so a truck carrying a route of two targets loses
only the leg whose target it just swallowed.

Tests: `tests/test_TargetLeavesPlay.gd` (7 tests; 3 of them go red if the guard is removed).

## A dropped command anchors before it clears

When `get_updated_state` returns null — target died, left aggro range, command fulfilled —
a FLYING unit anchors its orbit on the command's LAST-KNOWN destination before the command
is cleared, so the circuit starts around where the action ended rather than around wherever
the unit happens to be.

**TODO — the RVO idle-velocity experiment.** A grounded unit that goes idle is fed a ZERO
velocity rather than simply stopping to call `set_velocity`. Without that, its last non-zero
velocity lingers in the avoidance simulation and nearby movers steer around a "ghost"
heading instead of treating it as the stationary obstacle it now is.

The caveat, and the reason this is still marked: zeroing also lets RVO compute a possibly
non-zero avoidance velocity FOR the idle unit, which `_on_velocity_computed` then applies —
so idle units may drift aside when a mover pushes into them. That is in tension with
"enemies don't get out of the way". If it reads wrong, the fix is to keep feeding 0 here but
suppress *applying* avoidance velocity for commandless units in
`Commandable._on_velocity_computed`.

---

## An INTERRUPT keeps the queue; an ordinary order replaces it

An order given without `modifier_additive` clears what the actor was doing: the player has
said "forget that, do this". **A few orders are not a change of plan but a thing to do ON THE
WAY**, and those opt out through `MoveCommand.is_interrupt()`:

| | active command | rest of the queue |
|---|---|---|
| ordinary, no modifier | replaced | **cleared** |
| ordinary, `modifier_additive` | untouched | appended to |
| **interrupt**, no modifier | replaced, and the old one goes to the **front of the queue** | kept |
| interrupt, `modifier_additive` | untouched | appended to — an interrupt is the NON-additive version of keeping the queue, so the modifier already does what it needs to |

`Evacuate` is the only one today and is the case that prompted it: a transport with a route
queued, told to turn its garrison out, should do that and then carry on along the route.
Losing the route means re-issuing it after every drop-off.

Defaults FALSE, so every existing order keeps the standing behaviour. The mechanism is
`CommandReceiver.update_commands`'s PREPEND path, which is the same one a reactive command
swap and a deferred rearm already use — **it is now keyed on `a_prepend` alone** rather than
on `a_add_to_queue and a_prepend`, because an interrupt issued without the modifier is not
additive and gating on both made "keep the queue" and "append" the same flag.

Tests: `tests/test_InterruptingCommands.gd`.

## A command that fires on the press never stays armed

Holding `modifier_additive` while issuing an order normally keeps the armed sub-mode and tool
in hand for the next click — that is what lets five sites be laid out with five clicks (see
[ui/control-matrices](../ux/ui/control-matrices.md) §Context 1). **But only an order that WAITS
for a click has anything to stay armed for.**

`RTSController._arming_should_end` therefore ends the arming whenever
`requires_position()` is false, modifier or not. `Stop`, `Evacuate` and `Train` all fire the
moment they are pressed, so leaving one armed would leave the controller in a sub-mode the
player cannot spend and did not ask for — and the next right-click would re-fire it instead of
resolving normally. Additive on such an order means only "append it to the queue", which it
has already done by the time this is asked.

## Stagger suppresses the action, never the movement

A hit staggers the actor. If the active command's action opts into stagger (`Build`,
`Repair`, PLANT interactions — `MoveCommand.blocked_by_stagger`), the action is suppressed
and the unit holds position until it wears off. Movement itself is never stagger-blocked, so
a staggered actor still closes on its target normally.

### It also suppresses HEALING, on the patient's side

The rule above is about what a staggered ACTOR may do. There is one thing a staggered piece
may not have done TO it: **it cannot be healed while it is staggered.** A unit under fire
cannot be mended through the fire, so `Defense.restore` refuses outright and reports the
patient as "not full yet" — which keeps the mender standing by rather than dropping its
order and walking away.

It is enforced on `Defense.restore` rather than at each mender, because that is the one door
every one of them goes through: the `Repair` command, a `HealAOE` aura, and whatever is
added next cannot come to disagree about it. **Construction is not healing** and is
deliberately outside this: `Commandable.advance_build_progress` writes `hp` directly, so a
half-built structure taking fire still rises as its builders work — the builders' own
`blocked_by_stagger` is what answers a hit on THEM.
