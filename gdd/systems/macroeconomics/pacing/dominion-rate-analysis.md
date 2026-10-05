---
title: Dominion rate analysis
type: system-note
---
# Dominion rate analysis

WIP 2026-10-05 — steps 1 and 2 of 4 done, the per-faction rates retuned on the model's numbers
(§Retuned rates) and the Colonial route recalibrated (§Colonial decision); step 3 (check the model
against the engine) and the build-time half of step 4 wait on review.

**The question** (Alex, 2026-10-05): over a game, is each faction's dominion income about equal?
The Technocratic Lab is the reference: 5 dominion/s per extraction site, one site's worth of
energy ([sanction-calibration](sanction-calibration.md) §Fungibility). Only each faction's
PRIMARY mechanic is measured — the Colonial Servant route, for one, is meant to be inefficient and
is left out.

**Decided for this analysis** (Alex, 2026-10-05):

- One player alone on a 2-player map, playing to bank as much dominion as fast as it can.
- Real energy: today's costs and the real income (starting energy, the two free extractors, and
  every site and pond the player finds and builds on). Energy costs are NOT being recalibrated.
- The ceiling is every resource on the map, not the player's own half.
- Anarchist followers include infantry trained at the barracks, not only liberated residents.
- The knobs to assess: build/train times, and each faction's per-unit rate (dominion per captive,
  per follower, per tile). Technocratic stays fixed.

Everything here is reproduced by the two tools under `tools/dominion_analysis/`; numbers in this
note are their output and will move when a build time or rate does.

## Step 1 — the maps

`tools/dominion_analysis/export_maps.tscn` generates ten 2-player maps with the shipped
`MapGenerationParams`, writes them as map scenes (gitignored, `scenes/scenarios/generated/dominion/`)
and exports JSON (gitignored, `tools/dominion_analysis/out/maps/`): starts, shelters, extraction
sites, ponds, and the walkable grid as the loaded map's `TerrainGrid` reports it. Seeds 3000–3011;
3004 ("starts 0 and 1 cannot keep 2 routes") and 3008 (traversable share and obstruction balance
off target) were refused.

| Map | seed | grid | walkable cells | shelters | sites | ponds | nearest shelter to each start |
|---|---|---|---|---|---|---|---|
| dom_01 | 3000 | 202² | 18178 | 5 | 9 | 12 | 30.4, 34.7 |
| dom_02 | 3001 | 235² | 23849 | 3 | 9 | 10 | 31.9, 27.1 |
| dom_03 | 3002 | 219² | 20745 | 4 | 8 | 13 | 34.7, 27.6 |
| dom_04 | 3003 | 212² | 19552 | 3 | 10 | 10 | 34.5, 34.8 |
| dom_05 | 3005 | 220² | 21272 | 5 | 8 | 11 | 34.5, 34.8 |
| dom_06 | 3006 | 216² | 20576 | 4 | 8 | 11 | 34.8, 34.1 |
| dom_07 | 3007 | 225² | 21869 | 3 | 8 | 11 | 34.0, 34.7 |
| dom_08 | 3009 | 215² | 20406 | 4 | 8 | 11 | 34.8, 34.7 |
| dom_09 | 3010 | 215² | 20187 | 3 | 8 | 11 | 34.7, 34.5 |
| dom_10 | 3011 | 221² | 21589 | 3 | 10 | 10 | 31.7, 33.6 |

These use the shelter rules of 2026-10-05: 3–5 shelters per 1v1 map, and one inside its start's
25–35-cell band ([map-generation](../../terrain-and-navigation/map-generation.md) §Shelters).

**The band sits at its outer edge.** Placement still aims each shelter at a fair access split,
and a shelter nearer one start is more that start's, so the fairest point in the band is its
farthest: at 15–35 nearly every start had its shelter at ~34 cells. Decided (Alex, 2026-10-05):
narrow the band to 25–35 rather than drop the steering. Generation is unharmed — 35 of seeds
3000–3039 generate at 25–35 against 36 at 15–35, and no rejection is the band's.

