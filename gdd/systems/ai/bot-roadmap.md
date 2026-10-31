---
title: Bot roadmap
type: system-note
---

# Bot roadmap

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

What exists is [bot-architecture.md](bot-architecture.md). Everything
unbuilt below is a `TODO` with a stated cost, in the order it is worth doing.

## The one-line diagnosis

The perception layer is strong and the arbitration layer is thin. `Bot` exposes ~60 senses
and `BotProduction` already makes a genuinely derived decision from them — but **almost every
other choice the bot makes is a fixed ladder or a fixed call order, not a comparison.** The
economy builds in a set sequence; the scout wins over the military because it is called
first. Nothing anywhere asks *is scouting worth more than attacking right now*.

Two decisions are honourable exceptions and are the models for the rest: `BotProduction`
picks a unit by composition value, and `BotMilitary._committing_to_attack` decides to attack
by comparing army values under a humility prior. `BotScout` joined them — WHICH unit scouts
is now a score (2026-09-04, below).

That is also the exploitable surface: a ladder is a script, and a script is what a player
learns.

## Difficulty first, because everything else is calibration

Until difficulty was a real knob there was nowhere to PUT the outcome of any tuning work, and
every improvement below had to ship at one strength for everybody. It was read in exactly two
places.

**`BotDifficulty` (2026-09-04)** — one resource per tier holding the parameters the
managers already wanted, handed to `BotBrain` by `Scenario._attach_brain`. It is a data
object with no behaviour, deliberately: the tiers must differ by numbers a training run can
search, not by branches a training run cannot.

What it carries, and what each is FOR:

| Field | The handicap it expresses |
|---|---|
| `combat_period_seconds`, `strategy_period_seconds`, `scout_period_seconds` | REACTION TIME, per kind of decision. A slow bot notices late — the most human-feeling handicap there is, and the one a player cannot see being applied |
| `army_commit_threshold` | how large an army it wants before attacking; the aggression dial |
| `preserve_min_cost` | which units it bothers to save (−1 = never, 0 = always) |
| `retarget_switch_margin` | COMMITMENT. A high margin means it will not micro away from a bad trade |
| `scout_unit_budget` | how many units it is willing to have away from the fight |
| `economy_reserve` | how greedily it banks before expanding |
| `may_attack` | PASSIVE's whole definition |

**PASSIVE is now minimally active rather than inert.** It was `active = false` — the brain did
not run at all — which is not what "should be minimally active, and should never attack the
player" asks for. It now thinks, builds and trains, and `may_attack` is what stops it: the
military may DEFEND and MASS but never ATTACK, and `BotSanction` never strikes. A passive
opponent that still grows is a sparring partner; an inert one is scenery.

**What each tier is FOR** (Alex, 2026-10-28, restating the brief for the skirmish bot; the
campaign's EASY / MEDIUM / HARD are the mission's own,
[campaigns/mission-design](../../campaigns/mission-design.md) §Difficulty):

| Tier | Goal |
|---|---|
| PASSIVE | no threat to its opponents. Not a priority; whether it is non-aggressive (today: it builds, trains, defends and never attacks) or does literally nothing is undecided |
| EASY | beatable by just about any player: a loss takes a catastrophic blunder or an inactive player |
| MEDIUM | a challenge for players who have not played RTS games extensively |
| HARD | a challenge for players who have played RTS games extensively |
| IMPOSSIBLE | impossible for a human to beat. Its performance is unbounded; adaptive difficulty may come later |

**The acceptance test for the ladder** (Alex, 2026-10-28): on randomly generated maps, each tier
beats the tier below it in **80% or more** of matches, measured in pairs that exchange start
points so the start-position bias cancels (selfplay-results-2026-09-06.md §The verdict). Only
the Colonial bot is ready to be measured; `gdd/tasks.md` T-131 is the measurement.

**A tier throttles EXECUTION, never disposition** (Alex, 2026-10-29). How a bot wants to
win — rush, or turtle and out-invest — is a style a HARD bot and an EASY bot may each have;
what a tier says is how WELL the bot plays its style. So every disposition field in
`BotDifficulty` is the same number in every tier and is moved only by the personality draw,
at one spread for every tier. The brief names three axes of execution, and each is a throttle
the tiers ramp:

| Axis | The human it models | The throttle |
|---|---|---|
| **Latency** — how soon the bot acts on what it has decided | a player with one pair of hands: a purchase waits until they look at the base | `attention_orders_per_second` (`BotAttention`): every deciding job draws on one budget of orders per second, runs only when it has orders in hand AND it is its turn, and pays for what it issued. The turn is fair: a job refused for want of attention is owed the next refill, so a fight delays the economy by a turn rather than starving it (see the stalemate finding below) |
| **Wisdom** — how well a decision answers the game | a player reading the enemy a few seconds late, and sometimes picking the second-best thing | `perception_delay_seconds` (`CommanderBlackboard`): a new enemy piece is believed that long after it is first seen, and a believed position is re-read at most that often. Units still shoot what is in range; only what a DECISION reads is old. Plus `decision_temperature`, which already existed |
| **Concurrency** — how many things run at once | a player who can run one attack, or several fronts | the same attention budget (a second front waits for the first to be given its orders), with `squad_cap` and `build_concurrency` as the hard ceilings, and the decision periods as how often the bot looks at all |

**IMPOSSIBLE lifts every throttle**: unlimited attention, no delay, the argmax, uncapped
build and squads, the fastest periods. That is what "unbounded" means in the brief — the best
THIS model plays — and not perfect play, which no frame budget could compute (Alex, 2026-10-29).
The tiers are testable against each other all the same: the ladder below is the measurement,
and a model that plays better at every tier moves every tier.

