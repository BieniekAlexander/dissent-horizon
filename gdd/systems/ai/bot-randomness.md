---
title: Bot randomness
type: system-note
---

# Bot randomness

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**Approved 2026-10-03.** Two matches on one map used to play out identically, because the
bot made no random draw at all: placement rejected a random tie-break on purpose, the source
scan in `tests/test_SeededRandomness.gd` forbids an unseeded one, and every decision was a
pure function of state and the tier's parameters. The only variety between seeds was aim
scatter. This note is how the bot varies between matches without giving up the rule that
**a match is reproducible from its seed** — replay re-derives the bots' orders from the seed
and records nothing of theirs ([recording-and-replay](../commands/recording-and-replay.md)).

## Rules

- **Every bot owns ONE generator**, `BotBrain.rng`, seeded from the match seed, the
  commander id and a salt (`BotBrain.seed_randomness`, called by `Scenario._attach_brain`).
  Never `SU.rng`: two bots drawing from one shared stream in interleaved order get numbers
  that depend on the other bot's think order, which is the world-frame placement bug in
  another costume. A brain nobody seeded draws nothing and plays exactly as the bot did.
- **A personality is drawn once per match.** On the first think the tier's `BotDifficulty`
  is jittered: every field in `BotDifficulty.SEARCH_RANGES` moves by a Gaussian of
  `personality_spread` × its range, clamped, ints rounded, sentinels (−1 uncapped, PASSIVE's
  9999) never moved. The periods are not in the table — reaction time is the tier's
  identity — nor are the booleans or the two variety knobs. The harness records the config
  as PLAYED, so every self-play row names its personality.
- **A scored decision is sampled at `decision_temperature`**, relative to the best score
  (`BotSampling`): an option within τ of the best is a live alternative, and the same τ means
  the same thing in energy, in effectiveness × demand and in a normalised score. Sampled:
  which unit a structure trains (`BotProduction`), which errand gets a shared actor first
  (`BotOpportunist`), which unit scouts (`BotScout`). Not sampled, and never to be:
  **placement**, which must stay mirror-exact
  ([bot-architecture](bot-architecture.md) §Where a building goes), and anything that is a
  hard constraint rather than a preference (the cheapest affordable unit, the reserve floor).
- **Zero is the old bot.** `personality_spread: 0` and `decision_temperature: 0` reproduce
  the deterministic tier exactly, and a controlled experiment sets both — a search that did
  not would be measuring its own draw. PASSIVE ships at zero: a sparring partner is
  predictable on purpose.
- **The ladder is not randomised.** `BotEconomy`'s build order is a sequence, not a score;
  randomising it would skip rungs at random. Macro variety comes from the personality draw
  moving `economy_reserve`, `income_structure_target`, `build_concurrency` and the commit
  gates, and the ladder's conversion to scored options
  ([bot-roadmap](bot-roadmap.md) §arbitration) is what brings it under the temperature.

TODO: the scout's DESTINATION is still an argmax — that search is a resumable sweep keeping
one running best, and sampling it means keeping every point's score.

## Strength is a search over the vector, not a learner inside it (settled)

Asked whether reinforcement learning is the right model: **no, not in the usual sense.** The
bot is a hand-written, legible policy whose only free surface is the `BotDifficulty` vector,
built so a black-box search can tune it; `tools/selfplay/train.py` is that search.
Policy-gradient RL over a network issuing orders is a poor fit:
the simulation runs in GDScript at a few hundred ticks per wall second, an episode is tens of
thousands of ticks with a terminal reward, and the result would discard the difficulty knobs.
The one RL-shaped place is the posture-vector layer in
[objective-selection](objective-selection.md), and even there a bandit or the same evolution
strategy over a tiny policy is simpler.

**Variety and strength pull against each other.** Any optimiser converges on one best
vector, which is the opposite of what variety wants. So the search keeps a **population**:
`tools/selfplay/train.py` (built 2026-10-04) is a quality-diversity search whose archive is
a grid over two behaviour descriptors measured from play — aggression (simulated seconds to
the first ATTACK posture) and greed (structures built) — with one incumbent per cell, taken
only by out-rating it. Its rules, each the answer to a way the naive search goes wrong:

- **Rated against the roster, never against one parent.** Every match is kept in one ledger
  and every member's rating is refitted from it (Bradley-Terry on the soft score `analyze.py`
  gives, so a win beats any stalemate beats any loss). A single-lineage strategy learns to beat
  its parent, which is a counter and not a strength.
