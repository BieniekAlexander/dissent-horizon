 > [!info]- How this file works
> Each `##` is one task. Claude works this file via `/tasks` while I'm away, following the **AFK task sessions** protocol in `CLAUDE.md`.
>
> **Heading tags** — *(untagged)* not ready for execution · #ready ready to be reviewed and potentially executed · `#wip` started, unfinished · `#needs-input` has an open question · `#done` finished, mine to archive.
>
> **My job:** write tasks, and answer `[!question]` blocks after the `**Answer:**` line — usually just an option number. "Your call" hands the decision back and builds the stated **Leaning**. Then run `/tasks` again; answered questions are picked up first.
>
> Claude asks rather than assumes, and leaves undetermined pieces unbuilt. It only ever *appends* here — my task text is never edited.
>
> **This file is a work queue, not a record.** I delete tasks once they are in the project, so nothing here is durable. Anything worth keeping — a rule, a rationale, a decision and what it superseded — belongs in `CLAUDE.md` or a `gdd/` design note, and a `[!check]` note should be short enough to throw away: what changed, what is not done, and where the real write-up lives.

## Seeded pseudo-randomness, for deterministic replay #wip

The simulation is pseudo-random today but not *reproducibly* so, and the second half is what
a replay system needs.

`SU.rng` is a seedable `RandomNumberGenerator` and `Wander` uses it — but
`Projectile._apply_hitscan_error` (projectile.gd, in `_initial_velocity`) calls the **global**
`randf_range` instead, which nothing seeds and nothing can re-seed. Every hitscan shot in the
	game therefore has an unreproducible spread, so the same scenario run twice diverges from the
first shot fired.

**What it blocks right now:** duel simulations. "If these two units start attacking each other
at the same time, which wins?" cannot be answered as a single run — it has to be N trials
reported as a distribution — and a regression cannot be pinned at all, because there is no way
to replay the run that failed.

**The shape:** a scenario owns a start seed; every gameplay RNG draw goes through one seeded
generator derived from it; the seed is recorded with the scenario so a run can be replayed
tick-for-tick. Getting there is roughly:

1. Route `_apply_hitscan_error` through `SU.rng` (one line — this alone unblocks the duel sims).
2. Audit for other unseeded draws. `grep -rn 'randf\|randi\|randomize' scripts/` is short, and
   only one other gameplay site is unseeded: `ScenarioExpression` evaluates through Godot's
   `Expression`, whose `randi_range` is the global one — that is what resolves a wave's
   `15 + randi_range(0, 10)` interval, and it is exactly the kind of draw a replay must
   reproduce. Everything else already routes through `SU.rng` (`Wander`, the unit-placement
   scatter in `SpaceUtils`) or owns its own seeded generator (the terrain generators).
3. Give `Scenario` an authored `seed` and seed `SU.rng` from it at boot.
4. Only then: recording and playback of the input stream.

Steps 1–3 are worth doing whether or not 4 ever happens — they are what makes a simulation
result mean anything. Note the ordering constraint a replay adds later: seeding one shared
generator makes the draw sequence depend on iteration order, so anything that iterates a
`Dictionary` before drawing has to become order-stable first.

> [!done] Q — resolved — 2026-09-29
> Should the shipped game run the navmesh synchronously, as the self-play harness now does?
> **Why it matters:** replay (step 4) needs every navmesh change to land on the tick that asked for it. Today only the harness does that (`NavManager.use_async_iterations = false`); the game keeps chunk regions async, so a replayed match would land rebuilds on different ticks and drift. The frame cost of sync regions in normal play is unmeasured.
> **Options:**
> 1. Always synchronous — one code path, and every match is replay-safe by construction.
> 2. Synchronous only in a match that is being recorded or replayed — no cost otherwise, but two navigation timings to keep correct.
> 3. Keep async and drop exact replay — step 4 becomes "re-simulate from seed and inputs, accept drift".
>
> **Leaning:** 1 — the harness already runs sync at 15–25× real time, which suggests the cost is small; measure a rebuild's frame time before switching.
>
> **Answer:** 1; deterministic replay is the priority
> **Resolved:** option 1 — `project.godot` turns off async iteration for navigation maps and regions; the harness's own switch and `NavManager.use_async_iterations` are gone. Write-up: `navigation-and-pathing.md` §Navigation is synchronous, for replay.