## Step 2 — the model

`tools/dominion_analysis/run.py` plays each faction on each map for 15 minutes, one-second steps
(`sim.py`), and keeps the best of a small grid of strategies (a POLICY per faction). It is a model
of a good player, not a bot. Every number it uses is read from the project (`facts.py`): build
times and costs from `technology.json`, speeds from the speed ladder, vision and reach from the
shape library and piece scenes, rates from the generator and route scripts, starting energy
(5000) from `skirmish.tscn`.

**The common rules.** Starting units appear at the start point; the command centre and the two
free extractors are dropped there at t = 0 (each extractor pays a site's 5/s and draws 50
infrastructure). A build or training job pays its energy when it starts and waits until it can.
A piece that draws infrastructure needs the spare; a provider never waits on strain. Ground
units walk the shortest path over the walkable grid; fliers fly straight. Extraction sites and
ponds are unknown until some unit's vision has covered them; shelters are known from t = 0 (the
HEGEMONY reveal).

| Faction | What it plays | Policy grid |
|---|---|---|
| Technocratic | Surveyors scout (and supply infrastructure); Technicians build Labs on every found site, training a Surveyor whenever the next Lab lacks infrastructure; idle Technicians scout too | extractors before the first Lab: 0/1/2/3/5 · extra Technicians: 0/1/2/4 |
| Colonial | Servants build Compounds (at base or beside the nearest shelters); the Citadel trains Stock Trucks once one stands; trucks fill at the shelter with the most uncollected residents and deposit at the nearest Compound with room | Compounds 2–12 · trucks 2–8 · Compound spot · extractors 0/2 |
| Anarchist | Irregulars trained continuously at every Stronghold join the base pool; Warlords are trained as the pool outgrows them; liberator Warlords camp at the nearest shelters and liberate residents as they appear; optional Safehouse + Redoubts train the cheapest barracks infantry | liberators 0–3 · Redoubts 0/1 · extra Strongholds 0–2 · extractors 0/2/4 |
| Libertarian | Canaries build a Relay (the Opticon's tech), then Opticons, each at the walkable spot claiming the most tiles nobody claims yet | extra Canaries 0–12 · extractors 0/2/4 |

The policy kept per map is the one with the most dominion banked by 10 minutes.

**Simplifications, each to be checked in step 3 or accepted:**

- Followers are pools, not walked units: a Warlord's 2.5-unit reach is assumed to hold **25**
  followers (a packing estimate at the 0.45 avoidance radius). The Anarchist curve leans on this
  number more than on anything else — see the sensitivity table below.
- A Stock Truck takes **2 s** to run down each resident (they wander within 3 units of their
  shelter).
- A builder works from 2 cells off its target; co-building is not modelled (it does not speed a
  build).
- Neutral buildings do not block the walkable grid (they are not registered outside a scenario);
  a few cells each.
- Exploration sends a scout to the nearest unexplored point of a 10-cell lattice.
- No enemy, no losses, no upkeep beyond infrastructure.

## Step 2 — results (rates before the 2026-10-05 retune)

Dominion EARNED (the starting 100 is not counted); median over the ten maps, (min–max).

| Faction | 3 min | 5 min | 10 min | 15 min | avg rate, 0–10 min | rate at 15 min | first dominion |
|---|---|---|---|---|---|---|---|
| Technocratic | 1902 (1170–2480) | 6225 (5595–7655) | 18528 (17595–22105) | 30528 (29595–37105) | 31/s | 40/s (40–50) | 54 s |
| Colonial | 1042 (771–1182) | 2904 (2475–3246) | 8902 (8095–10933) | 14862 (13542–18459) | 15/s | 18/s (18–27) | 80 s |
| Anarchist | 7697 (5555–8037) | 24538 (17747–25399) | 83535 (64054–91776) | 143535 (119562–166776) | 139/s | 200/s (175–250) | 1 s |
| Libertarian | 7526 (6473–7880) | 19506 (18614–20765) | 51827 (46691–55791) | 83927 (74883–92997) | 86/s | 107/s (94–124) | 46 s |

Against the reference at 10 minutes: Anarchist **4.5×**, Libertarian **2.8×**, Colonial **0.48×**.

| Followers per Warlord (assumed 25) | Anarchist at 5 min | 10 min | 15 min |
|---|---|---|---|
| 12 | 20580 | 63578 | 106778 |
| 25 | 24538 | 83535 | 143535 |
| 50 | 25101 | 100726 | 190638 |

**What limits each faction:**

- **Technocratic — sites.** By 15 minutes every extraction site on the map holds a Lab: the end
  rate is exactly 5/s × the site count (8–10). Scouting is what spreads the opening: the first
  Lab pays at 30–100 s depending on how soon a site is found.
- **Colonial — shelter supply.** A shelter yields one resident per 10 s and each serves 60 s at
  1/s, so it supports at most 6/s. Three-shelter maps reach exactly that (18/s); on four- and
  five-shelter maps the trucks fall short of the full supply within the window (19–27/s). The
  chosen policies sit at the top of the Compound and truck grid, and raising them further barely
  moves the total — supply and the truck runs to far shelters, not capacity, are the wall.
- **Anarchist — energy, without a ceiling.** An Irregular costs 100 and pays 1/s for as long as it
  stands with a Warlord, so income grows for the whole game; liberation adds free followers from
  every shelter. Barracks infantry is never chosen — it costs more per follower than an Irregular.
- **Libertarian — energy, with a far ceiling.** An Opticon costs 250 and claims ~1250 tiles,
  about 4/s, overlap aside; it claims void tiles past the play area too (the route counts every
  in-grid tile). The map runs out only after the window measured here.

**Dominion per energy invested**, the root of the spread: an Opticon buys ~1/s for ~62 energy, an
Irregular 1/s for 100, a Lab 1/s for 100 (plus a site and a share of a Surveyor), a Compound 1/s
for 200 before the trucks — and the Colonial and Technocratic routes stop at map features while
the other two do not.

**Surfaced on the way:** the Libertarian opened in infrastructure debt — the Shard supplied none
and the two free extractors draw 100. Resolved 2026-10-05: the Shard supplies 100 (Alex). It moves
the Libertarian result by under 1%, since its first build is the Relay either way.

## Retuned rates

Decided (Alex, 2026-10-05): retune the per-unit reward rates alone, Technocratic unchanged, so
that over a game the Colonial route earns **1×** the Technocratic route, the Libertarian **2×**
and the Anarchist **3×**. "Over a game" is read as dominion banked by 10 minutes, the
checkpoint the strategies are ranked on. Every route's dominion is linear in its rate and no
strategy's choice depends on it, so each new rate is the old one scaled by target ÷ measured:

| Rate | Was | Now | Where |
|---|---|---|---|
| Colonial, per captive per 5 s | 5 (1/s) | **10** (2/s), since superseded by §Colonial decision | `OccupantDominionGenerator.dominion_per_unit` |
| Libertarian, per claimed tile per 5 s | 0.016 | **0.0114** | `LibertarianDominion.dominion_per_tile` |
| Anarchist, per follower per 5 s | 5 (1/s) | **3.33** (0.67/s) | `AnarchicalDominion.dominion_per_unit` |

The exact Colonial scale is 10.4; it stays 10 because every per-piece generator pays whole
dominion. The Anarchist rate is now fractional and carried between cycles like the Libertarian
one (its HUD badge shows one decimal).

Rerun with the new rates, ratio to Technocratic (median over the ten maps):

| Faction | 5 min | 10 min | 15 min |
|---|---|---|---|
| Colonial | 0.93× | **0.96×** | 0.97× |
| Libertarian | 2.23× | **1.99×** | 1.96× |
| Anarchist | 2.63× | **3.00×** | 3.13× |

The ratios drift with time because the curves are different shapes: the Anarchist route keeps
climbing after the Technocratic one levels off at its sites, and the Libertarian route starts
fast and slows. A constant rate can match one checkpoint, not all of them.

Model numbers, so they carry the model's assumptions — above all the 25 followers per Warlord,
which step 3 measures. The Prologue scenarios set their own Anarchist rate (1) and are untouched.

## Colonial recalibration sweep (2026-10-05)

Asked (Alex): room to raise dominion per captive and lower the Servant's price (to 150–300), with
the Stock Truck side unchanged and Work Detail ignored; deposit time and sentence length may move.
`tools/dominion_analysis/sweep_colonial.py` runs sentence length (30/60/120/240 s), Compound
capacity (2/3/6) and an extra deposit time (0 or 5 s per captive, on top of the shipped 0.5 s per
deposit) over the ten maps, and solves for the rate per captive R that puts 10-minute dominion at
1× Technocratic. V = R × sentence is dominion per captive; a Servant buys exactly V, so its energy
per dominion is price ÷ V (the Lab anchor is about 1).

| sentence | capacity | R (/s) | R per 5 s | V | 15-min ratio | share of shelter supply used at 15 min | Servant e/dom at 150 / 300 |
|---|---|---|---|---|---|---|---|
| 60 (today) | 3 | 2.23 | 11.1 | 134 | 1.02× | 100% | 1.1 / 2.2 |
| 120 | 6 | 1.11 | 5.6 | 133 | 1.01× | 100% | 1.1 / 2.3 |
| 120 | 3 | 1.58 | 7.9 | 190 | 1.08× | 72% | 0.8 / 1.6 |
| 120 | 2 | 2.28 | 11.4 | 273 | 1.12× | 60% | 0.5 / 1.1 |
| 240 | 3 | 1.35 | 6.7 | 323 | 1.17× | 52% | 0.5 / 0.9 |
| 240 | 2 | 2.02 | 10.1 | 485 | 1.16× | 35% | 0.3 / 0.6 |

Rows with no extra deposit time; the full grid is in the sweep's output.

**What the sweep says:**

- **V can only rise if the Compounds, not the shelters, are the limit.** A long sentence or a small
  capacity means fewer captives are processed at once, so each must be worth more to reach 1×. The
  price is the late game: those configurations are still growing at 15 minutes (1.08–1.17×), and
  their eventual ceiling, 0.1 × V per shelter, is up to 2–4× today's.
- **Deposit time** — see §How deposit time works, below: it costs about 5–15% of dominion at
  5 s per captive once the player has bought trucks to suit; at a fixed truck count it costs more.
- **The Servant price range caps V.** A Servant buys V dominion for its price, so raising V and
  cutting the price both make Servants more efficient. At V ≈ 130 (today's model) a 150–300
  Servant costs 1.1–2.3 energy per dominion; at V ≈ 190 it is 0.8–1.6, and beyond V ≈ 300 a
  Servant is cheaper per dominion than a Lab at any price in the range. A Servant also takes a
  place a free captive could have had, which only costs anything while Compounds are full.

### How deposit time works

Three stations in a row: a SHELTER makes one resident per 10 s but holds only three, and stops
making more while full, so a resident not collected in time is production lost; a TRUCK runs a
cycle — drive to a shelter, capture (and wait for spawns), drive to a Compound, deposit — carrying
up to three; a COMPOUND pays each captive while it serves. Dominion is captive flow × V.

Deposit time is a fixed cost on every truck cycle, independent of truck speed and of where
anything stands. Measured cycles run 40–66 s (longer with more trucks, which share the same
shelters and wait on spawns), so 5 s per captive — about 15 s a full load — adds a quarter to a
third to each one. With the Compounds held at 12 and the 60 s sentence:

| trucks | +0 s/captive | +2 s | +5 s | +10 s |
|---|---|---|---|---|
| 2 | 100% | 87% | 81% | 61% |
| 4 | 100% | 94% | 83% | 68% |
| 6 | 100% | 92% | 83% | 70% |
| 8 | 100% | 93% | 83% | 71% |

(10-minute dominion relative to the shipped 0.5 s deposit, median over the ten maps.) More trucks
do not buy it back, because the losses are at the shelters — a truck standing at a Compound is not
standing at a shelter when it fills — and in the captives, who earn nothing while being handed
over. So deposit time IS a usable throttle on Colonial income that leaves truck speed alone: about
−17% at 5 s per captive, −30% at 10 s, at any truck count. In the sweep above, where the strategy
also re-picks its Compounds and trucks, the same 5 s costs 5–15%.

### One-at-a-time processing

Asked (Alex, 2026-10-05): what if a Compound served one captive at a time? Modelled as: one
captive serves its sentence and earns, the rest of the Compound's places hold captives waiting
their turn, unpaid. A Compound then processes one captive per sentence and pays R, not 3R.

| sentence | hold | R (/s) | R per 5 s | V | 15-min ratio | shelter supply used at 15 min | Servant e/dom at 150 / 300 |
|---|---|---|---|---|---|---|---|
| 15 | 3 | 8.46 | 42 | 127 | 0.99× | 86% | 1.2 / 2.4 |
| 30 | 3 | 4.93 | 25 | 148 | 1.03× | 100% | 1.0 / 2.0 |
| 60 | 3 | 4.34 | 22 | 261 | 1.10× | 52% | 0.6 / 1.2 |
| 120 | 3 | 3.87 | 19 | 465 | 1.18× | 38% | 0.3 / 0.6 |

(No extra deposit time; a hold of 6 changes little. Full grid: `sweep_colonial.py 2 queue`.) The
pattern is the simultaneous one, shifted: a Compound is one place, so the same V needs a shorter
sentence. It makes a Compound a hard cap of one captive per sentence, which is what lets V rise —
and the Servant price range caps V just the same.

## Colonial decision

Decided (Alex, 2026-10-05): the one-at-a-time row at a 30 s sentence.

| Knob | Was | Now | Where |
|---|---|---|---|
| Processing | every captive serving at once | **one at a time**, the rest queue unpaid | `Garrison.SENTENCES_AT_ONCE` (1), `Garrison.paying_count()` |
| Sentence | 60 s | **30 s** | `cl_infrastructure.md` `garrison.sentence_length` |
| Rate per captive serving | 10 per 5 s (2/s) | **25 per 5 s** (5/s), so V = **150** | `OccupantDominionGenerator.dominion_per_unit` |
| Servant | 500 energy | **200 energy** (≈ 1.3 energy per dominion) | `cl_bioLight_builder.md` `build.cost.energy` |

Compound capacity stays 3, now a queue. Deposit time is unchanged (0.5 s a deposit). The HUD's
projected rate caps each Shelter at one captive serving to match (`Commander.projected_dominion_rate`).

Rerun with the shipped values (`run.py`, which now reads the processing mode from the game),
Colonial against Technocratic:

| | 5 min | 10 min | 15 min |
|---|---|---|---|
| ratio of medians | 0.85× | **1.05×** | 1.07× |
| median of per-map ratios (range) | 0.85× (0.66–0.97) | **1.02×** (0.85–1.13) | 1.05× (0.87–1.26) |

The best policy on every map is twelve Compounds at the shelters with four trucks: with one captive
serving per Compound, a worked shelter (one resident per 10 s) keeps three Compounds busy. Colonial
starts slower than Technocratic (first dominion 82 s against 54 s) and passes it by 10 minutes.

Accepted with it: the Servant is no longer very inefficient — 1.3 energy per dominion against the
Lab's ~1 — and V is held near 150 by the price range, not by the shelters.

## Next

- **Step 3** — measure the model's assumptions in the engine with scripted (not bot) runs: walking
  time, a truck cycle, a liberation, build completion, and how many followers really fit in a
  Warlord's reach. At most four short runs, reported before more.
- **Step 4** — fit build/train times and per-unit rates so the curves meet the Technocratic one at
  the checkpoints, and say where only a mechanic change can (the Anarchist and Libertarian curves
  keep climbing after the Technocratic one levels off, so no constant rate makes them equal at
  every time).
