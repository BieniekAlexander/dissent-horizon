---
title: Piece-usage audit
type: system-note
---

# Piece-usage audit

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Which of a faction's pieces the bot fields, and for each one it does not, WHY NOT — because
"the bot never builds X" has four different causes with four different owners, and a match
log that only counts what was built cannot tell them apart.

## The four causes, and who owns each

| Cause | What it looks like | Owner |
|---|---|---|
| **Not worth it** | the bot's own valuation scores the piece below its alternatives, every time | balance — the piece's price or numbers (or the scorer, if the valuation misses what makes it worth it) |
| **Cannot actuate** | no bot module can issue the order that uses the piece | the bot's actuation: a MISSING command in `tests/test_BotCommandCoverage.gd` |
| **Cannot signal** | the bot can order it and never does, because no decision wants it, or the decision aims it wrong | the bot's signalling: a scorer, a targeting mode, a sense |
| **Game bug** | the piece is ordered and the command refuses it, or it is fielded and does nothing | the game, not the bot |

The audit's job is to put every piece in one of those rows with evidence, not to fix any of
them.

## What is recorded

`BotUsageLog`, owned by `BotActuator` — the one surface every order passes through, so no
module can act without being counted. Two tables:

- **Choices**: every scored decision over a set of piece types, each candidate's score and
  which won (`record_choice`). Recorded by production's unit pick (`train`; `train_opening`
  for the no-intel cheapest fallback) and the economy's production- and defence-structure
  picks. A piece that is considered and never chosen is the first row of the table above,
  and the mean of its score over the winner's says how far below it sat.
- **Actions**: every order issued or refused, by kind, piece and outcome, with the refusal
  cause named (`record_action`), plus where every targeted sanction landed
  (`record_cast_position`). `sanction_aim` counts a charged sanction that found no target.

The harness writes the ledger into each result slot as `usage`, beside `produced_by_id` (the
distinct pieces of each id the slot fielded over the match, read from the samples — a floor
at the sample interval, not a census) and `faction`. The ledger never feeds a decision.

## The roster, and the verdicts

`tools/selfplay/results/piece_usage.py` builds the faction's roster from the AUTHORED content
rather than from a running game: `tools.json` (what produces what), `technology.json`
(prerequisites), `abilities.json`, the spec docs' `builds:`, `abilities:` and `kind:` keys,
and the faction scene's sanction cells. Reachability is a fixpoint from the command centre
and the opening builders: a structure some reachable builder lists, a unit some reachable
producer trains, with reachable prerequisites. Actuability is read off the coverage test's
buckets, so this report and that test cannot disagree about what the bot can order.

```
python3 tools/selfplay/results/piece_usage.py colonial results.jsonl [more ...]
python3 tools/selfplay/results/piece_usage.py colonial --catalogue
```

| Verdict | Meaning | Row above |
|---|---|---|
| `USED` | fielded, with counts | — |
| `CONSIDERED_NOT_CHOSEN` | scored, never preferred; the score ratio follows | not worth it (or the scorer) |
| `REFUSED` | ordered and refused, with the cause | game bug, or an actuation bug |
| `NEVER_AIMED` | a charged sanction that never found a target | cannot signal |
| `NEVER_CONSIDERED` | reachable, actuable, and no module scores it | cannot signal |
| `NO_ACTUATION` | the command it needs is MISSING in the coverage test | cannot actuate |
| `UNREACHABLE` | the faction's own tree never offers it | content |
| `STUB` | its doc says it does nothing yet | content |
| `NO_DATA` | the rows carry no ledger and it never appeared | run newer matches |

A used, targeted sanction also reports its **repeat fraction**: the share of casts landing
within two world units of an earlier one. Near 1 is a sanction aimed at the same spot every
time — the Scan case below.

## Findings (2026-10-04, Colonials)

**Static, from the roster alone.** Four abilities and the one upgrade are `NO_ACTUATION`:
Bombard and Spot (the siege loop), Irradiate (the Recruit's grenade) and Work Detail are
reachable and cast by no bot module; Advanced Targetting is researched by none. These are
the coverage test's MISSING entries seen from the piece side — the test says which commands,
this says which content those commands strand. Everything else the Colonials field is
reachable from the opening and orderable by the bot.

**Scan was aimed as if it were a strike.** `BotSanction._aim` had two targeting modes, both
for engagements: the densest VISIBLE enemy cluster, or a reinforcement point on our side of
it. A Scan therefore landed on ground the bot already saw, on the front, and both bots' on
the same front — exactly the repeated placement reported. Fixed 2026-10-05: the REVEAL
targeting, [bot-architecture](bot-architecture.md) §Sanction targeting beyond the strike.

## Measured (2026-10-04, six HARD mirror matches on `skirmish.tscn`, cap 900 s, twelve slots)

Fifteen pieces `USED`, and the rest in four groups, each with a different owner:

- **Two producers stood idle on units the bot could not train.** The picker scored every
  producible type on its gun and took the best; the Guard (behind `cl_tech1`) won 46,707 of
  56,794 barracks decisions and the Avalanche (behind `cl_tech2`) 9,247 of 10,212 war-factory
  decisions, and the spend gate refused each one every tick while the caller banked for it.
  Neither was ever trained, and the bot owned no tech structure. That is the infantry-heavy,
  war-factory-idle army seen in play, from a picker bug rather than a valuation: FIXED, the
  picker now considers only units the bot has the tech for (`tests/test_BotProductionTechGate.gd`).
  The verdict that found it, `CHOSEN_NOT_ORDERED`, exists for exactly this shape.
- **There was no tech rung.** Six structures were `NEVER_CONSIDERED`: both tech buildings,
  the three support buildings and the Bombard. The economy ladder bought production, income,
  defence and the dominion and infrastructure providers, and nothing else — so every piece
  behind a tech building was unreachable in play whatever the bot thought of it. FIXED
  2026-10-05: [bot-architecture](bot-architecture.md) §The tech rung. The support buildings
  and the Bombard stay `NEVER_CONSIDERED`: a structure a tech building unlocks scores nothing
  to that rung, which is the Relation model's work.
- **Two sanctions were aimed at ground and wanted a unit.** Freeze and Promotion were
  charged, aimed 596 and 790 times, and refused every time with `NO_VALID_TARGET`:
  `BotSanction` aimed every sanction at a point, and these two name a unit. FIXED 2026-10-05
  with the ENDANGERED_FRIEND and VALUABLE_FRIEND targetings. Beacon was `NEVER_AIMED` (524
  charged ticks, no target): it needs an enemy cluster of two within six units in vision,
  which the bot's engagement zone rarely offers, and a beacon's purpose — ground for a
  Bombard the bot never builds — gives it nothing to aim for anyway. Open until the siege
  loop is.
- **Scan.** 97 casts over twelve slots with a repeat fraction of 0.39, and 1,853 charged
  ticks with no target: aimed only inside an engagement, at the visible front. FIXED
  2026-10-05 with the REVEAL targeting.

One valuation finding: the Matilda (`cl_mechMedium_antiMech`) was `CONSIDERED_NOT_CHOSEN` at
0.62 of the winner's score across 10,212 war-factory decisions, consistent with the
crush-effectiveness measurement in [squads-and-relations](squads-and-relations.md). Whether
that is the game or the scorer is the balance question the audit leaves to its owner.
