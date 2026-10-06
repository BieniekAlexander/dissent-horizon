---
title: Design framework — goals, mechanics, and where each one lives
type: design-note
---

# Design framework

The running ledger of **what the game is trying to be** and **which mechanics serve it**. It
exists so a new piece or mechanic can be checked against the goals, and so the question "is
this generic or a faction's own?" is asked on purpose rather than answered by accident.

A mechanic's RULES live in its system note under `systems/`; this folder only records which
goals it serves and which tier it sits in. Piece stats live in the spec docs.

| Note | Covers |
|---|---|
| this file | tiers, goals, the concept index, mechanics → goals, settled decisions |
| [pacing](pacing.md) | the economic shape of a match: what each investment's term is, what volatility costs, and the open calibration behind it |
| [static-defence](static-defence.md) | what each faction's fixed defences cover and leave open, the cross-faction invariants, the Colonial and Libertarian pieces |
| [decisions](decisions.md) | the analytical spine: commitment, information, payoff and scarcity, and the decision structures built on them |
| [matchups](matchups.md) | matchup rules, faction identity departures, slots, absences, known skews |
| [commitment-and-movement](commitment-and-movement.md) | movement classes, travel time and scouting, evasion, action timing, and pricing disengagement through turn rate, holster, post-attack penalties, suppression and health-linked speed |
| [elasticity](elasticity.md) | execution elasticity: mechanical options, the floor/band/price/cap model, the axes an option is measured on, and every knob that tunes it |
| [unit-descriptors](unit-descriptors.md) | the descriptor vocabulary for power-budgeting a roster: properties, cost bands, canonical classes |
| [micro](micro.md) | micro-scaled effectiveness: the patterns and the rules for using them |
| [auditing](auditing.md) | how to see where a concept applies, per faction and per match timeline: role tags, not a knowledge graph |
| [ideas](ideas.md) | brainstormed proposals against the current roster, each named by the decision it creates |
| [proposals](proposals.md) | undecided designs: command-center win condition, Colonial dominion, parked ideas |

---

## Tiers

**A mechanic's complexity budget is set by how often a player meets it.** Learning cost is paid
once and amortised over every encounter, so a rule that applies to everything can afford to be
intricate, and one that shows up on four units cannot. Fighting games call the everywhere-present
ones *universal*; the tier here is *generic*, because almost nothing applies to literally every
piece — an actor that cannot move cannot kite.

| Tier | Meaning | Complexity budget |
|---|---|---|
| **Generic** | applies to (nearly) every piece, to a degree set by its properties | **high** — players meet it constantly, so they learn it fast |
| **Slot** | a generic CATEGORY that every faction fills differently (Heal, Mobility, Disable, Positional, Minion, Infrastructure, Dominion) | the category is generic; each expression is judged at its own tier |
| **Shared** | a named mechanic several pieces use, but not all | **low** — seen too rarely to carry many rules |
| **Faction-unique** | one faction's own | **sparing**; may be complex only where it anchors that faction's roster and shapes the enemy's target priority |
| **Absence** | a faction lacking a slot's expression, a frame, or a movement class | not a mechanic, but has matchup consequences — see [matchups](matchups.md) |

**Complexity is proportional to prevalence.** Stagger can carry several rules because every
unit is subject to it. Deployment appears on several units, but not often enough to support
more than one rule.

### What a faction-wide mechanic must do

*(Moved from the task file, 2026-09-28.)* The fighting-game analogy: some options are common but
not universal — a projectile, a divekick, a command grab, an air grab, a charge attack, a
character-specific resource. Street Fighter 6 has character-wide mechanics that change the
character's power over a match, becoming a necessary part of playing as them and against them:
Manon's medals reward landing command grabs and shape what the opponent expects as her payout
grows; Jamie's drink level raises his power over time, at a commitment that can be punished;
Bison's Psycho Mine is a status that makes the opponent take more damage if it is triggered.

A faction-wide mechanic in this game has to be designed on purpose so that it:

- pertains to a lot of actions and interactions, giving a lot of player expression and
  counterplay;
- appropriately influences the power of the army. TODO: this criterion was left unfinished in
  the original note.

---

## Micro, meso, macro

**The goals are organised by the layer of play they govern**, and the stance is that this game
rewards the first two and deliberately starves the third:

| Layer | What it is | The stance |
|---|---|---|
| **Micro** | executing an engagement — the moment-to-moment handling of pieces | **rewarded**; this is where skill is meant to pay, and where [elasticity](elasticity.md) is spent |
| **Meso** | the decisions between engagements — what to build, where to go, what to contest next | **rewarded**; uncertainty is what keeps it from collapsing into a solved line |
| **Macro** | the economic optimisation running underneath — build orders, saturation curves, timings | **starved on purpose**; simple, low-granularity, and resistant to being solved |

**Macro-level solving is the thing being designed against.** Randomised maps, a low-granularity
economy and non-exclusive spending are all the same move: they deny the optimiser a fixed
problem. → [pacing](pacing.md)

---

## Goals

| #   | Layer | Goal                                                                                                                                                                                                                                                                                 |
| --- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| G1  | Macro | **Simple macro.** Minimal mechanical execution of non-combat tasks.                                                                                                                                                                                                                  |
| G2  | Meso  | **Per-match variation.** Random maps; neutral things are *prizes*, never *obstacles*: interacting with one takes one or two units and is effectively instant, unlike a creep camp.                                                                                                   |
| G3  | all   | **A volatility curve: low early, high late.** Early fights are incentivised and confer advantage, but rarely decide the match. Late losses punish hard, and a sudden finish is possible — only late.                                                                                 |
| G4  | Meso  | **Positional nuance.** Unit and structure positions are constantly contested; resource access is tied to position (the "corner").                                                                                                                                                    |
| G5  | Micro | **Nuanced interactions.** The same tool leads to different follow-ups by state, distance and resources (combo routes).                                                                                                                                                               |
| G6  | Macro | **Multi-purpose pieces.** Uses compete through a shared resource (the Guilty Gear burst-meter shape), not by being mutually exclusive by construction.                                                                                                                               |
| G7  | Micro | **Handicap the larger force.** Systems lean against mass. Nothing non-generic punishes a player for using each unit hard, because the player who is behind is the one forced to.                                                                                                   |
| G8  | Meso  | **Decisive wins.** Dominion benefits the winner; matches still end.                                                                                                                                                                                                                  |
| G9  | Micro | **Micro-scaled effectiveness.** Many units — common in every roster, not on every piece — gain well-tuned, marginal effectiveness from small micro decisions. The patterns are in [micro](micro.md); how much a piece yields to skill, and what tunes it, is [elasticity](elasticity.md). |
| G10 | Meso  | **Fair matchups.** Every threat has a scoutable, reachable answer; no piece is dead weight against a faction. See [matchups](matchups.md).                                                                                                                                           |
| G11 | Micro | **Micro belongs where the game touches the opponent.** Execution that pays off against neutral or own-side mechanics is an anti-pattern — Warcraft III creeping is the case to avoid.                                                                                                |
| G12 | Micro | **Micro evolves the play space.** An engagement should leave the field changed and invite the next exchange, rather than resolving to the same board. TODO: no mechanism is identified; Kane's Wrath walker husks are the model.                                                     |
| G13 | Meso  | **No pareto-optimal line.** The decision space should resist collapsing to one best build; randomness and interaction nuance are what keep it open.                                                                                                                                  |
| G14 | Meso  | **Micro outcomes propagate into macro.** A decisive engagement should visibly change how the rest of the match is played.                                                                                                                                                            |
| G15 | Meso  | **Uncertainty is designed, not incidental.** Stealth, fog and ambiguous states (is that bunker occupied?) are the mechanisms.                                                                                                                                                        |
| G16 | Macro | **No mutually exclusive macro dilemmas.** "Army or economy?" is the shape to avoid; dominion is deliberately not traded against energy.                                                                                                                                              |
| G17 | Macro | **Economic leads are buffered.** A player should never feel the match was lost five minutes ago.                                                                                                                                                                                     |

---

## The concepts, and where they are analysed

**The analysis is grounded in decision structure — commitment, information, payoff and scarcity
— not in any genre's vocabulary.** [decisions](decisions.md) is that analysis. The table below is
an index into it: what the concept IS, what carries it here, and the reference where a
well-tested version of it can be studied. The reference column is the last column on purpose.