> [!check] Progress — 2026-09-29
> The "coin flip" (one seed, two trajectories) is found and fixed: the navmesh's chunk regions stayed async in the harness, so the opening force deployed on tick 1 or tick 2. `NavManager.use_async_iterations` now reaches them, and the harness turns it off. Same-seed runs are now bit-identical: 10/10 at 40 s, 4/4 at 300 s, and seeds 3 and 7 4/4 each with 8 processes in parallel. This also fixes the coin flip the CPU Bot notes below cite. Write-up: `selfplay-harness.md` §Determinism. The RVO-thread explanation there is now `REJECTED`.
> Also: `start_point.gd` had an unseeded editor `randf()` (the known `test_SeededRandomness` failure) and now uses its own generator. The harness now cuts the spectator labels' signal connections before freeing them; they used to log an error on every resource change.
> Tests: `test_SeededRandomness` 8/8, `test_NavChunks` 5/5 (2 new), the other nav suites pass. `test_NavChangeReplanning` failed once in 13 runs, and passed 8/8 with my line reverted, so it may be a rare flake.
> **Not done:** step 4 (recording and playback), not started, waiting on the Q above. (The harness's exit segfault is fixed: `PurchaseTransaction.cancel` no longer refunds a freed commander, `tests/test_PurchaseTeardown.gd`.)

> [!check] Progress — 2026-09-29 (navigation)
> Navigation is synchronous in the shipped game (`project.godot`). Measured first: no frame-time cost (seed-1 match, 9,000 ticks, headless: mean 5.3 ms sync vs 6.1 ms async, p99 ≈ 11 ms both). One fix it needed: `NavManager._advance_changes` waited for a map iteration AFTER the regions', which a synchronous map never publishes, so rebuilds never "landed" and units stopped re-planning around new structures. On a synchronous map, ready now means landed.
> Tests: `test_NavChunks` (navmesh is synchronous), `test_NavChangeReplanning` 13/13 ×3 (new test for an async map). Full per-file sweep: 2970 pass, 13 fail in 10 files, all known in-flight failures or the `debug_panel.gd` parse error (`DebugRoster.faction_of_scenes`). Seeds 1 and 3, 4 runs each at 300 s: bit-identical, no exit crash.
> **Not done:** step 4, recording and playback of the input stream. Needs scoping (`/scope`) before building.

> [!check] Progress — 2026-09-29 (scoping)
> Step 4 scoped and your answers recorded as a PLANNED plan: `gdd/systems/commands/recording-and-replay.md`, indexed as `deferred.md` 2.46, with pointers from the harness, debug-mode and dialogs notes.
> Also in the plan since: "Save replay" on end-of-scenario dialogs (name prefilled, editable), a replay list on the start screen, and three rotating autosaves named `autosaved_replay_<UTC timestamp>`.
> **Not done:** nothing built. Two TODOs stay in the note: which standard compression codec (and whether Godot's gzip output is plain gzip), and measuring cross-platform determinism.
## CPU Bot Behavior Work #wip #needs-input
I've made significant progress on the implementation of the game since starting the Bot Behavior modules. Now, I would say that the set of possible actions from a player will not change that much, so I'd like to revisit, fix, and improve how it works.
### High Level Goals
- Difficulty: Support various difficulty levels. The current set of difficulties in `player_slot.gd` is fine. The goals are:
	- PASSIVE - should be minimally active, and should never attack the player
	- IMPOSSIBLE - ideally, it works so effectively that a human player will never realistically beat it. With that in mind, it can have highly effective economic planning and execution, frame-perfect micromanagement, etc. The only caution I have is that, ideally, the bot shouldn't play so defensively that two IMPOSSIBLE bots end up in stalemates.
	- EASY, MEDIUM, and HARD can be progressions up to the IMPOSSIBLE difficulty level, with built-in handicaps in its decision-making against a hard opponent.
- Representation of behavior: A lot of stuff is built out already. I was loosely inspired by [this discussion](https://www.youtube.com/watch?v=Bo0X6XMsg6M) - please go through its transcript as research, and give me a summary of how the described framework fits or differs from what's built in this project right now
- Generalization - of course, this game is still in development, so things are subject to change. Many systems are crystallized though, so its in a state where it should be ready to built bot behaviors that can be used to see matches to completion. Some notes on my goals for generalization:
	- Most economic decision-making can be framed as short-term long-term trade-offs of collecting the primary resource (energy). Against a completely passive opponent, it would be most effective to just scour the map for primary resource deposits, take them, and start military production when all on-map resources have been secured. This will be infeasible if the opponent attacks, so the bot must have some sort of habit of scouting the opponent's capabilities, preemptively making military and technology to prepare itself to defend, and sometimes make the decision to attack the opponent
	- The unit counter system is pretty well defined by now. The bot should be able to derive decisions around unit combat effectiveness against other units based on the stats in the game.
	- Some mechanics in the game will probably just be too tricky to generalize for, and I'm okay with having to revisit the bot implementation and potentially hard-code some behaviors, though I think the hardcoding should just pertain to the most minute details of the gameplay decisions. For example, dominion is one of the game's core resources, and the bots should have some sort of model for wanting to acquire more dominion. However, the method of dominion gathering will vary a lot, so I'm okay with changes being needed whenever I introduce a new dominion generation method. The game currently has the following factions, with the mentioned methods:
		- Colonial - capture light infantry units from the map (enemy combatants are neutral units), and bring them to a structure so that they generate dominion
		- Anarchical - build Warlord units, and colocate them with friendly infantry units to generate dominion
	- Some of the properties of this game are very uncalibrated, and I do have to fix a lot of these things, but the decision making of the bot should still be able to correctly make decisions based on the balance of things as configured. For example, Colonial players will start with a Stock Truck, and I intend for it to be an appropriate scouting tool. However, given that the bot is wanting to scout (and it should generally always be doing it with at least one unit, which I think is already implemented), it could be that a different unit makes for a better scout (with more movement speed or better vision range). As such, the bot should use that other hypothetical unit for scouting, and it's on me to reconfigure the game unit's properties if I want a different unit to be what the bot opts for.
### Modeling
- If any particular things are hard to generalize for, I'd like to provide some signal that the bot can use to understand how to use them, rather than hard-coding the bot's use of them. But, surely some details will be so difficult to model to this extent that I'm okay with things being hardcoded and determined with heuristics. Some examples:
	- determining "what makes a good scouting unit" can involve the questions:
		- how much does this unit cost? How long does it take to make?
		- how fast is the unit? What is the unit's vision range?
		- What other responsibilities does this unit have? Are those responsibilities currently applicable to this unit?
			- For example, the stock truck is a good starting unit because it doesn't have any sort of responsibilities at the start of the game. Effectively, its only responsibility is to crush infantry units and bring them back to a Compound for dominion generation. So, the decisions regarding the Stock Truck's are ultimately (in descending priority):
				- If I'm in danger, run away
				- if I can run over nearby enemy units, do so
				- If I'm full of inventory, go back and drop it off
				- otherwise, scout around the map
	- On abilities:
		- I think most abilities (other than building) are best used as often as possible, though there are some tradeoffs to them:
			- If an ability has economic implications (Free resources or units), it should be definitely used all the time
			- If a unit has offensive application, it's probably good to use often, but such abilities are probably also good to save for more impactful moments, or particularly defensive moments
		- For example, the "Dignify" ability is effectively an economic ability (you can convert a cheaper unit into a more expensive unit), but  it can be used offensively and defensively (a warlord might be more appropriate in a given battle)
### Training
- I'm interested in taking an adversarial reinforcement learning approach to test these models and try to optimize them.
	- Some things to explore:
		- As faction X, if I'm playing against faction Y, how many of each production structure should I plan to use?
		- How should I be placing my structures?
		- What heuristics should I be using to aim my abilities?
	- Some thoughts on searching state spaces for bot parameters:
		- When exploring optimization of a particular behavior, it's probably best to constrain parameters for other behaviors so that they're equal. For example, if I'm looking to optimize parameterization of "how much of each production structure should my base have", best to constrain all other behavior parameters (how many units should be scouting, how greedily should I be getting more energy, etc.).
		- For the sake of speeding up such parameter optimizations, it would also make sense to have a harness of test scenarios which could be used to focus on the relevant thing being optimized:
			- Suppose I want to test what units I might want to produce (set X), knowing that my opponent will have a given set of units (set Y). To model and test the validity of a given decision rule, I can just make a scenario that will auto create units set X and Y, have them fight eachother, and see how they did.
			- Suppose I want to test how many units I should be using to scout a map. It doesn't suffice to test this by setting parameter `n`, creating a map to be explored, and seeing how many units `n` would best scout the map, because `n=infinity` is obviously ideal, and the correct number of scouting units is moreso a question of trade-off: how many units can I use to scout so as to see more of the map, and minimize the negative impact of having my scouts be isolated and away from their other responsibilities?
		- I'd be interested in having a harness for using human players as the testing opponents of the bots, though I imagine it would be infeasible to try to model the apparent decision-making of the human player to understand what parameterizations of the bot were ineffective

> [!done] Q — resolved — 2026-09-04
> Can you paste the talk's transcript (or its key points) into this task?
> **Why it matters:** you asked for a comparison of ZeroSpace's framework against what is built here, and **I could not retrieve the transcript** — YouTube serves neither captions nor description body to the tooling I have. All I confirmed is the chapter list (*RTS has a predictability problem* · *The Failed Experiments* · *The 3-Layer Solution* · *The Snowball Effect* · *Playtesting results*) and the premise, that a script players work out is a broken AI. Writing the comparison from chapter titles would be inventing someone else's design and then measuring yours against my invention, which is worse than not writing it.
> **Options:**
> 1. Paste the transcript here and I write the comparison properly next session.
> 2. Skip it — take the audit and roadmap I wrote on their own merits; the talk was inspiration rather than a spec.
> 3. I write the comparison against a NAMED public framework instead (Dave Mark's utility-based IAUS, or the standard three-layer strategic/operational/tactical RTS split), which I can cite accurately.
>
> **Leaning:** 1 — you picked that talk for a reason, and the two things its chapter titles alone suggest are both real gaps here: nothing in this bot reads whether it is winning or losing ("the snowball effect"), and its predictability is structural rather than incidental.
>
> **Answer:** I've placed it in `gdd/cure-for-predictable-game-ai.md`
> **Resolved:** Option 1 — comparison written against the real transcript in `gdd/systems/ai/three-layer-comparison.md`; the three gaps it found are `TODO`s in `gdd/systems/ai/bot-roadmap.md` §The vision layer / §Reading the game.

> [!check] Progress — 2026-09-04
> Mostly planning, as you expected, plus the one piece that was blocking everything else.
> Write-ups: **`gdd/systems/ai/`** — `bot-architecture.md` (what exists) and `bot-roadmap.md`
> (the plan, with a TODO per deferred decision). CLAUDE.md gained the pointer row.
>
> **The audit's one-line finding:** perception is strong (~60 senses on `Bot`, and
> `BotProduction` already derives its choice from the damage matchup table), but **almost
> every other decision is a fixed ladder or a fixed call order rather than a comparison.**
> The economy builds in a set sequence; the scout beats the military because it is called
> first; the military picks one of three postures. Nothing asks whether scouting is worth
> more than attacking right now — and a ladder is a script, which is exactly the
> predictability the talk's premise is about.
>
> **BUILT — difficulty is a real knob** (`scripts/interface/commander/bot_difficulty.gd`).
> It was read in two places and every module carried a "difficulty knob later" comment, so
> there was nowhere to put the outcome of any tuning. One flat data object per tier —
> reaction time, army commit threshold, preservation cost floor, retarget margin, scout
> budget, economy reserve, `may_attack` — read by `BotBrain`, `BotMilitary`, `BotTargeting`,
> `BotScout`, `BotEconomy` and `BotSanction`. **Numbers, not branches, deliberately**: the
> tiers are meant to be searched by the self-play harness, and holding other parameters equal
> (your own rule) is impossible for a tier that differs by `if`.
>
> **BUILT — PASSIVE is minimally active rather than inert.** It was `active = false`, i.e. no
> brain at all, which is scenery rather than the sparring partner you described. It now
> thinks, builds, trains and DEFENDS; `may_attack` stops the military ever leaving home and
> stops `BotSanction` opening with an ability (it still defends with one).
>
> **Not done, on purpose:** the ladder→scored-options conversion, which is the substantive
> work. It is blocked on one decision I did not want to make for you — see
> `bot-roadmap.md` §Then: arbitration, WHAT the common currency is. Energy-equivalent value
> works for the Opportunist because a captured unit has a price; it does not obviously price
> "seeing the enemy base", and a bad answer there is worse than the ladder we have.
>
> **Also worth knowing:** the tier NUMBERS are placeholders on a hand-made ramp — the test
> pins the ramp's DIRECTION, not the values, so don't balance against them yet. And the
> self-play harness is blocked on the seeded-RNG task above it, which is a prerequisite
> rather than a neighbour.

> [!done] Q — resolved — 2026-09-04
> What is the common currency the bot compares options in?
> **Why it matters:** this is the blocker on the whole ladder→scored-options conversion — the economy ladder, the scouting trade-off you named, and the military posture all wait on it. `BotOpportunist` already scores in ENERGY-EQUIVALENT value and that works because a captured unit has a price. It does not price "seeing the enemy's base", and picking wrong here is worse than the ladder we have, because a bad score is a confident bad decision where a ladder is at least a legible one.
> **Options:**
> 1. Unitless utility in [0, 1] per option, with per-tier weights — the classic utility-AI shape. Every module gets a `score()` returning a normalised number; `BotDifficulty` gains the weights and the self-play harness searches them.
> 2. Energy-equivalent throughout, with an authored constant for what information is worth. Keeps one currency and `BotOpportunist` unchanged; the information constant is the fudge.
> 3. Leave the economy on its ladder and score only the unit-claiming decisions (scout vs army vs errand). Smallest change, and it fixes the call-order arbitration without needing to price a building against a scout.
>
> **Leaning:** 1 — it is what the difficulty weights want to modulate anyway, and `BotScout._scout_score` (built this session) is already that shape, so it would be the second module in the same idiom rather than a third mechanism.
>
> **Answer:** Let's go with 2 for now. The primary resource is a reasonable proxy for decision-making in a lot of places:
> - "Should I sacrifice this kamikaze unit on a given target" definitely should be a calculation of "Will the result of this action outweight the cost of the unit"
> - Use of energy as a cost metric can be used to revisit unit costs - if this unit is not effective enough at its current cost, it might be a good idea to strengthen it or decrease its cost
> - My primary concern is the tradeoff of pursuing more energy gain vs more dominion gain, but this can be the subject of some sort of modeling exercise for the future.
> **Resolved:** Option 2 — energy-equivalent throughout, with `BotScout.INFORMATION_VALUE_ENERGY` as the one authored price. Written up with your three arguments in `gdd/systems/ai/bot-roadmap.md` §The currency is ENERGY-EQUIVALENT; the energy-vs-dominion half is a TODO there, and it is why the ECONOMY ladder is not the first conversion. First conversion built instead: scouting (`BotScout._scouting_is_worth_it`).

> [!done] Q — resolved — 2026-09-04
> Should the bot get a "am I winning or losing" signal, and measured over what?
> **Why it matters:** it is the single biggest gap the transcript comparison found, and it is upstream of the behaviour the talk singles out as the human one — retreat. Today the bot retreats a UNIT only when it is under 25% HP and can damage nothing in range (a hopeless matchup, not a losing fight), and its army never retreats at all: a launched wave runs until spent to 35% of its launch value whatever happens to it. That is exactly the hard-commit the talk opens by criticising. Nothing currently reads `relative_threat_level()`.
> **Options:**
> 1. Army-value trend — sample `army_resource_value()` over a window and read the slope. One number, cheap, unblocks army retreat immediately; blind to economy, so a bot losing on income reads as fine.
> 2. A position score — army value plus income plus territory held. Sees the slow loss the trend misses; more parameters to get wrong, and each needs its own weight.
> 3. Per-engagement outcome — did the last fight trade well. Closest to what retreat actually wants; hardest to attribute, since "the last fight" has no clean boundary.
>
> **Leaning:** 1 first, with 3 added specifically for the retreat consumer later. A trend line is one sampled value and it unblocks the army-retreat work in the same change; 2 can be grown out of 1 by adding terms rather than replacing it.
>
> **Answer:** Go for 1 for now so that it can be tested, subject to change.
> **Resolved:** Option 1 — `scripts/interface/commander/bot_momentum.gd` (army-value trend, 8 s window, read as a loss rate), consumed by `BotMilitary`'s new army retreat. `tests/test_BotMomentum.gd`. Its blind spot (it cannot see the enemy's losses) is a TODO in `bot-roadmap.md` §Reading the game.

> [!done] Q — resolved — 2026-09-04
> May I move clustering into the perception layer? (Refactor approval, per `~/.claude/CLAUDE.md` §9.)
> **Why it matters:** the transcript's vision layer is built on clusters, and the comparison found we have the idea implemented three times and shared zero times — `ClusteringUtils` (general, called only by a scenario event), `BotSanction._densest_cluster`, and `Bot._aoe_hit_value`. The absence has a concrete cost: `BotMilitary` can only ever point the whole army at ONE position, because it has no representation in which "half the army" or "the smaller of two threats" is a thing. This touches three modules, so it is your call before it starts.
> **Options:**
> 1. Add a `Bot.enemy_clusters()` sense over the blackboard belief (members, centroid, summed strength, mean velocity), and repoint `BotSanction` and `BotKamikaze` at it. One new sense, two call-site changes, three implementations become one.
> 2. Add the sense but leave the two existing scans alone — no regression risk to sanction aiming or kamikaze valuation, at the cost of keeping the duplication you already have.
> 3. Not yet — it only pays off once something consumes clusters strategically (splitting the army), so defer it until that is being built.
>
> **Leaning:** 1. It is the enabling primitive for both the military work and the "which threat" questions, and the risk is contained: the two existing callers have tests, and per-tick clustering cost is measurable before it is widened.
>
> **Answer:** 1. I'm planning to briefly iterate on army command issuance tactics and strategy.
> **Resolved:** Option 1 — `Bot.enemy_clusters()` / `Bot.best_covered_point()` in the perception layer, with `BotSanction` and `BotKamikaze` repointed at the shared scan. `tests/test_BotClusters.gd`. See `bot-architecture.md` §What the bot models about the enemy.

> [!check] Progress — 2026-09-04
> Picked up your answered question first, then built the one piece of the task that was determined without a decision from you.
>
> **BUILT — the transcript comparison** you asked for: `gdd/systems/ai/three-layer-comparison.md`. The short version: our three layers are not his three (ours splits by who may mutate state, his by scale of decision, and what we call "decision" is his strategy and micro fused — the fusion he warns about). Four things genuinely match, and one of them we arrived at independently and did not know was his: `Sanction.targeting` / `min_targets` IS his "per-ability drop-down of how the AI should use it". Three gaps: no clustering in perception, no history or "am I winning" anywhere, and no retreat worth the name. Each is now a `TODO` in `bot-roadmap.md`, and each has a question above.
>
> **BUILT — what makes a good scout, derived** (`BotScout._scout_score`, `tests/test_BotScout.gd`, 9 tests). It picked the fastest free unit; it now scores speed, vision, replacement cost (energy + build time) and how many of the unit's OTHER jobs are live right now — one per manager that would otherwise claim it, counted only when that manager has work to give. That last term is what makes the Stock Truck the right opening scout without naming it anywhere: unarmed, cannot build, and its capture errand has no target until enemy infantry is in sight. Change a unit's speed or vision and the bot's choice follows with no bot change, which was your stated goal. Weights are placeholders on the same footing as the difficulty ramp.
>
> **Corrected two stale claims in `bot-architecture.md`** that would have misled the next session: `BotTargeting` runs four signals, not one; and `BotMilitary`'s attack commitment is a real comparison (army value vs a decayed-peak enemy estimate, humility prior, anti-stalemate relaxation), not the bare threshold the note described. That commit rule is the anti-stalemate property you asked IMPOSSIBLE to have, and it already exists.
>
> **Tests:** 1964 passing, 1 pending (the deliberate RNG one), **1 failing — not mine**: `test_ControlBinding.gd::test_grid_collisions_are_all_acknowledged`, a hotkey collision between `command_tool_lb_dominion` and `command_tool_lb_tech1` at grid (2, 0). `command_tool_lb_tech1` exists only in the working tree's `resources/generated/tools.json` and not at HEAD, so it comes from your in-flight libertarian doc edits. Either move a binding or add it to `_ACKNOWLEDGED_COLLISIONS`. Lint clean (gdlint was not installed on this machine; I ran it from a throwaway venv rather than touching your environment).
>
> **Not done:** everything the three questions above cover — the arbitration currency, the winning/losing signal and the army retreat it unblocks, and the clustering move. Nothing speculative was written against any of them.

> [!check] Progress — 2026-09-04 (second session)
> All three answers picked up and built. Nothing is parked; there are no open questions on this task.
>
> **BUILT — clustering is a perception primitive** (Q3). `Bot.enemy_clusters()` groups visible enemy units into forces (members, centroid, summed strength, energy value, mean heading), strongest first — that is the thing you need for army command issuance, because before it there was nothing between "one unit" and "the whole army" to point half an army at. Alongside it `Bot.best_covered_point(candidates, radius, weight)` answers the other question, "where should a radius-R effect land"; `BotSanction`'s aiming and `BotKamikaze`'s blast valuation are now the same scan asked two questions instead of two independent O(n²) copies. **Worth knowing when you build on it:** the two are genuinely different questions — a group's centroid does NOT give you a good drop point, since a chain of units is one group whose centre may reach none of them. `Bot.entity_strength` fell out of the same pass: "damage × remaining HP fraction" was written three times and is now one definition. `tests/test_BotClusters.gd`, 12 tests. Clusters are of LIVE visible units; the believed-set variant is a TODO.
>
> **BUILT — `BotMomentum`, and the army retreat it unblocks** (Q2). Army value sampled on the think cadence, read as a loss rate over an 8 s window. `BotMilitary` now calls a wave off when the army has lost 30% of its launch value AND momentum says it is still bleeding — both halves, because losses already taken are not a reason to leave (a wave that spends a third of itself killing their army has won) and a bot that pulls back on damage is the dribbling bot the wave rule was written to stop. A called-off wave regroups at home for 20 s; without that the posture's army-size branch re-ordered the attack the same think the retreat was decided. `tests/test_BotMomentum.gd`, 12 tests. **One change beyond what you asked:** a wave that runs to SPENT now also regroups rather than immediately re-attacking with the remnant — the old comment said "then regroup" but there was no mechanism. Say if you want that back.
>
> **BUILT — energy as the currency, and its first conversion** (Q1). Written up with your three arguments in `bot-roadmap.md` §The currency is ENERGY-EQUIVALENT. **The economy ladder is NOT the conversion I did, and your own answer is why:** pricing a dominion structure against an extractor needs the energy-vs-dominion trade you deferred, so that conversion is blocked on the exercise you named. Scouting is not, so that is what I converted — `BotScout._scouting_is_worth_it` compares `INFORMATION_VALUE_ENERGY × how-blind-we-are ÷ (scouts already out + 1)` against `unit_cost × ABSENCE_RISK`. The divisor is the answer to "why not scout with everything": the second scout buys half what the first did at the same price. `scout_unit_budget` survives as a CEILING rather than the decision, so the difficulty knob still means something — and a budget above 1 now actually does something, which it never did. `INFORMATION_VALUE_ENERGY = 400` is the one authored price in the bot and the number I would most like you to argue with.
>
> **The Scout is now the model for converting the others.** It still runs before the Military, but it DECLINES the claim when scouting is not worth the unit's absence — so the Military gets the unit by the Scout's own reckoning rather than by losing a race. Converting a manager means giving it that refusal.
>
> **Tests:** 1995 passing, 1 pending (the deliberate RNG one), 31 new. **Same 1 failure as last session and still not mine** — `test_ControlBinding.gd::test_grid_collisions_are_all_acknowledged`, `command_tool_lb_dominion` + `command_tool_lb_tech1` at (2, 0), from your in-flight libertarian docs. Lint clean.
>
> **Not done, on purpose:** the economy ladder (blocked on energy-vs-dominion, above), the military posture as scored options, opponent HISTORY on the blackboard, and per-engagement outcome for momentum. All four are TODOs in `bot-roadmap.md` with the reason attached.

> [!done] Q — resolved — 2026-09-04
> How should strategic posture (all-in, booming, turtling) be represented?
> **Why it matters:** you asked me to explore this rather than decide it, and it is the one design choice that constrains everything else — every existing decision would consume it, so picking wrong means rewriting the consumers rather than the layer. Written up with the reasoning in `gdd/systems/ai/objective-selection.md`; this is just the choice.
> **Options:**
> 1. A POSTURE VECTOR that modulates the parameters the modules already read — 3–4 continuous dials (commitment, aggression, risk, curiosity) recomputed each think from game signals, multiplying `army_commit_threshold`, `economy_reserve`, `INFORMATION_VALUE_ENERGY` and so on. All-in and booming become regions of that space and are never written down anywhere.
> 2. SCORED OBJECTIVES in energy-equivalent — the bot prices candidate objectives (take that expansion, kill that army, reach that tech) and commits to the best. Reuses the currency directly, but answers "what to go for" rather than "how to play", and booming is not an objective.
> 3. A BLEND over named archetypes — a simplex like 0.6 boom + 0.4 turtle. Legible and gradated, but the archetypes are authored, so it is the categorical model with interpolation.
>
> **Leaning:** 1 as the strategy layer with 2 underneath it as objective selection — three levels, each a comparison, each searchable. It is a multiplication over what is already built rather than a rewrite, and it unifies `BotDifficulty` (a fixed parameter set), posture (a time-varying modulation of one) and your throttling idea (a third member of the same family) into one mechanism.
>
> **Answer:** Your approach sounds fine to me
> **Resolved:** Option 1 (posture vector) as the strategy layer with option 2 (scored objectives) underneath, recorded as SETTLED in `gdd/systems/ai/objective-selection.md`. Not built — and the note's own first check found a blocker worth knowing about before it is: there is no ECONOMY signal for either side, which is disqualifying for exactly the two postures the layer is named after.

> [!check] Progress — 2026-09-04 (third session)
> Decision-surface audit, the drift check you asked for, and the design write-ups. No behaviour changed this session.
>
> **BUILT — `tests/test_BotCommandCoverage.gd`.** Every command class is classified into ISSUED / COVERED_OTHERWISE / NOT_THE_BOTS / MISSING, and the test enforces it **both ways**: a new command nobody classified fails, an ISSUED claim the bot does not actually make fails, and a gap the bot has since filled fails rather than sitting in the table as fiction. Coverage is DETECTED by finding the construction in the bot's own source, not declared — a table taking my word for it would reproduce the same silent failure one level up. I verified it actually trips by breaking it in both directions before restoring it. `FocusFire` and `Wander` are your NOT_THE_BOTS entries; queueing has its own test asserting the bot never appends to a command queue.
>
> **The surface audit** is in `bot-architecture.md` §The decision surface — one row per decision, organised by what is being SPENT (energy, dominion, charges, unit-time), which is what makes it checkable for completeness. Gaps are `bot-roadmap.md` §The gaps in the decision surface. Sharpest finding: the actuator exposes 7 verbs against 23 command classes, and `BotSanction` makes no actuator call at all — it bypasses the one rule the architecture is built on, which is *why* abilities are the hardest thing to extend.
>
> **Written up from your reply**, each where it belongs rather than here: abilities are structure actions so they need no module of their own (roadmap, ability gap); "what to make" and "where to make it" are one decision (gap 5b, with your about-to-die-structure case); reload time as three tiers, with "a unit that must dock is a unit without an attack until it has docked" (gap 5c); managed-group count as a difficulty throttle, and attention — groups, decisions per think, reaction time — as one family (gap 1); idleness defaults to scouting but throttled idleness is legitimate and looks identical (gap 2); withholding stays `economy_reserve` and is explicitly deferred (currency section).
>
> **The one open question is above** — strategic posture. Everything else you said is recorded as a rule with its reasoning; that one I would rather not pick for you, because every existing decision would consume it.
>
> **Tests:** full suite green apart from the same `lb_dominion` + `lb_tech1` hotkey collision from your in-flight docs. Lint clean.

> [!check] Progress — 2026-09-04 (fourth session)
>
> **BUILT — `UseSanction` now goes through the player's interface.** `BotActuator.use_sanction` builds the CommandMessage, asks `UseSanction.meets_precondition` exactly as `RTSController` does before issuing, and hands the caster the command; `BotSanction` decides which sanction, which caster and where, and nothing else. It no longer holds a `ScenarioTriggerManager` at all — the command resolves the event host itself — so the constructor lost that argument.
>
> **What the bypass was actually costing:** firing the event directly skipped every gate in the precondition — unlocked, a real caster, finished being built, POWERED, charged, target spotted. A dark building could cast; the player's could not. That is the general hazard worth remembering: **a bot that reproduces an action instead of ordering it drifts from the player's version silently**, because no test is looking at both. `tests/test_BotCommandCoverage.gd` is now what keeps them together — `UseSanction` moved from COVERED_OTHERWISE to ISSUED, and the test verifies the construction rather than believing the table.
>
> One small guard came with it: a caster already carrying a `UseSanction` is skipped, since the charge is not spent until the command fulfils and the bot would otherwise re-order the same cast every think until it fired.
>
> **On the posture answer** — recorded as settled, not built. Before building it I checked the note's own prerequisite, that the postures are decidable from signals the bot has, and they are not quite: **there is no income sense for either side.** Booming is a response to being behind on economy and all-in is a response to the opponent being ahead on it; with only army values to read, the bot cannot tell "they out-produce me" from "they happen to have fewer units on the field", and those call for opposite play. Own income is arithmetic over `EnergyExtractor`; the enemy's is a fog-limited estimate off the blackboard — and being wrong about it is correct, since that is what makes scouting pay. That is the next thing I would build, ahead of the posture layer itself.
>
> **Tests:** 2002 passing, 1 pending, same single pre-existing `lb_dominion` + `lb_tech1` collision from your in-flight docs. Lint clean.


> [!done] Q — resolved — 2026-09-05
> What should a unit do when nothing claims it?
> **Why it matters:** `BotMilitary._combat_units` filters UNARMED units out of both the re-task and the idle sweep, `BotScout` caps itself at `scout_unit_budget` (1 for every tier below IMPOSSIBLE), and `BotOpportunist` only has work when a liberation or capture target exists — so a unit that is unarmed and currently unwanted is claimed by nobody and stands still for the rest of the match. Measured across ten self-play matches: idle units peaked at 8-22 per side before the engagement fixes and 3-7 after, monotonically rising in every one. This is `bot-roadmap.md` §gap 2 with numbers on it, and the roadmap's own answer (idle defaults to SCOUT) is one of the options below — but you also recorded that THROTTLED idleness is legitimate and looks identical from outside, which is why I am not picking.
> **Options:**
> 1. Idle defaults to SCOUT — `BotScout._scouting_is_worth_it` already prices the trade, so let a unit nobody else wants past the `scout_unit_budget` ceiling rather than being capped by it. The budget stays the cap on units DRAFTED away from a job; a unit with no job is free.
> 2. Idle defaults to DEFEND — unarmed units gather at the most valuable owned structure and garrison where one accepts them, so they are preserved and add vision at home rather than being spent as scouts.
> 3. Idleness is a difficulty THROTTLE — make "how many units the bot may have live jobs for" an explicit `BotDifficulty` field, so idle bodies are the visible handicap of a lower tier and IMPOSSIBLE has none. Nothing else changes.
>
> **Leaning:** 1 — the scout module is the one manager that already refuses a claim it cannot justify, so handing it the leftovers costs nothing when scouting is not worth it, and it directly buys the map knowledge every other decision is starved of.
>
> **Answer:** I don't have a very direct answer. Generally, I wouldn't expect the bot to own many units that can't attack. The options seem to be ad follows:
> - the bot started with Servants, which are builders and can be used for dominion generation, and Stock trucks, which are auxiliary units which collect more servants, but they can also be used in combat because they can crush. 
> - the bot created more such units. That would make sense particularly if the bot lost some units or could benefit from more in the game, but I think one of the biggest things to ensure is that the bot is not making too many such units, because there are likely better units to purchase.
> I would also say, however, that the hardcoded one scout maximum is definitely overtuned. This can be a per-difficulty throttle.
> **Resolved (in part):** Built the two pieces the answer determines — a real per-difficulty `scout_unit_budget` ramp (0/1/2/3/4, was flat 1 below IMPOSSIBLE) in `scripts/interface/commander/bot_difficulty.gd`, and crush-aware combat accounting (`Bot.unit_is_armed` / `unit_can_crush` / `unit_has_combat_utility`, consumed by `BotMilitary._combat_units`) so a Stock Truck is no longer filtered out of both the re-task and the idle sweep. `tests/test_BotCombatUtility.gd`, `tests/test_ScenarioPlayerSlots.gd`. The production half — capping utility units against better purchases — is a fresh question below.

> [!done] Q — resolved — 2026-09-05
> Should the bot's ATTACK objective be fog-limited?
> **Why it matters:** `Bot.nearest_enemy_structure_to_base()` and `Bot.get_enemy_units()` read the live scene, not the blackboard — the bot ALWAYS knows where the opponent's base is, from tick 0, without ever having scouted it. That is what made the broken-fog matches look committed (`has_attack_objective` true from tick ~300 while `believed_enemy_army_value` stayed 0) and it is why the bot can attack at all before it has seen anything. It also decides whether scouting is worth anything in the training harness: if the attack objective is free, `INFORMATION_VALUE_ENERGY` is buying much less than it appears to. Nothing records this as a decision either way.
> **Options:**
> 1. Leave it omniscient about the enemy BASE, and say so in `bot-architecture.md` as a deliberate handicap-free shortcut — a human player learns the map's start points too, so knowing where the opponent spawned is not really information.
> 2. Make ATTACK read the blackboard's believed structures, so an unscouted opponent has no attack objective and the bot masses at home until it finds one. Scouting becomes a precondition for aggression, which is what makes it worth its price.
> 3. Make it a PARAMETER (`BotDifficulty.knows_enemy_base`), omniscient for IMPOSSIBLE and fog-limited below — the same shape every other handicap already has, and searchable.
>
> **Leaning:** 2 — option 1 is defensible for the base's LOCATION but `get_enemy_units()` is not a start point, it is live perfect knowledge of the enemy army's position, and the two arrive through the same call.
>
> **Answer:** 2
> **Resolved:** Option 2 — `Bot.nearest_believed_enemy_structure_position()` / `nearest_believed_enemy_unit_position()` feed `BotMilitary._objective_for(ATTACK)`, so an unscouted opponent yields no attack objective and the bot masses at home. `tests/test_BotHostileTargets.gd`; write-up in `gdd/systems/ai/bot-architecture.md` §The attack objective is a belief, with the controlled A/B in `bot-engagement-fixes.md` §Fog-limiting the attack objective.

> [!done] Q — resolved — 2026-09-05
> When is a side beaten?
> **Why it matters:** the harness calls a slot eliminated only when it owns NOTHING. In seed 6 slot 1 was down to **zero structures and one surviving unit** by simulated minute 16 and rode that to the 20-minute cap, so a match that was decided at minute 16 is recorded as a stalemate. The winner had 4-5 units in ATTACK posture, three of them idle, and never hunted the straggler — `_objective_for(ATTACK)` sends the army to `enemies.front()`, an arbitrary unit, and the army does not re-task while the objective barely moves. This is the cheapest remaining fix in the whole engagement problem and it changes what the training objective measures, which is why it is yours.
> **Options:**
> 1. Change the RULE: a slot with no structures and no production is beaten, in the harness and in `Scenario._check_player_eliminated` alike. Matches the intuition ("they have no base") and needs no bot change.
> 2. Change the BOT: with no enemy structures left, ATTACK hunts the nearest believed enemy UNIT and re-tasks as it moves, so the army finishes the game. Slower to build, but it is a real behaviour the bot is missing rather than a scoring convenience.
> 3. Change neither, and score the objective on TIME-TO-DECIDED rather than on the outcome flag — the series already shows the minute the loser lost its last structure.
>
> **Leaning:** 1 — the win condition is the thing that is wrong (a commander with no buildings cannot come back), and 2 is worth building anyway but should not be what a match verdict depends on.
>
> **Answer:** 1.
> **Resolved:** Option 1 — `Commander.has_production_base()`, applied in `scripts/scenario.gd` (`_check_player_eliminated`, behind its own arming latch) and in `tools/selfplay/run_match.gd`. `tests/test_Elimination.gd`; rule written up in `gdd/systems/ai/selfplay-harness.md` §No structures and no production is a defeat.

> [!done] Q — resolved — 2026-09-05
> How should the three tests the fog fix un-blinded be repaired?
> **Why it matters:** `Fog` used to resolve its Map from `get_tree().current_scene`, which missed whenever the Scenario was hosted under another node — so inside GUT every fog was inert and `is_visible_to` answered false for everything. Three tests were green because of that, and are red now: `test_BotTestScenarios::test_kamikaze_no_cluster_scenario`, `test_KamikazeSuicide`, and `test_OrbitEntry`. They were asserting behaviour that only exists inside GUT — open the same scenes in the editor and fog has always been on. Details and the per-test mechanism: `gdd/systems/ai/bot-engagement-fixes.md` §What this broke. One of the three is a real bot finding: `BotKamikaze._hold` only walks the drone home, so nothing stops the drone's own aggro from spending it on a lone target, which is exactly what the no-cluster scenario says must not happen.
> **Options:**
> 1. Repair the tests in their own fixtures and fix the one real bug — separate the drone from the cluster where the test needs travel, drop the enemies where the test only borrows the scenario as a flying-unit harness, and make the kamikaze hold actually suppress the drone's aggro.
> 2. Fix only the kamikaze hold, and re-author `test_kamikaze_cluster.tscn` / `test_kamikaze_no_cluster.tscn` spacing so all three read correctly against live fog — the scenarios are the content that is now wrong, so change the content.
> 3. Keep `fog.gd` as it was and make the harness set `get_tree().current_scene` to the Scenario it instantiates instead. Smallest possible blast radius, everything stays green — at the cost of leaving a silent total blinding in place for the next thing that hosts a Scenario.
>
> **Leaning:** 1 — the kamikaze hold is a genuine bug the blindness was hiding, and a test that borrows a scenario as a harness should shape its own fixture rather than have the shared scene bent around it.
>
> **Answer:** 1
> **Resolved:** Option 1 — `Commandable.aggro_suppressed` plus `BotKamikaze._hold`/`_commit` (the real bug the blindness hid), and `test_KamikazeSuicide` / `test_OrbitEntry` repaired in their own fixtures. All three are green. `tests/test_BotKamikazeHold.gd`; write-up in `gdd/systems/ai/bot-engagement-fixes.md` §What this broke, and how the three were repaired.

> [!check] Progress — 2026-09-05
> Bot-versus-bot matches are decidable. **Before: 0 of 10 decisive. After: 8 of 10**, in 9.2-17.3 simulated minutes (median 12.1, none at the 20-minute cap) — so "a sooner victory is better" has real dynamic range. Full write-up, with the measurements: **`gdd/systems/ai/bot-engagement-fixes.md`**.
>
> **The root cause was not the bot.** `Fog` resolved its Map from `get_tree().current_scene`, so any Scenario hosted under another node (the self-play harness, and every GUT simulation test) left every fog inert and `is_visible_to` false for everything. Two bots built armies for twenty minutes that could not acquire each other. Three more fixes came out of the same matches: `BotTargeting` scanned to the aggro shape when the weapons reach further, the bot's attack-move ranked enemy BUILDINGS out of its own aggro, and the scout preferred stale cells over never-seen ones and could be parked forever by one unreachable waypoint.
>
> **The harness note's "ATTACK is satisfied by a neutral" finding was wrong** — nothing in `Bot` can return a neutral piece, and I have made that a test rather than a claim (`tests/test_BotHostileTargets.gd`, 9 tests; removing the `id != 0` filter turns 7 of them red). What produced the symptom is that the attack objective is not fog-limited while the belief is — hence the second question above.
>
> **Hysteresis, re-checked on matches that actually fight:** still none. 1,752 think passes, 3 and 2 posture transitions, ZERO fast reversals, 2 and 3 retargets in the whole match. Evidence in the note; the probe is `tools/selfplay/_hysteresis_match.gd` (temporary).
>
> **Tests: 2028 total, 2023 passing, 1 pending (the kamikaze one you skipped), 4 failing.** One is the pre-existing `test_ControlBinding::test_grid_collisions_are_all_acknowledged` hotkey collision. **The other three are mine, and they are the fourth question above** — they were passing only because fog was inert inside GUT.
>
> **Not done:** everything the four questions cover, and the two matches that still stalemate. Those are not perception or targeting any more — both bots find each other and trade down, and then neither rebuilds: army value goes flat by minute 8 and nothing moves for twelve more. The economy not recovering from the first exchange is the next thing I would look at, and it is the same missing income signal the fourth session's note named.

> [!check] Progress — 2026-09-05
> Ran the adversarial self-play experiment: **85 matches, 2.0 core-hours, 15.7 simulated hours.** Full write-up with every number: **`gdd/systems/ai/selfplay-results-2026-09-05.md`**; raw JSONL and analysis scripts in `tools/selfplay/results/`. No engine code changed, so the test suite is as the previous note reported it — I did not re-run it.
>
> **The parameter space does not support gradient descent today, and sample size is not the reason.** Of 29 one-at-a-time perturbations from MEDIUM, **8 changed the simulation not at all** (bit-identical digests, all 302 samples) and 11 more moved it less than the harness's own run-to-run noise. `preserve_min_cost` and `defend_threat_radius` are dead at BOTH ends. Every finite-difference slope has a CI spanning zero. Separately, **the harness is not reproducible**: same config and seed, three processes, two different trajectories — a bimodal coin flip in the first ~60 ticks that `avoidance_use_multiple_threads = false` does not remove.
>
> **Archetype round-robin: ECONOMIST dominates all four others, and there is no cycle** (Bradley-Terry R² = 0.95). MEDIUM is last of five. That follows from the audit — the live parameters are all economic and every combat knob is inert, so nothing can punish greed.
>
> **Your zero-structures question now has a number on it: 23 of 61 stalemates** had one side at zero structures and one straggler, still "alive". It is the largest single distortion in the corpus.
>
> **Not done:** nothing was fixed — this run only measures. The optimizer run is reported as flat and should not be read as a result. `defend_threat_radius` needs replication before you act on it: it was inert at 10 minutes but not at 20, and the coin flip above means I cannot yet separate "binds late" from "landed on the other branch". Next steps with match-count costs are the last section of the note; the first one is finding that coin flip, and it blocks everything else.

> [!done] Q — resolved — 2026-09-06
> Should the bot build its first extractor **before** it adds any production capacity?
> **Why it matters:** `BotEconomy.tick()` ranks dominion → infrastructure → production capacity → income. With the reserve now a floor and the surplus branch falling through, income is reachable — but the bot still spends its whole starting grant on production structures first and completes its first extractor at a mean of **125 s** (min 120, max 130, n=24). Changing that is a reorder of the rungs in `tick()`, i.e. the half of the opening ladder that is an ORDERING rather than a number — the half `bot-parameter-space.md` says no parameter reaches.
> **Options:**
> 1. Leave it — the fall-through already reaches income, and 125 s is a build-order choice a difficulty tier can own later.
> 2. Put income ahead of production capacity in `tick()`: claim a free site whenever one is affordable, before adding throughput.
> 3. Make it a number instead of an ordering — a `BotDifficulty.income_structure_target` the bot builds up to before adding any throughput, which a tuning run can then search.
>
> **Leaning:** 3 — it turns one rung of the opening ladder from a hardcoded ordering into a searchable field, which is what the parameter-space note asks for, and option 2 is just its special case at target = 1.
>
> **Answer:** 3. This is definitely a gameplay parameter that a bot should dynamically decide. Generally, a player should invest in resource acquisition when it's safe to do so and when committing to defense or offense would be wasteful. This is something that should manifest from model signals, as opposed to a hardcoded "build order".
> **Resolved:** Option 3 — `BotDifficulty.income_structure_target` (default 1), read through `BotEconomy.effective_income_target()` = target × `BotEconomy.safety()`, where safety is built from base-under-threat, the fog-limited believed-enemy ratio, and `BotMomentum`'s loss rate — so it is greed when safe and capacity when threatened rather than a build order. First extractor 120 s → 60 s. `tests/test_BotIncomeTarget.gd`; write-up in `gdd/systems/ai/bot-architecture.md` §The opening's income rung reads the game, bounds in `bot-parameter-space.md`.

> [!done] Q — resolved — 2026-09-06
> How should the bot cap production of UTILITY units against better purchases?
> **Why it matters:** you said the thing to get right is "the bot is not making too many such units, because there are likely better units to purchase" — and that is the one purchase in the bot still decided by a constant. `BotProduction._best_utility_unit_for` picks the CHEAPEST affordable utility type and stops at `BotDifficulty.utility_unit_cap`, which is 3 for every tier including PASSIVE and IMPOSSIBLE, counted per TYPE. It sits beside a module whose whole design is that nothing else is a count: a combat unit is chosen by `unit_composition_value` (effectiveness × demand) with cost explicitly not a tiebreaker. So the cap is both floor and ceiling — the bot will build a third Stock Truck when three armed units would serve it better, and never a fourth when the capture loop is the best energy on the map. It also now interacts with two things it did not before: the ATTACK objective is fog-limited, so utility units are where scouting comes from, and `BotMilitary._combat_units` claims crushers, so a Stock Truck is army as well as errand.
> **Options:**
> 1. Price a utility unit into the SAME comparison as everything else — give it a `unit_composition_value` derived from the job it would do (a truck's = expected dominion per minute from captures, a builder's = the construction throughput it unblocks), and demote `utility_unit_cap` to a safety ceiling. One currency, no count — but it needs the energy-versus-dominion trade that `bot-roadmap.md` §The currency defers.
> 2. Make the number DEMAND-DRIVEN: one utility unit per live errand — one builder per concurrent build job (`build_concurrency`), one capturer per believed capturable enemy cluster, plus one spare — so it follows the work rather than the tier. A utility unit with no errand is the definition of "too many", and the bot already has every input.
> 3. Cap by SHARE OF SPEND rather than head count: no more than X% of the energy spent in the last N seconds may go on units that cannot attack. Says "there are likely better units to purchase" directly, and stays honest when unit prices change.
> 4. Keep the count and just make it a real per-difficulty ramp, the repair `scout_unit_budget` just got. Smallest change; leaves one purchase in the bot decided by a constant.
>
> **Leaning:** 2 — it answers your actual worry with no new currency, and unlike option 1 it is not blocked on pricing dominion against energy.
>
> **Answer:** 2
> **Resolved:** Option 2 — `BotProduction._utility_demand_for` sizes each utility type to its live errands (one builder per `build_concurrency` job, one carrier per `Bot.capturable_clusters()` while somewhere exists to bank prisoners, plus a spare, plus one for an unfilled scout allowance and one for a type that also crushes), with `utility_unit_cap` demoted to a safety ceiling. New type-level senses in `bot.gd`; `tests/test_BotUtilityDemand.gd`; write-up in `bot-architecture.md` §The utility unit count follows the work.

> [!check] Progress — 2026-09-05 (third session)
> All four of your answers built; two fresh questions above. **The headline is your own hunch about the reserve: it was a bug, and a bigger one than it looked.**
>
> **The bots had no income at all.** `economy_reserve` was a *trigger*, never a floor — `BotProduction` trained on plain `can_afford` and never read it — and extractors were built only in the `else` of the surplus test, i.e. only once the balance had fallen BELOW the reserve. MEDIUM reserves 600; an extractor costs 500. The permitted window was 100 energy wide and two ungated spenders stepped over it every think. **145 of 170 slot-trajectories in the 85-match corpus finished the match owning zero extractors, at an energy collection rate of exactly 0.0.** Zero-banked-energy ticks: **70.4% → 1.6%**. Write-up: `gdd/systems/ai/bot-economy-diagnosis.md`.
>
> **That also explains the flat stalemates** — neither side rebuilt because neither side had a single unit of income, not because either decided not to. Worth knowing: the "next thing to build is an income sense" conclusion from the two previous sessions was drawn on a corpus where every commander's income was identically zero, so there was nothing for a sense to distinguish. It may still be worth building; it is no longer the explanation.
>
> **Built from your answers:** the fog-limited ATTACK objective (Q2), no-structures-no-production as a defeat in both `Scenario` and the harness (Q3), the three un-blinded tests repaired plus the real kamikaze-hold bug they were hiding (Q4), and the `scout_unit_budget` ramp (0/1/2/3/4) plus crush-aware combat accounting (Q1, in part). `override.cfg` is deleted — the harness forces single-threaded avoidance at runtime instead, so nothing changes your editor sessions.
>
> **Read the whole 85-match parameter search as provisional now.** It measured a bot with no economy: every "this parameter is inert" verdict, `economy_reserve` above all, needs re-running. Matches are also ~2× more expensive (entity counts roughly triple) and no longer resolve inside a 10-minute cap, so the next run wants the full 20.
>
> **Not done:** re-running the search on the fixed economy; the run-to-run coin flip in the first ~60 ticks (still unexplained, and it sets the noise floor for everything); nobody hunts a beaten opponent's last units, now a TODO in `bot-roadmap.md`.

> [!check] Progress — 2026-09-06
> Both answers built, then the whole search re-run on the fixed bot. Full write-up: **`gdd/systems/ai/selfplay-results-2026-09-06.md`** (the 2026-09-05 note now carries a supersede banner). 156 matches, 5.4 core-hours.
>
> **Your map is innocent, and you were right to be skeptical — but there IS a start-position advantage, and it is large.** Identical config, 16 seeds: the slot at `StartPoint1_mirror` leads on material **16 of 16** (p = 3e-5, mean margin +9,632). Swapping which slot deploys where flips the sign 15 of 16, so it follows the POSITION, not the slot index. I built the symmetric copy anyway as a control — `scenes/scenarios/skirmish_symmetric.tscn`, max height residual 0.000, 0 of 12,641 tile cells differing, every authored entity exactly its reflection's partner — and **the advantage is unchanged on it** (8/8, +10,189). Your authored `skirmish.tscn` was not modified.
>
> **The cause is bot code, not geometry.** `BotEconomy._find_build_spot` scans rings `for dx` then `for dy` from `-radius` and returns the first valid cell — a preference in WORLD coordinates. On the perfectly symmetric map both commanders place structures at mean offset dx ≈ −5 from their own base instead of ±5, so the two sides stop being mirror images at tick 60. Not fixed: the campaign was under instructions not to move the tree mid-measurement. **It is the largest confounder in the instrument and the first thing worth fixing.**
>
> **Of the 8 parameters previously "bit-identically inert", 3 came alive** — `economy_reserve` (exactly as the diagnosis predicted), `demand_coverage_falloff`, and `preserve_min_cost = −1` intermittently. **Five survive as inert**: `army_commit_threshold` at both ends, `preserve_min_cost = 0`, `wave_abort_fraction`, `defend_threat_radius`. The combat half of the parameter space is still unreachable, and that is now a replicated result rather than an artifact of the broken economy. `income_structure_target` is the strongest mover in the screen.
>
> **Still no cycle** (Bradley-Terry R² = 0.975, all ten 3-cycles open) — but the ordering churned: RUSHER fell from 3rd to LAST once income existed, and MEDIUM is no longer last. ECONOMIST still leads.
>
> **Two limits on every number above.** Matches ran at an 8-minute cap, not 20 — a 1200 s match cannot finish inside this environment's 180-second shell, so **0 of 144 measurement matches reached an elimination** and every verdict is a material margin at minute 8. And the run-to-run coin flip is still there (8 runs of one config → 2 trajectories, first divergence at 10 s), which produced at least one false positive where both ends of a parameter shared a digest.
>
> **Not done:** the build-spot ring scan; decisive full-length matches; the side-paired estimator, which collapsed variance ~20× in the cases tested and would make a real search affordable. Also worth knowing: idle units got *worse* (median peak 7, max 25), and DEFEND is 1.1% of samples yet accounts for 49 of 53 posture reversals.
### Feedback Notes
- I accidentally broke the generated symmetrical skirmish map. The map didn't have a correct visual mesh, so I tried to regenerate it, and I then tried to regenerate the remaining meshes. I'm not sure how, but it seems that the underlying mesh data didn't get overwritten because, when rebaking things, the terrain became completely flat. I suspect that when the bot generated the scene, it modified some derived data but didn't overwrite the underlying data, so when I recomputed the data in the editor, it used effectively blank primary data. So (maybe add this to my personal `CLAUDE.md`​) agents should be careful about what data is being modified in tasks.
- I found the bug regarding builders indefinitely failing to start the process of building something. It appears that the terrain grid distance calculation function (`` `_resolve_movement_target` ``​) was casting the Extraction Site as a Commandable, which _is_ a structure but is not a Commandable (it's just an Entity). I updated the functions to cast them as Entities instead, and this resolved the issue. Note that a structure need not be an Entity, so this probably should have been caught, but it instead became a silent bug.
- fog of war is now broken on the scenario mode where all players are bots. None of the settings show the fog of war mesh, though it does correctly hide unseen buildings.
- I ran a match to put bots against eachother to watch them play, and I'm noticing the following issues (note that this was a Colonial vs Colonial, both on MEDIUM, on my `scenario`​ scene):
    - The bots are placing buildings that can lead to some of their own units getting trapped (either existing units, or new units that would come out of production structures). Assuming that there's some sort of modeling that governs how a bot places its structures, the bots should probably trivially just avoid placing structures that would lead to disjoint navigation meshes on the map, and production structures should have at least one side that's exposed to the navmesh (note that I don't have a firm decision around where a unit should spawn if it comes from a production structure that is completely inaccessible from a navigation region; that's a TODO)
    - I see that the stock trucks aren't being used for scouting at all, which is surprising to me because they're fast, and they don't really have anything to do. Right now, it just looks like they idle and move around in a very small area on the map for much of the game.
    - Interestingly, I'm also seeing armies of units moving out to other parts of the map, but they don't really approach the enemy to engage in battle. It actually appears that the only units getting caught in combat are units which are scouting (though I'm not positive). Also, interestingly, the players do seem to be scouting the map, but for a very long amount of time into the game, they are not reaching the enemy spawn point in scouting. I don't know why that would happen.
    - Bot units appear to be receiving commands to attack targets which aren't applicable for their weapon. For example, I placed a scan drone near the enemy base, and several units had received a command to attack it (I believe an attack move command), but their weapons can't target it, so they sort of waited near their target until it had expired.
> [!question] Q — 2026-09-11
> Where should a unit spawn from a production structure with no navmesh access?
> **Why it matters:** you flagged this as undecided and nobody has decided it. The bot can no longer create the situation — every structure it places must keep a whole side on walkable ground in the region its own units stand on — but it is still reachable three ways: a PLAYER builds a production structure and seals it in with later buildings; terrain changes under an existing structure (rubble, a destroyed bridge, a scripted block); or a structure is scene-placed in a pocket by a scenario author. The code path is not dead, so something has to happen when a unit finishes training there.
> **Options:**
> 1. **Refuse the training order** — production is gated on having a navmesh-exposed side, the same test the bot's placement uses, and the button greys out like an unaffordable purchase. Honest and legible; costs the player their queued unit.
> 2. **Spawn onto the nearest navmesh point anyway** (`Map.nearest_navmesh_point`). Never blocks the player; units visibly teleport through walls.
> 3. **Spawn inside the pocket and leave it stranded.** Today's behaviour. Consistent with the simulation and useless to everyone.
> 4. **Extend the human player's placement validation with the same rule** so a production structure can never *become* walled in — `NavPlacement.accepts(grid, footprint, true, region)` already answers it in 117 µs, cheap enough for the build preview. Doesn't cover terrain changing later or scene-placed structures, so it pairs with one of 1–3 rather than replacing it.
>
> **Leaning:** 4 + 1 — prevention where it is cheap, and a refusal rather than a teleport for the cases prevention cannot reach. A greyed button is a rule the player can learn; a unit walking out of solid rock is a bug they will report.
>
> **Answer:** 

> [!question] Q — 2026-09-11
> What should a spectator session show by default now that the fog mesh actually renders?
> **Why it matters:** the all-bot fog bug is fixed (`Fog._physics_process` gated the terrain-material update on the local human, and in a spectator session `PLAYER_COMMANDER_ID` stays 0 while every bot fog resolves to 1, 2, … — so the test matched nobody and `fog_enabled` was never set). `Scenario._init_spectator_fog` sets `active_commander_id` to the first bot, which until now had no visible consequence. It does now: opening an all-bot match to watch shows a mostly black map with one bot's revealed bubble until you press a button. Changing it is one line; leaving it is also a decision.
> **Options:**
> 1. Keep the first bot's POV — a spectator watches *someone's* game, and the fog is part of what makes a bot's behaviour legible (you can see what it has and has not scouted).
> 2. Default to omniscient (`-2`, the existing "No Fog" button) — a spectator is a referee, and watching through one bot's fog hides half the match. The POV buttons stay for when you want one bot's view.
> 3. Omniscient only when every slot is a bot, keeping a nominated POV otherwise.
>
> **Leaning:** 2 — the reason you ran the match was to watch both bots play, and the first-bot default was chosen when it had no visible consequence.
>
> **Answer:**

> [!question] Q — 2026-09-11
> Should `CommanderBlackboard` drop a UNIT belief the commander has walked to and found empty, rather than only the ATTACK objective ignoring it?
> **Why it matters:** `Bot.belief_is_disproved` is asked at the objective, so a disproved belief still counts toward `believed_enemy_army_value` (which gates every attack wave) and toward `enemy_demand_map` (what the bot builds to counter). That is defensible — the sighting is still evidence the unit EXISTS, just not about where — but it means one belief is simultaneously true enough to build against and false enough not to march on. Moving the test into `CommanderBlackboard.update` would make unit beliefs behave exactly like structure beliefs, at the cost of the bot forgetting enemies faster and reading the enemy army as smaller than it is — which, under the humility prior, makes it MORE aggressive.
> **Options:**
> 1. Leave it at the objective (today): beliefs are only disqualified as destinations.
> 2. Move it into `CommanderBlackboard.update`: a unit belief is dropped on a revisit that finds the spot empty, exactly as a structure belief is.
> 3. Both, split by consumer: drop the LOCATION on revisit but keep the type and last-seen time as composition evidence — a new, smaller kind of entry.
>
> **Leaning:** 1 — it is the change that is already measured, and 2 moves a number that gates the attack-wave commit rule with nothing measured about the effect.
>
> **Answer:**

> [!question] Q — 2026-09-11
> May the bot treat the map's authored start points as prior knowledge when choosing where to scout?
> **Why it matters:** the shipped scouting fix makes a scout prefer frontier far from *its own base* — a belief derived only from what the bot can see ("the opponent is not next to me, because I can see next to me"). It finds the enemy base in 95–110 s, against 265 s before and only 2 of 8 matches finding it at all. Reading `Skirmish.START_POINT_GROUP` instead would make the search exact, but it is the bot knowing a fact about the scenario rather than about the game state — and `nearest_believed_enemy_structure_position` was deliberately made fog-limited to remove exactly that. It also changes behaviour on maps where the prior is wrong (asymmetric, 3+ players, a bot pushed off its start).
> **Options:**
> 1. Keep it as shipped — distance from own base only; start points stay invisible to the bot.
> 2. Let `BotScout` read the start-point markers and weight frontier near an unvisited one. Fastest search; the bot knows where to look before it has looked.
> 3. Make it a difficulty parameter (`scout_knows_start_points`, off below HARD) — the handicap becomes "does this opponent know the map", which is how a human's map familiarity actually differs.
> 4. Give the bot the start points only once it has *seen* one — the opening search is blind, map knowledge accumulates.
>
> **Leaning:** 1 — it already produces the behaviour you asked for, and it is the only option needing no argument about what the bot is allowed to know. If 95–110 s is still too slow, 3 is the next move, because it turns the question into a tier rather than a rule.
>
> **Answer:**

> [!check] Progress — 2026-09-11
> All four of your match observations worked, plus repairs. Write-ups: `gdd/systems/ai/bot-architecture.md` (§Where a building goes, §Scouting, the attack-objective subsection), `bot-engagement-fixes.md`, `bot-parameter-space.md`, and a new `CLAUDE.md` §Regenerating data. Four questions above; heading re-tagged `#needs-input`.
>
> **Scouting — fixed, and it was two bugs.** The Stock Truck scored **highest of any unit** and was claimed on think 1; `BotMilitary._combat_units` then re-tasked the whole army and took it, because the recent crusher widening made it army. `BotScout` dropped any scout whose command was no longer its own, so it never held one again — 0% of samples. A claim is now held against a standing rally (only a real errand takes a scout). Second, `_pick_best_scout` returned the best *scoring* candidate and then priced it — and the scorer rewards capability while the price test punishes cost, so **the top scorer is the one most likely to be unaffordable**; the budget-2 bot sat at one scout forever. It now walks candidates in score order and takes the first it can justify. Third, nearest-unseen is a spiral — the scout shaved its own frontier and never crossed the map. **Enemy base found 2/8 → 8/8 matches, at 265 s → 95–110 s; coverage at 60 s 0.05–0.10 → 0.24–0.26; truck scouting 0% → 45%.** No unit special-cased.
>
> **The untargetable-attack bug — real, and one code site.** Nothing between "choose an objective" and "issue an order" asked whether the target could be damaged. `Loadout.weapon_for_target` is the right question and is a *different fact* from a zero multiplier: the scan drone is `HOVERING`, so it is `TARGETABLE_AIR` only. An impossible `Attack` never resolves (`should_move` false, `can_act` false, `persist` true) — the unit stands there forever, exactly as you saw. Filtered at the objective, the kamikaze scan, and the actuator. **Untargetable commitment 0.34 → 0.13 of ATTACK samples.**
>
> **But "armies don't engage" is only partly that, and the rest is a composition problem.** Engagement did not improve: the bot fields armies with no weapons in them — dominion generators and servants, both with an empty `Loadout` — and now correctly MASSes instead of marching them out. That is `BotProduction`, not targeting.
>
> **Your map is still not the cause of the start-position bias, and neither was the build-spot scan.** Placement is now equivariant — mirror residual over structures **0.0000 at every sample**, and the two sides' mean offsets are finally opposite in sign (−3.75 / +2.17) where both used to sit at dx ≈ −5. The bias survives anyway: 8/8, p = 0.0078, +9,706, still flipping with the position. The 2026-09-06 attribution was a code reading, not an experiment; this was the experiment and the reading was wrong. **New leading suspect, unfixed:** `BotScout._grid_index_at` computes `roundi((local.x + 79.5) / 5)`, and `round(u + 15.9) + round(15.9 − u)` is not constant in `u` — a point and its reflection land in buckets that are not mirror partners. Same class of bug, one module over.
>
> **Repairs:** placement can no longer disconnect the navmesh or wall in a structure (`scripts/maps/nav_placement.gd`, 117 µs for both rules against the old 76 ms flood-fill; 1,020 checks over three full matches, zero sealed in). Fog renders in all-bot scenarios again (the terrain-material update was gated on the local human, who does not exist in a spectator session). `Map.footprint_origin` rounds even footprints in absolute grid coordinates — the same world-frame bug one layer down; the bot routes around it, **player placement still has it**.
>
> **Three things that need you:**
> 1. **Four `.gd` files do not parse**, and two are test files GUT is silently dropping from every run: `tests/test_CommandContextParser.gd`, `tests/test_Tool.gd` (`EntityIds.TC_BARRACKS`, `TC_LAB`, `TC_ARMORY`), `tools/generate_test_scenarios.gd` (`EntityIds.KAMIKAZE`), `tools/terrain_meshes/preview_scene.gd`. Those ids are gone from `scripts/generated/entity_ids.gd`. Presumably wants a spec-importer run, which agents are barred from. `tests/test_SourceFilesParse.gd` is new and **red on exactly these four** — that is the ninth failure, not a regression.
> 2. **`skirmish.tscn` is one click from flattening.** `mesh_plateau_terrain_surface.res` is flat while its `.tres` is sculpted (rebake residual **3.000**) — press Bake Terrain From Mesh and you lose the terrain, which is what happened to the symmetric map. `tools/terrain/resync_surface_mesh.gd` repairs it; surveyed but **not run against your files**.
> 3. **`skirmish_tournament_desert.tscn` renders pitch black** — no `DirectionalLight3D`, no `WorldEnvironment`.
>
> **Not done:** the `BotProduction` composition problem above; the `_grid_index_at` rounding; `_abandoned_spots` never expires, so one stall-timeout false positive blacklists a good spot permanently.

> [!check] Progress — 2026-09-11 (session close)
> **"CPU Bot Behavior Work" is PAUSED at your request.** Four questions above are unanswered and nothing is waiting on me. Everything built this session is in the working tree, uncommitted; the write-ups are in `gdd/systems/ai/`.
>
> **Your three follow-ups are done.**
> 1. **The importer already pruned dead ids — it just never said so.** `SpecGenerators.entity_ids_text` rebuilds `entity_ids.gd` wholesale from `registry.pieces` every run, so an id whose doc is gone stops being emitted on its own; the behaviour you asked for existed. What was missing is that a removal is a *parse* error in every file naming it, and GUT reports a run green when a test file fails to parse. The import now logs what it dropped and warns that a file still naming one will not parse. The four broken files are repaired and de-pinned from authored content (the technocratic structures were deleted outright and have no replacement; `kamikaze` was re-keyed to `an_aircraftLight_antiMech`). **49 tests rejoined the suite** — they had been silently absent.
> 2. **Surface mesh resynced.** `mesh_plateau_terrain.tres` rebake residual **3.000 → 0.000**; the `.tres` is byte-identical, only the mesh was written, and `skirmish.tscn` was not touched. A survey found only two such pairs in the repo, so no other map has the same latent flattening.
> 3. **The desert scene has a `Sun`**, copied from `skirmish.tscn` (`skirmish.tscn` has no `WorldEnvironment` either, so there was nothing else to copy). **It did not fix the black screen** — see the question below; the cause is the spectator camera, not lighting.
>
> **Two things that will bite you when you next run the importer:**
> - `gdd/Untitled.md` (24 bytes, `kind: ""`, untracked) **fails validation and aborts the whole pipeline**, writing nothing. Delete it or see the question below.
> - **A second import run is not a no-op**, which the README says is a bug. Two scenes flip forever because two docs each claim one scene path: `lb_support2.md`/`lb_support3.md` both name `lb_support2.tscn`, and `lb_aircraftMedium_antiBio.md`/`..._antiMech.md` both name `sentinel_thing.tscn`. Ids are checked for uniqueness; scene paths are not.
> When unblocked, a full run touched 10 files and nothing else — the two generated JSONs, one spec doc's frontmatter canonicalised, and 7 scenes that are your own untracked WIP. No shipped scene was rewritten.
>
> **Tests: 8 failing, 1 pending** — exactly your long-standing set (`test_CommandCard`, both `test_ControlBinding`, both `test_DamageCatalog`, `test_DamageTable::test_calculate_damage_applies_the_penalty_columns`, both `test_RequisitionPrerequisites`), and `test_SourceFilesParse` is now green.
>
> **Also worth knowing:** `CLAUDE.md:829` cites `tests/test_IndentationConsistency.gd`, which does not exist — the real guard is `tests/test_SourceFilesParse.gd`, which checks *parsing* rather than indentation on purpose. Left alone because CLAUDE.md is dirty in your tree.

### Importer and scene questions (2026-09-11) — NOT part of CPU Bot Behavior Work

> [!done] Q — resolved — 2026-09-29
> Should a doc with an empty or unknown `kind:` abort the import, or be skipped as not-a-spec?
> **Why it matters:** `SpecRegistry.scan` treats *presence* of a `kind` key as spec-hood and validates the value in `_register`. A stray Obsidian note — `gdd/Untitled.md`, `kind: ""`, 24 bytes — therefore fails the id check on its filename and aborts the entire pipeline, writing nothing. Your importer is blocked right now for that reason alone, and `gdd/` is a Sync-owned vault where accidental "Untitled" notes are routine.
> **Options:**
> 1. Delete the file and change nothing — accept that any stray spec-shaped note halts the run.
> 2. Treat an EMPTY `kind:` as not-a-spec (skip it silently, as a doc with no `kind` key), keeping a typo'd non-empty kind a hard error.
> 3. As 2, but emit a WARN naming the skipped file, so a genuinely half-written spec is still visible.
>
> **Leaning:** 3 — an empty value names no kind, which is the README's own definition of not-a-spec, and the warning keeps a half-finished doc from disappearing. `_register`'s "a typo'd kind fails loudly" rationale is untouched, because `""` is not a typo.
>
> **Answer:** 2
> **Resolved:** option 2 — an empty or null `kind:` is skipped silently as not-a-spec (`SpecRegistry._names_a_kind`); an unknown non-empty kind is still a hard error. README updated.

> [!done] Q — resolved — 2026-09-29
> Should validation reject two spec docs that declare the same `scene:` path?
> **Why it matters:** `lb_support2.md`/`lb_support3.md` and `lb_aircraftMedium_antiBio.md`/`..._antiMech.md` each name one shared scene, so every full import writes both docs into the same file and the last one wins. The scenes flip forever — `lb_support2.tscn`'s `id` alternates `lb_support2` ↔ `lb_support3` — which breaks the "a second run is a no-op" property the README says is how you tell a converged import from a broken pass.
> **Options:**
> 1. Add a uniqueness check on `scene:` alongside the duplicate-id check — a hard error. This will HARD-FAIL your importer until both pairs of docs are reconciled.
> 2. Warn rather than error, so the run completes and the non-convergence is at least named in the log.
> 3. Leave validation alone; just fix the four docs now (give each its own scene path).
>
> **Leaning:** 1 plus 3 — two pieces sharing one scene can never both be correct, and the check costs one dictionary; but it has to land together with fixing the four docs, or the importer stops working.
>
> **Answer:** 1 and 3
> **Resolved:** options 1 and 3 — two docs naming one `scene:` is now a validation error (`SpecRegistry._validate`, `_scene_owners`). The four docs had already been given their own scenes, whose ids match; a full import passes the check and writes nothing.

> [!done] Q — resolved — 2026-09-29
> Is `skirmish_tournament_desert.tscn` meant to be a spectated bot-vs-bot match, or is its human player slot missing?
> **Why it matters:** both its `PlayerSlot` sub-resources omit `is_bot` (which defaults to `true`), so there is no human commander and `Scenario` falls back to `_setup_spectator_camera()` — an orthographic camera hard-coded to `size = 15.0` at `(0, 20, 20)` looking at world origin. The map's geometry renders fine under an external camera (frame mean 25.9), so the pitch-black frame is that camera, not the light I added and not fog. Which fix is right depends entirely on what the scenario is for.
> **Options:**
> 1. It is meant to be PLAYED — set `is_bot = false` on slot 1, as `skirmish.tscn` does, and it gets the normal player rig.
> 2. It is meant to be WATCHED (a tournament map) — then `_setup_spectator_camera` is the bug: its hard-coded size and origin framing should derive from the map's bounds, which would fix every spectated scenario at once.
> 3. Both — fix the spectator camera's framing AND give this map a human slot.
>
> **Leaning:** 2 — the name says tournament, the spectator HUD path is clearly intended, and a camera that ignores map bounds is wrong for every spectated scenario rather than just this one.
>
> **Answer:** this issue looks deprecated, the scene is working fine for me; no scenario is particularly meant to be played exclusively by bots or not
no scenario is particularly meant to be played exclusively by bots or not
> **Resolved:** no change — closed as obsolete.

## Sapper Explosives Implementation #done
Written up in `gdd/systems/combat/planted-explosives.md`.

Today the Sapper carries an `Interaction` of type `PLANT` — enemy MECH targets only, spawning `an_plant_bomb` at the target, which detonates on arrival. Replace that with an ABILITY:

1. **Plant (ability, one charge).** Places an explosive on a terrain position, or on a unit or
   structure, depending on what is selected. Entity targets must be **MECH frame**.
2. **The charge recharges in 30 seconds, and the timer is BLOCKED while that Sapper's planted
   explosive is still in the game.** A Sapper holding a live charge somewhere on the map has no
   second bomb until the first one goes off.
3. **If the explosive's owner dies before it detonates, it disappears without exploding.** Killing
   the Sapper defuses what it planted.
4. The sapper's explosive becomes an Actor, with a single DETONATE ability; some complexity of implementation for this:
	- have the PLANT and DETONATE abilities share a command card button on the top row (Q if it's available, but if not that, then pick the next available one on that row)
	- If a sapper has planted its explosive, then the sapper cannot plant again, as mentioned; instead, if its explosive exists in the game, then the command card instead shows DETONATE on that command card position, and pressing the ability detonates the explosive; note that the player need not have vision of the explosive to detonate it using the sapper ability
	- The explosive itself should also be selectable by the owner, and the explosive should have a DETONATE command for itself in the command card; if the explosive is out of vision range, make the explosive unselectable and not visible to its owner
	- The explosive should be stealthed, where detection reveals it to the opponents
	- If the explosive is planed on the ground, it should have its own piece that is targettable and attackable; it should have LIGHT MECH defense with 50 HP; note that, if destroyed by attacking it, it should detonate; Finally, the explosive should be targettable with a HEAL command, which will remove the explosive from play such that it doesn't detonate; like with the Colonial bombard beacon, the explosive should be removed if an opponent heals the MECH unit which has the explosive attached
	 - If there's a collision between PLANT and DETONATE in the command grid (because some explosives are selected, or because some sappers are selected and they have charges to PLANT), then PLANT should take priority; keep PLANT as the option in the controller up until the point that no sappers are selected, or all selected sappers do not currently have any charges (which should be reflected when the plant action is fulfilled)

The bomb is an EMISSION, so its damage is authored on the emission and stays as it is for now.

> [!done] Q — resolved — 2026-09-29
> A charge planted on the GROUND does no damage when it goes off. Should its blast have an area?
> **Why it matters:** the blast is `an_plant_bomb`, which has no `blast:` — fired at a charge's carrier it hits the carrier, but fired at a point it hits nothing, so a ground charge is harmless today. The line that gave it "an area of effect of radius 3" was removed from this task along with the fuse, and the task says the emission's damage stays as it is.
> **Options:**
> 1. Give `an_plant_bomb` a 3-unit blast (the first version of `planted-explosives.md`) — ground and carried charges both splash.
> 2. Keep no area, and have a ground charge's blast hit the nearest piece within a small radius.
> 3. Leave it: ground charges are decoys/defuse bait only.
>
> **Leaning:** 1 — the only one that makes a ground charge a threat, and it is the radius this was written up with.
>
> **Answer:** 1
> **Resolved:** option 1 — `an_plant_bomb` has `blast: aoe_charge`, a new radius-3 sphere in `gdd/shapes/shapes.md` (no existing bucket was 3).

> [!done] Q — resolved — 2026-09-29
> When a charge's OWNER repairs their own charge on the ground, what happens?
> **Why it matters:** the task says a HEAL on the charge removes it, and that an OPPONENT healing a carrier removes the charge on it. Built: only an opponent's repair removes a charge; the owner's repair heals a damaged one like any MECH piece.
> **Options:**
> 1. Keep: the owner's repair heals it.
> 2. The owner's repair removes it too — a way to take a charge back and restart the Plant cooldown.
> 3. The owner cannot target their own charge with Repair at all.
>
> **Leaning:** 1 — removal as defusing reads as the opponent's answer, and 2 would make a free recall.
>
> **Answer:** 2
> **Resolved:** option 2 — `Repair._defuses` lets the owner's repair remove its own ground charge; the Plant recharge then starts. Heals also now strip enemy beacons and charges off any piece (`Defense.restore`, from `deferred.md` 1.50).

> [!check] Progress — 2026-09-29
> Built: `plant` / `detonate` abilities (`gdd/factions/anarchical/abilities/`), the charge piece `an_plantedCharge` with `PlantedCharge` (`scripts/entities/components/planted_charge.gd`), `Plant` / `Detonate` commands, the held recharge (`Abilities.hold_recharge`), defusing through Repair, owner-vision-only visibility (fog, minimap, selection), and the shared R cell (Q and W are Radiate and Spot) with Plant winning until no selected Sapper has a charge. `Interaction.Type.PLANT` and the Sapper's Interactor are retired. The card now re-reads the selection's commands every 0.1 s, so it flips when a charge goes down (this also fixes Deploy/Undeploy and Land going stale).
> Followed the task over the design note where they differ: no fuse — a charge goes off only by Detonate, by being destroyed on the ground, or by its carrier dying. The note is rewritten to match (`gdd/systems/combat/planted-explosives.md`).
> Tests: `test_PlantedCharge.gd` (19) and `test_Deploy.gd` (20) pass; `test_PlantInteraction.gd` deleted with the mechanic. Full per-file sweep: 3023 pass, 15 fail in 9 files — all on the known-failing list (DamageCatalog, DamageTable, DockingBay, HelpOverlay, Highlights, MapElevation, RequisitionPrerequisites, Shelter, StatusVisuals).
> **Not done:** the ground charge's damage (Q above); the bot never plants; a live charge keeps its owner from being eliminated (TODOs in the note).

> [!check] Progress — 2026-09-29 (2)
> Both answers built, plus the deferred 1.50 answer (any heal strips enemy beacons and charges, even at full hp). A charge is also removed if its Sapper is freed without a normal death (killed inside a transport). Tests: `test_PlantedCharge.gd` 23 pass.
> **Not done:** the bot never plants (TODO in `planted-explosives.md`).

## Spot animation — the Recruit calling in a beacon
*(Recorded by Claude from chat, 2026-09-28.)* The Recruit needs an animation showing the Spot action while it channels and holds a beacon. What an opponent may read from it is open — `deferred.md` 1.52 (the animation is itself a tell to anything with vision of the Recruit).

## Odds and Ends Work #ready
- Bugs
	- The Kamikaze drone is not correctly approaching and colliding with targets when they're fixtures; it looks like they're correctly colliding with units, though; I've tested this against extraction sites and Citadels
	- When a player issues a command to a unit that's inside a garrison, the waypoint indicator draws the line starting from the world origin; update it so that the starting position is based on the garrison that it still occupies
	- Issuing Force Fire and Defend commands should disable Hold Fire, in the same way that Attack Move does
- Requested Updates
	- Right now, when a player presses a button of a control group, the camera snaps to look at the control group; have a single press just select the control group, and a second press of the same button (a double tap) snap the camera
	- Changes were recently made to make sure that navigation mesh obstructing fixtures obstruct attack lines, so that an actor on one side of an obstruction cannot attack a target on the other side of the obstruction; Some terrain features have these same sorts of elevation considerations such that a terrain mountain (represented in the world height map) also obstructs attack lines; there's some complexity here regarding projectile collisions happening with the height map surface, but not necessarily with structures, so help me actually come up with better definitions regarding how this is represented in the physics
## Expansion of Neutral Buildings #ready
In this game, maps will feature neutral buildings that can be occupied and garrisoned by anybody. Currently, there's exactly one building in the game, called `nt_building`, which serves this purpose. However, now, I want to revisit these neutral structures and use a small library of neutral structures, rather than using a single neutral structure in generation.
The neutral structure library will work as follows:
- Neutral structures will take on various structure footprint sizes, and have varying amounts of HP; however, the structures should otherwise have the same properties as the existing `nt_building`
- To start, please make the following structures for me (note that this is list is proof-of-concept for now and subject to changes that will add or remove to this list):
	- `nt_building_square`: A 4x4 building with 1000 health
	- `nt_building_long`: A 3x5 building with 1000 health
	- `nt_building_shack`: A 2x2 structure with 600 health
	- `nt_building_large`: An 8x5 building with 1500 health
- The anarchical faction will also feature a structure that they build which is potentially meant to "blend in" with the specified structures. As an edge-case in building structures in the game: rather than the build structure taking exactly one form, the `an_infrastructure` structure will allow the player to select from a set of buildings.
	- as an edge case of implementation, the `an_infrastructure` game structure (as an enumerated type of game piece) should point to a set of underlying game pieces. For now, the list of underlying structures shall be [`nt_building_square`, `nt_building_long`]. This can probably be an edge-case in the game piece spec for `an_infrastructure`, where a property in that spec indicates the exact structures to be used
	- When the player is playing as the Anarchical faction, arming the Build command with `an_infrastructure` should be interpreted as arming the build command with one of the underlying structures that are specified.
		- When the player builds the structure, it should be created using the same scene as the underlying one that was selected; Note that, instead of this structure having the properties of, say, `nt_building_square` alone, the structure should be built with the general properties enumerated in `an_infrastructure`. (One example property is that `nt_building_*` does not provide any of the infrastructure resource, whereas `an_infrastructure` does).
		- Note that there also exists an edge case for this type of structure where, if the player "builds" `an_infrastructure` on top of an existing `nt_building_*` structure, the ownership of the structure is changed to the player, rather than a new structure being built. This functionality should stay in the game, though it might require some refactoring to fit the implementation being outlined here.
		- For the in-game interface of building selection: currently, when a command is armed and it can use applicable tools, the player HUD shows the applicable tools for the command, and hotkeys also get interpreted based on the controller being armed with the relevant command. As an edge-case, when the player presses the tool for `an_infrastructure`, subsequent presses of `an_infrastructure` should walk over the list of potential underlying variations of `nt_building_*` (and wrap around if the list was exhausted). Note that, currently, if the player tries to set a tool repeatedly in the controller, it basically no-ops, which is fine, so this is edge-case will no longer just be a no-op.
- In accordance with the use of a set of neutral buildings (rather than a single one), map generation will need to use the set of neutral buildings in neutral building placement, rather than using a single version as exists right now. For now, the map generation functionality can just arbitrarily grab one of `nt_building_*` when putting buildings onto maps.