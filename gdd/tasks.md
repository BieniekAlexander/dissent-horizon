---
title: Tasks — work saved for later
type: index
---

> [!info]- How this file works
> **One log of everything saved for later** — bugs, requests, open decisions and plans not yet built. It replaced `deferred.md` on 2026-10-06. Each `###` is one item with a permanent id (`T-001` …); an id is never reused, so `T-042` found anywhere in the repo points here. Claude works it via `/tasks`, following the **AFK task sessions** protocol in `CLAUDE.md`.
>
> **Every item carries three tags on its heading:**
>
> | Facet | Tags |
> |---|---|
> | Effort | `#effort/low` a simple change not yet made · `#effort/medium` between · `#effort/high` a system overhaul |
> | Scope — exactly one | `#scoped` everything needed to start is decided · `#needs-input` partly scoped, with written questions waiting on me · `#unscoped` not yet scoped; needs a scoping pass |
> | Progress — at most one | *(none)* not started · `#wip` a session is on it now · `#shelved` started and paused · `#done` finished; `/shelve` deletes it |
>
> **Search strings:**
> - `#unscoped` — items that need more scoping before anyone can start
> - `#needs-input` — items with open questions; each says where its questions are (a `[!question]` below it, or a `TODO` in the note it links)
> - `[!question]` — a question block I can answer right here, after `**Answer:**`
> - `#scoped` — what an unattended session may pick up
>
> **Detail lives at the right level.** A small or unscoped item carries its spec here. An item with real complexity is a few lines and a `→` link; its design, and the reasoning behind its questions, live in that note. While an item is `#wip` its notes may be as long as they need; when it is shelved or done, the history collapses to a few lines (or goes), because what was built is in the code and the notes.
>
> Next id: **T-101**

# Tasks

## AI

### T-001 · CPU bot behaviour #effort/high #needs-input #shelved
The standing goal: difficulty tiers from PASSIVE to IMPOSSIBLE, decisions derived from game stats rather than hardcoded, and adversarial self-play to tune them. The brief, verbatim, is [ai/brief](systems/ai/brief.md); the plan is [ai/bot-roadmap](systems/ai/bot-roadmap.md), and every open question is a `TODO` there or in [ai/bot-architecture](systems/ai/bot-architecture.md). The heaviest: how energy prices against dominion (blocks converting the economy ladder to scored options), whether the bot may field aircraft, and the start-position bias's suspected cause (`BotScout`'s world-anchored grid).
> [!check] Status — 2026-10-06
> Built since 2026-09-04: difficulty as data (`BotDifficulty`), energy-equivalent arbitration starting with scouting, `BotMomentum` and army retreat, clustering as a perception sense, fog-limited attack objectives, the no-base defeat rule, demand-driven utility units, navmesh-safe placement and training, and the work tracked below as T-002 – T-004. Answered decisions are recorded in the AI notes, not here.

### T-002 · Squads and relations #effort/high #needs-input #shelved
Approved 2026-10-03. Built: waves in series, staged reinforcements, rally points, placement bearing by role. Left: the squad registry with `Stage`/`Assault`/`Hold`/`Patrol` shared with `ScenarioTactic` and capped per difficulty; `Relation` (provider, consumer, reach, effect, value) read off the pieces; multi-actor opportunities and `Escort` for transport and the Sapper; relation affinity and approach coverage in placement; per-job Bot enable for missions.
→ [ai/squads-and-relations](systems/ai/squads-and-relations.md)

> [!check] Status — 2026-10-08
> Built: per-job enable for missions — `PlayerSlot.disabled_bot_jobs` names `BotBrain` jobs (`BotBrain.JOB_NAMES`) to leave unscheduled; an unknown name fails the boot (`tests/test_BotJobSwitches.gd`). The squad registry and guard were already built 2026-10-07, so of "Left" the registry is done.
> Tests: 3953 passing (one shard crashes intermittently, pre-existing — unresolved-crashes.md).
> **Not done:** step 3 (`Relation`, `Bot.relations()`, opportunities, `Escort`) — parked on the value question below; bot `Patrol` — parked on the second question.

