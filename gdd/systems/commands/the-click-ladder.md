---
title: The click ladder
type: system-note
---

# The click ladder

How a click becomes a command. `RTSController._resolve_command_class` answers it for ONE
actor; `_resolve_command_class_for_selection` then takes the most specific answer any
selected unit can actually execute.

Two questions, asked in order:

1. **Is a sub-mode armed?** A hotkey (`command_stop`, `command_bombard`, …) names the class
   outright — `HOTKEY_COMMANDS` is that table. Arming a sub-mode suppresses the ladder
   below entirely.
2. **Otherwise, what is under the cursor?** The default ladder, below.

---

## Arming a sub-mode is how you say something plainly

Every route to a plain move except `command_move` is the FALLBACK at the bottom of the
ladder, which anything more specific takes first. Without an explicit "move and nothing
else" a truck could not be told to drive *through* an enemy (there is no crush command —
crushing is what happens when it arrives) and a scout could not shadow one without opening
fire. See [saying-it-plainly.md](saying-it-plainly.md).

Two hotkeys are not in the table, because a name alone cannot express them:

* `command_attack_move` reads the cursor's target — `Attack` on a Actor,
  `AttackMove` on ground.
* `command_launch` WRITES the ability id onto the message before returning `Ability`.

Anything else — `command_tool_*` and other aliases — falls through to the default ladder,
where a producer holding a tool picks `Train`.

---

## The default ladder, and why it is in this order

| # | Branch | Taken when |
|--:|---|---|
| 1 | `Train` | the actor has `Production` and the message carries a tool |
| 2 | `Interact` | the actor's `Interactor` has an interaction for the target |
| 3 | `Assemble` | the target is the actor's own unfinished structure, and the actor can build that type |
| 4 | `Repair` | delegated to `Repair.meets_precondition` |
| 5 | `Rearm` | delegated to `Rearm.meets_precondition` |
| 6 | `Occupy` | delegated to `Occupy.meets_precondition` |
| 7 | `Embark` | delegated to `Embark.meets_precondition` |
| 8 | `Attack` | hostile, and some weapon in the actor's `Loadout` can target it |
| 9 | `MoveCommand` | everything else — a rally point for a stationary `can_rally()` host, a move for a unit |

### Branches 4–7 delegate rather than restate

Each asks its own command class whether the order would hold, and none of them re-states
that rule here. **A second copy of a rule in this ladder is a copy that rots**, and one
already had: Occupy's condition was restated, drifted from `Garrison.admits`, and resolved
Occupy for a CLOSED hold — a stock truck's cage, which refuses every voluntary occupant.
The click produced an invalid cursor and no order at all, where it should have fallen
through to a move.

Their ORDER is the interesting part, and each step of it is a trade:

* **Repair above Occupy**, gated on the target being DAMAGED. Plenty of repairable things
  are also garrisons — a safehouse, a transport — and "right-click a transport to board it"
  is too strong an idiom to lose, so Repair only takes the click when the target is
  actually hurt. An intact transport still loads; a burning one gets mended. The cost is
  that boarding a *damaged* transport needs the Occupy button rather than a right-click,
  which is the better half of the trade: mending damaged buildings is why the unit exists,
  and most of them garrison.
* **Rearm above Occupy** for the same shape of reason: an airfield may well garrison too,
  and an aircraft clicking its own airfield means "go and reload" — docking is the whole
  point of the building.
* **Rearm below Repair**, on the same reasoning: a unit that could both mend and rearm
  wants to mend a damaged airfield first.
* **Embark directly below Occupy.** The two cannot both apply unless each side would take
  the other, in which case the click reads as "I go in" — the older and stronger idiom.
* **TaskShelter has no order relative to the other four at all.** Its target is a Shelter,
  which carries neither a Garrison nor a Defense component, so it can never overlap what any
  of the above resolve for — unlike the other four, which trade off against each other on a
  shared kind of target. See [unit-tasking](unit-tasking.md).

### Attack above the rally fallback

A combatant structure (a turret) whose `can_rally()` — `Production` or `Garrison` — would
otherwise swallow the click still resolves an explicit attack order. Entities with no
`Loadout`, or whose weapons cannot target this entity, fall through to rally unchanged.

Hostility is `Entity.is_enemy_of`, the project's one definition, which requires the target
be OWNED (`commander_id > 0`) by another commander. **Neutral / world-owned entities are
therefore never attacked by a default right-click** — they fall through to move/rally.
Attacking a neutral deliberately is still available through the attack-move context.

---

## What the members that do NOT receive the order do

The standing mixed-selection rule is **"any member can offer it, only the members that can
carry it out receive it"**, and the incapable ones are left alone. That is right for an order
aimed at a THING to be done — a soldier has no business receiving a `Build`.

It is wrong for an order aimed at a PLACE. Right-clicking a friendly unit with a transport
and four soldiers selected means "everyone go there, and you pick him up", and skipping the
soldiers leaves four units standing still for an order the player plainly gave. So
`MoveCommand.bystanders_move()` lets a command ask for the other behaviour: the members that
did not receive it get a plain move to the same target.

Defaults FALSE, so every existing command keeps the standing rule. `Embark` is the one
command that opts in today. **TODO** — [control-matrices](../ux/ui/control-matrices.md) wants
this generalised to every command-issuance context, which is a separate redesign.

---

## Nothing matched

`null`, which the caller reads as "no valid command right now": the cursor goes invalid and
no assignment fires.
