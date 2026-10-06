---
title: Bot engagement fixes
type: system-note
---

# Bot engagement fixes

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Why a bot-versus-bot match was a guaranteed stalemate with zero
combat, what was actually wrong, and what the same ten matches do now. The instrument
throughout is [selfplay-harness](selfplay-harness.md) — nothing here was measured any other
way.

## The one thing to know first

**The bots could not SEE.** `Fog` resolved its `Map` from `get_tree().current_scene`, which
is the Scenario only when the Scenario is the opened scene. The harness instantiates the
Scenario as a child of a runner node, so the lookup missed, every `Fog` stayed inert, and
`fog_clear_at` then answered FALSE for every point on the map. `Commandable.is_visible_to`
is built on it, so aggro, `BotTargeting` and the blackboard all saw an empty world.

Two bots then spent twenty minutes building armies that could not acquire each other. That
is the whole of finding 1 in the harness note, and it is a total, silent blinding rather
than a visible failure — nothing errors, the match just never becomes a contest.

**Measured, one seed, 400 simulated seconds, everything else in this note applied, only
`fog.gd` moved:**

| `fog.gd` | `believed_enemy_army_value`, both slots, every sample |
|---|---|
| as it was | `0` … `0` (10 of 10 samples) |
| with `_resolve_map` | `400` by tick 1500, rising to `1400` |

## The four fixes

### 1. `Fog._resolve_map()` — the root cause

`scripts/maps/fog.gd`. The lookup now walks UP from the Fog node and searches each ancestor
with the owner filter OFF. A Fog is always a descendant of the Scenario that owns the Map it
belongs to, so walking up cannot miss; the owner filter is what missed, because a scene
instantiated from a script has no owner and `find_child(…, owned = true)` skips it.

**The shipped game is unaffected** — when the Scenario IS the current scene, both routes
find the same Map. What changes is every OTHER host: the harness, and GUT simulation tests.
See §What this broke.

`tests/test_FogVisibility.gd` gained two tests: one asserts the walk finds a Map through a
script-built host, the other asserts that the owner-filtered search — the old lookup, run on
the same fixture — does not.

### 2. `BotTargeting._engage_radius()` — scan as far as you can shoot

`scripts/interface/commander/bot_targeting.gd`. The retarget scan used the unit's AGGRO
shape alone, and on this content the aggro shapes are authored TIGHTER than the weapons: a
Badger aggros at 2 world units and shoots at 5. `BotMilitary` marches the army onto the
nearest enemy structure, `nearest_navmesh_point` puts it a few units short of the footprint
(a building blocks the navmesh it stands on), the AttackMove completes there — and nothing,
neither idle aggro nor this scan, could see a building the army was already in range to
destroy. Every unit idled at the foot of the enemy base.

The scan is now the FURTHER of the aggro shape and the longest weapon carried. Reach is also
the honest bound: `_retarget` issues a `persist = false` Attack, dropped when the target
leaves WEAPON range, so scanning to weapon range picks exactly the targets that stick.
`tests/test_BotEngageRadius.gd`, 5 tests.

### 3. `BotActuator.attack_move` — an attack-move that will hit a building

`scripts/interface/commander/bot_actuator.gd`. `AttackMove.get_updated_state` asks for aggro
at `message.target_priority`, whose default is `NON_COMBAT_UNITS`. An undefended enemy
structure ranks WORSE than that (`NON_COMBAT_STRUCTURES`), so the bot's entire ATTACK
posture could not raze anything: the army arrived at the enemy base and ranked the base out.

The bot's attack-move now defaults to `NON_COMBAT_STRUCTURES`. It is a DEFAULT rather than a
hardcode — a caller that wants the army to walk past buildings passes the narrower rank —
and the player's attack-move is untouched, because `RTSController` builds its own
`CommandMessage`.

### 4. `BotScout` — the coverage freeze

`scripts/interface/commander/bot_scout.gd`. Two independent causes, both of which froze
`observed_fraction` (0.28 and 0.15 in the original matches, and 0.28 / 0.15 again in all ten
of the before-runs here — the freeze is deterministic, not a seed accident).

