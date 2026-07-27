---
title: Commands
type: system-index
---

# Commands

Issuing, queueing and carrying out orders. The per-tick command lifecycle and the routing
warnings stay in `CLAUDE.md` — they are load-bearing for almost any task. The notes here are
the individual command families.

| Note | Covers |
|---|---|
| [construction.md](construction.md) | Build → Assemble → Repair, blueprints, and unfinished structures |
| [cooldowns-and-preconditions.md](cooldowns-and-preconditions.md) | charge and cooldown refusals, the additive modifier gate, what greys a button |
| [recording-and-replay.md](recording-and-replay.md) | PLANNED: the order stream a replay records and plays back, its file, and drift detection |
| [deploying.md](deploying.md) | Deploy and Undeploy: the planted stance, its transitions, and which orders a planting unit takes |
| [saying-it-plainly.md](saying-it-plainly.md) | Go and Fire — the plain move and the shot at a place the click ladder could not express |
| [the-click-ladder.md](the-click-ladder.md) | how a click becomes a command: the hotkey table, the default ladder, and why it is in that order |
| [the-command-tick.md](the-command-tick.md) | one tick of the active order: what suspends processing, why a fixed wing never stops, stagger |
| [unit-tasking.md](unit-tasking.md) | a standing order that pushes errands onto its unit's queue and never releases it; `TaskShelter` is the first consumer |

**Belongs here:** a new command class, the rules of an existing one, queue and rally
semantics, precondition policy, and how a command resolves from a click.

**Does not belong here:** which grid cell a command's button occupies
([ui/command-card-and-hotkeys](../ux/ui/command-card-and-hotkeys.md)), and scripted orders issued
by a mission ([scenario-scripting/tactics](../scenario-scripting/tactics.md)).
