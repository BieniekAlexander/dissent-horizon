---
title: Unit animation
type: system-note
---

# Unit animation

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Pieces will carry animated models, and what a model plays follows what the piece is doing. This
note owns how "what it is doing" is decided, how a kind of piece turns that into clips, and the
action badges that stand in for animation until models have any.

**The transitions are built; playback is not.** Every commandable tracks its action today and a
rig announces which clips it should be playing, but nothing plays a clip yet.

## Two questions, two halves

| Half | Answers | Where |
|---|---|---|
| `ActionTracker` | what is this piece doing? | a RefCounted on every `Commandable` (`action_tracker`) |
| `AnimationRig` + `AnimationProfile` | so what should its model play? | an optional component, with a profile per kind of piece |

The tracker is on every commandable because the action badges need it everywhere. The rig is
optional because an unanimated piece has nothing to ask it.

## An action is what the command tick actually did

**`CommandReceiver` reports the branch its tick took**, and that report is the action. A tick
that acted reports the active command's `acting_action()`, read before `fulfill_action` so a
command that finishes on the tick still reports it. A tick that moved reports `MOVING`, and
anything else reports `IDLE`. A suspended tick reports `STUNNED` if the piece is stunned, and
`IDLE` otherwise. A tick that swapped one command for another spends no time, so it keeps the
current action, and Build handing over to Assemble is still building.

A command names its own action (`MoveCommand.acting_action`, `ACTING` unless overridden):
Attack and FocusFire are `ATTACKING`, Build and Assemble `BUILDING`, Repair `REPAIRING`, and
Interact is `UNLOADING` for a deposit and `INTERACTING` otherwise. The command already knows
what it is, so a new command states its own action rather than widening a switch elsewhere.

REJECTED: an animator that re-asks `can_act` and `should_move` each tick. That doubles the
cost of the most expensive checks in the lifecycle, and it can disagree with the tick that
really ran. A stagger, for example, holds an action back after `can_act` has said yes.

**A cue is a moment inside an action.** It plays once and changes nothing about the action.
`ActionTracker.CUE_EMITTED` is sent by `Emitter.launch`, which every emitter calls, so a
weapon's shot and a Bombard's shell cue their piece on the exact tick they are launched.

## A profile per kind of piece

An `AnimationProfile` reads an `AnimationContext` (the action, health fraction, flight mode
and speed) and returns one `AnimationRequest` per model LAYER: a clip and a speed multiplier.
For a cue, it returns the requests that play once over the top. A layer is a part animated on
its own, such as a body, a rotor or a turret, so one clip never has to encode two parts.

The base plays one body clip named for the action (`idle`, `moving`, `building`…). Anything a
kind does differently is a subclass, so the detail lives in the kind it belongs to:

| Profile | Adds |
|---|---|
| `BipedAnimationProfile` | a wounded run below a health fraction |
| `HoverAnimationProfile` | a rotor layer that idles when landed and spins far faster in the air |
| `TurretAnimationProfile` | a one-shot recoil on the turret layer for every emission |

Profiles are pure and touch no node. The context is the one place that reads the piece, so a
new thing to vary on is a context field. Profiles export only scalars, because a
Resource-valued export on a Resource crashes the editor's inspector.

TODO: the biped's wounded threshold wants to be the low-health movement penalty's threshold
once that mechanic exists, rather than a second number.

TODO: a piece with two guns recoils one turret for both. Telling which gun fired needs the cue
to name its Weapon, and `Emitter.launch` is not told which Weapon fired.

## The rig announces transitions

`AnimationRig` refreshes every physics tick, emits `requests_changed` when any layer's clip or
rate changes, and emits `one_shot_requested` for each cue request. Left without a profile, it
uses the base profile.

TODO: playback. A proposal, not approved: when models carry animations, the rig hands its
held requests and one-shots to the model's AnimationTree, and its two signals are where that
work attaches.

TODO: no piece carries a rig yet. Attaching one is authoring a component and a profile on the
piece's scene. Whether it becomes a doc key waits until a second piece shares a profile.

## Action badges, until there are animations

**An action with no animation can still be seen.** `StatusVisuals` draws a badge for the
current action at the head of the status row, flashing at `ACTION_BLINK_HZ`:

| Action | Badge |
|---|---|
| `BUILDING` | a hammer (`action_build.svg`) |
| `UNLOADING` | a yellow disc (`action_unload.svg`), while the stock truck deposits captives |

A deploying unit's STANCE gets a badge the same way (`StatusVisuals.stance_badge`), read off
`Deployable` rather than the action: a flashing down-arrow while it deploys, a steady planted
bar while deployed, a flashing up-arrow while it undeploys. TODO: retire it when deploying is
animated, with the question below.

Badges show for everyone, because what a unit is visibly doing is no secret. They hide with
the unit under stealth or while planned, like every other badge
([condition-visuals](ui/condition-visuals.md)).

TODO: `REPAIRING` shows no badge. It could share the hammer or get its own, and that is
undecided.

TODO: whether a badge retires once its action is animated, or stays as a readout, is
undecided.

TODO: a structure's production is not an action, because it is not a command. Training has no
action, and so no badge and no clip.
