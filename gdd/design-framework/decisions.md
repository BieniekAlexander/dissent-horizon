---
title: Decisions — the analytical spine
type: design-note
---

# Decisions

Every mechanic in this game exists to create a **decision under commitment, information,
payoff asymmetry and scarcity**. That is the level the analysis lives at. Genre vocabulary —
RTS macro and micro, the fighting-game terms — is *downstream*: it names where a decision
structure happens to show up and what a well-tested version of it looks like, never what the
thing is.

The practical use: to design a piece, name the decision it puts in front of both players, then
pick the mechanics that give that decision its shape. To critique one, ask which of the four
axes it actually moves.

Fighting games are the richest reference for this project's MICRO decisions specifically — they
are almost entirely moment-to-moment commitment under imperfect information, which is the same
problem an engagement poses. Their macro layer is thin, so nothing about long-horizon resource
planning should be sought there.

---

## The four axes

| Axis | The question it asks | Levers in this game |
|---|---|---|
| **Commitment** | how long, and how irreversibly, does this bind the player? | production and build time, channelled actions, travel time, cooldowns, stance changes, structure placement |
| **Information** | what does each side know at the moment it chooses? | fog, tells and status visuals, reaction window length, **attention** |
| **Payoff** | how large, how variable, how asymmetric? | damage tables, punish magnitude, one-shot versus attrition outcomes |
| **Scarcity** | what does the option spend, and is that resource fungible across uses? | energy, dominion, charges, hit points, position, attention |

**Attention is the scarce resource that the RTS form adds.** A fighting game gives both players
one locus of attention; an RTS makes attention a budget spent across a map, and a player's
budget per piece falls as their holdings grow. Several goals depend on this — it is why micro
that pays per unit favours the smaller army (G7), and it is why every reaction window in this
game is probabilistic where a fighting game's is deterministic.

---

## Commitment and payoff: what a startup window costs

An action's startup is an **irreversible investment made before its payoff is known**, during
which the actor cannot revise the decision. A player takes it only when

```
p_success · Gain  −  p_punished · Loss   >   the next-best safe option
```

Three design consequences follow, and they are the spine of the risk/reward relationship:

1. **A longer or more visible commitment raises `p_punished`, so `Gain` must rise with it.** An
   action that exposes you for a long time and pays little is never chosen; one that exposes you
   for a long time and pays enormously is the most interesting choice in the game.
2. **`Loss` is a separate lever from `p_punished`, and the cheaper one to tune.** Making a
   commitment *recoverable* — an aborted channel that refunds most of its cost, a charge spent
   rather than a unit spent — keeps the risk while removing the all-or-nothing outcome. This is
   the difference between a high-variance option and a coin flip.
3. **In an RTS, `p_punished` is not a property of the action.** It is
   `p(the opponent notices) × p(they have something in position)`. The designer controls the
   first through tells and fog, the second through map distances and unit speeds.

---

## Reactability: sequential or simultaneous

Whether an action can be reacted to decides **which game is being played**.

- **Reactable** — the opponent observes, then chooses. The interaction is sequential with
  observation, so the responder has a best response, and the action only profits when they read
  it wrong or cannot pay for the answer. **Such an action can safely be strong**, because its
  payoff is conditional on the opponent's failure.
- **Unreactable** — both sides effectively choose at once. The interaction is simultaneous and
  its equilibrium is mixed, in the matching-pennies sense: no pure choice is correct, so the
  outcome is a guess weighted by payoffs. **Such an action must be bounded**, or the game
  degenerates into a coin flip with a large stake.

**In an RTS the window is longer, fuzzier, and probabilistic**, because reaction requires that
the player be *looking* and *have an answer in position*. The knobs, in the order they are worth
reaching for:

- **The tell and its lead time** — projectile travel, a channel, a visible stance change, a
  structure going up. A tell that only exists on the screen the player is not looking at is not
  a tell.
- **Vision** — fog is the dial that converts a reactable action into an unreactable one. It is
  the cheapest way to make something strong, and the easiest way to turn skill into a coin flip.
- **Attention load** — pressure on two fronts does not beat a specific defence; it lowers
  `p(notice)` everywhere at once. That is this genre's version of a mixup, and it is why the
  attacker's real currency is the defender's attention.

**Rule: an action's payoff should scale with the reaction window it grants**, measured against a
player who is looking elsewhere, not one who is watching it happen.

---

## Reversal: keeping the safe attack from dominating

A defender who has no risky option lets the attacker's low-risk pressure **dominate** — there is
no reason ever to stop applying it. A reversal exists to make that pressure non-dominant: an
immediate answer that pushes the attacker off, at the cost of a window in which the defender is
exposed if the answer was baited.

Its value is mostly in **not being used**. It is a deterrent, and the interesting play is the
game of chicken around it: the attacker feints to spend it, the defender holds it as long as
they dare.

Two structural requirements:

- **The after-window must be visible to the attacker.** Otherwise baiting is a guess rather than
  a read, and the whole interaction collapses back into a coin flip.
- **The reversal must be spendable.** A continuous defensive effect is not a reversal; a charge
  is, because spending it is what creates the window.

**The Bombard is the game's reversal**, and it arrives at the shape from cooldown rather than from
a charge: it answers a push decisively, and its owner is meaningfully more exposed while it
reloads.

Three things follow, and they are what makes this concept useful here rather than borrowed:

- **Not every faction needs one.** Fighting-game characters do not all have a reversal either.
  The question is coverage, not presence.
- **A reversal here is not one-size-fits-all**, because the threats are not one shape. A Bombard
  handles a slow ground push and is useless against nimble or airborne attackers, so **what a
  faction's reversal fails to cover is a compact statement of what that faction cannot defend
  against** — which is the audit worth running ([auditing](auditing.md)).