- **The waypoint chooser did not distinguish a frontier cell from a stale one.** One pass
  over "expired" treats a cell nobody has ever seen exactly like a cell seen 61 seconds ago
  — and the second kind is always nearer, because the bot's own base and army refresh a disc
  around home continuously and everything just outside it re-expires every
  `SCOUT_EXPIRATION_TIMER`. The scout re-walked its own neighbourhood forever. Never-seen
  points are now taken first, and only when there are none left does it fall back to stale
  ones.
- **A scout is only handed its next waypoint when it goes idle, and a Move that can never
  arrive never goes idle.** One unreachable point parked a scout permanently: alive,
  un-retasked, standing 1.4 world units from a destination it never reached. A scout that
  covers less than `SCOUT_STALL_DISTANCE` in `SCOUT_STALL_SECONDS` is now re-dispatched.
  Deliberately distance-over-time rather than a plain timer: a long walk across the map is
  not a stall, and a timer sized to allow it would be too slow to catch one.

This was a genuine bug, not the consequence of `scout_unit_budget = 1`: a single scout on
this map reaches 0.65 coverage now, against 0.28 frozen before.

## What was NOT wrong: the neutral commander

The harness note's finding 2 — that `_objective_for(ATTACK)` is satisfied by a NEUTRAL, so
the bot marches on map furniture and stands there — **is not what was happening.** The
senses were already clean: `Commander._enemy_commanders` filters `id != 0`, and
`get_enemies_near`, `get_enemies_in_aggro_range` and `visible_enemies` each carry their own
`commander_id != 0` test. Nothing in `Bot` — `get_enemy_units`, `get_enemy_structures`,
`nearest_enemy_structure_to_base`, `enemy_clusters`, `relative_threat_level`,
`enemy_demand_map`, `believed_enemy_army_value` — can return a neutral piece.

What actually produced the reported symptom is that `has_attack_objective` and
`believed_enemy_army_value` do not measure the same thing. `nearest_enemy_structure_to_base`
is NOT fog-limited: the bot always knows where the opponent's base is. So the objective was
the REAL enemy base from tick ~300, the army genuinely marched on it, and
`believed_enemy_army_value` stayed 0 because the fog was broken. The bot looked committed
and was not fighting anybody — for the other reason.

The audit is now a test rather than a paragraph: `tests/test_BotHostileTargets.gd`, 9 tests
over the commander set, the senses and the ATTACK objective. Removing the `id != 0` filter
from `_enemy_commanders` turns 7 of the 9 red, which is what makes it a guard rather than a
restatement.

That the bot knows the enemy base through fog is a real property and a deliberate-looking
one, but it is not written down anywhere as a decision — it is raised as a question on the
"CPU Bot Behavior Work" task (`gdd/tasks.md` T-001; the brief is [brief.md](brief.md)).

## Before and after

Ten matches, seeds 1-10, mixed tiers (HARD/HARD, HARD/MEDIUM, MEDIUM/MEDIUM,
IMPOSSIBLE/EASY, IMPOSSIBLE/IMPOSSIBLE, and two `attack_value_ratio` variants), 20-minute
cap, `skirmish.tscn`, Colonial mirror. Same ten configs both times; the only difference is
the four files above.

| | before | after |
|---|---|---|
| **decisive results** | **0 / 10** | **8 / 10** |
| outcomes | 9 stalemate, 1 wall-clock cap | 8 elimination, 2 stalemate |
| peak `believed_enemy_army_value` | **0.0, both sides, all 10** | 1300 – 2300, both sides |
| peak scout coverage | 0.11 – 0.34 | 0.30 – 0.65 |
| peak idle units | 8 – 22 | 3 – 7 |

**Match length, decisive matches only (simulated minutes):** 9.2, 10.7, 11.5, 11.9, 12.3,
13.8, 16.7, 17.3 — median **12.1**, and none of them at the cap.

That answers the question the objective needs answered: **"a sooner victory is better" has
real dynamic range here**, roughly a factor of two, and the spread is not an artifact of
matches piling up against the 20-minute wall.

