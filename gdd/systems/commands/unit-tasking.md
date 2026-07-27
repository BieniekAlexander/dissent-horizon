---
title: Unit tasking
type: system-note
---

# Unit tasking

*Design note for [Dissent Horizon](../../../CLAUDE.md).*

Shipped 2026-09-17 — `TaskShelter` (`scripts/interface/commands/task_shelter.gd`), the first
and so far only consumer. **TODO — the bot does not issue it yet** (`tests/test_BotCommandCoverage.gd`
lists it as a known gap); every other player-issuable behaviour below is live.

A **task** is a standing order that never completes. It watches for contextual signals and
pushes ordinary commands onto its unit's queue as they arrive; when those finish, the unit is
back on its task. **Nothing in the task's own state machine relieves the unit of it** — no
arrival, no completed errand, no missing target. Only the player replaces it.

Its purpose is [design-framework](../../design-framework/README.md) G1: a job that is a loop of
obvious errands should cost one order, not one order per errand. The first consumer is the
Colonial Stock Truck working a Shelter
([combat/colonial-dominion](../combat/colonial-dominion.md)).

## Shape

**A task is a command.** — the queue already resumes the thing underneath a follow-up,
already drives commands that deliberately do not end on arrival, and already lets a command swap
what it is doing each tick from `get_updated_state`. A task is that pattern with the ending
removed.

The alternative considered and rejected was the **tactics** rule vocabulary
([scenario-scripting/tactics](../scenario-scripting/tactics.md)), which is already
condition → action over a unit. Widening one system beats cloning it (`~/.claude/CLAUDE.md` §1.3), but tactics would have had to
gain player issuance, a target bound at order time, and per-unit arbitration before it could
carry this — three additions against a command class that already has all three.

## The Stock Truck's task

Tasked on a Shelter, a truck cycles:

| Condition | What is pushed |
|---|---|
| room aboard, a resident is available, and this truck is its commander's **earliest-tasked** truck on that Shelter | go take that resident |
| no room aboard | go to the nearest Compound that can take a deposit and is not full, deposit, then resume the task |
| nothing to do | hold — at the Shelter |

**Arbitration is by task age, not by distance.** Among one commander's trucks tasked on the same
Shelter, the earliest-issued task claims the resident; the others wait. That needs a monotonic
task sequence per commander — the production queue's `sequence` is the precedent, and its reason
is the same: positions shift, so ordering has to be stamped rather than inferred. Re-arbitrate
whenever the claim lapses: the claimant fills up, dies, is re-tasked, or the resident is taken
by someone else.

**Every failure resolves to "hold", never to "task cleared".** A resident taken by an opponent,
a Compound destroyed while the truck is en route, no Compound with room, the Shelter itself
destroyed — each drops the pushed command and leaves the truck on its task.

**A holding truck waits at its Shelter.** With no errand to push, the task itself walks the
truck back to the Shelter's approach cell and stops there. Waiting where it happened to stop
left it beside the Compound it had just emptied into, at the far end of the route from the
next resident. The Shelter is the readable answer and the exposed one; that exposure was
accepted. It applies to every hold, including a full truck with no Compound to go to.

**A direct player order REMOVES the task command from the unit's queue.** The guarantee is
against the task's own state machine, not against the player: a truck told to go somewhere is
done hauling until it is tasked again. This is the queue's existing rule — issuing a command
replaces the current one — and the alternative was rejected for producing a unit that appears to
ignore a direct instruction and silently goes back to work.

## What it needs from elsewhere

- **The Shelter's residents are readable.** `Shelter.residents()` — built as a plain read
  accessor rather than a signal: `get_updated_state` already runs every tick, so a new
  resident is seen on the next tick without anything having to announce it. A signal would
  only earn its keep the day something needs to react to an ARRIVAL rather than poll a state.
- **A Compound says whether it can take a deposit and has room.** Both questions exist on the
  garrison already (`Garrison.can_intern`, `has_room_for`/`can_garrison`).
- **The receiver keeps the task under a pushed command.** The mechanism that defers an order and
  resumes it is already there for rearming aircraft — `get_updated_state` returning a different
  command IS the general form of it (`CommandReceiver._process_commands`'s reactive-swap
  branch), so `TaskShelter` needed no bespoke queue handling of its own at all.

## Later consumers

Anything whose loop is currently hand-driven: a repair unit kept on a structure, a builder kept
on a rebuild, and the bot, whose dominion gaps are the same loop
([ai/bot-roadmap](../ai/bot-roadmap.md)). Each one is a task definition, not a new system — if
the second consumer needs a new system, the first one was written too narrowly.

## Testing

Against a synthetic Shelter, Compound and trucks built by the test, never against a shipped
scenario (`CLAUDE.md` §A unit test does not assert facts about authored content). The cases
worth pinning are the ones the state machine exists for: two trucks contending, a claim lapsing,
a full truck with no Compound to go to, and a task surviving every one of them —
`tests/test_TaskShelter.gd`.