| Underlying concept                                      | What carries it here                                                     | Reference                       |
| ------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------- |
| Irreversible investment before payoff                   | production and build times, channels, travel time                        | fighting-game *startup*         |
| Payoff of a decision, or of declining one               | punish magnitude, scaling up over the match (G3)                         | *plus / minus*                  |
| Payoff conditional on the target's state                | colocation against area damage; disable windows                          | *counter hit*                   |
| Intercepting a commitment                               | stagger                                                                  | *parry*                         |
| A fungible resource spent across several uses           | shared ability pools                                                     | *burst meter*                   |
| Sequential versus simultaneous information              | reaction windows, tells, fog                                             | *reactability*                  |
| Mixed strategies forced by scarce attention             | pressure on several fronts at once                                       | *mixups*                        |
| Deterrence: buying space with threat                    | bombarded ground, persistent area effects, visible charge states         | *zoning*                        |
| Attrition over a contested boundary                     | range bands, vision, reinforcement distance                              | *footsies*, *neutral*           |
| Conditional dominance earned by position                | the Sapper (see [proposals](proposals.md))                               | *grappler*                      |
| A real option: probe cheaply, commit in the good state  | EMP into focused fire; Freeze into siege; spotting into bombardment      | *confirm*                       |
| Betting on a hidden choice                              | pre-aimed slow projectiles, ambush, pre-splitting                        | *read*                          |
| A risky defensive option with a punishable after-window | the Bombard; coverage differs per faction and is not meant to be generic | *reversal*                      |
| Diminishing returns on chained control                  | tech level governs disable availability, area and duration               | *combo scaling*                 |
| Position tied to resource access                        | map generation's quotas and bands                                        | *corner*                        |
| Committed states with entry and exit costs              | deployment, weapon recharge, rearming                                    | *stance*                        |
| A resource accrued by absorbing losses                  | infrastructure overhead: losses do not re-pay it                         | *meter gained on taking damage* |

---

## Mechanics → goals

| Mechanic                                       | Tier                      | Serves  | How                                                                                                                                                                                                                                                            | State                                                                                         |
| ---------------------------------------------- | ------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Energy from few extractors, one collector type | Generic                   | G1      | small marginal structure count                                                                                                                                                                                                                                 | built                                                                                         |
| Infrastructure overhead                        | Generic                   | G1, G3  | speed bump on growth; a player who took losses does not pay it again                                                                                                                                                                                           | built                                                                                         |
| Dominion through exposure                      | Slot                      | G4, G8  | each faction's route keeps it vulnerable over the match                                                                                                                                                                                                        | Anarchist, Libertarian built; Colonial under revision                                         |
| Dominion decoupled from battle outcome         | Slot                      | G3      | a player who loses a fight but keeps their generators still accrues                                                                                                                                                                                            | by design                                                                                     |
| Sanction price scaling across tiers            | Generic                   | G3, G8  | steep; top tiers are what end games                                                                                                                                                                                                                            | TODO: the price/power curve is not designed                                                   |
| Tech level scales disables and abilities       | Generic                   | G3      | combo scaling                                                                                                                                                                                                                                                  | principle                                                                                     |
| Telegraphs that shrink as the match runs       | Generic                   | G3      | an early action is loudly announced and a late one is not, so volatility rises through information rather than damage — the Bombard's beacon and capture investment both work this way                                                                         | principle                                                                                     |
| Structure armour vs tech                       | Generic                   | G3      | early units are weak against structures; attacks confer advantage without ending the game                                                                                                                                                                      | principle                                                                                     |
| Command-center win condition                   | Generic                   | G3, G8  | see [proposals](proposals.md)                                                                                                                                                                                                                                  | **proposal, not built**                                                                       |
| Damage table (type × frame × armour)           | Generic                   | G5, G10 | the core of every interaction                                                                                                                                                                                                                                  | built                                                                                         |
| **Stagger**                                    | Generic                   | G3, G4  | a parry: a hit blocks building (no oppressive structure drops — SC2 cannon rush, AoE2 castle drop) and healing (no quasi-invincible units, while heal rates can stay fast and free — the job mana and resource-cost heals do elsewhere). Never blocks movement | built                                                                                         |
| Colocation vs area damage                      | Generic (emergent)        | G4, G7  | the counter-hit analogue                                                                                                                                                                                                                                       | built                                                                                         |
| Shared ability pools                           | Generic                   | G6      | burst-meter shape                                                                                                                                                                                                                                              | built                                                                                         |
| Reinforcement distance                         | Generic (emergent)        | G3, G4  | a defender reinforces faster near home                                                                                                                                                                                                                         | TODO: calibrate map size against unit speeds and their spread                                 |
| Start ring + per-start resource quotas         | Generic                   | G2, G4  | random maps without mirroring                                                                                                                                                                                                                                  | planned — `systems/terrain-and-navigation/map-generation.md`                                  |
| Disable                                        | Slot                      | G5      | EMP (MECH, Anarchist), Freeze (Colonial), bio stun                                                                                                                                                                                                             | partly built                                                                                  |
| Channelled actions                             | Shared                    | G4, G9  | a unit commits — stationary, not attacking — for a payoff (Spot, plant)                                                                                                                                                                                        | built                                                                                         |
| Stance / deployment, recharge, rearm           | Shared                    | G4, G9  | per-unit time commitments                                                                                                                                                                                                                                      | partly built                                                                                  |
| Lazer damage over time                         | Shared                    | G5, G9  | stronger against static and slow targets; moving a unit trades combat uptime for longevity                                                                                                                                                                     | high-level definition kept; exact calculation open                                            |
| Neutral Shelters                               | Shared                    | G2      | low-commitment prize                                                                                                                                                                                                                                           | built                                                                                         |
| Bombardment by spotting                        | Faction-unique (Colonial) | G4, G5  | reach is vision by proxy; the Spot gate is the investment that makes a Bombard a threat                                                                                                                                                                        | built; TODO: raise the Bombard cooldown a lot, so sniping a command center takes several guns |
| Freeze                                         | Faction-unique (Colonial) | G5      | immobile + no action + armour step; routes into Siege damage and stationary Bombard targets                                                                                                                                                                    | built                                                                                         |