**One caveat worth carrying into any search: slot 1 won 7 of the 8.** On `skirmish.tscn` the
two start points are not equivalent, so a parameter scored on this map is scored together
with a side advantage. Run every configuration on both sides before believing a difference.

## The hysteresis re-check

The harness note's finding 4 looked for hysteresis and found none, and said so as a WEAK
negative: a bot that never fights has no retarget decisions to thrash. Re-run now that
combat happens.

`tools/selfplay/_hysteresis_match.gd` (a temporary subclass of the runner — delete it when
it stops earning its place) adds, per sample, the army posture, whether a wave is committed,
each unit's current target, and the production queue's contents. Seed 1, HARD vs HARD, 700
simulated seconds sampled every 0.4 s — exactly HARD's `think_interval_ticks` of 12, so one
sample is one think pass. 1,752 samples, and the match is a real fight throughout (both
armies lose value, both beliefs are non-zero, units carry Attack commands).

| | slot 0 | slot 1 |
|---|---|---|
| posture transitions in 1,752 think passes | 3 | 2 |
| posture A→B→A within 5 think passes | **0** | **0** |
| wave commit/end toggles | 3 | 2 |
| enemy → *different* enemy retargets, whole match | **2** | **3** |
| a dropped target re-acquired within 5 think passes | **0** | **0** |

Slot 0's postures: MASS at tick 12, ATTACK at 204, DEFEND at 13,584. Slot 1's: MASS at 12,
ATTACK at 204, and nothing after that.

**Verdict: no hysteresis.** The commitment margin and the wave rule are doing their job —
if anything the bot is under-reactive rather than twitchy; two retargets in twelve minutes
of fighting is very few.

The twelve "A→B→A within 5 passes" the scan does flag are all **idle ↔ plain Move**, which
is the SCOUT arriving at a waypoint and being handed the next one on the following think.
That is the mechanism working, not thrash. One unit acquired an Attack target and dropped it
three think passes later (slot 1, tick 4404): a `persist = false` leash release, also by
design.

**One limit of the instrument:** `production_queue.pending()` was empty at every sample in
both slots, so this says nothing about build/cancel thrash. It is not that the queue was
stable — it is that purchases dispatch to a producer rather than sitting in the pending
queue, so there was nothing there to watch. The bot has no cancel path at all
(`ProductionQueue.cancel` has no bot caller), so the only build oscillation possible is a
composition MIX that flips, and reading that needs a different probe.

## What this broke, and how the three were repaired

The fog fix un-blinds GUT simulation tests too, and **three tests were passing only because
fog was inert inside GUT.** Reverting `fog.gd` alone turned all three green again, which is
how they were attributed. All three were asserting behaviour that exists only under GUT: open
those same scenes in the editor and fog has always been active, because then the Scenario IS
the current scene.

**They were repaired in their own fixtures, and one of them was a real bug.** The rule the
three share: *a test that borrows a scenario shapes its own fixture; it does not have the
shared scene bent around it, and it does not get its expectation lowered.*

### 1. The kamikaze hold was never enforced — a genuine bot bug

The `test_kamikaze_no_cluster` simulation scenario asserts "the kamikaze stays
command-free for 10 s against spread irregulars". It stayed command-free because the bot could
not see anything at all; with vision the drone acquired a target and was commanded.

**The expectation was right and the hold was fiction.** `BotKamikaze._hold` only walked the
drone home — and only when the bot owned a structure, so a drone with no base was not even
walked. Walking is not holding: idle aggro (`Commandable._update_state`) picks up whatever
comes into range on the way, so the cost-effectiveness scan this module exists to perform was
silently overridden by proximity.

`Commandable.is_holding_fire` is the fix: a flag that stops a piece acquiring targets ON ITS
OWN while leaving explicit orders untouched. `_hold` now sets it, drops any engagement aggro
has already committed the drone to (suppression only prevents the NEXT pickup), and only then
takes the drone home if there is a home. `_commit` clears it first, so a drone flying a run is
never held. Deliberately a flag rather than a command: a command is exactly what the
expectation says a held drone must NOT have. Cover: `tests/test_BotKamikazeHold.gd` plus the
scenario itself, which is the end-to-end half.