> [!question] Q — 2026-10-08
> What is a relation worth, in the energy-equivalent currency every bot comparison uses?
> **Why it matters:** build step 3 (`Relation`, `Bot.relations()`, multi-actor opportunities, `Escort`) prices every consumer by the relation's `value`: an opportunity is "the relation's value against the journey" and placement affinity is "priced by the relation's value". The note gives the unit (energy-equivalent, per second or per event) but no rule for any row of its table, and several rows (a Warlord's dominion per follower, a Compound's cooldown reduction) depend on how energy prices against dominion, which T-001 lists as open.
> **Options:**
> 1. Derive each effect kind once: ENABLES = the value of the action it enables (a Bombard shot's expected damage × cost); SCALES = the output rate gained, priced at a fixed energy-per-dominion constant until T-001 settles it; MOVES = the consumer's cost × the travel time saved; PROTECTS = the consumer's cost × the damage reduction.
> 2. A doc key per relation (`value:` on the provider's spec), authored by hand until a derivation exists.
> 3. Build the read model (`Relation`, `Bot.relations()`) and one consumer that needs no price — `Escort` for transport and the Sapper, issued whenever a consumer is in a squad without its provider — and leave pricing for when opportunities and placement need it.
>
> **Leaning:** 3 — it builds what the note fully specifies, and the pricing question gets answered against a working read model rather than in the abstract.
>
> **Answer:** 3

> [!question] Q — 2026-10-08
> When and where does the bot patrol?
> **Why it matters:** the note lists `Patrol(route)` as "the Bot's map control" but says nothing about which units patrol, along what route, or what decides it. A patrol squad takes units out of the wave and the reserve, so it competes with them.
> **Options:**
> 1. A patrol squad between the bot's own outlying extractors, drawn from the reserve while no wave is out, sized like the guard (`guard_strength_ratio`).
> 2. A scout-like circuit through the map's contested middle by one cheap fast unit, under `BotScout` rather than `BotMilitary`.
> 3. No bot patrol for now; `Patrol` stays a mission-only policy.
>
> **Leaning:** 1 — it guards what raids actually hit (outlying economy) and reuses the guard's sizing rule.
>
> **Answer:** 3. Patrol and Defend can be out of scope for bots. these commands are alternate means of handling unit aggro provided as a convenience to the player, and its underlying behaviors are already usable by the bot.

### T-003 · A population of bot personalities #effort/medium #needs-input #shelved
Built: the per-bot seeded stream, the personality draw, temperature sampling, the quality-diversity search (`tools/selfplay/train.py`), and scenarios naming a roster member. Left: a tier as a distribution over the roster instead of one point plus jitter, and categorical preference weights on the vector so composition is searchable.
→ [ai/bot-randomness](systems/ai/bot-randomness.md) §Strength is a search

> [!check] Status — 2026-10-08
> Nothing built this session. The tier-as-distribution half is blocked by the note's own precondition ("waits on a roster worth drawing from: several cells holding members rated clearly above the seeds"); `resources/bots/roster.json` is at generation 2 and the 2026-10-07 rerun still rates a seed (the rusher) first. The preference-weights half waits on the question below.

> [!question] Q — 2026-10-08
> What are the categorical preference weights, and where do they enter the bot's choices?
> **Why it matters:** the note names "a weight per unit class in production, an opening-style weight, static-defence and garrison appetites" but no class set and no mechanism. Since 2026-10-07 production picks by the learned combat model (`BotProduction`, T-100), so a weight has to multiply that score or the demand map's, and each class set makes a different personality reachable.
> **Options:**
> 1. Three production weights, by frame and flight (`BIO`, `MECH`, aircraft), each multiplying a candidate's score in `BotProduction`; plus one static-defence weight multiplying the turret appetite. All four as `BotDifficulty` fields in the search ranges. Opening style and garrison appetite left out until defined.
> 2. A weight per piece id in the faction roster: maximally expressive, but the search dimension grows with the roster and a vector stops transferring between factions.
> 3. Weights by unit role (anti-light / anti-mech / anti-air / support, from the matchup table), so a personality prefers a counter type rather than a chassis.
>
> **Leaning:** 1 — it makes the personalities the note names (air-heavy, mech-first) reachable with four searchable numbers that mean the same thing in every faction.
>
> **Answer:** 2. The options available to factions differ enough that they're worth modeling independently.

### T-004 · The bot's unused Colonial pieces #effort/high #unscoped #shelved
Audited 2026-10-04; the tech-locked picker, the tech rung, Scan's REVEAL and Freeze/Promotion targeting are fixed. Open, each a coverage-test MISSING entry or the Relation model's (T-002): the siege loop (Bombard, Spot, Beacon), the support buildings a tech rung cannot score, the Recruit's Irradiate, Work Detail, researching Advanced Targetting, and a unit worth having only beside another (Reverence beside a Bombard).
→ [ai/piece-usage-audit](systems/ai/piece-usage-audit.md) §Measured

### T-005 · How much of a tick does the AI get? #effort/low #needs-input
`BotScheduler.WORK_UNITS_PER_TICK`, the budget every bot's jobs share; a provisional 2000 units (~2 ms).
→ [ai/think-scheduling](systems/ai/think-scheduling.md) §Decision 2

### T-006 · How is a lithium pond priced against an extraction site? #effort/medium #needs-input
The bot picks by distance; a pond pays double and is finite, so which is worth more is a value-over-time question sharing a currency with the ability one.
→ [ai/bot-architecture](systems/ai/bot-architecture.md) §The bot works lithium ponds

### T-007 · The bot's scout and its fog disagree about terrain #effort/low #unscoped
Scout raycasts stop on terrain and fog does not, so ground behind a ridge is never counted as scouted. Resolves with T-008, or with the scout reading fog instead.
→ [combat/scan-and-vision-cost](systems/combat/scan-and-vision-cost.md)

### T-092 · How the bot is told to stay out of an area #effort/medium #unscoped
Lingering effects over ~3 s (frost fields, the Blizzard's gathering) should publish an avoid-region signal; its form, weight and route into pathing are open.
→ [ai/bot-roadmap](systems/ai/bot-roadmap.md) §The gaps in the decision surface, gap 7

### T-098 · Unit value is a stand-in: revisit strength per energy #effort/medium #unscoped
Decided 2026-10-07 as a first cut, with a revisit deferred: the bot values a unit at √(DPS × matchup × HP ÷ the target's multiplier against it) ÷ cost — Lanchester's square law — instead of the bare matchup multiplier, which made the 100-energy Recruit always win. Deliberately missing: range, speed, splash, and which layers the target's weapons can reach (a build preview cannot say). `Bot.unit_strength_per_energy_vs`.

### T-099 · A cautious bot that still commits in the end #effort/low #unscoped
`assumed_enemy_parity` above 1 / `MIN_ATTACK_RATIO` (≈1.18) meant a bot that could never attack; the search range was capped at 1.15 on 2026-10-07 as the fix for now. Deferred: making the cautious end of the range playable instead — e.g. the stalemate clock relaxing parity too, so a timid bot still commits eventually. `bot_difficulty.gd` SEARCH_RANGES; `BotMilitary._committing_to_attack`.

### T-100 · Learn the bot's purchase valuation #effort/high #needs-input #shelved
The macro valuation (demand map → strength per energy → savings) is one additive form that cannot express interaction, distance, a mix, or payback, and tuning its constants cannot change that. Proposed: a combat model learned from sim fights, a threat clock on the lattice, a state value from logged matches, and the existing trainer searching the models' weights. Also: rerun the 2026-10-04 roster round before using it as a baseline (stale). Supersedes T-098 if adopted.
→ [ai/macro-learning](systems/ai/macro-learning.md)

> [!check] Status — 2026-10-07
> Stage 1 built and ON BY DEFAULT in every tier (`BotDifficulty.should_use_learned_production`), with the model as trained: a combat model fitted on 6,000 single-faction sim fights (`tools/combat_model/`, `CombatModel`, `resources/bots/combat_model.json`), held-out R² 0.655, scoring `BotProduction`'s unit choice. Self-play: learned 17/31 against the demand map (p = 0.72) and 4/10 on random maps — not worse, not shown better; it fields fewer Recruits and more anti-mech infantry. Baseline roster rerun: rusher first but even with the economist. Fixed on the way: a freed avoidance partner (`movement.gd`), and `run_batch.py` deleting every match's event log.
> Tests: 3883 passing before the editor was opened (22:52 local). Every full run since crashed one shard at a random test, with the default on OR off, so the editor running on the same project is the likely cause — rerun `gut_shards.py` with the editor closed. The ~2,900 tests that ran all passed. Lint clean except `line_slots.gd` / `test_LineSlots.gd` (not this work).
> **Not done:** the shipped model underrates the anti-mech tank against Sloops (corpus misses pairwise matchups; `counter_the_tanks_learned` fails) — stratified sampling proposed; a ~200-match comparison; charged weapons, abilities and support value the fights cannot see; the slot-0 bias (27/41); stage 2 waits on world-model steps 3–5. All in `macro-learning.md` §1 and §Still open.

> [!question] Q — 2026-10-08
> Build the stratified fight corpus and retrain the combat model?
> **Why it matters:** macro-learning.md §Still open proposes it (unapproved) as the fix for the shipped model rating the Sloop level with the anti-mech tank against Sloops (3 such fights in 6,000), which the default bot now plays with. It changes `tools/combat_model/` sampling and the committed `resources/bots/combat_model.json`, so every tier's production shifts.
> **Options:**
> 1. Yes: sample so every pair of armed unit types meets a minimum number of times (on top of the faction-proportional draw), grow the corpus, retrain, and gate the new model on `counter_the_tanks_learned` passing.
> 2. Yes, but keep the current corpus and only add the missing pairs as a top-up set.
> 3. Not yet: switch the learned valuation off by default until it is shown better than the demand map.
>
> **Leaning:** 1 — it fixes the known blind spot at its cause, and the gate makes the regression visible.
>
> **Answer:** My only feedback here is that I will frequently be making changes to the roster, and I'm aware that changes to the pieces will impact the quality of the bot's evaluations. I think the simulations can represent safe expectations of the evaluations, and failing simulations implies that retraining is warranted.

## Combat

### T-008 · Does terrain obstruct shots, or sight? #effort/high #scoped #done
Changes were recently made to make sure that navigation mesh obstructing fixtures obstruct attack lines, so that an actor on one side of an obstruction cannot attack a target on the other side of the obstruction; Some terrain features have these same sorts of elevation considerations such that a terrain mountain (represented in the world height map) also obstructs attack lines; there's some complexity here regarding projectile collisions happening with the height map surface, but not necessarily with structures, so help me actually come up with better definitions regarding how this is represented in the physics.
Cases so far: a ridge should not block, high terrain such as a mountain probably should, a cliff between two elevations probably should not, artillery may be exempt; blocking sight is open too, subject to performance, balance and visual fidelity.
→ [combat/target-acquisition](systems/combat/target-acquisition.md) §Line of fire

> [!check] Status — 2026-10-08
> Sight is never obstructed by terrain. A shot is obstructed by terrain when the weapon's reach is below `RangeShapes.artillery_reach()` (the artillery shape's radius): one `TERRAIN`-layer ray, `Attack._terrain_on_line`; rule in `target-acquisition.md` §Terrain on the line of fire. Tests in `test_LineOfFire.gd`.
> **Not done:** no height judgement (a ridge above the 0.5 ray lift blocks); in-flight emissions still ignore terrain. T-007 now resolves toward fog (terrain does not hide ground from sight), so the scout should read fog.

### T-013 · Should aggro rise for long-reach pieces? #effort/low #needs-input
`AGGRO_MAX_RADIUS` sits below both artillery classes and below `ground_range_long` / `air_range_long`, so a target in that band is never picked up idle.
→ [combat/range-buckets](systems/combat/range-buckets.md) §Asymmetries between the families

### T-014 · Which units out-see structures? #effort/low #needs-input
Meant to be rare; which unit vision bucket, if any, sits above `vision_ground_large`.
→ [combat/range-buckets](systems/combat/range-buckets.md) §Asymmetries between the families

### T-015 · What happens when an attack startup's hold breaks? #effort/low #needs-input
Built: it resets. The framework says a begun startup completes; a grace tolerance is the middle option.
→ [combat/weapon-cadence](systems/combat/weapon-cadence.md) §Attack startup

### T-016 · Weapon cadence per piece #effort/medium #needs-input
Whether the rest of the infantry follows the Irregular and Recruit onto multi-round bursts, which later units are built around a long reload window, and which vulnerable states and reload variant each piece carries.
→ [combat/weapon-cadence](systems/combat/weapon-cadence.md)

### T-017 · How much projectile lead error is too much? #effort/medium #needs-input
The arithmetic exists, the threshold does not; the simulation-test framework can now sweep it.
→ [unit-calibration](unit-calibration.md) §Open questions, [scenario-scripting/simulation-tests](systems/scenario-scripting/simulation-tests.md)

### T-018 · What defines projectile evasion? #effort/high #needs-input
The vocabulary is written; open: the envelope per class pair, outpacing by range rather than speed, the close-range window, whether mid-range jukes are a band, hover evasion, launch readability, and whether the AI jukes.
→ [combat/projectile-evasion](systems/combat/projectile-evasion.md) §Open questions

### T-019 · How long a garrison's door takes #effort/medium #needs-input
Entry and exit are instant, so a defender can empty a host before any flushing weapon lands. Exit time, entry time, exposure on exit, or a flush that acts on the door.
→ [combat/garrison-and-transport](systems/combat/garrison-and-transport.md) §Entry and exit take no time

### T-023 · The Spot animation, and what an opponent reads from it #effort/medium #needs-input
The Recruit needs an animation showing the Spot action while it channels and holds a beacon. Open: what an opponent with vision of the Recruit may read from it, since the animation is itself a tell.
→ [combat/bombardment](systems/combat/bombardment.md) §Beacons, [ux/unit-animation](systems/ux/unit-animation.md)

### T-024 · What does an opponent see of a Beacon Drop landing? #effort/low #needs-input
→ [combat/bombardment](systems/combat/bombardment.md) §Beacons

### T-025 · Security Tower: per-drone properties and swap time #effort/medium #needs-input
Built: one drone at a time, firing from inside; the Shock Drone fires at long range (a stub). Open: what each other drone confers, and how long a swap takes.
→ [design-framework/static-defence](design-framework/static-defence.md) §Libertarians

### T-028 · Alliances #effort/high #needs-input
Up to 8 players and up to 7 alliances; possibly 8 alliances under the hood, shown only in a team-game mode. Widens every "yours" rule to "yours or an ally's": `is_enemy_of`/`is_friendly_to`, shared vision, capacity pips.
→ [combat/target-acquisition](systems/combat/target-acquisition.md) §Alliances

### T-029 · Fog resolution: one pixel per cell, or coarser? #effort/medium #needs-input
Coarser is cheaper and blurs vision edges and the per-cell structure-sighting test.
→ [combat/scan-and-vision-cost](systems/combat/scan-and-vision-cost.md) §Proposal: the fog of war

## Commands

### T-031 · What deploying gains, and three order cases #effort/medium #needs-input
Built as placeholders: an armour step as the bonus; a plain Attack/Stop while deploying waits behind it; a plain move while undeploying runs after it; weapons offline in both transitions; undeploy takes 1 s against "3 s in all cases". Also the Sharpshooter's deploy-only weapon and 15-unit reach.
→ [commands/deploying](systems/commands/deploying.md)

### T-032 · Deploy and undeploy durations #effort/low #needs-input
Deploying is decided to be uncancellable; how long it and packing up take is not.
→ [design-framework/commitment-and-movement](design-framework/commitment-and-movement.md) §Commitment, per action

### T-033 · Repair and motion #effort/low #needs-input
Whether the repairer, the patient, or neither may move while a repair runs.
→ [design-framework/commitment-and-movement](design-framework/commitment-and-movement.md) §Commitment, per action

### T-034 · How does a second builder join a PLANNED site? #effort/low #needs-input
A second plan there is refused today.
→ [commands/construction](systems/commands/construction.md) §A plan claims its site

### T-035 · Building things that are not structures #effort/high #unscoped
`is_built` is group-keyed, so a unit is always built; constructing a vehicle on a pad wants exactly this rule, and the build system assumes everything it raises registers on the terrain grid.
→ [commands/construction](systems/commands/construction.md)

### T-037 · Recording and replay #effort/high #scoped #shelved
Built: a match is bit-reproducible from its seed (navigation synchronous project-wide, 2026-09-29). Left: human orders recorded as a tick-stamped stream and fed back into a re-run; pieces gain a spawn serial; orders land at tick start; compressed JSON-lines files with a version stamp and a per-second state hash. The stream is also the intended input exchange for future rollback netcode.
→ [commands/recording-and-replay](systems/commands/recording-and-replay.md), [ai/selfplay-harness](systems/ai/selfplay-harness.md) §Determinism

> [!check] Status — 2026-10-09
> Built: the order boundary and the record/replay core (every player action a `PlayerOrder` applied at tick start; spawn serials; versioned gzip JSON-lines files with a per-second digest and keep-three autosaves; debug mode invalidates), and watching: the start screen's replay panel (`MainMenu`, `ReplayLibrary`), opening a playback through `SceneManager.play_replay` with refusals for another version, a debug-invalidated recording or a missing scenario; Save replay with a name at the foot of every end-of-match summary (`ReplaySaveForm`); a playback runs as a spectator session (every slot a `Bot`; the recorded human stays the simulation's local player) watched through the look-only HUD — the player's HUD scene (`scenes/interface/player_hud.tscn`, split out of `player.tscn`) with selection, info panel and minimap in place and the `SpectatorPanel` (views; Pause/Slower/Faster in a replay) in the command grid's slot — plus `ReplayViewer`'s banner and Q/W/E/R keys; a Hide HUD button above the minimap on every HUD, leaving Show HUD on the bottom edge; dialogs resolved only by the recording; UI clip picks off the simulation's global generator (`pick_random`/`shuffle` guarded); the header's start point per slot. Rules in recording-and-replay.md §What is built and ux/ui/hud-layout.md §The look-only HUD, §Hiding the HUD.
> Tests: replay and HUD tests all pass (`test_ReplayLibrary`, `test_ReplayViewer`, `test_ReplaySaveForm`, `test_ReplayPlayback`, `test_MainMenuReplays`, `test_HudToggle`, `test_ReplayRoundTrip` incl. a human-rig skirmish played back as a spectator). This cloud container has no `.godot/imported` or UID cache, so its full suite is red on the untouched base too (161 failures); the only new ones are 4 menu/scenario tests failing on the container's "invalid UID" load warnings alone.
> **Not done:** alerts and voice lines following the perspective — there is no alert system yet (note §The plan, `TODO`). Still open in the note: the codec decision and measuring one seed across two platforms. Deferred by design: seeking, rollback networking, play-from-here.

### T-038 · Move-line drag: the follow-ups #effort/medium #unscoped #shelved
Built for the unarmed right click only. Left: the minimap, armed orders, navmesh snapping of slots, recording issued destinations in the replay (T-037).
→ [commands/move-line-drag](systems/commands/move-line-drag.md) §Not built

### T-039 · `bystanders_move` in every command-issuance context #effort/medium #unscoped
Not just `Embark`.
→ [ui/control-matrices](systems/ux/ui/control-matrices.md), [commands/the-click-ladder](systems/commands/the-click-ladder.md)

### T-040 · Does the RVO idle-velocity experiment read right? #effort/low #needs-input
Built: an idle unit is fed a zero velocity so it stops being a "ghost" in the avoidance sim. Cost: idle units may drift aside when pushed, against "enemies don't get out of the way"; the fallback is to stop applying avoidance velocity to commandless units.
→ [commands/the-command-tick](systems/commands/the-command-tick.md)

### T-041 · Should an in-reach target outrank a more important one out of reach? #effort/low #needs-input
Decides how soon a unit plants, and so how soon it obstructs its own side.
→ [terrain-and-navigation/navigation-and-pathing](systems/terrain-and-navigation/navigation-and-pathing.md) §Avoidance priority

## Calibration and economy

### T-042 · Which speed/turn-rate family do vehicles use? #effort/medium #needs-input
Anarchical 4.0/150 vs Colonial 1.5/1080 — the second is infantry handling on a tank chassis. A faction-identity question, not a calibration one.
→ [unit-calibration](unit-calibration.md) §Open questions

### T-043 · What does faction identity do to the calibration norms? #effort/medium #needs-input
Every heuristic is stated for the game as a whole; identity ought to be a systematic departure from several at once.
→ [unit-calibration](unit-calibration.md) §Open questions

### T-044 · The Colonial dominion knobs #effort/medium #needs-input
Sentence length, Shelter spawn rate, truck capacity and load time, Compound capacity. Pick the truck counts wanted at a near and a far Shelter and the rest derives.
→ [design-framework/proposals](design-framework/proposals.md) §The model

### T-045 · The movement system and attack states #effort/high #needs-input
Turn rate, holster, post-attack speed penalties, suppression and health-linked speed all price the decision to disengage; no values or mechanics are chosen.
→ [design-framework/commitment-and-movement](design-framework/commitment-and-movement.md)

### T-046 · The structure armour and HP policy #effort/medium #needs-input
Which structures are STRONG, and what the primary-resource structures resist.
**Answered so far:** Extractor → MEDIUM MECH and Bombard → MEDIUM (done 2026-09-24). STRONG to be revisited as a *tough* class (Zero Hour's `StructureArmorTough`): extra durability against ordnance, siege and super-weapons, on command centres and late high-tech pieces — e.g. STRONG should blunt the Bombard so it cannot snipe a command centre from home. Open: which weapons still do fine against it. Keep in view: too many units weak against structures.
→ [design-framework/pacing](design-framework/pacing.md), [design-framework/timings](design-framework/timings.md) §Structure armour

### T-047 · What a command centre is #effort/medium #needs-input
Cost, health, size, and what extra ones are worth. Health runs 3000 / 2500 / 400 / 400 / 400 today.
**Answered so far:** STRONG as a defensive choice — killing all of them ends the game, so they damp early volatility. See T-046.
→ [design-framework/pacing](design-framework/pacing.md), [design-framework/proposals](design-framework/proposals.md), [pacing/dominion-and-ordnance](systems/macroeconomics/pacing/dominion-and-ordnance.md) §The command centre

### T-048 · Investment terms and their ratios #effort/medium #needs-input
What a production structure is worth against the units it makes, how much technology should cost, and whether an infinite long-term income route exists at all.
**Answered so far:** reworked 2026-10-01 (site and pond rates, a per-player budget of 37000, structure prices cut by role) — next is a playtest against the wanted extractor ladder and opening menu written in [timings](design-framework/timings.md) §The extractor ladder.
→ [pacing/resource-allotment](systems/macroeconomics/pacing/resource-allotment.md) §Second pass, [pacing/structure-costs](systems/macroeconomics/pacing/structure-costs.md), [pacing/tech-investment](systems/macroeconomics/pacing/tech-investment.md)

### T-049 · The value of dominion over a match #effort/high #needs-input
Small benefits early, game-swinging late — the curve is asserted, not designed.
→ [design-framework/pacing](design-framework/pacing.md), [pacing/dominion-and-ordnance](systems/macroeconomics/pacing/dominion-and-ordnance.md)

### T-050 · Veterancy per unit #effort/medium #needs-input
What each rank grants and the experience it costs — one threshold table serves every piece today.
→ [design-framework/elasticity](design-framework/elasticity.md) §Veterancy

### T-051 · Travel-time and dodge calibration #effort/medium #needs-input
Foot, transport and scout crossing times against defender response; which rockets each flyer class evades, and whether rockets lead.
**Answered so far:** starting distance ~150–250 (feel); tune it against production times per tech tier.
→ [design-framework/commitment-and-movement](design-framework/commitment-and-movement.md) §Travel time and scouting, §Evasion; [timings](design-framework/timings.md) §The equations

## Terrain, navigation and maps

### T-052 · Which terrain artifact is the source of truth? #effort/medium #needs-input
`TerrainData.heights` and the map's `_surface.res` mesh are one surface authored twice; one should be derived from the other.
→ [CLAUDE.md](../CLAUDE.md) §The terrain pipeline

### T-053 · Map generation, pass 7 #effort/high #needs-input #shelved
Passes 1–6 and obstacle regions are built; visual facets and doodads are not. Open inside it: favor bounds, revisiting collocation, pass 4's routes rule, and whether pass 6 should flatten levels rather than reject a map whose starts lose their routes.
→ [terrain-and-navigation/map-generation](systems/terrain-and-navigation/map-generation.md)

### T-054 · Map-size parameterization #effort/medium #unscoped
`play_size` is 100 … 120 per axis; rework it together with resource and pseudo-resource allocation, spawn distances, and the share of openly traversable ground.
→ [terrain-and-navigation/map-generation](systems/terrain-and-navigation/map-generation.md) §Obstacle regions

### T-055 · Should openness be a map invariant? #effort/low #needs-input
Obstacles keep a 20-cell gap and the report lists every choke; nothing rejects a map for them. Open: whether too many chokes under some width rejects a map, and what the width and count are.
→ [terrain-and-navigation/map-generation](systems/terrain-and-navigation/map-generation.md) §Openness

### T-056 · Cliffs: what is left #effort/medium #unscoped #shelved
A cliff reads as a rocky strip rather than a face; a grown mass's face is not built; two `test_MapElevation` seeds pending; incremental relabel planned after it.
→ [terrain-and-navigation/map-generation](systems/terrain-and-navigation/map-generation.md) §6, Cliffs

### T-057 · Building-cluster balancing #effort/medium #unscoped
Guarantee counts of clusters of given sizes, positioned relative to the starts — ideally a fairness constraint like the other currencies.
→ [terrain-and-navigation/map-generation](systems/terrain-and-navigation/map-generation.md) §Buildings

### T-058 · Footprint rotation: what is left #effort/medium #scoped #shelved
Built: `Structure.quarter_turns`, oriented footprints, `[` `]` and press-drag-release placement. Left: the bot placing non-square structures at both orientations (with mirror equivariance), recording the count in the replay stream (T-037), and two-form (deploy) pieces once they exist.
→ [terrain-and-navigation/footprint-rotation](systems/terrain-and-navigation/footprint-rotation.md)

> [!check] Status — 2026-10-08
> Built the bot half: `BotEconomy` ranks a non-square footprint at both orientations in one list (a tie goes to the one lying across the threat axis), faces it up the threat axis (`facing_turns`), and orders it with that `quarter_turns` (`BotActuator.build`). Replay recording came with T-037 (an order's message carries `quarter_turns`). Tests: four new in `tests/test_BotPlacementEquivariance.gd`.
> **Not done:** two-form (deploy) pieces — still the note's §Deferred `TODO`, since no shipped piece has two forms. `Map.mirror_map` / `shift_map` keeping a rotated structure's count is unexercised until an authored map holds one.

### T-059 · Tile-type movement cost and harvestable ground #effort/medium #unscoped
`TileType.texture` is read by the shader but no tile type has one assigned; `move_cost` / `harvestable` are commented out and unread.
→ [terrain-and-navigation/tile-types](systems/terrain-and-navigation/tile-types.md)

### T-060 · Per-size-class navmesh topology #effort/high #unscoped
The shared-vertex quad topology produces holes, miters and swallowed cells for the larger classes.
→ [terrain-and-navigation/agent-size-classes](systems/terrain-and-navigation/agent-size-classes.md)

### T-061 · A wide unit must always reach a building's wall #effort/medium #unscoped
Close enough to crush a unit standing against it. Today a Stock Truck cannot reach a Shelter resident pressed to the wall.
→ [terrain-and-navigation/agent-size-classes](systems/terrain-and-navigation/agent-size-classes.md) §Reaching a building

### T-062 · Should the simulation run slower than 30 Hz? #effort/high #needs-input
With interpolated rendering; 20 Hz would cut every per-tick cost by a third. Not proposed; recorded as the largest performance lever.
→ [combat/scan-and-vision-cost](systems/combat/scan-and-vision-cost.md) §Beyond both

## UX

### T-095 · What the Drop and reinforcement sanctions draw while aiming #effort/low #unscoped
A sanction now draws an area only when the ability itself states one (an authored `effect_radius`, or an event deriving its own, like the Gunship's reach and the Mortar's blast). Drop and the Anarchist reinforcement sanctions (Ambush, Informant, Dignify) state none, so they draw nothing; what they should show — the spread their pieces land in, a marker, nothing — is deferred (Alex, 2026-10-06). Scavenge lost its unsourced circle too and was not discussed.
→ [combat/range-buckets](systems/combat/range-buckets.md) §Where a reach is measured from

### T-091 · Command-grid labels are clipped #effort/low #needs-input
Every label of five characters or more is clipped at the cell width the 6-column grid gives it ("Attack" draws as "Attac"). The remedy is a choice: shrink the font to fit, wrap to two lines, or make short labels an authoring rule.
→ `scripts/interface/hud/button_spec.gd` (`create_button_from_spec`)

### T-065 · `cursor_unknown` does two jobs #effort/low #unscoped
Catch-all and "aim elsewhere", one image. Answered "fine for now"; the two want separating together.
→ [ui/cursor](systems/ux/ui/cursor.md) §2

### T-066 · When is the OS cursor actually lost? #effort/low #unscoped
Three window notifications is a guess, not a rule.
→ [ui/cursor](systems/ux/ui/cursor.md) §The re-assert policy

### T-067 · How does a pending piece look? #effort/low #needs-input
Opacity tiers are a placeholder; hatching and outline-only are the alternatives.
→ [ux](systems/ux/README.md) §How "pending" looks

### T-068 · An estimated time to a pending piece #effort/medium #needs-input
How much of travel, build time and income to fold in, given the cost and a possible navmesh-knowledge leak.
→ [ux](systems/ux/README.md) §Estimated time to a pending piece

### T-069 · What are "fallback" and "non-fallback queued" energy commitments? #effort/low #needs-input
The Energy bar's consumption side was specified as those two; neither name exists in the code. Built as a placeholder showing `energy_spend_rate()` alone. Candidate reading: REJECT-mode vs WAIT-mode commitments.
→ [ui/economy-bars](systems/ux/ui/economy-bars.md)

### T-070 · Is the damage-multiplier table tunable in debug? #effort/low #needs-input
It is authored as TSV rather than as a doc, so tuning it means Save writing TSV.
→ [ux/ui/debug-tuning](systems/ux/ui/debug-tuning.md) §What can be tuned

### T-071 · What do real piece icons look like? #effort/medium #unscoped
Every unit and structure wears a stock-photo placeholder; no style for real icon art is decided.
→ [ux/ui/piece-icons](systems/ux/ui/piece-icons.md) §The placeholders

### T-072 · Does research get a picture? #effort/low #needs-input
An upgrade's build button has no piece behind it, so no icon slot, and keeps its text.
→ [ux/ui/piece-icons](systems/ux/ui/piece-icons.md) §The placeholders

### T-073 · Card HP: flat red, or the world bar's green→red ramp? #effort/low #needs-input
→ [ux/ui/actor-cards](systems/ux/ui/actor-cards.md) §The colour vocabulary

### T-074 · Green is both "garrison" and "funded purchase" on cards #effort/low #needs-input
Never on one card today.
→ [ux/ui/actor-cards](systems/ux/ui/actor-cards.md) §Colour collisions

### T-075 · Does the global production readout show what is being made now? #effort/low #needs-input
Built with a producing column; asked for only in Details.
→ [ux/ui/hud-layout](systems/ux/ui/hud-layout.md) §Production

### T-076 · The READY card's visuals #effort/low #unscoped
The banner says "READY" and the card shows one Cancel button; it wants elements naming the armed command and its tool.
→ [ui/control-matrices](systems/ux/ui/control-matrices.md) §Context 1a

### T-078 · Minimap visual details #effort/low #unscoped
The map layer's symbols and palette were carried over from the map generator's old review images; revisit them.
→ [ui/hud-layout](systems/ux/ui/hud-layout.md) §The minimap

### T-080 · A win/lose screen #effort/medium #unscoped #shelved
`Scenario._on_game_over` only logs.
→ `scripts/scenario.gd`, [ux](systems/ux/README.md) (menu screens)

> [!check] Status — 2026-10-07
> A match's end now shows the match summary (units and structures per commander, the winner marked) with Victory / Defeat / "Commander N wins" as its heading — [scenario-scripting/match-log](systems/scenario-scripting/match-log.md) §The summary view.
> **Not done:** pausing at the end, a way back to the menu, anything else a win/lose screen should carry.

### T-081 · A piece's model as named parts and keyed variants #effort/high #unscoped
Hull and turret; an upgrade's model swap; later cosmetics. **Blocked** on the movement and action physics rework, which owns how a part aims. The Matilda's turret already works through a scene-authored node path.
→ [ux](systems/ux/README.md) §Pieces, [combat/turrets](systems/combat/turrets.md) §The visual

## Scenario scripting

### T-082 · Does `MISSION` keep the implicit wipe-out loss? #effort/low #needs-input
Built provisionally as KEEP (the local player still loses on owning nothing / no base), because every shipped mission was written against it.
→ [scenario-scripting/objectives-and-completion](systems/scenario-scripting/objectives-and-completion.md) §Win conditions

### T-083 · The three tactics gaps #effort/medium #unscoped
A target primitive for own/neutral targets, a `Build`-issuing rule action, and a flee verb (no such command exists).
→ [scenario-scripting/tactics](systems/scenario-scripting/tactics.md)

## Authoring, tooling and code health

### T-097 · Unresolved crash causes #effort/medium #unscoped
Two crashes whose root cause is unknown, logged with their evidence: a fixture freed without leaving `Map.structure_cell_map` (surfaced by the minimap at 9:05 into a game; the minimap is guarded, the leak is not found), and an intermittent GUT shard crash tied to the 12:45 skirmish map (not reproducing with the current map). Revisit when either recurs.
→ [authoring/unresolved-crashes](systems/authoring/unresolved-crashes.md)

### T-096 · Doc values derived from other doc values #effort/high #unscoped
Alex's ideal state: a spec value may be written as an expression naming other keys of the same doc (`movement.speed`, `movement.turn_rate`, a weapon's reach …), and the importer evaluates it at import. Today the one such derivation — a `range_from: orbit` weapon setting `aerial.orbit_radius` to its ground reach — is a hard-coded edge case in `SpecRegistry._derive_orbit_radius`, which this would replace. Deferred (Alex, 2026-10-06); the expression grammar, its evaluation order and how the debug tuning editor shows a derived field are all open.
→ [authoring/spec-importer](systems/authoring/spec-importer.md)

### T-093 · The movement body is still centred on the origin #effort/low #unscoped
`MovementBody` — the cylinder a piece pushes through the world with — is centred on the origin, half underground, while the hurtbox now stands on the origin fitted to the model. Nothing aims at it (it only collides for avoidance), so whether it should be seated too, and fitted to what, is open.
→ [ux/ui/generated-visual-defaults](systems/ux/ui/generated-visual-defaults.md) §The hurtbox

### T-087 · 14 doc blocks marginally over the escalation threshold #effort/low #scoped #shelved
All at ratios between 12/10 and 16/13 — arguably not "outgrown its level" by §4.2's own test.
→ `gdd/refactoring-plan.md` item 5

> [!check] Status — 2026-10-08
> Option 2, outside the bot's files: the 16 clear blocks are a summary plus a `§` pointer now; two needed new write-ups (agent-size-classes.md §Reaching a building — the edge-adjacent rule; scan-and-vision-cost.md §One Fog drives the terrain shroud).
> **Not done:** the 13 clear cases in `scripts/interface/commander/bot*.gd`, held back for the bot session; refactoring-plan.md item 5 lists them by count.

### T-088 · Wire CI #effort/medium #unscoped
gdformat is the house style and `tools/lint.sh` enforces it; CI is what remains — and GUT in CI needs Godot plus the committed `.godot/imported/`.
→ [authoring/linting](systems/authoring/linting.md)

### T-089 · Is a pre-commit hook required? #effort/low #needs-input
Linting is (§6.3); mandating the hook is separate.
→ `~/.claude/CLAUDE.md` §Deferred
