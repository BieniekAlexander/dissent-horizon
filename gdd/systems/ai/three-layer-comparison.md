---
title: The three-layer model, compared
type: system-note
---

# The three-layer model, compared

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**What this note is.** A reading of the framework Marvin Gouw describes for ZeroSpace's AI
(*[Cure for Predictable Game AI](https://www.youtube.com/watch?v=Bo0X6XMsg6M)*, transcript at
[`gdd/cure-for-predictable-game-ai.md`](../../cure-for-predictable-game-ai.md)) against what
this project's bot actually does. It is research, not a plan: where it finds a gap it names
one, and the gap goes in [bot-roadmap.md](bot-roadmap.md) as a `TODO` rather than here.

It is worth saying plainly that the talk is a conversation, not a spec. It names its layers
and its principles; it does not give data structures. So the comparison below is between his
stated *organising ideas* and our code, and where a reading is mine rather than his, it says
so.

---

## The premise, and whether it applies here

His diagnosis: **an RTS AI gets pattern-matched and exploited the moment the player learns its
script.** His illustration is StarCraft 2's build orders — the AI picks one, commits to it,
and keeps committing after the player has visibly countered it. *"I counter it and it is
failing, but it doesn't react."*

That diagnosis lands here, and the roadmap already reached it independently: **almost every
decision this bot makes is a fixed ladder or a fixed call order rather than a comparison.**
The economy builds dominion → infrastructure → production → extractor, in that order, every
game. The scout beats the military because it is called first. Nothing asks whether scouting
is worth more than attacking right now.

But the *shape* of our predictability differs from his in one way worth naming. StarCraft's AI
picks one of several scripts, so the exploit is **recognising which**. Ours has one script, so
there is nothing to recognise — the exploit is simply **knowing it**, and it is the same every
match against every faction. That is a worse position, not a better one, and it does not show
up as an obvious symptom the way a committed rush does.

His second point is the maintenance one, and it is the argument that should carry the most
weight here: *"if the meta changes slightly, we change the game a little bit, that's a lot of
maintenance… I don't want to babysit the AI code."* This project is pre-calibration by the
user's own account — the numbers are going to move. Every decision the bot derives from stats
survives that; every decision hardcoded against them has to be re-tuned by hand.

---

## His three layers against ours

The two three-layer diagrams are **not the same three**, and conflating them would be the easy
mistake. Ours splits by *purity* — who is allowed to mutate the world. His splits by *scale of
decision* — how big a question is being answered.

| | ZeroSpace (his) | Dissent Horizon (ours) |
|---|---|---|
| Split by | scale of decision | who may mutate state |
| 1 | **Vision** — cluster units, rate threat, project where things end up | **Perception** — `Bot`'s ~60 read-only senses |
| 2 | **Strategy (macro)** — tech position, opponent history, am I winning, push or defend | **Decision** — `BotBrain` + 9 managers |
| 3 | **Micro** — per-unit, per-ability execution | **Action** — `BotActuator`, the only mutating surface |
| plus | a "mastermind on top to keep them in sync" | the call order of `think()` |

They coexist comfortably: his axis could be laid over ours inside the decision layer without
disturbing the actuator rule. **Our layer 1 is roughly his layer 1, our layer 3 is not his
layer 3 at all** — ours is a mechanical funnel, his is where per-unit skill lives. What we
call "the decision layer" is his layers 2 and 3 fused, which is exactly the fusion he warns
against: *"you're basically fusing those two things together and you could separate that."*

His guiding rule is the same one our actuator embodies, stated for a different axis: *"keep
decision making compartmentalized in the areas they need to be made… don't overwhelm each
subsystem with more than it needs to handle."*

---

## Layer 1 — vision, and the clustering we don't have

**His claim:** clustering *is* the perception primitive. Not "how many marines are there" but
"there is a big threat here and a fast one on the flank". The clusters carry weapon strength,
movement speed and direction, so the strategy layer reasons over a handful of objects instead
of hundreds of units. His argument for it is that this is how a human organises the board
before deciding anything: *"if I just have tons of units spread out all over the map as my
information, I can't really make sense of it."*

**What we have.** `Bot`'s senses are strong and genuinely fog-limited — `CommanderBlackboard`
is a real belief model with per-entity last-seen times, structures persisting until disproved
on revisit and units expiring after 180 s. He confirms his AI is held to the same fog rule
(*"we're not going off pixels… this unit came in vision"*), so on that point we already agree.

**What we don't have is his primitive.** Our senses are *aggregates* and *nearest-X queries*:
`relative_threat_level()` collapses the whole board to one scalar; `army_centroid()` averages
every unit into one point, which for a split army names a location where nothing is;
`nearest_enemy_structure_to_base()` picks a single node. There is no object between "one unit"
and "the whole army".

Clustering does exist in the codebase — three times, none of them in perception:

- `ClusteringUtils.get_nodes_clustered` (single-linkage agglomerative), used by exactly one
  scenario event and never by the bot;
- `BotSanction._densest_cluster`, an O(n²) neighbourhood scan for aiming an area sanction;
- `Bot._aoe_hit_value`, the same scan again, valuing a kamikaze blast.

Two ad-hoc reimplementations of the idea, in the two places that could not proceed without
it, and a general implementation nobody calls. That is the signature of a missing layer.

> The consequence is concrete, not stylistic. `BotMilitary` commits its whole army to one
> objective position because one position is all its inputs can express. It cannot answer
> "leave four units home and take the rest" because it has no representation in which "the
> rest" is a thing. Nor can it distinguish one 20-unit push from two 10-unit ones.

`TODO` in [bot-roadmap.md](bot-roadmap.md) §The vision layer.

---

## Layer 2 — strategy, and the four questions it asks

He lists what his macro layer reads: *where I am in the tech tree, what my opponents have been
doing, a historical categorisation of what's been happening, am I on a losing footing, should
I be defending, should I be pushing.* Taking those as four questions:

**"Where I am in the tech tree" — we have this.** `game_phase()` derives a coarse phase from
distinct structure types owned, with elapsed time as a backstop.

**"Should I push or defend" — we have this, and better than the roadmap gives it credit for.**
`BotMilitary._committing_to_attack` is not the timer-or-threshold the architecture note
implies. It compares own army value against a decayed-peak estimate of the believed enemy
army, applies a **humility prior** (never assume the unseen enemy is weaker than 0.85× our
own, because under fog we compare our whole army to the slice of theirs we can see), relaxes
the bar the longer it holds without fighting so two even bots cannot deadlock, and floors that
relaxation so a losing bot does not throw its army away. **That is the one real strategic
comparison in the bot, and it is a good one.** It is also, precisely, the anti-stalemate
property the task asks IMPOSSIBLE to have.

**"What my opponent has been doing" — we do not have this.** The blackboard remembers *what
exists and where*, never *what changed*. There is no record that the enemy's army doubled in
the last 60 seconds, that a structure type appeared it did not have before, or that a
composition shifted toward air. Every strategic read is taken against the present instant.

**"Am I winning or losing" — we do not have this either**, and it is the more important
absence of the two. `relative_threat_level()` is an instantaneous strength ratio, and it is
read by nothing. Nothing anywhere asks whether the last engagement went well, whether the bot
is ahead on economy, or whether the game is slipping away. Which leads directly to:

---

## The snowball effect, and the one behaviour he singles out

His snowball argument: in an RTS, five units beating three often leaves **five** survivors, not
two. Losses are not subtracted, they are multiplied, so *timing* is what decides games and a
bot that mistimes by a little loses by a lot. He is blunt about the consequence: an AI that
does not get its builder to the right place at the right time will not compete with a decent
human ten minutes later, however good its micro is. He is equally blunt about the priority —
*"macro is basically the thing we need to solve first… micro really doesn't matter that much
until macro reaches that level."* Our own ordering agrees; the roadmap puts the economy first
for the same reason.

And the behaviour he names as the one that reads as human: **retreat.** *"Seeing the AI
retreat is very human-like."* It is his answer to the StarCraft failure he opened with — not
"pick a better plan" but "abandon the plan you are losing".

**We retreat in exactly one narrow case and nowhere else.** `BotBrain._tick_preservation`
pulls a unit out when it is below 25% HP **and** currently in a fight **and** can do zero
damage to anything in range — a *hopeless matchup* check, not a *losing* check. A unit at 30%
HP trading badly stays and dies. And there is no army-level retreat at all: `_committing_to_
attack` holds a wave until the army is spent to 35% of its launch value, whatever is happening
to it. **The bot hard-commits to a losing push, which is the exact behaviour the talk opens by
criticising.** The reason it is in the code is honest — it was the fix for a bot that dribbled
its army in — but the remedy for dribbling is a wave that retreats *together*, not one that
cannot retreat.

> Both gaps trace to the same missing input: **nothing in this bot reads whether it is winning
> or losing.** Retreat, re-planning, and reacting to a counter are all consumers of that one
> signal, which is why it is the highest-value single addition on the roadmap.

`TODO` in [bot-roadmap.md](bot-roadmap.md) §Reading the game.

---

## Layer 3 — micro, and the per-ability dropdown

*"For every ability we have and for every unit we have, we have a drop-down of how the AI is
supposed to effectively utilize that."*

**This is the strongest match in the codebase, and it was arrived at independently.**
`Sanction` exports `targeting` (`ENEMY_CLUSTER` / `REINFORCE`), `effect_radius` and
`min_targets` — authored per ability on the ability's own data, read by `BotSanction` when it
aims. That is his dropdown, in the place he would put it: the ability declares how it wants to
be used, and the AI code stays generic. The same instinct runs through the bot elsewhere and
is our best existing habit: a structure's role is read from its components, an AOE-suicide unit
is identified by its projectile's blast, counter-effectiveness comes from the damage matchup
table.

**The gap is coverage, not design.** That dropdown exists only for *sanctions* — commander
abilities. The bot never uses a unit's own ability at all: `Abilities` appears in `BotSanction`
and nowhere else in any bot module. Dignify, the task's own example, is unusable by a bot
today, and there is no field on an ability doc that would tell one how to use it.

The user's stated model for abilities — economic ones used as often as possible, offensive ones
worth saving for an impactful moment — maps cleanly onto extending the same authored field to
`kind: AbilityDefinition` docs, rather than onto a new bot module.

`TODO` in [bot-roadmap.md](bot-roadmap.md) §What has to be modelled.

---

## Waves versus a steady stream

A playtesting result of his, reported as a surprise: he expected collecting units into waves
to beat sending them continuously, and the opposite held. **Waves give the player breathing
room between them, and a good player converts breathing room into an advantage.** A
semi-steady stream arriving from several directions was harder to hold and — his words — more
fun for high-level players.

**We are a wave bot**, deliberately and at two levels: `configs/.../events.json` spawns timed
waves in scripted scenarios, and `BotMilitary` masses until a threshold and commits. His
result is a claim about *his* game's balance, not a law, so this is not a defect to fix. But it
is a cheap experiment once the self-play harness exists — wave versus stream is one parameter,
and it is exactly the sort of question that harness is for.

---

## What he tried and rejected, and what we should take from it

Two failed experiments, both worth recording because both are attractive.

**An LLM as the brain.** He wired GPT-3.5 in about two years ago. It forgot state, and told
that it was on tech level four it would start building a supply depot it did not need. His
conclusion was not "the model was too small" but that the architecture was wrong: cramming
everything into one brain, rather than parsing the world into a distilled form first and
handing that to separate, coordinated pieces.

**A neural network.** He had sparse CPU-runnable networks working in C++ and never shipped
them — no time to use them properly.

Both are the same lesson from opposite directions: **the win came from separating pieces and
giving them a clean interface, not from a stronger decision-maker.** That is worth holding
against the task's own interest in reinforcement learning. RL here is aimed at *searching
parameters of a legible model*, which is the opposite of replacing the model — and it is the
right target. What it needs is not a better learner but the thing the roadmap already blocks
on: a seeded, reproducible simulation and focused scenarios.

His advice to anyone building one is also a caution against how this bot has grown: *"approach
it in steps — what's the first step with the most visible effectiveness… and expand off
that."* This bot has nine managers before it has an answer to "am I losing".

---

## The comparison in one table

| His idea | Us | Verdict |
|---|---|---|
| Layered, compartmentalised decisions | perception / decision / action | **Match** — different axis, same principle |
| Same fog as the player | `CommanderBlackboard`, genuinely fog-limited | **Match** |
| Per-ability authored usage hints | `Sanction.targeting` / `min_targets` | **Match**, sanctions only |
| Derive from stats, don't script | components, damage table, projectile blast | **Match**, and our best habit |
| Clustering as the perception primitive | absent; two ad-hoc reimplementations | **Gap** |
| Historical read of the opponent | belief is a snapshot, not a history | **Gap** |
| "Am I winning or losing" | nothing reads it | **Gap** — the big one |
| Retreat | one hopeless-matchup case; no army retreat | **Gap** — the behaviour he singles out |
| Macro before micro | roadmap agrees, economy first | **Match** |
| Strategy is a comparison, not a script | true only of `_committing_to_attack` | **Partial** |
| Steady stream over waves | we are a wave bot | **Open question** — a harness experiment |