### 2. `test_KamikazeSuicide` — separate the drone, and count its OWN bomb

The assertion is that a rammer detonates in contact rather than from cruise altitude, and it
was a knife edge: `altitude 0.50 <= reach 0.50`, with the drone parked 0.2 world units from
its victim and therefore already inside the AttackRange cylinder at cruise height. Two fixture
faults, both now fixed and neither by relaxing the bound:

- **The drone starts `APPROACH_DISTANCE` (6 units) away**, so the run is an approach and a
  dive — the thing the assertion is about — rather than a detonation from where it stands.
  Both bot brains are switched off for the run: the owning bot's `BotKamikaze` would hold or
  re-target the drone the test just ordered, and the far commander would move its units.
- **`_live_projectile_count` is asked of the DRONE'S commander**, not of the whole scenario.
  Scanning the scenario counted the defenders' return fire, whose first bullet arrives while
  the drone is still on its way in — so "the drone has fired" read true several ticks early
  and the altitude was sampled mid-approach. The sample is also taken one tick BEHIND the
  bomb's first appearance, because the bomb exists at the END of the frame the weapon fired
  in, by which point `Movement` has begun easing the drone back up.

### 3. `test_OrbitEntry` — empty the harness

It borrows the kamikaze scenario as a HARNESS for a flying unit and cares about nothing else
in it. With vision the drone attacked and detonated before the orbit could be observed, and
the test read a freed node. It now frees every commandable except the unit under test and
silences the brains. Nothing about orbit entry changed.

## What still blocks a decisive result

The two remaining stalemates share one shape, and it is not a perception or targeting
problem any more — both bots find each other, fight, and trade down.

- **Neither side rebuilds.** In seed 3 both armies are ground to 2-3 units by simulated
  minute 8 and then NOTHING changes for the remaining twelve: army value flat at 200 / 400,
  structures 4 and 2, no production. The economy does not recover from the first exchange.
  **Superseded (2026-09-05) — read §Fog-limiting the attack objective §The measurement that
  nearly went wrong first.** These bots held ZERO energy at every sample of every match; the
  economy was not failing to recover, it was never running. Concurrent economy work has since
  changed that, and the failure mode on the current tree is the opposite one: both sides bank
  thousands, build twice as much, and no longer finish inside ten minutes.
- **A won match was not scored as won.** In seed 6 slot 1 is reduced to **zero structures and
  one unit** by minute 16 and survives to the cap. **FIXED (2026-09-05):** no structures and
  no production is now a defeat, in the harness and in `Scenario._check_player_eliminated`
  alike — see [selfplay-harness](selfplay-harness.md) §No structures and no production is a
  defeat. The winner still does not hunt the straggler down, which is a real missing behaviour
  and remains a TODO in [bot-roadmap](bot-roadmap.md); it is simply no longer what a verdict
  depends on.

## Fog-limiting the attack objective

The attack objective now reads the blackboard's beliefs rather than
the live scene — see [bot-architecture](bot-architecture.md) §The attack objective is a belief
for what it does and why. This section is what measuring it showed, including the part that
is not about this change at all.

### The controlled comparison

Six seeds, HARD vs HARD Colonial mirror on `skirmish.tscn`, 10-minute cap, **one working tree,
one change**: `BotMilitary._objective_for(ATTACK)` reading the belief versus reading the live
scene, everything else identical. Sampled at t = 480 s, both slots.

| | omniscient objective | fog-limited objective |
|---|---|---|
| decisive results | **0 / 6** | **0 / 6** |
| mean army value | 5,009 | **11,742** (×2.34) |
| mean structures standing | 9.3 | **16.2** (×1.74) |
| median wall seconds per match | 132 | 154 |

**Read it the right way round.** Fog-limiting does not change the VERDICT at this horizon —
nothing decides within ten minutes on this tree either way. What it changes is how much
fighting happens: armies more than double and structures nearly do, because neither side is
losing anything. Both bots reach ATTACK posture early and stay there, but slot 1 believes
**zero** enemy structures at eight minutes in every one of the six fog-limited matches, so its
objective is a believed *unit* position — the last place a wandering enemy SCOUT was seen —
and the two armies march at each other's ghosts near their own bases while both economies boom
undisturbed. The extra 22 wall seconds per match is the same story in the cost column: more
entities alive, more per-tick work.

