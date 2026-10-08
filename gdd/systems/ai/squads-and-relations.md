---
title: Squads and relations
type: system-note
---

# Squads and relations

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**Approved 2026-10-03.** Steps 1 and 2 of §Build order are built (2026-10-03 and
2026-10-07); everything marked `PLANNED` is agreed and waits for the build. This note supersedes
[bot-roadmap](bot-roadmap.md) §The gaps in the decision surface items 1 and 2 and §Tactics
and the Bot, and [tactics](../scenario-scripting/tactics.md)' "merging or splitting is out of
scope".

## What started it: the army arrives one unit at a time

`BotMilitary.tick()` re-tasks the army as a body only when the posture or the objective
changes; every other combat period it sweeps `get_idle_units()` and attack-moves each one to
the standing objective. A freshly trained unit is idle the moment it appears, because the bot
set no rally point, so every reinforcement walked to the front alone. Ten units arriving one
at a time lose to ten arriving together, and it reads as a bot rather than a player.

Two things compounded it, and both are rules now:

- **ATTACK posture and an attack WAVE are the same thing.** The posture had two commit gates
  in PARALLEL: the value ratio launched a wave, and failing that a plain body count still
  returned ATTACK — without `_wave_active`, so the retreat rule, the spent fraction and the
  regroup window never applied to a count-triggered attack, and the humility prior was
  decorative whenever the count was met. The gates are now in SERIES: a wave launches when
  the army is big enough in bodies AND ahead enough in value, and ATTACK is only ever a live
  wave. `assumed_enemy_parity = 0` reproduces the old count-only aggression for an A/B.
- **Reinforcements are STAGED and released together.** In ATTACK posture an idle unit that is
  not in the wave goes to the staging point — the threat side of the base — rather than to
  the objective, and the staged reserve is released as a body once its value reaches
  `reinforce_fraction` of the wave's launch value, or the wave has nobody left. The bot's
  production structures rally to the same point, so a new unit walks there on its own.
  `reinforce_fraction = 0` is the old trickle, for the A/B.

Built 2026-10-03 in `BotMilitary`; the wave and the reserve are the first two squads.
Cover: `tests/test_BotStaging.gd`.

### Measured

The harness samples `wave_units` and `reserve_units` per slot (`run_match.gd`), so staging
is read directly rather than inferred from who won. One MEDIUM match on `skirmish.tscn`,
seed 11, staged against `reinforce_fraction: 0`, sampled every 2 s for 420 s:

| | staged | trickle |
|---|---|---|
| reserve released as a body (reserve ≥ 2 → 0 while the wave grew) | 3 times, of 2–4 units | never |
| largest reserve held while attacking | 5 | 1 |

The releases are small because a MEDIUM wave launches at a few units' value and the
reserve bar is half of that; `reinforce_fraction` is the dial.

**Wins do not measure it on this map.** Seven matches (three seeds, both assignments, plus
a staged mirror, 900 s cap): slot 0's position won or led every one, whichever side staged,
which is the start-position advantage [bot-architecture](bot-architecture.md) §Where a
building goes already documents. The one hint is that the staged attacker closed out two of
its three matches from the strong position and the trickling attacker none of its three — it
beat the staged side to zero units twice and then never razed the last two structures,
which is the finishing-off gap ([bot-roadmap](bot-roadmap.md) §The gaps, item 1). A
win-rate verdict needs a map without the position bias, or many more seeds.

## The boundary between the Bot and mission scripting (settled)

`ScenarioTactic` is "a node-group of units, an ordered rule list, re-issue the rule to idle
members". `BotMilitary` is "the unclaimed set, a posture FSM, re-issue the objective to idle
members". The DISPATCH half is one loop; only who chooses the rule differs — authored
`Condition`s in a mission, scored comparisons in the Bot.

**The rule: share the action side, keep the decision side separate.** A squad and its
policies are one mechanism used by both; which policy a squad runs is a mission author's
`TacticRule` or the Bot's comparison, and the two never merge. The roadmap's worry — that
unifying waits on bot decisions becoming scored — does not apply, because nothing scored is
shared.

## Squads

