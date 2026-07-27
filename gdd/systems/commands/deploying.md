---
title: Deploying
type: system-note
---

# Deploying

A unit that can **deploy** plants itself where it stands: a timed transition, then a stance
it holds until it is told to **undeploy**. It is the pseudo-static of
[static-defence](../../design-framework/static-defence.md) — a unit that commits to a spot for a
bonus, keeping the option to leave. A doc opts a piece in with
`deploys: {time, undeploy_time, cancellable}`; every sub-key is required.

This is not the two-form transformer (`Entity.deploy`, [composition-rework](../authoring/composition-rework.md)
§Step 1), which trades a unit for a structure on a validated footprint. A deployed unit stays
a unit, and **claims no grid cells**: it switches its locomotion off and broadcasts its
avoidance obstacle on the STANDING channel, which every agent of every team steers round
one-sided (`AvoidanceAgent3D.STANDING_OBSTACLE_BIT`).

## The four stances

`MOBILE → DEPLOYING → DEPLOYED → UNDEPLOYING → MOBILE`. The Deploy and Undeploy commands ARE
the transitions: each holds its unit for the transition's time and then ends.

- **Deploying and undeploying**, the unit cannot move and **its weapons are offline** — it picks
  no fights and runs no other order.
- **Deployed**, it cannot move and fires as a turret (it has no facing to wait on).
- A stun pauses a transition; it does not reset it.

## What a deployed unit gains

**Its armour steps up one class** (LIGHT → MEDIUM → STRONG, capped), on the tick the deploy
finishes, and steps back down the moment an undeploy begins — the bonus is paid for by being
planted.

TODO: the armour step is a placeholder so that deploying has a reason to exist; what each
deploying unit really gains is undecided. Rule to keep: the deployed bonus never matches a true
static's efficiency per cost.

## Which orders a deploying unit takes

Every order enters a Commandable at one point (`Commandable.update_commands`), and a deployable
unit judges it there against the form it will be in when the order runs — its PROJECTED form,
walking the queue it would join. The rules:

1. **An order that relocates the unit is dumped if the unit will be planted when it runs** — a
   plain move, attack-move, patrol, defend or occupy. So a move queued behind a Deploy, or given
   to a deployed unit plainly or queued, is ignored; one queued behind an Undeploy is kept.
2. **A transition is never interrupted by an order.** An order given without the additive
   modifier replaces whatever was queued BEHIND the transition, not the transition itself, and
   rule 1 then applies to it.
3. **Except a cancellable deploy.** A piece whose `cancellable` is true abandons a deploy still
   in progress when it is given a plain move or attack-move without the additive modifier, and
   takes that order as a mobile unit. Nothing else cancels it, and an undeploy is never
   cancelled.
4. A Deploy given to a unit already planted (or heading there) is a no-op, and so is an Undeploy
   given to one that is mobile.

TODO: rules 2 and 3 settle three cases the brief did not — an Attack or Stop given plainly
while deploying (waits behind the deploy rather than being dumped), a plain move given while
UNDEPLOYING (waits and runs once the unit is mobile, rather than being dumped), and weapons
being offline while undeploying as well as while deploying. Each is a choice to confirm. So is
the undeploy time: the unit docs give 1 s, against a later "3 s in all cases" that was read as
the deploy alone.

## The command card

Deploy and Undeploy are one button in two states, on the Land cell (Z). A unit offers the one
for the form it is heading for, so:

- a selection with **any** unit not yet planted draws **Deploy**, and pressing it deploys those
  and leaves the planted ones alone;
- a selection that is **all** planted draws **Undeploy**.

Both outrank Land in that cell: while Deploy is drawn, Z issues Deploy alone, and no aircraft in
the selection is told to land (`ControlBinding.wins_its_cell`).

## Known gaps

The standing obstacle is RVO avoidance only, deliberately: paths are not re-planned around a
deployed unit, so a column ordered straight through one steers round it locally rather than
routing round it.

TODO: a crushing vehicle's avoidance exemption (`set_crush_excluded_obstacles`) works per
commander channel, and a planted unit is on the shared standing channel — so a truck that could
crush a deployed unit steers round it instead.

TODO: the CPU commander never deploys or undeploys.

TODO: the Sharpshooter (`an_bioLight_antiBio`) is described as deploying with a weapon usable
only while deployed; neither that weapon rule nor its 15-unit reach (no reach bucket is 15) is
built.