**Raising the scout budget does not rescue it.** A third arm — the same six seeds with
`scout_unit_budget` at its new HARD value of 3 — nearly doubles map coverage (0.35 → 0.55 at
t = 480 s) and gets 2-3 scouts out instead of 1, and still produced no decisive result inside
the same window, with armies at 13,500-15,900. More looking is not the missing piece.

> **TODO — the ATTACK fallback to a believed UNIT is the suspect, and it is a design decision
> rather than a tuning one.** The fallback predates fog-limiting: it was written for the
> endgame case where the enemy has no structures LEFT, and under fog it also fires when the
> bot has simply not FOUND any — two situations the bot cannot currently tell apart. The
> options (require a believed structure and otherwise MASS; make the scout prioritise the
> opponent's start region; give the bot a "they must have a base somewhere" prior) change what
> the bot does, so they belong on the task file rather than here.

### The measurement that nearly went wrong, and what it exposed instead

A first pass compared twelve matches run EARLIER IN THE SAME SESSION against six run after,
and read 12/12 decisive versus 0/6 — a collapse, attributable to the one change under test.
**It was not.** A second working tree had moved underneath the comparison: the earlier twelve
ran before concurrent economy work landed, and re-running the omniscient objective on the
current tree turned those same seeds into stalemates too. The table above is the re-run, and
the lesson is the plain one — **a before/after taken across a working tree that somebody else
is editing is not a before/after.** Both arms have to be run against the same tree, even when
that means running the control again.

What the accident exposed is worth more than the false finding was:

| | earlier tree | current tree |
|---|---|---|
| energy held at t = 480 s, every slot, every match | **0** — all 24 samples | 100 – 4,410 |
| structures at t = 480 s | 1 – 5 | 5 – 15 |
| decisive within 20 minutes | **12 / 12**, median 10.3 min | not measured at 20 min |

The earlier bots were completely energy-starved: they never banked a single unit of energy,
never got past five buildings, and fought to a conclusion with two-to-three-thousand-energy
armies because that was all either side could field. The bots on the current tree bank
thousands, build twice as much, and grind on — **so the decisiveness the fog arm appeared to
destroy was in fact the decisiveness of a broken economy, and it is the economy change that
made matches long, not the objective change.** Whether a bot that can afford things should
still be finishing games inside twenty minutes is the open question, and it is an economy
question.

## The objective nobody could act on

**FIXED (2026-09-11).** Two symptoms from a watched Colonial-vs-Colonial MEDIUM match
(the task's Feedback Notes, 2026-09-11), in his words:

> "armies of units moving out to other parts of the map, but they don't really approach the
> enemy to engage in battle. It actually appears that the only units getting caught in combat
> are units which are scouting"

> "Bot units appear to be receiving commands to attack targets which aren't applicable for
> their weapon. For example, I placed a scan drone near the enemy base, and several units had
> received a command to attack it … their weapons can't target it, so they sort of waited near
> their target until it had expired."

### One code site, two mechanisms — and only one of the symptoms is explained

The second report is a defect and is now fixed. The first is *partly* the same defect and
partly not, and the honest split matters more than the tidy answer:

- **The scan-drone report is entirely this bug.** Nothing between "choose an objective" and
  "issue an order" asked whether the thing being committed to could be damaged at all.
- **"Armies move out but never engage" is this bug for as long as the objective is something
  the army cannot hurt** — measured at **34% of ATTACK samples** below, and the army genuinely
  walks over and stands there. It is NOT this bug the rest of the time: with the fix in, the
  fraction of ATTACK samples with somebody actually attacking did not move (0.32 → 0.30, n=4
  slot-observations). The dominant residual is the bot fielding an army with no weapons in it
  at all — on this tree the early Colonial "army" is dominion generators and servants, both
  carrying an EMPTY `Loadout` and admitted to `_combat_units` by the crush clause — which is a
  production/composition question, not an objective one.

### The mechanism, and how it was proved

`Loadout.weapon_for_target` is the real question: a weapon may fire on a target iff its
`target_mask` intersects that target's TARGETABLE_GROUND / TARGETABLE_AIR bits
(`Weapon.can_target`). **It is not the same question as a damage multiplier of zero** —
`Bot.unit_effectiveness_vs` answers 0 both for "no weapon can lock onto this" and for "this
weapon does no damage" — and the Scan drone is the first kind: `scenes/entities/scout.tscn` is
HOVERING, so `Entity._apply_targetable_layers` files it on TARGETABLE_AIR **alone**.

The capability was always there. Aggro (`Commandable.get_aggro_near_position`) and
`BotTargeting._retarget` both filter candidates through it. The two places that did not were
the two that decide WHERE AN ARMY GOES and WHAT A DRONE COMMITS TO — and a third that could
have caught either: `BotActuator.attack` issued whatever it was handed.

**Why an impossible order never resolves itself.** `Commandable.update_commands` does not
consult preconditions — that is `RTSController`'s job, and the bot does not go through it. So
an `Attack` at an untargetable entity sits there: `should_move` returns false (no weapon to
close for), `can_act` returns false (nothing to fire), and with `persist = true`
`get_updated_state` returns `self` for ever. The unit stands beside its target holding an
order it can neither finish nor abandon — exactly "they sort of waited near their target until
it had expired". `Bot.kamikaze_best_target` is what hands out such an order in a real match:
it priced a blast purely off the damage table, which answers for anything with armour, so a
hovering drone could be the best-covered anchor for a ground-ramming drone.

Measured in self-play, the objective the army actually held: the beliefs no army member could
damage were `cl_mechLight_dominionGen` (28 samples) and `cl_airField` (7) — an unarmed,
crush-only early army marched onto a building it cannot scratch and onto a mech too big to
drive over. The direct count is `tools/selfplay/_engagement_match.gd`, a temporary runner
subclass that reports, per slot per sample, which branch of `_objective_for` produced the
march, whether the army can damage what is remembered there, how many units have arrived
holding no `Attack`, and a death ledger split by whether the dead unit was scouting.

### What changed, and at which layer

| Layer | File | Change |
|---|---|---|
| Objective | `BotMilitary._objective_for(ATTACK)` | Belief set filtered by `Bot.any_unit_can_damage` and `not Bot.belief_is_disproved` before the nearest is taken. A FILTER, not a veto: the drone at the gate is skipped and the base behind it is still the objective. |
| Perception | `Bot.unit_can_shoot` / `unit_can_damage` / `any_unit_can_damage` / `belief_is_disproved` | The questions themselves. `unit_can_damage` = a weapon that can lock on (own or bunker) OR a crush class heavy enough to drive over it; `unit_can_shoot` is the weapon-only form. |
| Commitment | `Bot.kamikaze_best_target` | Candidate bodies filtered by `unit_can_shoot`, so a drone with no reachable blast is HELD rather than sent. |
| Issue | `BotActuator.attack` | Skips any unit `Attack.meets_precondition` refuses — the same way `use_sanction` asks `UseSanction`'s, so the actuator can never issue an order the command itself calls impossible. |

`Bot.belief_is_disproved` is the second half of the "the walk is self-correcting" claim in
[bot-architecture](bot-architecture.md) §The attack objective is a belief. Structures were
already covered — `CommanderBlackboard.update` drops a structure belief when the commander
regains vision of its cell and finds it gone — but UNIT beliefs lapse only on
`BLACKBOARD_EXPIRATION` (180 s), so an army standing on the spot where it last saw an enemy
scout kept marching at ground it could see was empty.

### Before and after

Same tree, one temporary toggle, both arms run back to back — the lesson of §The measurement
that nearly went wrong, applied deliberately this time. Two matches (seed 1, with and without
`swap_start_points`), MEDIUM mirror on `skirmish.tscn`, 480 simulated seconds sampled every
10 s, giving 4 slot-observations and 103 / 70 samples in ATTACK posture.

| Per ATTACK sample | fixes off | fixes on |
|---|---|---|
| **objective nothing in the army could damage** | **35 / 103 = 0.34** | **9 / 70 = 0.13** |
| objective from the UNIT-belief branch | 45 / 103 = 0.44 | 22 / 70 = 0.31 |
| at least one army unit attacking | 33 / 103 = 0.32 | 21 / 70 = 0.30 |
| units arrived at the objective holding no `Attack` | 196 total, **1.90 per sample** | 69 total, **0.99 per sample** |
| armies that ever fight | 4 / 4 | 4 / 4 |
| combat deaths, scouting / army | 0 / 0 | 2 / 0 |

**The untargetable-commitment rate is what this change is for, and it falls by 2.6×.** The
residual 13% is expected rather than a miss: the objective is recomputed on the think cadence,
not per sample, so an army whose composition changed since the last think can be measured
standing at an objective it could act on when it set out. The stall count halving per sample
is the same effect seen from the units' end.

**Engagement did not improve, and the note should not pretend otherwise.** On this tree armies
barely fight at all in either arm — zero army combat deaths in 480 seconds on both sides of
the toggle — so the reported asymmetry ("only the scouts get caught in combat") reproduces
only in the weak sense that the scouts are the only units that die at all. The instrument to
answer the rest of that report is the same one; the cause is elsewhere.

### What this does NOT explain, and what to look at next

1. **Unarmed armies.** `_combat_units` admits crush-only units by design, and on the current
   tree the Colonial opening fields several of them with nothing else. An army with no weapon
   in it has no legal offensive objective, so the bot now correctly MASSes instead of marching
   — which is right, and is also why the fix cannot raise the engagement rate on its own.
   `BotProduction`'s composition is the next place to look.
2. **The ghost march in transit.** `belief_is_disproved` only fires once the bot has VISION of
   the remembered spot, so an army crossing the map toward a 77-second-old sighting is still
   marching at a ghost for the whole walk; the correction lands on arrival. That is the
   fog-limited objective behaving as designed, and shortening it means choosing a staleness
   rule — see the question below.
3. **The 2026-09-10 measurements in this session's earlier runs are void.** A bulk reformat of
   42 `.gd` files to tab indentation broke the project mid-session and the repair reverted
   other files with it, so numbers taken before and after that point are not comparable. Every
   figure above was taken after it, on one tree.

> [!question] Q — 2026-09-11
> Should `CommanderBlackboard` itself drop a UNIT belief the commander has walked to and
> found empty, rather than only the ATTACK objective ignoring it?
> **Why it matters:** `Bot.belief_is_disproved` is asked at the objective, so a disproved
> belief still counts toward `believed_enemy_army_value` (how strong the bot thinks the enemy
> is, which gates every attack wave) and toward `enemy_demand_map` (what it builds to counter).
> That is deliberate — the sighting is still evidence that the unit EXISTS, just not about
> where — but it means one belief is simultaneously true enough to build against and false
> enough not to march on. Moving the test into `CommanderBlackboard.update` makes unit beliefs
> behave exactly like structure beliefs and removes the split, at the cost of making the bot
> forget enemies faster and read the enemy army as smaller than it is, which under the humility
> prior makes it MORE aggressive.
> **Options:**
> 1. Leave it at the objective (today): beliefs are only disqualified as destinations.
> 2. Move it into `CommanderBlackboard.update`: a unit belief is dropped on a revisit that
>    finds the spot empty, exactly as a structure belief is.
> 3. Both, split by consumer: drop the LOCATION on revisit but keep the type and a last-seen
>    time as composition evidence — a new, smaller kind of entry.
>
> **Leaning:** 1 — it is the change that is already measured, and 2 moves a number that gates
> the attack-wave commit rule with nothing in this session's budget to measure the effect.
>
> **Answer:**

## Cost

Unchanged from the harness note in shape, and no longer cheap: matches on the current tree
run to their cap rather than ending early, and the entity count climbs the whole way. A
10-simulated-minute match is **120-160 wall seconds single-process**, so a 20-minute one is
past five wall minutes — budget batches on that rather than on the 76-130 seconds a decisive
match used to cost. Fog-limiting adds about 20 seconds per 10-minute match, which is the extra
entities and nothing else.