**Why attention and not a delay per purchase.** A fixed reaction delay would slow every
decision equally and leave the bot as parallel as ever; a forgetting model would float energy
at random. One budget shared by every deciding job produces the stall a human actually has —
macro waits while a fight is being managed — and limits the fronts a bot can run from the
same number, so it is one knob where the brief named two. It is not the scheduler's work-unit
budget (`BotScheduler`), which bounds what the AI may cost the machine and is the same at
every tier; it is counted in simulated seconds, so a seed replays the same.

**What it superseded.** The first ladder (2026-10-29, `tools/selfplay/results/ladder/`
`2026-10-28T2226` through `ladder_d`) ramped the DISPOSITION fields: EASY as the measured
economist vector (commit at 8, reserve 1200, five utility units, four extractors before
production, tech margin 2.0), IMPOSSIBLE as the rusher (commit at 1, no reserve, no retreat,
trickle reinforcement), the personality spread shrinking 0.2 → 0.03 toward the top. It
measured EASY < MEDIUM 89%, MEDIUM < HARD 70%, HARD < IMPOSSIBLE 60% of ten matches per pair,
against 44 / 38 / 50 for the table before it. **REJECTED as a difficulty axis** — it bought
separation by deciding how each tier wants to win, which is exactly what a tier must not
encode. Two findings from it stand: the decision periods below about a second are not realised
under the shared scheduler budget ([think-scheduling](think-scheduling.md) §Open), and the
attack ratio and parity knobs are near-decorative because the stalemate clock relaxes the
bar to its floor within a minute of the body count being met (`BotMilitary._committing_to_attack`).

**The execution ladder, measured (2026-10-29, T-131; `tools/selfplay/results/ladder/exec_*`).**
Colonial-mirror matches on generated maps, start points exchanged, a 1200 s cap, every
disposition field at its default in every tier and the personality draw on at spread 0.15, so
the only differences between the seats are the throttles:

| ladder | attention (orders/s) E / M / H / I | delay (s) E / M / H / I | EASY < MEDIUM | MEDIUM < HARD | HARD < IMPOSSIBLE |
|---|---|---|---|---|---|
| `exec_a` (10 per pair) | 0.25 / 0.5 / 1.0 / ∞ | 6 / 3 / 1 / 0 | **100%** (8–0, 2 stalemates) | 75% (6–2, 2) | 44% (4–5, 1) |
| `exec_b` (10 per pair) | 0.2 / 0.35 / 0.6 / ∞ | 8 / 5 / 2.5 / 0 | 50% of 4 (6 stalemates) | 100% of 5 (5 stalemates) | 60% (6–4, 0) |
| `exec_c` (30, top pair) | — / — / 0.6 / ∞ | — / — / 2.5 / 0 | | | **76%** (22–7, 1), CI 58–88% |
| `exec_d` (10, middle pair) | — / 0.5 / 0.6 / — | — / 3 / 2.5 / — | | 67% (4–2, 4 stalemates) | |
| `exec_e` (30 per pair, stall fixed) | 0.25 / 0.5 / 0.6 / ∞ | 6 / 3 / 2.5 / 0 | **92%** (24–2, 4 stalemates) | 68% (15–7, 8 stalemates) | **80%** (24–6, 0) |
| `exec_f` (30, lower pairs) | 0.25 / **0.4** / 0.6 / — | 6 / **4** / 2.5 / — | **84%** (16–3, 11 stalemates) | 59% (13–9, 8 stalemates) | |
| `exec_g` (30 per pair, fair turn) | 0.25 / 0.5 / 0.6 / ∞ | 6 / 3 / 2.5 / 0 | **97%** (29–1, 0 undecided) | 57% (12–9, 5 stalemates + 4 cut by the wall clock) | 72% (21–8, 1 stalemate) |
| `exec_h` (30 per pair, answerable threats) | 0.25 / 0.5 / 0.6 / ∞ | 6 / 3 / 2.5 / 0 | **97%** (28–1, 1 stalemate) | 54% (14–12, 4 stalemates) | 70% (21–9, 0) |
| `exec_i` (30 per pair, reachability fixed; scout floor, inert cut, wave sweep) | 0.25 / 0.5 / 0.6 / ∞ | 6 / 3 / 2.5 / 0 | **89%** (25–3, 2 stalemates) | 67% (18–9, 3) | 61% (17–11, 2) |
| `exec_k` (30 per pair, the `exec_i` fixes + chain-cost valuation + front momentum) | 0.25 / 0.5 / 0.6 / ∞ | 6 / 3 / 2.5 / 0 | **87%** (26–4, 0 stalemates) | 66% (19–10, 1) | **50%** (15–15, 0; by IMPOSSIBLE's start 4–11 / 11–4 — the start point decides, not the tier) |
| `exec_j` (30 per pair, the `exec_i` fixes; VOID past its 21st match — two sessions began editing the bot's scripts in the same checkout at 06:05, so the middle and top pairs measured code in flight) | 0.25 / 0.5 / 0.6 / ∞ | 6 / 3 / 2.5 / 0 | **96%** (24–1, 1 stalemate, 4 matches with script errors from a half-edited `bot.gd`) | 57% (17–13, 0) — void | 48% (14–15, 1) — void |

What the three say together. The unthrottled bot issues 0.6–1.9 orders a second (measured on
three probe matches), so an attention budget of 1.0 barely binds and HARD and IMPOSSIBLE were
a coin flip at it; at 0.6 HARD is in debt about half the time and the top pair separates to
three in four. Below about 0.35 orders a second a bot is too slow to FINISH the other: `exec_b`
left six of ten EASY–MEDIUM matches and five of ten MEDIUM–HARD matches undecided at the cap,
so the lower tiers stay at `exec_a`'s values, where EASY < MEDIUM cleared the bar outright.
The shipped table is `exec_a`'s EASY and MEDIUM with `exec_c`'s HARD (0.6 orders/s, 2.5 s).
The periods (1.5 / 0.667 / 0.4 / 0.1 s) are kept as the tier's identity but buy little:
the budget realises 0.6 / 1.2 / 1.3 / 2.4 military runs a second
([think-scheduling](think-scheduling.md) §Open).

**A finding under the top pair that was not a tier, now fixed.** One start point on maps 7101
and 7102 held the first barracks back by three to nine minutes for whoever started there, at
any tier and with any drawn personality, and decided about one match in five — eleven of
thirty matches in `exec_c` had a stalled side. It was two rungs of the economy ladder (a
producer anchored on an outpost it could not stand on, and a balance dip buying extractors),
fixed 2026-10-30 and written up in [bot-economy-diagnosis](bot-economy-diagnosis.md) §What
this does NOT settle. `exec_e` is the first ladder run on the fixed bot: the by-start split
is level in every pair (13–0 / 11–2, 7–4 / 8–3, 12–3 / 12–3), where `exec_c` had been 15–2
against 7–5 by start.

**The stalemates were attention starvation, not a tier.** Eight of the thirty MEDIUM–HARD
matches in `exec_e` and in `exec_f` ended undecided with one shape on both sides: every
producer idle, every unit type trainable and affordable, and five to thirty-two thousand
energy banked for the last ten minutes (probe `bank_7105`/`bank_7106`, 2026-10-30, with the
producer, savings and unmet-need fields added to the sample). The balance was in debt in 88 to
100% of samples from 300 s on. The gate ran jobs in due order, and the jobs on the combat
cadence are due three times as often as production and the economy, so once an army was
fighting they took every refill and a refused production job was not tried again for a
whole period — by which time the balance was in debt again. Slowing MEDIUM (`exec_f`) made it
worse, not better: a lower rate is more of the time in debt. Fixed by making the turn FAIR
(`BotAttention.claim`: a refused job queues, the next positive balance is the longest
waiter's) and by marking a refused job pending (`BotBrain._attention_pending`), so the
scheduler retries it next tick. On the probe both bots trained and fought to the end. The
per-job spend the sample now carries (`attention_spent_by_job`) shows where a throttled
bot's orders go: on both probes the opportunist job issued the most (185–263 over 1200 s),
ahead of the military — TODO below.

**The fair turn compressed the ladder.** `exec_g` is the first run on the fair-turn bot, same
maps and seeds as `exec_e`. The bottom pair cleared outright with no undecided match (97%,
29–1), the middle fell from 68% to 57% of 21 with nine undecided, and the top from 80% to
72% (21–8). That is the shape of a bug that only ever hurt a throttled bot being removed:
MEDIUM gained on HARD, HARD gained on IMPOSSIBLE, and the 0.5 / 0.6 rungs — a difference of
0.1 orders a second, which both bots now run flat against (0.45 and 0.55 realised) — were
never separating the tiers; starvation was. `exec_f`'s reading that a slower MEDIUM
stalemates more is pre-fix and void. The per-job spend is the same in decided and undecided
matches (opportunist 27–30%, military 26–31%, production 20–23%, scout and targeting 5–9%),
so where attention goes is not what decides a stalemate now.

**What the undecided matches look like now.** Nine of thirty in the middle pair, on maps 7100,
7101, 7105, 7106, 7108, 7110 and 7114 — 7100 and 7101 in every batch so far. Both bots run at
budget with a few thousand energy and their producers mostly busy; nobody is starved. The
recurring shape is on the HARD side: it masses forty to eighty units at home (7100_base: 80
units, 9000 of army value, 4900 banked, against ten MEDIUM units), believes one to seven
enemy structures with its scouts having seen about 30% of the map, and launches waves of 35,
77 and 94 units that are back home and counted idle within one 50 s sample, their value
intact and the opponent's structure count unchanged. A wave that ends with its value intact
was not spent and not aborted: its objective was abandoned (`OBJECTIVE_STALL_SECONDS`, nobody
fighting at it for 20 s) or its belief erased, `_objective_for(ATTACK)` found nothing else
actionable, and `tick()` demoted the posture to MASS — the army walks home, and goes again
when the 120 s abandonment lapses or a scout adds a belief. Whether the believed structure
was a stale image of one already dead, or stands behind a terrace the wave could see but not
reach, the samples cannot say — TODO below. Those matches also run below real time (20–34
ticks a second with eighty-unit armies) and four hit `run_match`'s 900 s wall-clock cap
before the 1200 s simulation cap; the ladder now passes a wall cap under its kill timeout and
reports the two apart.

**The wave that comes home without a fight — diagnosed from the replay** (2026-10-30): the
base was never found. The objective was the bot's one belief, a structure or a unit sighting;
once verified gone the posture fell back to MASS and the next sighting relaunched. Scouting by
foot soldiers after the opening drones lapse covered 30% of the map in ten minutes. And the
same match showed every threat sense treating an air raider the ground army cannot touch as a
threat it was answering: construction frozen, savings released, army marched, no SAM — fixed
the same day (`Bot.can_answer`). Write-up and what is still open:
[bot-engagement-fixes](bot-engagement-fixes.md) §An unanswerable threat.

**The answerable-threat fix resolved matches; it did not move the ladder** (`exec_h`, same maps
and seeds, 100 min). Every decided match of `exec_g` ended the same way in `exec_h` except the
two on map 7112 at the top, which swapped sides with each other. What changed is the
undecided: nine in the middle pair became four (7100, 7101, 7105 and 7108, all with HARD at
start A — 7100 and 7101 for the fifth batch running), and the five that resolved went 1–3 for
HARD; the one undecided at the top resolved for HARD. So the pairs read 54% of 26 and 70% of
30 against `exec_g`'s 57% and 72% — unchanged within the interval, with the middle pair level
by start (8–5 / 6–7). The four that remain have `exec_g`'s shape: on 7100 HARD masses 9000 of
army value and 74 idle units at 700 s against one believed structure and no objective, spends
it in one wave at 800–900 s, and MEDIUM then sits on 13300 in ATTACK against eleven believed
structures for the last 300 s without finishing. The SAM the fix asks for is still almost
never built in a match (six across 180 seats, against 300 enemy combat aircraft fielded):
on 7100 the Recruit side never had a defence candidate at all, and on 7101 MEDIUM chose a SAM
twelve times and built none — open in the same note.

> **TODO — the opportunist is the biggest spender of a throttled bot's attention.** Over
> 1200 s it issued 185–263 orders against the military's 148–195 and production's ~105
> (`bank_7105`); across the thirty `exec_g` middle-pair matches it took 27–30% of every
> throttled bot's orders, level with the military and ahead of production, while the units
> it sends stayed counted idle, which reads as the same errand re-issued every strategy
> period. Under an attention budget that is a tax on every other decision. It is not what
> decides a stalemate (the share is the same in decided matches). Measure what it re-issues
> before touching it.
> - [ ] Is it re-issuing an order a unit already holds (a cache of what was sent would stop
>   it), or sending a new unit each period to an errand the last one abandoned?

**Disposition notes** (`config` in each result row is the drawn personality; the script is a
scratch tool, the method is: mean of each drawn field among a tier's wins against its losses).
Over `exec_a` and `exec_b`, a tier lost more often with a HIGHER `utility_unit_cap` (MEDIUM
2.3 won / 3.1 lost, HARD 2.4 / 3.3) and a HIGHER `economy_reserve` (EASY 327 / 579,
IMPOSSIBLE 572 / 713), and IMPOSSIBLE lost with a LOWER `army_commit_threshold` (3.4 won /
2.8 lost) and `attack_value_ratio` (1.26 / 1.04): the trickle of two-to-three-unit waves at
70–140 s that the first ladder blamed on the rusher table is a disposition the draw hands out,
and it loses. None of this moves a tier; it is what the disposition model should learn from.
Over `exec_e` and `exec_g` (sixty matches a tier) the one field that diverges in every tier
is `income_structure_target`: a tier lost with a HIGHER draw (MEDIUM 0.68 won / 1.23 lost,
HARD 0.70 / 1.00 in `exec_g`; the same sign in `exec_e`), and MEDIUM won with a higher
`risk_bias` (0.51 / 0.36). On the fair-turn bot `attack_value_ratio` is lower among wins in
every tier (HARD 1.22 / 1.39): the bot that commits sooner wins more often.

> **TODO — the two upper pairs are under the bar at thirty matches each: 54% of 26 in the
> middle, 70% of 30 at the top (`exec_h`; 57% and 72% in `exec_g`).** The stall, the
> starvation and the unanswerable threat are fixed, and with them gone the rungs the table has — 0.5 / 0.6 / ∞ orders a second, 3 / 2.5 / 0 s
> of delay — are too close to separate at 80%: the two throttled tiers run flat against
> budgets 0.1 apart, and IMPOSSIBLE realises 1.0–1.8 orders a second, so HARD at 0.6 is a
> third of the way to it. Re-spacing is the next move, measured at thirty a pair (~70 min a
> ladder); `exec_f`'s "slower stalemates more" was starvation and does not constrain it.
> **Superseded before it was measured (2026-10-30, after `exec_h`):** the live probe of 7100
> found `Bot.is_reachable` on Godot's default path budget, which read every enemy main-base
> structure as unreachable for both bots ([bot-engagement-fixes](bot-engagement-fixes.md)
> §The objective nobody could reach). Every `exec_*` row above was measured with that bug;
> the ladder is re-run (`exec_i`) on the fix — and on the scout floor, the inert-purchase cut
> and the wave sweep built the same day on Alex's rulings (same note, §Built on Alex's four
> rulings) — before any rung moves. `exec_i` (2026-10-31): **89 / 67 / 61**, the middle pair
> up and the top pair down, with a deployment regression, a sweep hang and an unfilled floor
> found and fixed from it (same note, §What `exec_i` found), plus the first three defects of
> [decision-pathologies](decision-pathologies.md); re-run as `exec_j` before any rung moves.
> `exec_k` (2026-10-31, on everything above plus the chain-cost valuation and the front
> momentum read): **87 / 66 / 50**, one stalemate in ninety. The stalemates are gone, and so is
> the top pair: HARD and IMPOSSIBLE split 15–15, and which wins is the START POINT (IMPOSSIBLE
> 4–11 from A, 11–4 from B), so at the top the tiers no longer separate at all. Two things
> changed between `exec_i` and `exec_k` besides the bugs: the valuation prices every candidate
> through its prerequisite chain, and the wave reads strength fields at its front — and the
> bot's own CPU per seat went 47 → 127 M µs at IMPOSSIBLE and 21 → 55 M µs at HARD, with the
> ECONOMY job's share rising from 38% to 49% (`jobs` samples). The scheduler's work budget
> is shared per tick and is not a tier knob, so a costlier economy delays every other job
> most for the tiers that think most often. TODO: attribute the top pair's collapse — the
> chain-cost valuation's cost (profile the economy job; memoise the chain per think), the
> front read's retreats (does IMPOSSIBLE now abort waves it used to win?), or the fixes'
> removal of the stalemates that `exec_i` counted as neither — before any rung moves.
> - [ ] Which first: the economy's CPU (cheap, mechanical) or the retreat A/B (one ladder run
>   with the front read switched off)?
> `exec_j` also carries the chain-cost valuation built 2026-10-31 — a locked unit or turret
> priced at its unowned prerequisites plus itself, the goal rung, and a tech margin that now
> stacks on a priced chain ([bot-architecture](bot-architecture.md) §Valuing a unit, and
> saving for it) — so its rows are the first measured with the SAM and the Academy reachable.
> - [ ] Which re-spacing: attention alone (MEDIUM 0.4, HARD 0.8), or every throttle widened
>   together (periods, delay and attention)?
> - [ ] Does the 1200 s cap stay, with an undecided match counted as neither tier's win, or
>   does it count against the higher tier (which would make "too slow to finish" a failure
>   of the ramp rather than of the match)?

> **TODO — IMPOSSIBLE's "unbounded" is the throttles lifted, not a supernatural half.** The
> brief's "a human will never realistically beat it" is met only as far as the model plays
> well with every throttle off; perfect play is not the goal (Alex, 2026-10-29), and a resource
> handicap is not either. What raises the ceiling is the model — per-unit micro, placement,
> the siege loop — which raises every tier with it. The stated caution stands: two IMPOSSIBLE
> bots must not deadlock into a stalemate, which argues against making DEFEND cheap.
> - [ ] Does IMPOSSIBLE want a per-unit execution layer (frame-paced micro) once the model's
>   own ceiling is measured, or is the ladder's top pair enough?

## Then: arbitration, not sequence

The Opportunist already has the right shape — gatherers return scored candidates in a common
currency (energy-equivalent value) and the best are executed. **The plan is to widen that
currency until it covers the decisions the call order currently arbitrates**, rather than to
add a fourth mechanism beside the ladder and the FSM.

Concretely, in the order they are worth converting:

1. **The economy ladder → scored options.** "Build an extractor" and "build a barracks" are
   both energy-equivalent gains over a horizon; the ladder is a hand-ordering of a comparison
   the bot could make. This is the single biggest predictability win, because the opening is
   what a player learns first.
2. **Scouting → a scored option.** The value of a scout is the value of the information
   against the cost of the unit being away — which is exactly the trade-off the user named
   ("n = infinity is obviously ideal, so the question is a trade-off"). It cannot be answered
   by a call order.
3. **The military posture → scored postures.** Three states become three scores, and MASS
   stops being "otherwise".

### The currency is ENERGY-EQUIVALENT (SETTLED 2026-09-04)

**Every option the bot compares is priced in energy**, with an authored constant wherever a
thing has value but no price. The alternative considered and rejected was a unitless utility
in [0, 1] per option — the classic utility-AI shape, and the one this note previously leaned
toward. Energy won on three arguments, all of which are about the currency doing work
*outside* the decision it was introduced for:

- **It is already the right answer in the place the bot reasons best.** "Will this blast
  destroy more than the drone costs" is a subtraction in energy and nothing else. A unitless
  utility would have had to launder that back into a comparison it already makes correctly.
- **It reads back into balance.** If a unit is not worth its price to the bot, that is a
  finding about the unit, not about the bot. A normalised utility cannot say that — every
  option scores 0 to 1 by construction, so nothing is ever revealed as overpriced.
- **`BotOpportunist` needs no conversion**, and the existing scored decisions stay comparable
  with the new ones rather than living in a second scale.

**WITHHOLDING stays a threshold for now, deliberately.** "Should I buy this cheap unit or
save for the expensive one" is a genuine option the currency could price, and it is NOT being
modelled: `economy_reserve` exists to stop the bot spending down to zero so that it can
always afford something, and that crude guarantee is worth more today than a rigorous model
of saving. Revisit alongside the energy-versus-dominion trade below — they are the same
short-term-against-long-term question.

The cost accepted: **anything without a price needs one authored**, and that number is a
judgement rather than a derivation. There is exactly one so far —
`BotScout.INFORMATION_VALUE_ENERGY`, what knowing the whole map is worth. Keep them few,
named, and defensible in a line each; a formula with a hidden rate in it is the failure mode.

> **TODO — energy against DOMINION is the open half.** Both are real resources and the bot
> will eventually have to trade one for the other ("should I take another extractor or push
> the dominion route"), which energy-equivalent pricing does not answer on its own. Deferred
> deliberately as a modelling exercise of its own. **The practical consequence is that the
> economy ladder cannot be converted yet** — a dominion structure and an extractor are not
> comparable until it is settled, which is why §1 below is not the first conversion despite
> being the biggest win.

**Conversion 2, scouting (2026-09-04).** `BotScout._scouting_is_worth_it` compares
`INFORMATION_VALUE_ENERGY × stale_fraction ÷ (scouts already out + 1)` against
`unit_cost × ABSENCE_RISK`. The divisor is the answer to "why not scout with everything": the
second scout buys half what the first did at the same price. `scout_unit_budget` survives as
a CEILING rather than as the decision — a cap says what is permitted, not what is wise — so
the difficulty knob still means something, and a budget above 1 now does something, which it
previously did not.

## What has to be modelled, and what may stay hardcoded

The user's rule: signal what a thing is FOR, so the bot works it out; hardcode only where
modelling would cost more than it returns.

**Already derived — do not regress these.** Unit counter-effectiveness (the damage matchup
table), what a structure is for (component presence), what an AOE-suicide unit is (its
projectile), whether a piece can build/repair/produce (its components). A new piece needs no
bot change today and that must stay true.

**Should be derived and is not:**

- **What makes a good scout: `BotScout._scout_score` (2026-09-04).** It picked
  the fastest free unit; it now scores speed, vision, replacement cost (energy + build time)
  and how many of the unit's OTHER jobs are currently live — one per manager that would
  otherwise claim it, counted only when that manager has work. That last term is what makes
  the Stock Truck the right opening scout without naming it: unarmed, cannot build, and its
  capture errand has no target until enemy infantry is in sight. The WEIGHTS are placeholders
  on the same footing as the difficulty ramp; the terms are settled. `tests/test_BotScout.gd`.
  Deliberately a COUNT rather than a value — pricing "this unit's other job" against "seeing
  the enemy base" is the currency question below, and a count needs no answer to it because
  every candidate is being asked the same single question.
- **Whether an ability is worth using now.** `BotSanction` is a policy (defend, else strike,
  else hold). The stated model is better: an economic ability is used as often as possible; an
  offensive one is worth saving for an impactful moment. That is a value-over-time question,
  not a policy.

**Accepted as hardcoded, for now:** the ERRANDS of each faction's dominion route. Colonial
capture-and-deposit and Anarchical Warlord-colocation are separate gatherers; keep them as
gatherers so the cost stays one function each. Which STRUCTURES a route is built from is no
longer hardcoded — see [bot-architecture](bot-architecture.md) §Dominion routes.

## The training harness

The user wants adversarial self-play to search the parameters. Two things have to exist
first, and both are worth having anyway:

1. **A seeded simulation.** Nothing can be measured while the sim diverges from the first
   shot — see the seeded-pseudo-randomness task, which is a prerequisite rather than a
   neighbour.
2. **Focused scenarios**, one per question, so a run measures one parameter. The user's own
   examples are exactly right: a duel scene for "unit set X against unit set Y", a map for
   "how many scouts". `tools/simulation/run_scenarios.gd` and `scenes/harnesses/` are the
   beginnings of this.

**The parameter-search discipline the user stated is the important part:** hold every other
behaviour's parameters equal while searching one. That is an argument for the flat
`BotDifficulty` data object above — a tier that differs by BRANCHES cannot be held equal.

> **TODO — a human-versus-bot harness is not planned.** The user is interested and doubts it
> is feasible ("infeasible to model the apparent decision-making of the human player").
> Agreed for now: recording matches is cheap and worth doing once replays exist, but
> attributing a loss to a parameter needs the counterfactual, which a human opponent cannot
> supply. Revisit only if replays make batch re-simulation cheap.

## The gaps in the decision surface

The surface itself is enumerated in [bot-architecture](bot-architecture.md) §The decision
surface. What follows is only the holes, in the order they are worth filling.

**1. Own-side grouping — the army is one undifferentiated set.** `BotMilitary` points every
combat unit at one position because there is no object in which "half the army" is a thing.
`Bot.enemy_clusters()` groups the ENEMY; nothing groups us.

> **PLANNED — the squad: an army object with merge and split, and a per-difficulty cap on
> how many the bot runs at once.** Approved 2026-10-03 and written up, with the mission
> tactics sharing the same object, in [squads-and-relations](squads-and-relations.md)
> §Squads. Attention — groups managed, decisions per think, reaction time — remains one
> family; what its units are is still [objective-selection](objective-selection.md)'s
> question.

> **TODO — NOBODY FINISHES A BEATEN OPPONENT OFF.** `_objective_for(ATTACK)` sends the whole
> army to one remembered position and re-tasks only when that position moves more than
> `OBJECTIVE_EPSILON`, so a side reduced to a handful of scattered survivors is never hunted
> down: measured, the winner sat in ATTACK posture with several units idle while the loser
> rode the clock (`gdd/systems/ai/bot-engagement-fixes.md`). Changing the elimination rule
> stopped that mis-scoring a match, and deliberately did not fix the behaviour — a bot that
> cannot close out a won game is still a bot that cannot close out a won game, and it is the
> same missing primitive as gap 1: with no way to split the army there is nothing to send
> after two survivors in opposite corners.

**2. Standing behaviour — the bot has no way to leave a unit somewhere.** `Defend`, `Patrol`
and rally points are all unissued, so idleness is only ever a fallback that the military's
sweep picks up. The user wants idleness to be *possible and sometimes correct* (a unit
holding a region), and wants it without command queues. Standing orders are exactly that
answer: one decision that keeps a unit busy indefinitely.

> **TODO — issue `Defend` for a held region, and set rally points on production
> structures.** Cheap, and it removes the two commonest causes of a unit doing something
> stupid because it went idle at a bad moment.

**The default for a unit with nothing to do is to SCOUT** — it is the one job that is always
available and always worth something, and `BotScout` already prices it. But that default is
subject to the same throttling as everything else: a bot permitted only a few managed groups
should be *allowed* to leave a unit standing, and an idle unit is not automatically a bug.
Deliberate idleness (a unit holding a region) and throttled idleness (a unit the bot has no
attention left for) look identical on screen, and both are wanted.

**3. Unit abilities are unreachable.** `Ability` is not an actuator verb and `Abilities` is
read only by `BotSanction`, so Dignify — the user's own example — cannot be used by a bot at
any difficulty.

**An ability is cast by a STRUCTURE**, which collapses the modelling: "should I cast this"
is not a separate question at all, it is "what should this structure do", with the ability as
one of the options available to that actor. A structure is then a commandable with an action
set like any other, and abilities stop needing a module of their own.

> **TODO — an `ability` verb on the actuator, and a usage hint on the ability doc.**
> `Sanction.targeting` / `min_targets` is the pattern to copy onto `kind: AbilityDefinition`; the
> user's model (economic → use as often as possible, offensive → worth saving for an
> impactful moment) is a field, not a module. What remains is folding it into the actor's
> action set rather than leaving it as a manager that runs last.
>
> **`BotSanction`'s actuator bypass is FIXED (2026-09-04)** — it issues `UseSanction` through
> `BotActuator.use_sanction` now, so a commander ability already travels the player's route
> and only unit abilities are unreachable. `tests/test_BotCommandCoverage.gd` is what keeps
> the two routes from parting again.

**4. Aerial operations are entirely outside the surface.** No bot module mentions aircraft,
docking, runways or charged ammunition. A bot that trains an aircraft flies it until the clip
is empty and then keeps flying it, because it can issue neither `Land` nor `Rearm`.

> **TODO — decide whether a bot may field aircraft at all before fixing this.** The cheap
> interim is honest: keep aircraft out of `BotProduction`'s candidate set so the bot does not
> buy what it cannot operate. The real fix is a docking/rearm manager, which is a whole
> subsystem — see [aerial-operations](../combat/aerial-operations/).

**5. Repair is not a decision the bot can make**, so a damaged structure stays damaged and
`Repairs`-carrying units never use the component they were given.

**5b. "What to make" and "where to make it" are one decision, and the bot only makes the
first.** `BotProduction` walks the idle production structures and trains each one's best
unit, so WHICH structure builds a wanted unit is decided by iteration order. The case that
shows it: the bot needs anti-infantry, one structure trains it, and that structure is about
to be destroyed — training there is the wrong call even though the unit is the right one.

> **TODO — pick the producer as part of picking the product.** Needs a per-structure
> survivability read (`Bot.most_threatened_structure` is the beginning of one) and a
> tie-break on queue depth, so a want is placed where it will actually arrive.

**5c. Reload time belongs in a unit's decisions, and is absent.** Three tiers, and only the
first is free:

- **Short reload** — no decision at all; the unit fights and reloads inside the fight.
- **Long recharge** — the unit is defenceless for a meaningful window, so it should
  REPOSITION while it is vulnerable rather than stand in the open waiting.
- **Must dock to recharge** — the sharpest case, and the useful reframing: **a unit that
  cannot rearm in the field is a unit WITHOUT AN ATTACK until it has docked.** It should stop
  reading as army strength, stop being retargeted, and be claimed by whatever sends it home.

For aircraft this composes with scouting: a spent aircraft may as well look at what it passes
over on the way, but **docking is the correct ultimate decision** and scouting must not defer
it. See [aerial-operations](../combat/aerial-operations/) and gap 4 above.

**5d. REJECTED 2026-09-17 — a spare Servant has nowhere to be, and now genuinely doesn't.**
This used to describe a real gap: the Compound admitted Servants by order and paid dominion
per occupant, so a spare builder parked there was a standing income option the bot could not
reach (`BotOpportunist._bunker_garrison_candidates` filters on `u.weapon_inventory.has_weapons()`,
excluding an unarmed Servant before the host was even considered). The Colonial dominion
refactor ([combat/colonial-dominion](../combat/colonial-dominion.md)) closed the Compound's
garrison for a different reason — a captive it holds is sentenced and consumed, never
converted into a Servant that could walk back out — so there is no longer a Servant-shaped
slot to fill at all. The value-over-time question this used to compete with `build_concurrency`
over (§What has to be modelled, for abilities) is unaffected; it simply lost this one consumer.

**6. Objective selection is a fixed rule, and there is no layer above it.** "Which enemy
thing do we go for" is `nearest_enemy_structure_to_base()`; "which site do we expand to" is
buried in the economy ladder.

**The important half is the layer that does not exist at all.** Buying and commanding are LOW
-level decisions that should sit under a statement of what the bot is trying to do — all-in,
booming, turtling — which is not another decision beside them but a disposition that tilts
all of them at once. Without it, individually reasonable choices cannot add up to a plan.
Written up as a proposal, with three candidate representations and a recommendation:
→ **[objective-selection.md](objective-selection.md)**

> **TODO — the low half is unblocked and could be built first.**
> `EnemyCluster.energy_value` prices a force and `Bot.unit_cost` prices a structure, so "what
> is worth attacking" is already a comparison the bot could make. Worth doing only if it does
> not prejudge the layer above it.

**7. Nothing tells the bot to stay out of an area.** Many effects punish whatever stands in a
region — a frost field, a radiation field, a gathering Blizzard — and the bot walks into all of
them, because nothing it reads says "keep clear".

> **TODO — an avoid-region signal.** The bot-side half is settled (2026-10-08): the lattice's
> `avoid` channel is a cost term in the distance fields the bot DECIDES on, and routing stays
> with the navmesh — [world-model/lattice-and-topology](world-model/lattice-and-topology.md)
> §Distance fields, where navmesh region costs are rejected. The pathing half is still open. A lingering area effect publishes a signal the bot reads
> as "stay clear of this region", and only effects that last longer than about 3 seconds
> publish one: steering around every brief blast would be excessive and twitchy. Undecided:
> what the signal is (a group the effect joins, a registry on the Map, a flag on the emission's
> phase), whether it carries a weight or is a plain keep-out, and how it reaches pathing,
> since today the bot routes only through the navmesh. Raised 2026-10-05.

## Tactics and the Bot

`ScenarioTactic` / `TacticRule` (see
[scenario-scripting/tactics](../scenario-scripting/tactics.md)) is a rule engine a scenario
author points at a group of units. The Bot is a commander deciding for itself. They overlap
in obvious ways and are deliberately separate.

**The boundary is settled (2026-10-03): share the action side, keep the decision side
separate.** A squad and its policies are one mechanism used by both; which policy a squad
runs is a `TacticRule` in a mission and a scored comparison in the Bot, and the two never
merge. See [squads-and-relations](squads-and-relations.md) §The boundary.

## What the referenced talk contributes

The comparison against ZeroSpace's framework is written up separately —
**[three-layer-comparison.md](three-layer-comparison.md)** — because it is research rather
than plan. The three gaps it found are below, in the order they are worth doing.

## The vision layer

**Clustering is missing from perception**, and the comparison argues it is the primitive
everything else should be reading: a handful of threat objects carrying strength, speed and
direction, instead of either one unit or the whole army. The consequence here is concrete —
`BotMilitary` commits everything to one objective position because one position is all its
inputs can express, and it cannot say "leave four home and take the rest" for want of a
representation in which "the rest" is a thing.

The pieces already exist: `ClusteringUtils.get_nodes_clustered` is a general implementation
that no bot code calls, and `BotSanction._densest_cluster` / `Bot._aoe_hit_value` are two
ad-hoc reimplementations of the idea in the two places that could not proceed without it.

Perception now answers TWO cluster questions, and keeping them apart
is the part worth remembering — **a group's centroid does not answer the coverage question**,
because a long chain of units is one group whose centre may sit within reach of none of them:

- **Grouping** — `Bot.enemy_clusters()` returns `EnemyCluster`s (members, centroid, summed
  strength, energy value, mean heading), strongest first. This is the primitive the military
  work needs: it is what makes "the smaller of two threats" or "leave half at home" sayable
  at all, where before there was nothing between one unit and the whole army.
- **Coverage** — `Bot.best_covered_point(candidates, radius, weight)` answers "where should a
  radius-R effect land". `BotSanction`'s aiming (weight = 1 per body) and `BotKamikaze`'s
  blast valuation (weight = damage × price) are now the same scan asked two questions, where
  they were two independent O(n²) reimplementations of it.

`Bot.entity_strength` came out of the same pass: `estimate_army_strength`,
`relative_threat_level` and a cluster's strength were three copies of "damage × remaining HP
fraction" and are now one, so they cannot drift.

> **TODO — clusters are of LIVE visible units, not of remembered ones.** Strategic planning
> wants the believed set (attacking a force you remember), which needs the grouping to work
> on positions rather than on nodes. Not built.

> **TODO — the grouping is O(n²) single-linkage on the think cadence.** Fine for the handful
> of visible enemies it runs over today; measure before pointing it at a larger set.

## Reading the game

**Nothing in this bot knows whether it is winning.** `relative_threat_level()` computes an
instantaneous strength ratio and no module reads it; the blackboard records what exists and
where, never what CHANGED. Both of the talk's headline behaviours are consumers of that one
missing signal:

- **Retreat**, which the talk singles out as the thing that reads as human. We retreat in one
  narrow case — `BotBrain._tick_preservation`, below 25% HP and unable to damage anything in
  range, i.e. a HOPELESS MATCHUP rather than a losing fight. There is no army-level retreat at
  all: `BotMilitary`'s wave runs until spent to 35% of its launch value whatever is happening
  to it. That is precisely the hard-commit the talk opens by criticising. The wave rule is
  there for a real reason (it fixed a bot that dribbled its army in), so the remedy is a wave
  that retreats TOGETHER, not one that cannot retreat.
- **Reacting to a counter** — noticing that the enemy's composition moved against ours, which
  needs the blackboard to carry history rather than only a present snapshot.

**`BotMomentum` (2026-09-04)** — the army-value trend, sampled on the think cadence
and read as a loss rate (fraction of the army bled per second) over an 8-second window.
Chosen over a fuller position score (army + income + territory) because it is ONE sampled
value, it unblocked the retreat in the same change, and the richer version grows out of it by
adding terms rather than by replacing it. It is blind to the enemy's losses on purpose — belief
ratchets UP as an attack reveals more of the enemy, so a trend over believed enemy value reads a
successful push as a disaster — and it is the read for the questions that are about the BOT:
the economy's expansion risk and the posture layer's risk dial.

**Army-level retreat (2026-09-04; the front read 2026-10-31).** `BotMilitary` calls a wave off
when the wave has lost 30% of everything committed to it **and** it is losing its front —
`BotMomentum.front_balance`, the wave's share of the answerable strength reaching its leading
edge, from `BotFields`' strength fields, with its trend. Both halves are load-bearing,
and the second one is the whole design: heavy losses ALONE are not a reason to leave — a wave
that spends a third of itself to destroy the enemy's army has won — and a bot that pulls back on
damage is the dribbling bot the wave rule was written to stop. The second half was the global
army trend until 2026-10-31, and that was the wrong question for a wave: home units diluted a
loss at the front and production masked it, so a wave meeting a superior force retreated late or
never, and a raid at home called off a wave that was winning. Reading the front also lets the
enemy's losses count, where the global trend could not: a believed enemy that dies in sight
leaves the belief and the field. The per-engagement outcome once held in reserve for that is
superseded by it. Rule and reasoning: [bot-architecture](bot-architecture.md) §The retreat
reads the front. A called-off wave regroups at home for 20 seconds, which the army-size posture
branch honours; without that window the retreat was re-ordered as an attack the same think it
was decided.

> **TODO — a HISTORY of the opponent is still missing.** The blackboard records what exists
> and where, never what changed, so the bot cannot notice that the enemy's composition moved
> against its own. That is the other consumer named above and it is not built.

## What the talk changes about the ability plan

`Sanction.targeting` / `effect_radius` / `min_targets` turn out to be exactly the talk's
per-ability "drop-down of how the AI is supposed to use this", authored on the ability's own
data. That is the shape to extend rather than replace — but it exists only for SANCTIONS, and
the bot never uses a unit's own ability at all (`Abilities` appears in `BotSanction` and
nowhere else in any bot module). The user's stated model — economic abilities used as often as
possible, offensive ones saved for an impactful moment — is a field on a `kind: AbilityDefinition` doc,
not a new bot module. Recorded under §What has to be modelled above.

## Waves versus a steady stream

The talk reports a playtest result that contradicted its own expectation: collecting units
into waves gave players breathing room they converted into an advantage, while a semi-steady
stream from several directions was harder to hold and more fun at high level. **We are a wave
bot** at two levels (`events.json` spawn waves; `BotMilitary`'s mass-then-commit). That is a
claim about his game's balance rather than a law, so it is not a defect — but it is a cheap
experiment once the harness exists, and it is one parameter.
