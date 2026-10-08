---
title: Learning the bot's macro decisions
type: system-note
---

# Learning the bot's macro decisions

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PLANNED — approach A below, decided 2026-10-07; its first stage, the combat model, is built
(§1).** How
machine learning models the bot's MACROECONOMIC decisions — what to buy, and when — in place of
the hand-written valuation it uses now. The decisions are folded in where they apply (§Decided).
What exists is [bot-architecture](bot-architecture.md); the knobs a search may move today are
[bot-parameter-space](bot-parameter-space.md); the signals a model would read are
[world-model](world-model.md) and [debug-signals](debug-signals.md). The work item is
`gdd/tasks.md` T-100.

**Scope: the purchase decision only.** Combat decision-making (targeting, engagement, retreat)
and positioning — including where a macro purchase is PLACED — are modelled separately, and
are downstream of this one: they act on what the macro model bought (Alex, 2026-10-07). This
model reads their outputs as state; it never takes their decisions.

## Why tuning the parameters cannot get there

**A parameter search tunes the constants of functions someone wrote; the FORM of those
functions is the assumption, and no constant changes it.** Every purchase today is valued by
one chain (`Bot.enemy_demand_map` → `Bot.unit_composition_value` → `BotSavings`):

```
value(buy X) = Σ over believed enemy TYPES e:
                 strength_per_energy(X vs e) × demand(e)
demand(e)    = importance(e) / (1 + coverage(own army vs e) × falloff)
strength_per_energy(X vs e) = √(dps × matchup × hp ÷ incoming) / cost        (T-098)
```

Against Alex's four requirements (2026-10-07), that form is structurally blind, not mistuned:

| Requirement | What the form does | Why no constant fixes it |
|---|---|---|
| **Interaction effects**: a unit weak alone, strong beside another | The value is a SUM over enemy types of a per-unit duel score; own units enter only as "coverage" of an enemy type | There is no term in which two OWN types multiply. A spotter that makes a siege gun useful, a crusher beside a capture truck, a tank that screens artillery: each is a product, and an additive model has no product to weight |
| **Spatial factors**: a tank on the doorstep versus across the map | Every believed enemy counts the same wherever it stands; safety reads a single radius (`defend_threat_radius`) | Distance and travel time are not inputs. The one radius is a step function; an arrival time compared against a build time is a different variable, not a different radius |
| **Specificity**: the exact make-up of the army | Per-type demand, each type answered separately, coverage divided down | The response to a MIX is not the sum of the responses to its parts: splash against massed infantry, anti-air only once the air is a real share. A per-type sum cannot say "this combination" |
| **Short versus long term** | Units are priced in strength per energy; an extractor is a COUNT (`income_structure_target × safety`); a tech building is a margin (`tech_value_margin`) over the best unit it unlocks | Three different scales with no exchange rate between them. Nothing prices an extractor's payback against a unit's immediate value, so "greedy" is a count the search sets rather than a trade the bot makes |

**The self-play results are a weak test of the space for the same reason.**
[selfplay-results-2026-09-06](selfplay-results-2026-09-06.md) searched a handful of these
constants, found most of them bit-identically inert, and found a transitive archetype matrix
with no counter-cycle. A space whose purchases are all one additive form is not expected to
produce rock-paper-scissors: intransitivity needs interactions, and the form has none.

## What the problem is, stated for a learner

The macro decision is a choice among purchases `a` — each trainable unit, each buildable
structure, each upgrade, and SAVE — in a state `s`, and the bot should pick the one with the
highest value `Q(s, a)` in one currency. Everything Alex listed is a property of `Q`:

- **interaction** — `Q` depends on what is already owned, not only on what is faced;
- **specificity** — `Q` depends on the enemy composition as a set, not type by type;
- **space and time** — a threat's weight depends on when it can arrive against how long the
  answer takes to field;
- **horizon** — some `a` change future income, so `Q` is a value over the rest of the match,
  not over the next fight.