- **Strength is modulated by reach, cooldown and mobility.** A structure has none of the last,
  which is what lets the first two be generous.

Because a reversal is at its best defensively, **it should sit early in a tech tree** — one that
arrives late has missed the period it was for.

---

## Zoning: buying space with threat rather than damage

A zoning tool **raises the price of occupying a region**. Its executed damage is almost
incidental; what it sells is the cost it imposes on standing somewhere, and a threat that is
never executed has done its whole job.

For it to be a decision rather than a wall, the opponent needs **an option portfolio at
different risk levels**: go around (pay time), push through (pay attrition), or kill the source
(pay risk). One option means a wall; three means a choice.

Design rules: low damage per second and high denial value; the denied area must be legible,
which makes it a UI requirement as much as a combat one; and the threat should persist without
being fired. Bombarded ground, persistent area effects, and a warmed lazer or a charged attack
meter are all this family — a visible threat state *is* zoning, even when nothing has been
fired.

---

## Footsies: attrition over a boundary, and why it needs a gradient

Jockeying is a **war of attrition over a contested boundary**: each side advances while the
marginal expected gain exceeds the marginal expected risk, and the player who commits first from
the worse position pays for it.

It requires that **positional value be continuous and reversible**. Where value is a step
function — in range or not, inside the radius or not — there is nothing to jockey over, only a
line to be on the right side of. Where a position is a permanent commitment, as a structure is,
the decision happens once and then stops being a decision at all.

The continuous gradients available here: range bands, vision, reinforcement distance, resource
proximity, terrain height. The discrete commitments: structures, and any radius with a hard
edge. **Prefer smooth gradients wherever dynamic positioning is the goal**, and where a
commitment must be discrete, make its value depend on what the opponent does — see
[matchups](matchups.md) and the structure rule in [README](README.md).

---

## Grappler: an option that taxes the opponent's safe choices

A grappler's function is **conditional dominance**. Once it is close, the defender's passive
option stops being safe, so they are forced into a guess they would rather not take. The
character does not need to land the throw often; the *threat* is what changes the opponent's
behaviour, and that is the payoff being bought.

Four requirements:

1. the payoff is high enough to change behaviour at range, not just when it lands;
2. **reaching the position is the cost** — the setup is the price of the option;
3. spacing and screening are the counter, so the defender has real agency;
4. the defender's escapes cost something, or the threat is empty.

Both failure modes are visible in the precedents. **Too volatile:** a cheap early suicide unit
resolves to a binary outcome before either player has the tools to play around it — high payoff,
no setup cost, no counterplay window. **Too weak:** a slow, expensive demolition vehicle
telegraphs everything and dies to any answer, so its setup cost exceeds its payoff and the
threat never taxes anyone.

**The lever that separates the two is what the option SPENDS.** A unit that spends *itself*
turns every whiff into a total loss, which forces the payoff up and the variance with it. A unit
that spends a *charge* turns a whiff into a punish it can walk away from — lower variance,
repeatable threat, and a standing tax on the defender's positioning rather than a single coin
flip. That is what makes a grappler a presence instead of a gamble.

TODO: decide whether the Sapper spends a charge or itself — see
[proposals](proposals.md) §The Sapper as a grappler.

---

## Confirm: buying an option, then exercising it in the good state

A confirm is a **real option**. The opener is cheap, does little on its own, and its payoff is
that it reveals a state and opens a window; the expensive follow-up is committed only if the
state turned out well. Its value comes precisely from the right to *not* exercise.

Three conditions, and all three have to hold:

- the opener is weak alone, or there is no decision to make;
- the follow-up is a **separate commitment**, ideally of a different resource or unit, or the
  two collapse into one action;
- the window is long enough to observe the state and commit within it — which is the
  reactability analysis pointed at the attacking player.

This is where the language of combos actually applies. In this project the concept is **windows,
not links**: a disable, a stagger, a freeze or a spotted position each opens a period in which a
second commitment becomes profitable, and the payoff belongs to the player who noticed and paid
for it. An EMP that is worth little by itself and a great deal when the disabled units are
finished off is the worked example.

---

## Read: committing before the information arrives

A read is a **bet on a hidden choice**: acting on a belief, with a payoff if the belief was
right and a cost if it was not.

Reads are only meaningful where reaction is impossible — **prediction is what fills the space
that reactability leaves empty**. Where an action can be answered after the fact, predicting it
is strictly worse than waiting. So a game with no unreactable lead times has no reads, and a
game made entirely of them has nothing else.

At the micro level, the levers that create reads are lead times and irreversibility: slow
projectiles that must be aimed where a unit *will* be, area denial placed where the opponent
*will* go, an ambush held for an approach that may not come, splitting a formation before the
area attack that may not be thrown, and holding a reversal charge for pressure that may never
arrive. A unit already committed to a long action is the most predictable thing on the map,
which is what ties this back to commitment.

**Rule: a correct read should be paid in tempo, not in elimination.** A read that deletes an army
makes the match a guessing game; a read that buys a window compounds through every other system
and still leaves the loser something to play.

---

## The rules this produces

- Payoff scales with the reaction window granted, judged against a player looking elsewhere.
- Anything unreactable is bounded; fog that hides a commitment is a payoff increase, and should
  be priced like one.
- Prefer recoverable commitments to all-or-nothing ones; tune `Loss` before `p_punished`.
- Every zoning threat has at least two counter-options with different risk profiles.
- Positional value should vary smoothly where jockeying is wanted, and depend on the opponent
  where it cannot.
- A defender's risky option needs a visible after-window, or baiting it is a guess.
- An opener that opens a window must be weak alone, and the follow-up a separate commitment.
- Reads pay in tempo.
