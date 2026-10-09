---
title: The match event log
type: system-note
---

# The match event log

Every match keeps one EVENT LOG (`MatchLog`, owned by the `Scenario`): what happened, in order,
as JSON-ready records. **Every after-the-fact view of a match reads the log and never the game**
— the summary screen, a statistic, an analysis of a self-play run — so a number comes out the
same live and from a file. Built 2026-10-07.

It is the project's one HISTORY, and the bot does not read it. The bot's world model keeps state
and deliberately no event log ([ai/world-model/layers](../ai/world-model/layers.md) §The model), and the bot
signals the debug overlay draws are that state ([ai/debug-signals](../ai/debug-signals.md)), so
none of them could be reused as events. The log hooks the game itself, which is also what makes
it cover a human player.

## The events

Every event carries `tick`, `t` (seconds, to a hundredth) and `type`.

| type | fields | written when |
|---|---|---|
| `match_started` | `scenario`, `seed`, `win_condition`, `commanders` [{`id`, `faction`, `is_bot`}] | the scenario starts, before the opening force spawns |
| `purchase_funded` | `commander`, `purchase` (id), `piece`, `kind` (`unit` · `structure` · `upgrade`), `energy`, `dominion` | a purchase's cost is taken |
| `purchase_refunded` | the same | a funded purchase is cancelled and its cost returned |
| `purchase_completed` | the same | what it bought exists: a unit spawned, a foundation laid, an upgrade researched |
| `construction_finished` | `commander`, `piece` | a structure's construction completes |
| `stats` | `commander`, `energy`, `dominion`, `infrastructure_provided`, `infrastructure_required`, `army_value` | every 5 seconds for each standing commander, and once more at the end |
| `commander_eliminated` | `commander` | HEGEMONY removes a commander |
| `match_ended` | `winner` (commander id, or -1) | the match ends; once |

Purchases are recorded by the transaction itself, at the one place each stage happens, so
every route that buys something is covered without a call at each. **Resources are sampled,
not evented**: energy changes every tick, and an event per change would be most of the file.

Not recorded yet. TODO: losses (a piece destroyed), captures and liberations (a piece changing
owner), pieces a match starts with, and ability casts. Each is a statistic a summary will want,
and none is needed by what is derived below.

## What it derives

From the log alone:

- **A build order**: `purchase_funded` in order, per commander. A refunded purchase was
  ordered and taken back; net it out by `purchase`.
- **Purchases per piece**: the same events, counted.
- **Energy, dominion and infrastructure over time**: `stats`.
- **Army value over time**: `stats.army_value`, the summed price of the commander's units.
- **Units and structures made** (what the summary shows): units are `purchase_completed` of
  kind `unit`; structures are `construction_finished`, because a laid foundation is not yet a
  building. Pieces the match started with, or that were taken by capture, were not made and are
  not counted.

`MatchSummary` holds the derivations the game uses. They are pure functions of an event array,
so they work the same over a parsed file (`MatchLog.parse_jsonl`).

## The summary view

`scenes/interface/match_summary.tscn`: a table of each commander's units trained and structures
built, the winner marked; below it the same counts per piece (a column per commander, the pieces
made most first, scrolling once it is long); and a line naming the log it was read from. Pieces
are named by id, as the log records them. It is handed the log and
reads nothing else. It is shown:

- **in the pause menu, while the debug view is up**, as "Match so far";
- **when the match ends, debug view or not**, with the verdict as its heading: Victory or
  Defeat for the local player, "Commander N wins" in a spectator session. It does not pause, and
  closes with its own button. TODO: the rest of a win/lose screen — pausing, a way back to the
  menu — is still [gdd/tasks.md](../../tasks.md) T-080.

**A match ends** (decided 2026-10-07) at the local player's win or loss, whoever won; in a
spectator session, when two or more commanders have deployed and only one is left standing; and
in a self-play run, at the harness's verdict, if the scenario has not ended it first.

## Where it is written

**Only the self-play harness writes it to disk** (decided 2026-10-07), as gzipped JSON lines
beside its result, `<out>.events.jsonl.gz` ([ai/selfplay-harness](../ai/selfplay-harness.md)).
`PackedByteArray.compress(COMPRESSION_GZIP)` writes standard gzip, read by `gunzip -c` and
Python's `gzip`. In-game the log is kept in memory only. TODO: writing every match's log to
`user://`, which would be the game's first persistence.

A ten-minute bot-versus-bot match is about 700 events and 8 KB compressed.
