---
title: Cooldowns and preconditions
type: system-note
---

# Cooldowns and preconditions

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## A spent charge is refused; the modifier is what queues it

**This reverses the rule that stood here before**, and the reversal is deliberate — see
§What this superseded.

An ability with nothing left in its pool **fails `meets_precondition`**, exactly as an
unaffordable purchase does, and for the same reason: the player asked for something to
happen now, and nothing about it can happen now. Holding `modifier_additive` is what asks
for it to be QUEUED instead — the actor keeps the order and acts the moment the charge
comes up.

One flag carries it. `CommandMessage.defer_if_unaffordable` is the same field
`Train`/`Build` read for money, so a charge and a price are one idea at the call site:

| | bare click | `modifier_additive` held |
|---|---|---|
| price the commander cannot meet | refused | queued, funded when its turn comes |
| pool with no charge left | refused | queued, fired when the charge returns |

Three commands implement it — `Ability`, `Bombard` and `UseSanction` — each gating its own
readiness test on `not a_message.defer_if_unaffordable`. The flag **defaults to true**, so
scenario events, the bot's actuator and every test that predates the gate keep the old
always-queue behaviour without opting in.

## The button still only greys

`MoveCommand.actor_is_recharging(actor)` is unchanged and stays a **separate question**
from `meets_precondition`: it is asked of the ACTOR alone, with no message, so it cannot
know whether the modifier is down — and it should not. `RTSController._selection_is_recharging`
marks the grid button while every selected actor offering the command is reloading — amber,
the colour of every order that is refused unless queued (see
[command-card-and-hotkeys](../ux/ui/command-card-and-hotkeys.md) §What a darkened button means). **Every, not any** — a mixed selection where one battery is loaded
can still fire, matching `selection_precondition`'s rule that a command reads as available
as soon as anybody can act on it. Actors lacking the ability entirely are skipped, or one
Recruit in the selection would keep the Bombard button lit forever.

So the amber means *"refused unless you hold the modifier"* rather than *"accepted, will
happen later"*. `CommandContextParser.command_for_name` is the lookup that makes it
possible — the HUD holds a button, not a command, and needed the inverse of `name_for`.

## `can_act` must gate on the charge too, or a queued order is thrown away

This is the half that is easy to miss, and it was a real bug. `fulfill_action` returns null
when the charge cannot be spent, and **a null return DROPS the command** —
`CommandReceiver` sets `_command = null`. So a command whose `can_act` says "yes, in range"
while the pool is empty is not queued at all: it is silently discarded the instant the
actor arrives.

`Bombard` and `UseSanction` always gated `can_act` on readiness and so always waited
correctly. `Ability` did not — it tested range alone — which meant a queued ability with a
spent pool was thrown away rather than held. Fixed; tests in `tests/test_ChargeGating.gd`.

**The rule for any new charge-bearing command: readiness belongs in BOTH
`meets_precondition` (gated on the modifier) and `can_act` (ungated).** The first decides
whether the order may be given; the second decides whether this is the tick to act on it.

## What this superseded

The previous rule was that *a cooldown greys a button and never refuses the order* — a
recharging ability stayed unconditionally orderable, so "fire as soon as you can" was the
BARE click. The Bombard was its worked example: telling the gun where the next shell goes
while the last is still in the air.

That behaviour is not lost, it is **modified rather than default**. What was gained is that
a resource is a resource: energy, dominion and a charge now behave the same way at the
point of order, under one modifier, rather than the first two refusing and the third
quietly waiting. The accepted cost is that the Bombard's own idiom now needs a held key,
which is a real regression in convenience for the one piece built around it.

**An immobile actor is the one case a range DOES refuse.** A mobile unit walks into range, so a far-off target is just a longer order; a structure would sit on an order it can never fulfil, which reads as the ability being broken. `MoveCommand.unreachable_for_immobile(actor, message, range)` states that once, and a command with a reach calls it (`Ability` does; `Bombard` has no distance to be out of).

---