---

## Settled — do not re-propose

Each bullet here is `REJECTED` in the §13.1 sense: turned down, with the reason it was turned
down, so it is not proposed again.

- **Selling structures.** It complicates the economy, adds mechanical elasticity, walks back
  investments too cheaply, and would distort veterancy and the planned Marxist dominion route.
  Nothing implements it today; this is a constraint on what gets built.
- **Implicit dynamics are not visualised.** Overkill and similar emergent skill surfaces are left for players to discover or learn outside the game; in-game visualisation is for what a player must know to play at all.
- **Losses do not convert to dominion.** Not thematic; dominion benefits the winner (G8).
- **No non-generic overuse penalties** (e.g. lazer overheat). They snowball the player who is behind (G7). Overcommitment already exists through economic and positional commitment.
- **Dominion rate scaled by distance from home.** Too volatile to tune, and it punishes building extra primary structures.
- **Enclosure-based Colonial dominion.** Too close to the Libertarian design.
- **Gated Colonial build areas.** Slows the game down.
- **Colonial position benefits through energy income.** Variation in primary-resource access makes macro decisions too important (G1).
- **Stagger is not a combo mechanic, and does not grow.** Rejected additions: suppressing dominion generation, pausing production, pausing ability recharge (time-to-kill is too low for it to matter). Blocking garrison entry/exit: probably not.
- **Chained EMP is bounded by rearming.** Condors return to base to recharge; chaining costs a large investment in more Condors.
- **Disabled vehicles as path blockers.** Maps are too open for it to matter.
- **Extra damage against EMP'd targets.** Not planned; a status-conditional bonus may appear elsewhere.
- **Colonial dependence on Shelters is fine.** One or two units, instant interaction — a prize, not a creep camp.
- **Adjacency bonuses are contested.** Base area is finite, so which buildings take the exposed edge is a real trade.
- **Command-center armour, if the win condition is adopted: STRONG plus high HP**, not a new armour class. Vulnerability is set by cost, exposure and tech depth together — see [proposals](proposals.md).

---

## Open calibration

- TODO: relative sizes of units, structures and map space — work in progress.
- TODO: map size against unit speeds, and the spread of speeds, which together set reinforcement distance.
- TODO: the pacing calibrations — structure armour and HP policy, the command centre's cost, size
  and health, static-defence reach and specificity, what a production structure is worth against
  the units it makes, and the value of dominion over a match. Each is stated where it bites in
  [pacing](pacing.md); `tasks.md` logs them.
