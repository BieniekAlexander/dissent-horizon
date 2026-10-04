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

**Scan is aimed as if it were a strike.** `BotSanction._aim` has two targeting modes, both
for engagements: the densest VISIBLE enemy cluster, or a reinforcement point on our side of
it. A Scan therefore lands on ground the bot already sees, on the front, and both bots' land
on the same front — exactly the repeated placement reported. The fix is a third `Targeting`,
REVEAL, aimed at the scout grid's least-recently-observed point weighted toward the believed
enemy, with no engagement gate; it is marked `TODO` at `_aim`. PLANNED: see
[deferred](../../deferred.md) 2.51.

**Measured.** See §Measured below, written from the first six-match HARD mirror batch; the
report itself is regenerated from any results file, so the table is not reproduced here.