Built 2026-10-07. **A `Squad` is a set of units and the standing policy they are kept to,
and its `tick()` is the one dispatch loop**: a new policy is issued to every member, the
same policy only to a member that went idle or joined since, and a member busy with its
order is left alone. `Commander.squads` is the registry, so a side's army reads as squads
whoever runs them: `BotMilitary` keeps three (`main`, `reserve`, `guard`), and
`ScenarioTactic` syncs its node-group cluster into one and makes the winning `TacticRule`
its policy (`TacticRulePolicy`). The tactic's "rule changing redirects everyone; the same
rule re-runs for the idle" is now `Squad.tick`, written once. Cover: `tests/test_Squad.gd`,
`tests/test_BotStaging.gd`, `tests/test_ScenarioTactic.gd`.

Policies are the shared vocabulary; the first three are built:

| Policy | What it keeps the squad doing | Who wants it |
|---|---|---|
| `StagePolicy(point)` | gather and wait to be handed on; the release rule is the decision side's (`reinforce_fraction`) | the reinforcement reserve; a mission's "wait for the wave" |
| `AssaultPolicy(point, believed target)` | attack-move on the objective; an arrived member razes the believed structure while the belief stands | the wave; a mission's "attack this region / kind of target" |
| `HoldPolicy(point)` | stand at a post; deliberate idleness | the army at home; the guard; a mission's garrison |
| `Patrol(route)` | `PLANNED` — the standing order the bot cannot give today | a mission's patrol; the Bot's map control |
| `Escort(provider role, consumer role, reach)` | `PLANNED` — keep a provider within reach of a consumer — see §Relations | transport, spotting, retinue, the Sapper's carrier |

**Hold leaves an arrived member idle on purpose, and does not use `Defend` posts yet.** A
`Defend` order is itself the standing order — it never goes idle — so a held unit would be
invisible to the bunker opportunity (§Cover) and to the idle sweep. TODO: move the cover
rule onto the policy, then Hold can post a leashed `Defend`.

**How many squads a bot may run at once is a difficulty parameter**, `squad_cap`: 1 is one
body — every reinforcement walks to the front alone, the trickle, whatever
`reinforce_fraction` says; 2 is wave and reserve; 3 adds the guard. PASSIVE and EASY run
one, MEDIUM two, HARD three, IMPOSSIBLE is uncapped. A bot that manoeuvres a hundred units
independently is optimal and unbelievable; a player plays through a handful of control
groups. A cap is a handicap that reads as human, bounds the think cost by construction, and
is a number a search can move.

**The guard** (decided 2026-10-07): while a wave is out and the base comes under threat, the
staged reserve answers it (`HoldPolicy` on the most valuable threat) instead of waiting to
reinforce, and goes back to being the reserve when the threat passes. A committed wave used
to override DEFEND outright, so a raid during an attack went unanswered; now the part of the
army that is NOT committed answers it. A fraction held home by rule is deliberately not a
parameter — the reserve is whatever the release rule has not yet sent, and the guard is the
reserve with somewhere to be. Merge and split beyond these three (a raid squad, a second
wave) are `PLANNED` with the relations that give them a reason.

**The guard is sized to the threat, and only an armed piece is one** (Alex, same day). A
threat is a visible enemy that can damage the structure it stands beside, valued at its cost
× that matchup (`Bot.base_threats`); a builder, a parked recon drone or an enemy extractor
next to ours is none. The guard is drawn from guard and reserve together, best answer first,
until its own cost × matchup against the threats reaches `guard_strength_ratio` × their
value — a searched parameter, because "as big as the raid, or twice it" is a question for
the search — and the rest stays the reserve and goes on to the wave. It supersedes "the whole
reserve guards", which under a threat nobody could end (that parked drone, held over a
forward extractor for the rest of the match) put every unit built from then on in the guard:
measured 2026-10-07, 110 units held home behind a wave of two, posture ATTACK throughout.

**The wave is valued by itself, and re-pointed when its objective moves on.** Whether a wave
is spent, or bleeding badly enough to call off, reads the main squad's value against what it
launched with — never the army's, which counted a growing guard as the wave holding up.
And the wave is compared with the point it HOLDS: a new believed structure, or a drift past
`OBJECTIVE_EPSILON` from that point, re-points it (the reserve and guard keep their orders).
The objective is re-read every think, so a creep of a few metres a think, or the next
building a short step on, used to change nothing — 164 units stood idle at a point whose
target had fallen.

