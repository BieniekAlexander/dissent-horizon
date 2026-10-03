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
built so a black-box search can tune it; `tools/selfplay/results/es.py` is already an
evolution strategy over it. Policy-gradient RL over a network issuing orders is a poor fit:
the simulation runs in GDScript at a few hundred ticks per wall second, an episode is tens of
thousands of ticks with a terminal reward, and the result would discard the difficulty knobs.
The one RL-shaped place is the posture-vector layer in
[objective-selection](objective-selection.md), and even there a bandit or the same evolution
strategy over a tiny policy is simpler.

**Variety and strength pull against each other.** Any optimiser converges on one best
vector, which is the opposite of what variety wants. PLANNED — a **population**: a
quality-diversity search (MAP-Elites over axes such as aggression × greed) that keeps a
roster of distinct strong personalities; a tier becomes a distribution over the roster and
the per-match draw picks one and jitters it. `tools/selfplay/results/archetypes.json` is the
seed of that roster. **Prerequisite:** the start-position bias
([selfplay-results-2026-09-06](selfplay-results-2026-09-06.md)) would be learned as "play
from the good corner"; the search plays both assignments (as `effects.py` does) or runs on
a map where the bias is fixed first.

Tests: `tests/test_BotPersonality.gd`.
