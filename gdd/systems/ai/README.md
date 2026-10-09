---
title: AI
type: system-index
---

# AI

The CPU commander: what it perceives, how it decides, and how it acts.

| Note | Covers |
|---|---|
| [brief.md](brief.md) | Alex's original brief, verbatim: difficulty tiers, generalisation, what to model versus hardcode, and adversarial training |
| [bot-architecture.md](bot-architecture.md) | what is built today — the layers, the modules, and where each decision is made |
| [bot-roadmap.md](bot-roadmap.md) | TODO: planning over ladders, the gaps below, and the training harness |
| [objective-selection.md](objective-selection.md) | TODO, unapproved: the layer above every decision — all-in and booming as postures, not modes |
| [world-model/](world-model/README.md) | one fog-limited, layered model of the game state (sightings → tracks → fields and groups → assessment → attention) that every manager reads instead of the scene; the frameworks it adapts, the fog boundary, and the migration — TODO, unapproved except [lattice-and-topology](world-model/lattice-and-topology.md): PLANNED 2026-10-08, the lattice, distance fields over passable ground, approaches, arrival time, and defending assets across space |
| [ontology.md](ontology.md) | TODO, unapproved: what the model is made of — the five kinds, affordances as capability × scope × magnitude derived per component, the perception floor and reaction latency, attention as the human tiers' sensor, and the rule that the bot perceives exactly what the presentation layer presents |
| [decision-sims.md](decision-sims.md) | TODO, unapproved: simulations that assert what the bot DECIDES — four grammar keys and one family of bot-state checks on the existing sim harness, situations organised as controlled pairs per decision domain, and the first specs from the 2026-10-07 samples |
| [three-layer-comparison.md](three-layer-comparison.md) | RESEARCH: ZeroSpace's framework read against this bot — what matches, and the three gaps |
| [bot-parameter-space.md](bot-parameter-space.md) | what a tuning run may MOVE: the audit behind every `BotDifficulty` field, each one's search range, what interacts with what, and the ladders no parameter reaches |
| [selfplay-harness.md](selfplay-harness.md) | headless bot-versus-bot matches with injected parameters — how to run one, the JSON in and out, and what determinism actually holds |
| [bot-engagement-fixes.md](bot-engagement-fixes.md) | why a bot-versus-bot match was a guaranteed stalemate with zero combat, the four fixes, the before/after decisive rate, and the hysteresis re-check |
| [selfplay-results-2026-09-06.md](selfplay-results-2026-09-06.md) | MEASURED: 156 self-play matches on the fixed economy, and it SUPERSEDES the 2026-09-05 note — the start-position advantage is real, follows the POSITION, and survives an exactly symmetric map because the bot's build search prefers a world axis; which "inert" parameters came alive; the archetype matrix is still transitive but RUSHER is now last |
| [bot-economy-diagnosis.md](bot-economy-diagnosis.md) | FIXED: why the bot was broke in 70% of sampled ticks and never owned an extractor — the reserve was a trigger and not a floor, and income was gated behind being poor; the before/after, and why the flat stalemate is the same bug |
| [bot-performance.md](bot-performance.md) | MEASURED 2026-09-25: what a physics tick costs with bots running, a navmesh rebuild phase by phase, and the ranked fixes for the three ways the game misses the 30 FPS budget |
| [macro-learning.md](macro-learning.md) | PLANNED: learning the bot's purchase valuation — a combat model with interactions, a threat clock, a state value — and an outer search over the models' weights |
| [debug-signals.md](debug-signals.md) | every signal a bot holds or derives, grouped into the debug overlay's categories with its world-model level and cost to draw; all seven categories built, the discarded and heavy signals TODO |
| [think-scheduling.md](think-scheduling.md) | how a bot's thinking is paced: jobs on their own periods, one shared work-unit budget, resumable sweeps, and the claims registry that replaced run order |
| [bot-randomness.md](bot-randomness.md) | the bot's own seeded stream, a personality drawn per match, scored decisions sampled at a temperature, zero is the old bot; why strength is a search over the vector and not a learner, and the PLANNED population |
| [piece-usage-audit.md](piece-usage-audit.md) | which of a faction's pieces the bot fields and, for each it does not, which of four causes — not worth it, cannot actuate, cannot signal, game bug — with the ledger and the report that decide it |
| [squads-and-relations.md](squads-and-relations.md) | APPROVED 2026-10-03, steps 1–2 built: why the army trickled, the squad as the unit of orders shared with mission tactics, relations (one piece granting to another within a reach) as the model for every inter-piece dependency, and placement by role |

**Belongs here:** the Bot's perception API, the decision modules and their cadence, the
actuator, difficulty tiers, and anything about how the CPU chooses what to do.

**Does not belong here:** the commands it issues ([commands](../commands/)), the economy it
plays ([macroeconomics](../macroeconomics/)), or scripted mission behaviour, which is
authored per scenario rather than decided
([scenario-scripting/tactics](../scenario-scripting/tactics.md)). The line between a TACTIC
and the Bot is worth stating: a tactic is a mission author saying "these units do this",
the Bot is a commander deciding for itself. They share the ACTION side — a squad and its
policies — and never the decision side; see [squads-and-relations](squads-and-relations.md)
§The boundary.