**Missions switch Bot jobs off per slot rather than switching the Bot off.** `BotBrain.active`
is all-or-nothing today. A per-job enable on `PlayerSlot` lets a mission run the economy and
production but author the military as squads, or spawn its waves by event and let the Bot
assault with them. Preordained groups versus dynamic countering is then which side owns
`BotProduction`, not a second bot.

## Relations

`PLANNED`. **A relation is one piece granting something to another within a reach.** Every
inter-piece dependency the game has or plans is one of these, and the Bot reads them off
the pieces rather than knowing any by name — the same rule as `AnarchicalDominion` asking
what a piece GRANTS rather than naming the Warlord:

| Provider | Consumer | Reach | Effect |
|---|---|---|---|
| a `BeaconRange` carrier, a `Spotter`'s beacon | a Bombard | `RADIUS` / `POINT` | ENABLES an action: a shot needs spotted ground |
| a MECH carrier | a Sapper | `CONTAINED` (rides on) | ENABLES: the charge needs a vehicle to reach the enemy |
| a transport's `Garrison` | its admitted passengers | `CONTAINED` | MOVES: mobility the passenger lacks |
| a Warlord's `DominionRegion` | friendly infantry | `RADIUS` | SCALES output: dominion per follower |
| a stealth-field structure (planned) | pieces inside the field | `RADIUS` | PROTECTS |
| a Compound | edge-adjacent friendly structures | `ADJACENT` | SCALES output: cooldown reduction per sentence |
| a bunker `Garrison` | admitted armed units | `CONTAINED` | PROTECTS and extends reach |

```
Relation
  provider   predicate over pieces: a passive ability id, a component, a doc key
  consumer   predicate over pieces
  reach      RADIUS(r) | POINT | ADJACENT | CONTAINED | ANY
  effect     ENABLES | SCALES | PROTECTS | MOVES
  value      energy-equivalent, per second or per event — the currency every bot
             comparison already uses (bot-roadmap §The currency)
```

**Where a relation comes from.** From the piece: `BeaconRange`, `Spotter`, `Garrison` masks,
a passive ability's region shape, the Compound's adjacency rule all exist in code already,
so `Bot.relations()` is a read over the build previews, like `unit_type_can_build`. A new
faction's stealth structure needs a doc, not a bot change. Where the game cannot yet express
a relation in code, it is a doc key on the piece rather than a bot constant.

**Three consumers of a relation, and that is the generalisation asked for:**

1. **Squads** — `Escort` is one policy for every reach kind: the truck keeps the Servant
   inside (`CONTAINED`), the spotter keeps a beacon where the battery wants to fire
   (`POINT`), the Warlord keeps its infantry in reach (`RADIUS`). A squad whose members
   include a consumer wants a provider, and `Stage` waits for the role to be filled.
2. **Opportunities** — `BotOpportunity` carries ONE actor and uses it as the conflict key,
   which is why no two-unit plan exists today. It gains `actors`, and a relation-shaped
   opportunity — put the Servant in the truck and drive to the far site; rig the carrier
   and drive it into the strongest cluster — is priced by the relation's value against the
   journey, exactly as a capture is priced today.
3. **Placement** — below.

A fourth follows for free and is a `TODO`: an enemy provider is worth more than its own
cost (kill the spotter, not the gun), which is one more term in `BotTargeting`'s threat
signal once relations are readable.

## Where the army stands

Built 2026-10-03. An army with nothing to do used to mass on the base centroid — the middle of
its own buildings, on whichever side they happened to lie. It now stands `STAGING_OFFSET` in
front of the structure the enemy would reach first along the threat axis
(`Bot.frontmost_structure`, `BotMilitary._station_point`): next to what is exposed, on the
side the threat comes from. The axis is `Bot.threat_direction`, the one sense placement
already read, so the army and the buildings agree about which way is forward; fog-limited,
it faces the map's middle until something has been seen. The reserve stages by the same rule
toward its objective.

PLANNED — the rest of "which positions matter":

- **Approach coverage** for static defence, below: a chokepoint is where the approach samples
  bunch, so the same term that places a turret finds the chokepoint.
- **Undefended entrances.** The believed enemy base's approach cells not covered by any
  believed defence's reach, as an objective for a raid squad of fast or stealthed units.
  Needs the relation model (a defence PROTECTS what its reach covers) and the believed
  clusters over positions ([bot-roadmap](bot-roadmap.md) §The vision layer).