The literature splits `Q` into parts that can be learned separately and cheaply, which is the
part that matters here: a full-game learner is out of reach (§Compute is the constraint).

## Compute is the constraint

A 20-simulated-minute match costs about 170 wall-seconds alone
([selfplay-harness](selfplay-harness.md) §The training budget); a 200-match sweep is six hours.
End-to-end deep RL on RTS games has needed millions to billions of frames:

- AlphaStar trained a league of transformer-and-LSTM agents for weeks, starting from human replays
  ([Vinyals et al., Nature 2019](https://deepmind.google/blog/article/AlphaStar-Grandmaster-level-in-StarCraft-II-using-multi-agent-reinforcement-learning));
- TStarBot1 needed one to two days on a GPU even over 165 hand-coded macro actions
  ([Sun et al. 2018](https://arxiv.org/pdf/1809.07193));
- ELF's Mini-RTS was built as a 165,000-frames-per-second engine precisely so that RL could
  train a full-game bot in a day ([Tian et al., NeurIPS 2017](https://arxiv.org/abs/1707.01067)).

At roughly 210 ticks per wall second this simulation is three orders of magnitude slower than
Mini-RTS. **So the methods that fit are those that learn from CHEAP data (isolated fights, logged
matches) or that search a SMALL parameter set (a model's weights, not a network over pixels);
end-to-end RL is REJECTED for now** unless a fast abstract simulator is built first (§Option C).

## The components, and the methods for each

### 1. A combat model — interaction and specificity

**This section is stage 1, built 2026-10-07.** `tools/combat_model/` holds
the fight generator, the trainer and the pinned requirements; `CombatModel` reads the export;
`BotDifficulty.should_use_learned_production` switches `BotProduction`'s unit choice onto it
(on in every tier since 2026-10-07, Alex; a run may set it false). The decision-sim pair is `sims/bot/production/counter_the_tanks{,_learned}`.
Regenerate the model with `generate_fights.tscn` (three shards of 2,000 took 55 minutes) and
`train.py` (20 seconds).

**First fit (2026-10-07): 6,000 fights, 17 armed units (Colonial, Anarchical, Technocratic),
held out by fight:**

| Model | R² | mean abs. error | winner right |
|---|---|---|---|
| value only (the two sides' energy) | 0.06 | 0.56 | 55% |
| additive (one shape per side and type) | 0.53 | 0.37 | 78% |
| with 40 pairwise terms | **0.64** | **0.32** | **82%** |

Two findings. **The pairs carry real signal** — a tenth of the variance and four points of
winner accuracy past the additive model — and the strongest are counters
(`own:cl_mechMedium_antiMech × enemy:cl_mechMedium_antiLight`, artillery against light air),
which is the interaction structure the current valuation cannot represent. **Energy spent
predicts almost nothing**: with budgets up to 2× apart, the richer side wins 55% of the time.
What a side buys decides a fight far more than how much it spends, so unit costs are not
calibrated to fighting value — a balance finding as much as a bot one.

**First self-play comparison (2026-10-07):** 32 matches, HARD against HARD, Colonial mirror,
personality and temperature pinned to 0, 20-minute cap; one slot on the learned model and one on
the demand map, every seed played with the learned model on each slot and from each start
point. Rows: `tools/selfplay/results/learned_production/learned_vs_demand.jsonl`.

- **31 of 32 ended in an elimination**, all clean (no script errors).
- **The learned model won 17 of the 31: 55%, two-sided p = 0.72 — no difference this sample
  can see.** A ten-point edge would need about 200 matches to show. What it does say is that
  a valuation fitted only on isolated fights is not worse than the hand-tuned demand map in a
  whole match.
- **It fields a different army.** Over the 32 matches the learned slots trained five times the
  anti-mech infantry (338 against 62), twelve times the light air (48 against 4), and an eighth
  of the anti-heavy infantry (9 against 73).
- **It decided most of its slot's training**: in a typical match 85–100% of that slot's unit
  choices were scored by the model; the rest fell back, mostly before any enemy was seen.
- **A slot bias, not a start-point bias.** Wins split 16–15 by start point, but slot 0 won
  20 of 31 (p ≈ 0.15). The counterbalancing cancels it here; TODO: whether it is real, and
  what in slot order (deploy, commander id, think order) would cause it.

**Retrained on single-faction sides (2026-10-07, the shipped model):** 6,000 fights, held-out R²
0.655 (was 0.637), winner right 82.9% (was 82.0%); every own-side pair is now fieldable (the
strongest, Constable × Sloop). But the anti-mech tank against Sloops regressed — see §Still
open — and the learned production sim fails on it. The mixed-faction corpus and model are kept
in `tools/combat_model/out/mixed_2026-10-07/`.

**Ten random maps (2026-10-07):** learned against demand map, HARD Colonial mirror, a generated
map per match, the learned side alternating slots. Learned won 4 of 10, slot 0 won 7 (27 of 41
across both batches, p ≈ 0.06). Over the ten, the learned side fielded 878 Colonial units to
1,087 — a third fewer Recruits (525 to 836), three times the anti-mech Recruits (112 to 38) and
Constables (20 to 7) — and fewer turrets (6 to 14). Rows:
`tools/selfplay/results/learned_production/random_maps.jsonl`.

**Each side is drawn from one faction** (Alex, 2026-10-07: a mixed side is reachable only by
capture, too rare to model yet); the two sides may differ, and a faction appears in proportion
to its armed units.

**What the fights cannot see** (2026-10-07). The model values a unit only by what it does in a
short, flat, unordered fight, so a unit whose worth lies elsewhere is undervalued:

- TODO — **charged weapons and rearming.** There is no airfield in the arena and the window is
  90 s, so a charged clip fires once. The Drake (four rockets, `charged: true`) shows half its
  value — fielded alone it destroyed 35% of the enemy's value and kept 48% of its own, with 60
  of 110 fights timing out because nothing could reach it — and none of the sortie cadence. It
  needs an airfield in the arena and a window several sorties long.
- TODO — **support and control.** The Avalanche alone destroys 4% of the enemy's value, as
  designed; its freeze IS its payload, so it fires on its own, and the model found the combo
  with infantry (Avalanche × Constable 0.41, Avalanche × anti-mech Recruit 0.31 — two of the
  strongest own-side pairs). What it cannot find: the combo with Bombards (a structure and a
  bot-cast ability, absent from the fights), and saving a friendly unit or delaying an enemy,
  which the end-of-fight margin does not reward.
- TODO — **abilities a bot must cast.** Both sides are inert, so nothing a decision triggers
  is ever used. Running the fights with thinking slots would measure the bot's use of them —
  which is the point below.
- **Transports and other unarmed pieces are out of scope here, not missing.** Mobility is
  strategic value: the state value (§3) and a positioning model own it. Unarmed pieces are not
  in the fight pool, and production's unit choice skips them under both valuations.
- **Value is bounded by actuation.** A unit is worth what the bot can make it do: with no heal
  order, healing is worth nothing to it, whatever the unit can do (Alex, 2026-10-07). Fights
  with inert sides are narrower still — they measure what a piece does unordered. Closing the
  actuation gap ([bot-architecture](bot-architecture.md) §The action space is a third of the
  game) is deferred and is a known limitation of every learned value here.

### 2. A threat clock — spatial factors

**What it computes:** for each believed enemy group, the time it needs to reach each own region
(path length over the lattice divided by its speed, or the `approach` channel's sampled paths),
against the time an answer needs to be fielded there (build time plus queue plus the walk from
the producer). A threat's weight in the purchase decision becomes a function of that margin:
full when it arrives before the answer could, falling off when there is time to spare.

This is mostly computation, not learning: influence maps with walking-distance fields are the
standard RTS representation of threat
([gamedev.net, The Core Mechanics of Influence Mapping](https://www.gamedev.net/articles/programming/artificial-intelligence/the-core-mechanics-of-influence-mapping-r2799)),
and qualitative spatial reasoning frames the question as "can they get there in time"
([Forbus, Mahoney & Dill, IEEE 2002](https://www.qrg.northwestern.edu/papers/Files/QRG_Dist_Files/QRG_2002/ForbusMahoneyDill_IEEE2002.pdf)).
The learnable part is the falloff's shape and scale: a few parameters per bot, fitted by the
outer search or learned inside the value function (§3) with the margin as a feature. It needs
the world model's lattice, `threat` and `approach` channels ([world-model](world-model.md)
§Migration steps 3–5) and `TrackTable.velocity` for heading.

### 3. A state value — the short and long term

**What it learns:** `V(s)`, the probability of winning (or the material margin at the cap) from
the current state, on the bot's own fog-limited features. Every purchase is then priced in one
currency: `Q(s, a) ≈ V(s after a) − V(s)`, which puts an extractor's payback, a tech
building's unlock and a unit's fight on the same scale — the exchange rate the current three
scales lack.

- **Supervised from logged matches.** Erickson & Buro (AIIDE 2014) predicted the winner from a
  game state with logistic regression on replay features, above 70% accurate in later states,
  and read the probability as the state's value
  ([paper](https://ojs.aaai.org/index.php/AIIDE/article/view/12725)). The match event log
  ([match-log](../scenario-scripting/match-log.md)) already records purchases, energy, dominion,
  infrastructure and army value every 5 seconds; the gap is per-sample STATE features (believed
  enemy composition, income, map control), which the world model's L1–L3 reads are.
- **Offline RL over the same logs.** Fitted Q iteration (Ernst, Geurts & Wehenkel, JMLR 2005)
  learns `Q(s, a)` from logged `(state, action, reward, next state)` tuples as a sequence of
  supervised regressions with tree ensembles, without new play
  ([paper](https://jmlr.org/papers/v6/ernst05a.html)). It turns every past self-play match into
  data, and its trees are inspectable.
- **The accepted pitfall:** logged matches are the bot's own play, so the value learned is the
  value under the CURRENT policy, which is why the outer loop (§4) must keep generating new play.

### 4. An outer loop — search over the models' weights

The models above have weights where today's bot has 27 constants. The trainer that exists
(`tools/selfplay/train.py`: MAP-Elites archive, Bradley-Terry ratings, prioritised fictitious
self-play, both start positions) already searches a VECTOR; it can search a weight vector
instead, with the right optimiser:

- **Evolution strategies.** Salimans et al. (2017): a derivative-free search over policy
  parameters that tolerates long horizons and delayed reward and needs no value function or
  discounting, scaling across workers by communicating only scalars
  ([paper](https://arxiv.org/abs/1703.03864v2)). A match result is exactly the delayed scalar it
  handles, and GDScript never needs gradients.
- **Quality diversity**, as built: MAP-Elites keeps the best solution per behaviour cell rather
  than one champion ([Mouret & Clune 2015](https://arxiv.org/abs/1504.04909)), which is what
  keeps a roster of distinct personalities.
- **The league as a game-theoretic loop.** PSRO (Lanctot et al., NeurIPS 2017) generalises
  fictitious play and double oracle: add a best response to the current mixture, re-solve the
  meta-game ([paper](https://arxiv.org/pdf/1711.00832)); AlphaStar's main agents, main exploiters
  and league exploiters are this with prioritised opponent sampling
  ([TStarBot-X's account](https://arxiv.org/pdf/2011.13729)). `train.py`'s equilibrium report is
  already the meta-game half; adding EXPLOITERS, members trained only to beat the incumbent, is the
  cheap step that finds counters the population would otherwise never meet.

### 5. Opponent modelling — specificity under fog

The bot sees a slice of the enemy. Synnaeve & Bessière (CIG 2011, AIIDE 2011) inferred an
opponent's opening and tech tree from noisy observations with a Bayesian model learned from
replays ([opening](https://hal.archives-ouvertes.fr/hal-00607277),
[plan recognition](https://ojs.aaai.org/index.php/AIIDE/article/view/12429)). Here: a model
of P(unseen composition, tech | seen), learned from self-play logs where the truth is known,
replacing the fixed `assumed_enemy_parity` prior (which, measured 2026-10-07, caps every bot's
read at `1 / parity` — [bot-parameter-space](bot-parameter-space.md) §Where holding-others-equal
is a lie, item 3). It fills the world model's per-commander knowledge
([world-model](world-model.md) §L1).

## Three ways to assemble them

**A — Learned valuation inside the current architecture.** Keep the managers, the ladder's
safety rails and the actuation; replace the valuation chain with `Q(s, a) = combat model (§1)
weighted by the threat clock (§2) + V-difference for investments (§3)`, and let the outer loop
(§4) search the models' few hundred weights. Legible, incremental, testable per component in GUT
and in decision sims (`sims/bot/production/` is the acceptance suite). **Cost:** the economy
ladder's ORDERING stays hand-written ([bot-parameter-space](bot-parameter-space.md) §Ladders the
search cannot reach), so a purchase the ladder never reaches is still unreachable.

**B — A learned macro policy over macro actions.** TStarBot1's shape: hand-coded executors
(build X at the ladder's chosen spot, train Y, research Z, save), and a learned chooser over
them reading the world model's features, trained by ES (§4) against the league. Removes the
ladder ordering. **Cost:** sample-hungry; a chooser with no value model underneath has to
discover what a fight is worth from match outcomes alone.

**C — Planning on an abstract simulator, distilled into a policy.** An economy simulator in
the BOSS mould — build mechanics, income and production queues only, no physics — was what made
build-order search real-time in StarCraft (Churchill & Buro, AIIDE 2011,
[paper](https://ojs.aaai.org/index.php/AIIDE/article/view/12435)). With the combat model (§1)
as its fight resolver it becomes a forward model fast enough for rolling-horizon evolutionary
planning of build orders, as COEP did inside UAlbertaBot (Justesen et al., GECCO 2017,
[record](https://pure.itu.dk/en/publications/continual-online-evolutionary-planning-for-in-game-build-order-ad/)).
Expert iteration then trains a fast policy to imitate the planner, and the planner to search
around the policy (Anthony, Tian & Barber, NeurIPS 2017, [paper](https://arxiv.org/pdf/1705.08439)).
**Cost:** a second simulator that must agree with the real one, which is exactly the drift
[CLAUDE.md](../../../CLAUDE.md) §Regenerating data warns about, here between two models of the game.

**Decided: A, in this order** — the combat model (§1) because its data is cheapest and it is
testable today; the threat clock (§2) once world-model steps 3–5 land; the value function (§3)
once the match log carries state features; the outer loop over weights (§4) last. B and C stay
options the components of A would feed, not alternatives to them.

## What the signal framework gives a model

The world model is already shaped like AlphaStar's observation — an entity list, spatial
layers and scalars ([world-model](world-model.md) §Frameworks adapted), and that is the input
side of every model above:

| Model input | Source |
|---|---|
| own and believed enemy composition, with confidence | L1 tracks (`TrackTable`, migration step 2); today the blackboard |
| per-unit stats for a set model | the piece docs, through `PieceFields` |
| threat, influence, approach, value per cell | L2 lattice channels (step 3) |
| arrival margin per believed group | L2 groups with `velocity`, against L2 `approach` |
| income, own and believed | L2 enemy income; the commander's own |
| exposure, standing, engagements | L3 reads (steps 4–5) |
| purchase history and resource series | the match log |

## Decided

Alex, 2026-10-07; the work item's questions are resolved in `gdd/tasks.md` T-100.

- **The state value predicts the material margin at a horizon now, and win probability once
  matches reliably end in eliminations.** Usable today, without baking in the proxy: the
  margin is the label until the corpus has enough decided matches to train on outcomes.
- **The combat model starts legible**: GA2M / explainable boosting (§1).
- **Training may use third-party Python packages, offline only, after verification** (§The
  training dependencies). Inference stays in GDScript, from exported weights.
- **A learned valuation decides PRODUCTION first**, behind a `BotDifficulty` switch, so a tier
  can be compared against itself; the ladder's production, tech and turret rungs and the
  savings goal keep the current valuation until the model has earned them.
- **The switch is ON in every tier, with the model as trained on 2026-10-07** (Alex): the bot
  plays the learned valuation by default while the work continues, before it has been shown
  better than the demand map, and with the weak matchup §1 records. Experiments that compare
  the two set the switch on each side explicitly.
- **Combat and positioning are separate models, downstream of this one** (§Scope above).

## The training dependencies

Verified 2026-10-07, against what each package publishes rather than its name:

| Package | Version | Why | License | Supply chain |
|---|---|---|---|---|
| `interpret-core` | 0.7.8 | the EBM | MIT | `interpretml/interpret` (Microsoft Research origin, maintainer `interpret@microsoft.com`), ~7k stars, pushed 2026-10-05; OpenSSF Scorecard 4.8/10; PyPI provenance attestation from its own `release_interpret.yml` |
| `numpy` | 2.5.3 | arrays | BSD-3-Clause (bundled 0BSD/MIT/Zlib/CC0) | attestation from `numpy/numpy-release` |
| `scikit-learn` | 1.9.1 | EBM's base; tree ensembles for §3 | BSD-3-Clause | attestation from `scikit-learn/scikit-learn-release` |
| `scipy`, `pandas`, `joblib` | 1.18.1, 3.0.6, 1.6.0 | pulled in by the above | BSD-3-Clause | the projects' own GitHub organisations |

None has a known vulnerability at those versions (OSV, 2026-10-07), and each ships a prebuilt
wheel for this machine (CPython 3.14, macOS arm64), so nothing is compiled from source. Rules
that follow:

- **Pinned, with hashes**, in a requirements file beside the trainer, installed into a virtual
  environment under the trainer's own directory and git-ignored; never into the system Python.
  `train.py` keeps running with no packages at all; only the fitting step needs them.
- **A version bump re-runs the same checks** — provenance, OSV, license — before the pin moves.
- **Nothing pickled crosses into the game or the repo.** `joblib` and pickle loading execute
  code, so a fitted model is exported to plain JSON (shape functions as tables, pairwise terms
  as grids), and GDScript reads only that.
- **The exported model is COMMITTED, the corpus is not.** The game reads
  `resources/bots/combat_model.json` at runtime and a clone must play, so it follows
  `resources/bots/roster.json`: generated by its trainer, never hand-edited, checked in. The
  fight corpus and the virtual environment (`tools/combat_model/out/`, `.venv/`) are
  git-ignored and regenerated.

## Still open

> **TODO — the corpus misses pairwise matchups.** With each side drawn from one faction, a
> fight between two single-type sides of two given units is rare (3 in 6,000 for the anti-mech
> tank against Sloops), so the shipped model rates the Sloop level with the anti-mech tank
> against Sloops, which the fights contradict, and `sims/bot/production/counter_the_tanks_learned`
> fails. Proposed: stratified sampling that guarantees every pair of unit types meets, and a
> larger corpus. This is what the default plays with until then.

> **TODO — whether the learned valuation is BETTER.** Not worse than the demand map at 32
> matches, and 4 of 10 on random maps (§1); showing a ten-point edge needs about 200
> counterbalanced matches. Then stage 2, the threat clock, which waits on the world model's
> lattice (world-model.md §Migration steps 3–5).

The 2026-10-04 balance result was rerun on 2026-10-07: [bot-randomness](bot-randomness.md)
§Strength is a search.
