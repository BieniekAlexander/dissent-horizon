---
title: Decision simulations
type: system-note
---

# Decision simulations

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**The grammar below is BUILT (2026-10-07)** — the settings keys, the bot-state checks,
`command`'s `target:`/`near:`, `needs:`, `sims/bot/` discovery and the three-count summary —
and `sims/bot/targeting/crush_a_counter` and `sims/bot/errand/two_prey_one_truck` pass. The
rest of this note — the organisation and the first situations — is a proposal still: a suite of simulations that set up a
game situation and assert what the bot DECIDES, organised so the state space is covered on
purpose rather than by accident. It extends the existing sim harness
([simulation-tests](../scenario-scripting/simulation-tests.md)) rather than adding a third
one; every lever it needs exists in the engine and is missing only from the spec grammar.
The decisions it tests are the [world-model](world-model/README.md)'s reads and the actuation they
drive; the brief is [brief.md](brief.md) §Training.

## What the harness has, and what it lacks

The YAML sim (`sims/<id>.sim.yaml`, run by `tools/simulation/run_sims.tscn`) places groups
of pieces per slot on a flat arena, scripts five orders (`attack`, `attack_move`, `move`,
`defend`, `stop`, with `after:` batches), runs a seeded window at fixed fps, and asserts on
PIECE state: `alive`, `dead`, `hp_fraction`, `owner`, `distance_to`, `command`, `idle`,
`garrisoned_in`, `hit_rate`, each at end, `by:` a time, or `when: always`. Every shipped sim
is a unit-versus-unit duel with both slots inert (PASSIVE). Four things a decision sim needs
are absent from the grammar and present in the engine:

| need | in the engine | in the grammar |
|---|---|---|
| a bot that sees everything | `Entity.is_visible_to` is true for a commander with no `Fog`; `Scenario._create_bot_fogs` always makes one | nothing |
| a bot's parameters | `PlayerSlot.config_overrides` → `BotDifficulty.apply_overrides`, validated at boot | `settings.difficulty` only; `personality_spread` and `decision_temperature` are non-zero on every thinking tier, so a sim bot draws a random personality it cannot be told not to |
| what the bot may consider | — (the candidate sets come from owned builders' tools and tech) | nothing |
| what the bot decided | `BotUsageLog` (`choices` per domain, `actions` issued/refused), `BotClaims`, `BotMilitary.current_posture()`, the blackboard | nothing; only the editor-authored `run_scenarios` route can reach bot state, through a `Condition` |

So the work is grammar: four keys and one family of checks, below. The self-play harness
(`tools/selfplay/`) is a different tool — a whole match, two real bots, an outcome and a
winner, no pass/fail — and stays that way; it answers "who wins", these answer "what did it
do".

## Grammar extensions

### `settings` for a thinking slot

```yaml
given:
  A:
    settings:
      difficulty: HARD
      vision: full            # no Fog for this commander: the bot sees the whole arena
      energy: 1200            # starting energy (today forced to 0)
      dominion: 0
      config:                 # BotDifficulty overrides, validated as PlayerSlot's are
        build_concurrency: 1
      consider:               # the bot may build / train ONLY these (a sim-only lever)
        structures: [cl_defense_antiLight, cl_barracks]
        units: [cl_mechMedium_antiMech]
```

- **`vision: full`** is the harness convenience the brief asks for: the sim is about a
  decision, not about scouting, so the bot is handed the truth. The perception layer is the
  same code with no fog; nothing is bypassed — and a commander with no fog SEES EVERYTHING
  (`Commander.visible_enemies`), not merely what lies in its own pieces' vision ranges, which
  until 2026-10-07 quietly re-imposed a fog the slot was given none of. A sim about belief
  (a remembered base, a disproved unit) leaves vision at its default and places vision
  sources.
- **`config`** is the existing override route. **A thinking sim slot zeroes
  `personality_spread` and `decision_temperature` unless the spec sets them**, so a decision
  sim is the argmax and reproducible; a spec that wants the sampled behaviour says so.
- **`consider`** is the constraint the brief describes — "constrain parameters for other
  behaviours so that they're equal" — applied to the CHOICE SET rather than the weights: a
  macro sim that asks "extractor or tower" lists exactly those two, so no third option
  decides the test. It is a filter on `Bot.buildable_structure_types` and the producible
  set, honoured by every rung and the opportunist, and it exists for sims only — a bot in
  play never carries one, and the spec importer need not know of it.
- An inert slot stays PASSIVE (the default) and carries scripted orders as today; it is the
  "only one of the players uses a bot" convenience, already built.

### Bot-state checks

One family, read from the bot's own records; each takes `slot:` and the usual temporal mode.

| check | arguments | true when |
|---|---|---|
| `posture` | `is: ATTACK / MASS / DEFEND` | `BotMilitary.current_posture()` |
| `objective` | `near: <group or place>`, `within: N` | the military's attack objective lies within N of that group's centroid, or of a place |
| `placed` | `piece:`, `near: <group or place>`, `within: N` | a build order for that piece was issued to stand within N of the group or place — where a turret went (2026-10-08) |

A `near:` is a group reference, or a PLACE beside one in the form `at:` takes — `{ from: A.base,
distance: 7, bearing: north }`, read live off the `from` group's centroid (2026-10-09). A place
is for a check against a point nothing stands on: a mark on an approach. A group that moves
is the wrong mark — the raiders of `turret_covers_the_band` walked to the turret and made the
check read when it went down rather than where.
| `ordered` | `kind: build / train / attack / move_at / …`, `piece:`, `of:` (optional), `at_least: N` | `BotUsageLog.actions` records that many ISSUED orders of that kind for that piece — and `of:` narrows to orders whose target is in that group |
| `refused` | same, plus `cause:` | the actuator refused it, with that precondition cause |
| `chosen` | `domain: train / production_structure / defence_structure / …`, `piece:` | `BotUsageLog.choices` records it as chosen in that domain |
| `considered` | same | it was scored at all — the "not aware" versus "judged not worth it" split of the piece-usage audit |
| `claimed` | `of: <group>`, `by: scout / combat / errand` | every member is held by that owner |
| `believes` | `of: <group>`, `at_least / exactly` | the blackboard believes that many of the group |

`move_at` is recorded as its own action kind and `BotMilitary.current_objective()` is the
objective's readable value (both 2026-10-07). The authoritative table is
[simulation-tests](../scenario-scripting/simulation-tests.md) §The check vocabulary.

### Decision or outcome?

Both are allowed, and a sim is strongest with one of each: the DECISION check says the bot
chose rightly, the OUTCOME check says choosing rightly mattered. A decision check settles in
one think and does not depend on balance; an outcome check depends on both and is the one a
retune can move. The piece-usage audit's rule applies — a sim whose outcome check goes red
after a stat change is content drift, not a regression, and the decision check is what says
which.

## Organising the state space

**One directory per decision domain, one spec per SITUATION, and every situation a
CONTROLLED PAIR.** The pair is the unit of coverage: the same `given` with one thing changed,
and the assertion is about the difference. A sim that asserts an absolute ("the army attacks
the exposed structure") is a special case of a pair whose control is implicit, and the file
says what the control is.

```
sims/bot/
  targeting/     who a unit fights — crush, matchup, threat, finishability
  retreat/       preservation — when a unit leaves a fight, and where to
  objective/     where the army goes — exposure, defended fronts, value, commitment
  macro/         what to build — income vs defence vs capacity, the demand reads
  production/    what to train — counters to the believed composition
  commitment/    whether and when the army attacks — the value ratio, the stalemate clock, the gates
  errand/        capture, deposit, liberation, garrison
  placement/     where a building goes — coverage, exposure, corridor
  scouting/      where to look — information value, focus
  posture/       how the dials tilt the decisions above — a lead commits sooner, a poorer side holds
```

The domains are the world-model's reads, not the managers': `retreat/` and `targeting/`
both run through `BotTargeting` and preservation, and that is fine — a situation is filed by
the DECISION it tests.

**Each domain has an axis list**, and a situation names which axis it varies: distance,
exposure (threat at the place), value (what is there), effectiveness (the matchup), reach
(can it be hurt at all), commitment (how much of the army). A domain's coverage is the
axes × the pairs that exist; the gaps are visible by construction.

**A situation says what it needs.** A sim written against the model's L2 reads before they
exist is a SPECIFICATION: it is allowed to be red, it names the migration step that turns
it green (`needs: fields`), and the runner reports it under a separate heading. The suite
is then the acceptance test of the migration, and a step is done when its sims pass.

## The first situations

Written from the sample tests of 2026-10-07. Each is a sketch of its spec — the ids are the
Colonial roster's — with its control, its checks, and what it needs.

### objective/ — two armies, one near our structures

```yaml
description: Two identical enemy armies; one stands beside our extractor. Ours attacks THAT one.
given:
  A:
    settings: { difficulty: HARD, vision: full }
    with:
      base:    { of: [{ piece: cl_commandCenter, count: 1 }], at: west }
      mine:    { of: [{ piece: cl_infrastructure, count: 1 }], at: { from: A.base, distance: 20, bearing: north } }
      army:    { of: [{ piece: cl_bioLight_antiMech, count: 4 }], at: { from: A.base, distance: 6, bearing: east } }
  B:
    with:
      near:    { of: [{ piece: cl_bioLight_antiLight, count: 4 }], at: { from: A.mine, distance: 8, bearing: east } }
      far:     { of: [{ piece: cl_bioLight_antiLight, count: 4 }], at: east }
run: { for: 30s, seed: 1 }
expect:
  - { slot: A, check: objective, near: B.near, within: 10, by: 5s }     # decision
  - { of: B.near, check: dead, by: 30s }                                 # outcome
```
Control: the two armies are identical; the axis is **value** (what each threatens).
Needs: the `own exposure` read (world-model §L3) — today the objective is the nearest
believed structure, so this is a specification.

### objective/ — two structures, one under a tower

Two identical enemy structures; one has `cl_defense_antiLight` beside it. `objective near:
B.exposed`. Control: identical structures; axis **exposure**. Needs: the `threat` field.

### retreat/ — a tank among its counters

Three specs sharing one `given` — `A.tank` (`cl_mechMedium_antiLight`) beside five
`cl_bioLight_antiMech` — and varying the **map**:
- *open ground*: `ordered: {kind: move, of: A.tank}` by 3s and `A.tank alive` at end — it
  leaves;
- *friends to the north*: a second group `A.friends` 20 units north; the move's destination
  is within 10 of `A.friends` (`ordered … near: A.friends`) — it leaves TOWARD them;
- *cornered*: the arena edge and a `B.wall` of structures close every exit; `ordered: {kind:
  attack, of: A.tank}` and no move — it fights.
Control: the same enemies; axis **reach** (where it could go). Needs: a `threat`-aware
retreat destination; today preservation retreats to the nearest own structure, so *open
ground* passes by accident and the other two are specifications.

### targeting/ — a counter it can crush

`sims/bot/targeting/crush_a_counter` — PASSING. A Sloop (`cl_mechMedium_antiLight`, given
the Matilda's `crush_class: MEDIUM` on 2026-10-07) beside one `cl_bioLight_antiMech` — and
the Sloop carries a hold, so its run-over CAPTURES the trooper (`garrisoned_in` at tick 84)
rather than killing it; the outcome check accepts either, since a captive keeps its own side
and `owner` does not change; `command
is: MoveCommand target: B.trooper` by 3s, and `B.trooper dead`. Control: one enemy; axis
**effectiveness**. Writing it found that the attack-move's own aggro had already put the tank
on an Attack at the trooper, so `BotTargeting` now converts a crushable CURRENT target to the
run-over too; the trooper dies at tick 83 where shooting took until 254.

### macro/ — a builder, an extractor and an enemy in sight

```yaml
given:
  A:
    settings:
      difficulty: HARD
      vision: full
      energy: 1500
      consider: { structures: [cl_infrastructure, cl_defense_antiLight, cl_barracks] }
    with:
      mine:    { of: [{ piece: cl_infrastructure, count: 1 }], at: west }
      builder: { of: [{ piece: cl_bioLight_builder, count: 1 }], at: { from: A.mine, distance: 3, bearing: east } }
  B:
    with:
      raiders: { of: [{ piece: cl_bioLight_antiLight, count: 3 }], at: { from: A.mine, distance: 30, bearing: east } }
expect:
  - { slot: A, check: ordered, kind: build, piece: cl_infrastructure, at_least: 1, when: never }
  - any:
      - { slot: A, check: ordered, kind: build, piece: cl_defense_antiLight, by: 10s }
      - { slot: A, check: ordered, kind: build, piece: cl_barracks, by: 10s }
```
(`when: never` is the safety form of `when: always` on a negated leaf — spelled as `not`
around an `at_least` today.) Control: the choice set is three types; axis **exposure**
(an enemy with lethality, and we have none). Needs: the static-defence demand read and a
site-threat read for the income rung (world-model §L3) — a specification. Its pair, with
`B` empty, asserts the opposite: the extractor is ordered and no tower is.

### production/ — the counter to a believed composition

`A` owns `cl_warFactory` and five `cl_bioLight_antiLight`; `B` fields one
`cl_mechMedium_antiLight`; `consider.units: [cl_bioLight_antiLight, cl_mechMedium_antiMech]`.
`chosen: {domain: train, piece: cl_mechMedium_antiMech}` by 5s. Control: two options; axis
**effectiveness**. Needs: nothing — `unit_composition_value` already reads the demand map;
this one measures whether the weights say so.

### errand/ — two prey, one truck

`sims/bot/errand/two_prey_one_truck` — PASSING. `A.truck` (`cl_mechLight_dominionGen`, a
Compound in range) and two enemy soldiers ten and eighteen units off (a spec cannot place
neutral pieces, and an enemy soldier is capturable too). `ordered: {kind: move_at, at_least:
2}` by 25s and the truck alive; the "no deposit before the second" half waits on the order
journal (§Identity in a check). Control: one truck, two prey; axis **value** (load before banking).
Needs: nothing — built 2026-10-07 (`deposit_value`); its pair places the prey 40 units apart
and expects the deposit first.

### commitment/ — even armies and no income

`sims/bot/commitment/` — PASSING, all three, over six seeds (2026-10-07). Two HARD bots, full
vision, scouting off, each with six Recruits beside an unarmed Annex and nothing to earn with.
- *even_armies_no_income*: neither commits on value (1.0 against 1.3); the stalemate clock
  commits both at about 15.6 s, they fight, and the fight resolves: a side is wiped out or
  what is left on both sides is under the commit gate.
- *below_the_gate_never_attacks*: two Recruits a side, 200 energy against the 300 gate; nobody
  attacks in 90 s. Two bots that trade down below the gate stay home for good.
- *behind_side_waits*: 8 against 6. The larger side does NOT commit at once — see the third
  finding — but after about 7 s; the smaller one (0.75, under the 0.85 floor) never commits.

Control: one army size changed per pair; axis **commitment**. Writing them found:

1. **An army with no structure creeps forward.** With no base, `BotMilitary._home_anchor` is
   the army's own centroid, and the massing point is that plus `STAGING_OFFSET` toward the
   threat, so every re-anchor walks the army 10 units closer: two base-less armies meet with
   neither attacking. Hence each side's Annex. TODO: whether a base-less army should anchor
   where it stands (Alex's call; only reachable in sims and in a match after every structure
   is lost).
2. **Scouting splits a small army.** A HARD bot sends three of six units scouting, which drops
   the army to the body-count gate and turns the match into scout skirmishes. Off here, since
   full vision makes a scout worthless.
3. **The humility prior caps every bot's ratio at 1 / `assumed_enemy_parity`** (1.18 at 0.85),
   seen enemy or not, so an `attack_value_ratio` above that never fires on value and every
   attack waits on the stalemate clock — see [bot-parameter-space](bot-parameter-space.md)
   §Where holding-others-equal is a lie, item 3.

### fields/ — where the army stands, where a turret goes, who guards

Built 2026-10-08 with the spatial model
([world-model/lattice-and-topology](world-model/lattice-and-topology.md)), under
`sims/bot/fields/`. Each puts the believed enemy STRUCTURE east — the threat axis the bearing
rules read — and the believed enemy ARMY north and nearer, so the approach band runs north
and a decision that reads the band parts from one that reads the bearing:

- **`stage_on_the_approach`** — a massing army's objective lands beside a marker on the north
  approach (`objective near: A.marker`), not out east. Green.
- **`turret_covers_the_band`** — with `place_coverage_weight` set high enough to outweigh the
  frontage bearing, the turret is ordered onto the north approach (`placed`, the check added
  for it). Green; its control with the weight at 0 places by bearing and goes red, which is
  what makes it a test of the term rather than of the default weight.
- **`guard_arrives_in_time`** — a near unit answers a raid on an outlying building and a far
  one, whose walk is longer than the building's time to kill, does not. `needs:` a way to
  start a slot with a wave out and a staged reserve: without one the posture is DEFEND and
  the whole army answers, so it reads specification-red until that setting exists.
- **`builds_where_it_can_hold`** (2026-10-09, T-101) — two enemy rocket batteries north and
  nothing of the bot's own to answer them; with the bearings at 0 the `safety` field alone
  tilts the barracks to the south side of the citadel (`placed` within six of a mark six cells
  south). Its control with `place_safety_weight` at 0 breaks the ring along the threat axis
  instead and reads red (run 2026-10-09). Two devices the spec needs: the bot EARNS its way to
  the barracks from a far-off extractor (energy 250, reserve 0), so its one order (cap 1)
  comes after the batteries are believed — nothing is believed on a bot's first think, and a
  barracks bought at tick 3 is placed blind; and the prerequisite and the extractor stand
  thirty cells south as a base of their own, so the citadel is the anchor and the only
  neighbour (a prerequisite beside the citadel moved the anchor to their mean).
- **`spacing_keeps_structures_apart`** (2026-10-09, T-101) — the same setup without the
  batteries; at the top of `place_spacing_weight`'s range the one barracks is never ordered
  within eight cells of the citadel's centre (`not` around a `placed`); at 0 it lands against
  the eight-by-eight footprint's wall, within seven, and the negation reads red (run
  2026-10-09). A first draft asked "within six" and read green at every weight, because six
  from the centre of an eight-wide footprint is inside it: a `placed` bound has to be measured
  from the footprint, not the centre.
- TODO: the site valuation (lattice-and-topology.md §Safety, sites and placement, item 2) has
  no sim because the harness has no NEUTRAL slot: an extraction site or a pond cannot be
  authored into a spec, so "the bot takes the safe site over the richer exposed one" is a
  unit test (`tests/test_BotSiteValuation.gd`) until one exists. The macro/ specification
  above wants the same slot.

## What the runner adds

- A `needs:` key per spec, and a summary that separates passing, failing, and
  specification-red (`needs:` named and not yet built) — three counts, not two.
- `bot/` runs in the same invocation as the duels; a spec under `sims/bot/` with no thinking
  slot is a validation error, since a decision sim with nobody deciding tests nothing.
- The self-play harness keeps its JSON; nothing here is a match.

## Harness findings (2026-10-07, unfixed)

Found while reading the harness for this note; each is a bug in the existing sim tooling
rather than this proposal's:

1. **`facing:` is dead.** Parsed and validated (`sim_spec.gd`), documented as a group key,
   never applied by `SimArena`.
2. **The documented `Condition` escape hatch is not implemented.** simulation-tests.md
   §Checks describes `{ condition: ConditionScoutCoverage, … }`; a leaf must name a `check:`.
3. **Three specs carry a copy-pasted description** (`apc_vs_badger`, `apc_vs_tank`,
   `badger_vs_tank` all describe `antimech_vs_truck`).
4. **`settings.faction` is accepted and undocumented**; `CLAUDE.md` still says the spec
   grammar is "planned, not built".
5. **`run_sims` exits 0 on a failing check** (1 only on a parse or build error), unlike
   `run_scenarios`. Deliberate, per simulation-tests.md §Running one — a false design claim
   is a finding, not a gate. Whether a FAILING decision spec (no `needs:`, expected to pass)
   should be different is an open question below; a WAITING spec never is.

## Identity in a check

`BotUsageLog.actions` is a ledger by TYPE — `kind → piece type → issued / refused` — so it
answers "was a tower ever ordered" and never "which unit was ordered at what". Three of the
first situations need the latter (the tank at THAT trooper, the retreat TOWARD friends, the
objective NEAR a group). Decided 2026-10-07, two routes and when each applies:

- **The live command, now.** The existing `command` check grows `target: <group>` (true when
  the member's current order names a piece of that group) and `near: <group>, within: N`
  (its destination lies within N of the group's centroid). It reads the present order; an
  order issued and finished between two polls is invisible, which no real order is, since
  polling is per tick and an order lasts many. The objective check reads
  `BotMilitary.current_objective()` directly and needs neither.
- **An order journal, when the first SEQUENCE check is written.** One record per issue —
  `{tick, kind, actor id, piece type, target id or position, outcome}` — appended by the
  actuator beside the type ledger, under a sim-only recording flag (off in play and in
  self-play, where the type ledger is what the audit reads). It answers "did it ever" with
  identity and "which came first"; the errand situation's "no deposit before the second
  capture" is its trigger, and it arrives with that sim.

`consider` is a sim-only lever (decided 2026-10-07); it is not a difficulty parameter and
never reaches a bot in play.

## Open decisions

> **TODO — should a failing decision spec fail the exit code?** The duel suite deliberately
> exits 0 on a false claim (simulation-tests.md §Running one): a balance finding is not a
> gate. A decision spec with no `needs:` is a claim about the BOT'S SOFTWARE rather than about
> balance, which argues for the exit code; the summary's three counts are the alternative.
> Leaning: keep the exit code as it is and read the counts, until a decision spec regresses
> in a way the counts were not noticed to show.