## Cover, and a wave that finds nothing

Built 2026-10-04, from two watched behaviours.

**The bot garrisons neutral buildings.** `BotOpportunist` only ever offered the bot's OWN
bunkers, and the Colonials own no open one, so no Colonial bot ever took cover.
`Bot.get_bunker_hosts` adds the neutral buildings: a neutral host adopts its first
occupant's side and is closed to the enemy from then on, so it is as good as owned, and it
is where most of the cover on a map is. An idle armed unit near one goes in; the wave
collects bunkered units when it launches (`BotActuator.evacuate`, the host's own order, and
a neutral host the bot occupies takes it because it is the bot's while occupied). MASS and
DEFEND leave them firing from cover.

**A unit that has arrived is left standing.** Every idle unit used to be re-ordered to its
destination each combat period, and an order to walk to where you already stand is a swirl;
issued to a whole army it is the swarm around a point that was reported. `HOLD_RADIUS` is
the arrival radius below which no order is re-issued, in every branch.

**A wave that has arrived razes the building it came for.** The point the army is sent to
lies beside the believed building, often outside the aggro range a unit picks targets from
on its own, so an army could arrive, stand, and wait — the "waiting around beside an
undefended base" that was reported. `_objective_for(ATTACK)` now keeps the remembered
entity beside the position, and an idle wave member within `STALL_RADIUS` of the objective
is ordered to Attack it while it stands (`BotActuator.attack`, which refuses a unit that
cannot hurt it). Waiting for a sizeable army is the commit gates' job and happens at HOME;
once a wave is at the front, standing is never the plan.

**A wave standing on a silent objective abandons it.** A believed building the walk can
never disprove — across a cliff, behind a ridge, nobody gets vision of it — kept the army
beside it for the rest of the match. Two rules: an objective is only chosen if the
navigation mesh reaches within `REACH_TOLERANCE` of it (`Bot.is_reachable`), and a wave that
has stood within `STALL_RADIUS` of its objective for `OBJECTIVE_STALL_SECONDS` with nobody
fighting abandons it for `OBJECTIVE_ABANDON_SECONDS` — a cooldown, not a ban, since the
ground changes. The clock restarts while the wave travels or fights.
Cover: `tests/test_BotStaging.gd`.

## Placement beyond open ground

`BotEconomy`'s placement is already a scored cost in the bot's own frame — compactness, a
bearing along the threat axis, corridor clearance ([bot-architecture](bot-architecture.md)
§Where a building goes). The extension is more terms, not a new mechanism:

- **Bearing by ROLE, derived from components.** Production forward and everything else
  behind was the whole asymmetry. It becomes: a structure with weapons and no production
  (static defence) forward; production forward; a structure with docking bays (an airfield)
  BEHIND, because what it holds is fragile; everything else behind. Derived, so a new
  defence or airfield classifies itself. Built 2026-10-03
  (`BotEconomy._wants_frontage`).
- **Approach coverage for defence.** `PLANNED`: "where enemy units are likely to be" is the
  ground on the walk from the believed threat to the base. Sample that path as `BotScout`
  samples a corridor, and a defence's cost rewards the fraction of samples inside its reach.
- **Relation affinity.** `PLANNED`: a consumer type wants the nearest provider within reach
  (`ADJACENT` wants edge contact, `RADIUS` wants to be inside), and a provider wants to
  cover the most consumers — which is `Bot.best_covered_point` asked of own structures. Both
  are one term each, priced by the relation's value so a weak synergy never outbids
  compactness.

TODO: a doc override for bearing (`placement: {bearing: ...}`) for a piece whose derived
role is wrong. Not built until a piece needs it; derivation first, as everywhere else.

## Build order

1. Built 2026-10-03 — waves in series, staged reinforcements, rally points, role bearing.
2. Built 2026-10-07 — the squad registry with `Stage`/`Assault`/`Hold`, the military
   rewritten over it, `ScenarioTactic` reading the same object, the squad cap as a
   difficulty parameter, and the guard.
3. `PLANNED` — `Relation`, `Bot.relations()`, multi-actor opportunities; `Escort` for
   transport and the Sapper.
4. `PLANNED` — `Patrol`, relation affinity and approach coverage in placement, the per-job
   enable for missions.
