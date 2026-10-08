---
title: Scenario scripting
type: system-index
---

# Scenario scripting

The mission layer: authored triggers, objectives, dialogs and scripted behaviour. Built *on*
the trigger system rather than beside it, so composition, region scoping and chaining come free.

| Note | Covers |
|---|---|
| [triggers-and-events.md](triggers-and-events.md) | the three ways an event runs, unconditional triggers, prerequisites, wave groups |
| [conditions-and-regions.md](conditions-and-regions.md) | condition lifetime across sessions, and region shape nodes |
| [objectives-and-completion.md](objectives-and-completion.md) | objective scope, chains, scenario completion, elimination |
| [dialogs-and-pause.md](dialogs-and-pause.md) | `SimulationClock` holds, dialog page scenes, input prompts, the help book |
| [highlights-and-fog-reveal.md](highlights-and-fog-reveal.md) | world and minimap highlights, and opening the fog |
| [tactics.md](tactics.md) | `ScenarioTactic`/`TacticRule`: ongoing behaviour for one cluster |
| [starting-formations.md](starting-formations.md) | where a `Skirmish` deploys a faction's opening force, and how it is arranged |
| [match-log.md](match-log.md) | the match's event log: what each event records, what is derived from it (summary, build order, series), and the summary view that reads only it |
| [simulation-tests.md](simulation-tests.md) | the `sims/*.sim.yaml` grammar and its runner: commanders, groups, symbolic order targets, a run window, a boolean tree of checks; why none of it runs in GUT |

Reference scenario: `scenes/scenarios/tutorial.tscn`. It is authored content, so nothing
unit-tests its contents.

**Belongs here:** anything authored per-mission rather than true of the game everywhere.

**Does not belong here:** the skirmish AI (`Bot`/`BotBrain`), which is a whole-commander
opponent rather than mission scripting.