- **Both start assignments, always.** The start-position bias
  ([selfplay-results-2026-09-06](selfplay-results-2026-09-06.md)) would otherwise be learned
  as "play from the good corner". The map pool is one scene until the generator's maps are
  stable enough to rotate — that is the remaining prerequisite, now for breadth rather than
  for correctness.
- **Opponents weighted toward the ones the parent loses to**, over a uniform floor
  (prioritised fictitious self-play). Pure self-play against the strongest member forgets the
  counters it already found.
- **Parents chosen by an upper-confidence rule over cells**, mutation scale self-adapting per
  lineage with occasional large jumps and crossover, and a stagnant generation widens the
  next. Exploitation alone fills one cell; exploration alone never rates anything well.
- **The dice are pinned.** Every match sets `personality_spread` and `decision_temperature`
  to 0, so the ledger measures the vector and not the draw; the tiers keep their spread in
  play.

What the search reports is the roster's pairwise score matrix and its mixed equilibrium: how
many members the mixture plays, and how much the best single member gains over it. **A
dominant member is a finding about the game, not a failure of the trainer** — the search is
the instrument that checks whether the units actually form the rock-paper-scissors the design
wants (the Matilda-versus-recruit measurement in
[squads-and-relations](squads-and-relations.md) was the first such finding).

**Rerun (2026-10-07, 20 matches, cap 900 s, same seed roster and settings, every match
clean):** the rush is still rated first (+1.08) and the equilibrium is still the rusher alone,
but it is no longer dominant: it scores 0.88 against the tier and 0.92 against the turtle,
and only **0.54 against the economist**, which it beat 0.77–0.90 before. The default tier beats
the economist (0.84) and the turtle (0.88). Two matches per pairing, so this ranks the roster
and measures little else. Report: `tools/selfplay/results/train_2026-10-07/report.md`. The run
below predates squads and staging gates, the savings goal, the defence demand, the tech rung,
crush targeting and the fog-honest senses.

**First run (2026-10-04, 52 matches, cap 900 s, HARD periods, `skirmish.tscn`):** the
rush is dominant. The seed that commits at one unit with no reserve won 11 of its 12 matches,
eliminating in under six simulated minutes on average, and scored 0.77–0.90 against every
other roster member; the equilibrium is the rusher alone, exploitability 0, and two
generations of eight children found no counter (a rusher's own child could not take its
cell). That is the balance finding the search exists to make: as tuned, a beeline army beats
any economy, which is the premature commitment Alex intends command-centre cost and health to
punish ([objectives-and-completion](../scenario-scripting/objectives-and-completion.md) §Win
conditions). Rerun the seed round after that tuning before reading anything else into the
roster. Report: `tools/selfplay/results/train/report.md`.

## Naming a personality in a scenario

A member of the roster is a scenario's to field. `train.py export` writes the live roster to
`resources/bots/roster.json` (never hand-edited: the trainer owns it, and re-exports it from
the archive), `BotRoster` reads it, and a `PlayerSlot` names a member by id in its
`personality` export. The vector lands ON TOP OF the slot's tier, so the tier still sets the
periods — reaction time is the tier's identity and is never searched — and a member plays as
trained only at the tier it was trained at, which the roster records. `config_overrides` on
the slot is the one-off tweak that does not deserve a roster entry ("this one never
attacks"), keyed by `BotDifficulty` field name. An id the roster lacks, or a key that names no
field, fails the boot in `Scenario._validate_player_slots`, as authored content should: the
dictionary is refused whole, never half-applied (`BotDifficulty.apply_overrides`). The
self-play harness's per-slot `config` goes through the same door. Switching a bot's tier from
the debug menu replaces the personality with the tier's own vector; it asked for the tier.

PLANNED — **a tier as a distribution over the roster.** Today a slot names one member or
plays the tier plus jitter; a tier becomes a list of roster ids to draw from, and the
per-match draw picks one and jitters it. Waits on a roster worth drawing from: enough
generations that several cells hold members rated clearly above the seeds, after the
command-centre tuning above. PLANNED — **categorical preference weights on the vector** (a
weight per unit class in production, an opening-style weight, static-defence and garrison
appetites), without which an air-heavy or mech-first personality is not reachable by any
search, since production picks by demand value alone.

Tests: `tests/test_BotPersonality.gd`, `tests/test_BotRoster.gd`.
