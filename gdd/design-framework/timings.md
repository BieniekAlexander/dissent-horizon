---
title: Timings — threat arrival, scouting windows, and what the economy costs
type: design-note
---

# Timings

**The equations are the durable part; the tables are a dated snapshot (2026-09-24)** and go
stale the moment a stat moves. The note answers M2 of [matchups](matchups.md) — can a player see
a threat coming and answer it in time — and what an economic investment costs in army at the
moment of contact. It feeds deferred items 1.20 (structure armour), 1.23 (investment ratios) and
1.30 (travel time). Battle outcomes are out of scope: an army ratio here says who arrived with
more, not who wins.

Grounded in Colonial (far along) and Anarchical (stale). Libertarian is too early to include.

---

## Symbols

| Symbol | Meaning | Snapshot value |
|---|---|---|
| `D` | start-to-start distance | 150–250 (playtest feel; `skirmish.tscn` is ~79 today) |
| `κ` | path factor, route length ÷ straight line | 1.15, a guess for open generated maps |
| `v`, `v_s` | threat speed, scout speed | per unit |
| `τ = κD/v` | a threat's crossing time | — |
| `t_ready` | when the threat's first unit exists: the sum of build times along its `requires` chain, plus walking | per unit |
| `t_tell` | when the tell becomes visible — the unlocking structure is placed | per unit |
| `T_ans` | the defender's time to field an answer, given what already stands | per answer |
| `B` | starting bank | 5000 |
| `c`, `t_b`, `r` | an extractor's cost, build time, income per second | 500, 20 s, 20/s today |
| `R₀` | income from the two free extractor drops, from the command-centre drop on ([starting-formations](../systems/scenario-scripting/starting-formations.md) §Deferred deployment, PLANNED) | `2r` |
| `I_k` | income with `k` extractors beyond the starting two | `R₀ + k·r` |
| `S` | a player's production throughput, energy per second across producers | per producer: cost ÷ build time of its unit |
| `δ` | the defender's fighting advantage at home — statics, position | unknown; the equations carry it |

---

## The equations

### 1. When a threat lands

```
t_arr = t_ready + κD/v
```

`t_ready` is set by the tech tree and `κD/v` by the map. **Distance adds the same number of
seconds to every tier, so it is a large share of an early threat's lead time and a small share of
a late one's.** Distance is an early-game knob; build times are a late-game knob.

### 2. Can the defender scout it and answer in time (M2)

The defender learns of the threat at `t_info` and must field its answer by `t_arr`:

```
t_info + T_ans ≤ t_arr
```

There are three ways to learn of it.

**A scout that must travel.** It leaves at `t_s0` and arrives after the tell is already up, so
`t_info = t_s0 + κD/v_s`:

```
κD · (1/v_s − 1/v)  ≤  t_ready − T_ans − t_s0
```

- **Scout faster than the threat (`v_s > v`):** the left side is negative and shrinks further as
  `D` grows. **Distance helps the defender.**
- **Scout slower than the threat (`v_s < v`):** there is a ceiling on distance,
  ```
  D_max = (t_ready − T_ans − t_s0) / (κ · (1/v_s − 1/v))
  ```
  and **beyond `D_max` scouting that threat is impossible.** Worked: a Stock Truck (1.75) scouting
  a Toxin Tractor (4.0, `t_ready` 60) against a Badger answer (`T_ans` ≈ 10) gives
  `D_max ≈ 50 / (1.15 · 0.32) ≈ 135`, short of 150. That is why no ground scout sees the first
  wave at the distances under discussion.

**A scout already in place, or a reveal** (Scan, Informant): `t_info = t_tell`, and the
condition becomes a floor on distance rather than a ceiling:

```
κD/v  ≥  T_ans − L,    where  L = t_ready − t_tell
```

`L` is the lead the tell gives: the unlocking structure's build time plus the unit's. **Once
information is in place, more distance only helps.** Distance hurts scouting only while the
information is still walking there.

**Spotting it en route**, a fraction `φ` of the way across:

```
W = (1 − φ) · κD/v  ≥  T_ans
```

At `φ = ½` this leaves foot armies 57–96 s, a Matilda 35–58 s, an Anarchical vehicle 21–36 s and a
Drake 14–24 s.

### 3. The defender's reinforcement advantage

While the attacker walks, the defender keeps producing, and it reinforces from closer:

```
H = min(I_def, S_def) · κ · (d_att − d_def) / v
```

`d_att` and `d_def` are each side's distance to the fight. For an attack on the defender's base,
`d_def ≈ 0` and `d_att ≈ D`, so **the home advantage is the defender's spendable income times the
attacker's crossing time.** It grows linearly with `D`. Worked, at D=200 with a Matilda army
(τ = 92) against a defender on five extractors at the 50% rate (50/s): `H ≈ 4600` energy of army.

At a contested site halfway between the starts, `d_att ≈ d_def` and `H ≈ 0`. **Distance protects
the base, not the map.**

### 4. What greed costs at the moment of contact

Take two players spending everything on army as it arrives, one with `n` extra extractors and one
with `m < n`. Past `t_b`, their army values differ by

```
G(t) = (n − m) · [c − r · (t − t_b)]
```

This is positive until the **payback time**

```
t* = t_b + c/r
```

and negative after it. An attack departing at `t₀` finds the greedy player behind only if

```
G(t₀)  >  H + δ · A_def
```

Two consequences:

- **At the base, `H` wins.** The largest greed gap, `3c` at `t₀ ≤ t_b`, is 2250 with `c` = 750,
  against an `H` of several thousand. **An army walking across a 150–250 map cannot punish
  greed at the defender's base.** Greed is punished where `H ≈ 0`: at a contested extractor site,
  or by raids that kill extractors rather than armies.
- **At a contested site the question is `t*` against the contact time `t_c`.** If the greedy
  extractors have paid back before the armies meet, greed was free.

**The rule that falls out: payback should outlast first contact by a margin.**

```
t* ≈ t_c + f · A(t_c) / r
```

`f` is the army lead, as a fraction, that one extractor's worth of greed should cost. At
150–250, `t_c` is ~120 s for the fast raids and ~160 s for the first tank army (§Earliest
arrival). Since `t_c = t_ready + κD/v`, **the extractor's payback has to be tuned together with
the starting distance**: moving the starts apart moves contact later, and an extractor that paid
back before contact becomes a free choice.

**Production caps change the picture early.** While money exceeds what producers can spend
(`money > S·t`), both armies are capped at `S·(t − t_ready)` and the greed gap is zero. The
5000 bank keeps both players in that regime for the first ~100 s, so an all-in player only turns
saved money into a lead by also buying *throughput*: another producer, a pair of Barracks. In
simulation, with equal throughput on both sides the gap never opened; with the greedy defender
held to one producer against an attacker that bought three, it did. The honest summary is that `S` is a third knob beside `c` and `r`.

### 5. What the opening bank buys

```
B = core + Σ producers + tech + k·c + dominion + army + scouts
```

`core` is what every opening needs: Colonial Compound + Barracks (1500), Anarchical Safehouse +
Redoubt (1500). What is left, `B − core` = 3500, is the menu.

**The menu is low-granularity when every choice on it costs about the same.** If a producer, a
tech structure and an extractor each cost roughly 1000, then 3500 buys about three and a half
of them, and every opening is a choice of three or four chunks — your stated shape:

| choice | as a chunk | notes |
|---|---|---|
| second producer | 1 | Sky Port 1000, Hangar 800 — on the scale. **Yard / Chop Shop 2000 is two chunks**, and builds in 15 s |
| third producer | 1 | three producers plus core leaves ~500: over-invested, as intended |
| tech | ~1.2 | Ops Centre, Stockpile 1200 — one, at the cost of a producer or army |
| extractor | `c / 1000` | at `c` ≈ 1000, three is all the bank allows beside core — greedy by construction |
| dominion | small | the direct price is small; the real cost is the army that defends the generator |
| army, scouts | the rest | for Colonial a scout also costs dominion when it is the Stock Truck |

The war factories are the outliers in both price and speed (§Build-time outliers).

---

## The extractor ladder

Army ratio at contact, fewer-extractor player ÷ three-extractor player, from equation 4 with
`H = 0` (a contested site) and `B − core − producers` = 2500 for both. Above 1 means the greedy
player arrives behind. The infrastructure draw is left out.

| extractor (cost, build, rate) | payback `t*` | contact 120 s: 3v2 / 3v1 / 3v0 | contact 160 s | contact 200 s |
|---|---|---|---|---|
| 500, 20 s, 20/s (today) | 45 s | 0.87 / 0.75 / 0.62 | 0.85 / 0.71 / 0.56 | 0.84 / 0.69 / 0.53 |
| 500, 20 s, 10/s | 70 s | 0.92 / 0.84 / 0.77 | 0.89 / 0.79 / 0.68 | 0.88 / 0.75 / 0.62 |
| 750, 30 s, 10/s | 105 s | 0.97 / 0.94 / 0.92 | 0.93 / 0.85 / 0.78 | 0.90 / 0.80 / 0.70 |
| 1000, 45 s, 10/s | 145 s | 1.06 / 1.12 / 1.18 | 0.98 / 0.95 / 0.93 | 0.93 / 0.87 / 0.80 |
| 1250, 45 s, 10/s | 170 s | 1.15 / 1.29 / 1.44 | 1.02 / 1.04 / 1.06 | 0.96 / 0.92 / 0.88 |
| 1500, 45 s, 10/s | 195 s | 1.28 / 1.57 / 1.85 | 1.08 / 1.15 / 1.23 | 0.99 / 0.98 / 0.98 |
| 1000, 45 s, 5/s | 245 s | 1.34 / 1.68 / 2.03 | 1.15 / 1.30 / 1.45 | 1.06 / 1.12 / 1.18 |

The ladder you want — 3v2 about even, 3v1 clearly behind, 3v0 badly behind — needs `t*` about
40–80 s past contact. **Today's 45 s, and last pass's 750/30 s proposal at 105 s, both pay back
before contact at these distances, so greed is free.** It takes `t*` ≈ 170–245 s: a pricier
extractor (1250–1500 at 10/s), a slower rate (1000 at ~5/s), or a longer build (`t_b` counts in
full, and a long build is also a long window in which the foundation stands at a fraction of its
hp). Army ratios compound in a fight — under a square law, a 1.15 army is ~1.3 in strength — so
a modest-looking ratio is a real edge.

TODO: pick `c`, `t_b` and `r`. The ladder only holds for a contested site; the base is protected
by `H` regardless (equation 3), which makes **how many sites lie inside a player's reinforcement
advantage** the other half of the tuning — see §Map levers.

---

## Earliest arrival of each threat

Ready = rush chain from an empty base, funded from the bank, +10 s overhead. Arrival = ready +
`κD/v`. A single unit, not an army. The whole first wave is **time-gated, not money-gated**: 5000
funds any of these chains at t=0.

TODO: the Safehouse figures in this table and in `core` are its old price (500 energy, 20 s). A
Safehouse now takes its price and build time from its underlying building variant (default
800 energy, 25 s), so they are not recomputed here yet.

| Threat | Chain | Ready | D=150 | D=200 | D=250 |
|---|---|---|---|---|---|
| AN Toxin Tractor | Safehouse 20 → Chop Shop 15 → 15 | 60 | 103 | 117 | 132 |
| AN Irregulars (starting) | — | 0 | 105 | 139 | 174 |
| AN Kamikaze | Safehouse 20 → Hangar 25 → 10 | 65 | 108 | 122 | 137 |
| AN Collective + Sappers | Safehouse → Redoubt 20 → Sapper 20 | 70 | 113 | 127 | 142 |
| CL Drake | Compound 20 → Barracks 10 → Sky Port 25 → 25 | 90 | 119 | 128 | 138 |
| AN MLRS / War Wagon | … → Stockpile 25 → 15 | 85 | 128 | 142 | 157 |
| CL Sloop | Compound → Barracks → Yard 15 → 12 | 67 | 130 | 151 | 172 |
| CL Matilda | Compound → Barracks → Yard 15 → 15 | 70 | 139 | 162 | 185 |
| AN Raven | Safehouse → Hangar → 15 | 70 | 142 | 166 | 190 |
| CL Caravel (8 infantry) | Compound → Barracks → Sky Port → 25 | 90 | 148 | 167 | 186 |
| CL Clipper | Compound → Barracks → Sky Port → 15 | 80 | 149 | 172 | 195 |
| CL Recruit / Badger | Compound → Barracks → 8–10 | 48–50 | 163 | 201 | 240 |
| AN Shock Trooper | Safehouse → Redoubt → 20 | 70 | 185 | 223 | 262 |
| AN Condor | Safehouse → Hangar → Clandestine Lab 40 → 30 | 125 | 197 | 221 | 245 |
| CL Bombard shelling a spotted target | … → Ops Centre 25 → Bombard 30, + a walked spotter | 95 | ~210 | ~250 | ~290 |
| CL Avalanche | … → Yard → Academy 40 → 20 | 115 | 230 | 268 | 307 |
| CL Reverence | … → Academy → 15 | 110 | 282 | 340 | 398 |

Crossing times, `κD/v`:

| Mover | speed | D=150 | D=200 | D=250 |
|---|---|---|---|---|
| Drake | 6 | 29 s | 38 s | 48 s |
| Anarchical vehicle / Kamikaze | 4 | 43 s | 57 s | 72 s |
| Clipper, Matilda | 2.5 | 69 s | 92 s | 115 s |
| Stock Truck | 1.75 | 99 s | 131 s | 164 s |
| Irregular | 1.65 | 105 s | 139 s | 174 s |
| Foot | 1.5 | 115 s | 153 s | 192 s |
| Reverence | 1.0 | 173 s | 230 s | 288 s |

---

## What the first wave means for scouting

By equation 2, **no starting-unit scout sees a first-wave tell in time** at 150–250: they arrive
at 99–174 s, after the first wave has left. The first wave is therefore met by what a player
builds unconditionally, and the M2 test for it is whether that default is cheap and
non-exclusive (G6). **Reveals — Colonial Scan (500 dominion), Anarchical Informant (100) — are
the only t≈0 information**, which makes how soon a player holds 100–500 dominion a pacing
question. (Skirmish slot 1 starts with 5000 dominion and slot 2 with 0, which hides this.)

| Defender | Cheap default | Covers | Not covered |
|---|---|---|---|
| Colonial | Compound + Barracks + 1 SAM (1900), ready by ~45 s | air (SAM), vehicles (Badger), infantry (Recruit, Stock Truck crush) | a Sapper drop |
| Anarchical | Warlord + Irregulars, garrisoned in a Safehouse for anti-air | Drake, infantry; Matilda via Shock Trooper / Kamikaze | — |

The SAM is ready at ~45 s against the first aircraft at 108 s: comfortably early, as intended.

With the Extractor now `MEDIUM MECH`, the anti-BIO raid that was the worst case last pass is
gone: a Toxin Tractor takes 185 s on a 500-hp extractor (was 28 s), the three starting Irregulars
46 s (was 11 s). The raid role moves to EXPLOSIVE and SIEGE carriers — Badger 19 s, Matilda 15 s,
four Kamikazes, four Drake sorties — which the defaults above already answer. Far extractors now
want a SAM each against Kamikazes.

**Still intractable: the Sapper's plant.** Its 10000 EXPLOSIVE kills any structure. What is
planned ([planted-explosives](../systems/combat/planted-explosives.md)) — a quick plant, a
10 s fuse, a long recharge that caps its DPS, damage very effective against MEDIUM and fairly
effective against STRONG — is what brings it inside M2: by equation 2 the fuse is `T_ans`'s
budget, so it must exceed a defender's walk to the bomb.

### A faster Stock Truck

TODO (under consideration): Stock Truck speed 1.75 → 2.75, paid for with a long unload time.
First contact is wanted early, and the base should stay hard to contest while extractors stay
contestable.

| | D=150 | D=200 | D=250 |
|---|---|---|---|
| Truck reaches the midpoint | 31 s | 42 s | 52 s |
| Truck reaches the enemy base | 63 s | 84 s | 105 s |
| *for comparison:* Irregulars reach the midpoint | 52 s | 70 s | 87 s |
| *for comparison:* first Collective reaches the midpoint | 77 s | 84 s | 91 s |

- **First contact moves from ~100–120 s to ~30–50 s at the middle of the map**, and ~60–105 s at
  the enemy base. The truck becomes the game's first contact, and it lands while contested
  extractors are still foundations: an Anarchical builder walking to a midpoint site arrives at
  52–87 s and needs 20–45 s more to finish.
- **It fixes Colonial scouting** (equation 2). Against the Tractor and Kamikaze, `D_max` rises
  from 135 to ~380; against the Drake, from ~160 to ~330. The whole first wave becomes scoutable
  at 150–250 — by a unit that pays for scouting in dominion time.
- **It does not move the extractor ladder.** The ladder's contact time is when *armies* meet at a
  contested site; the truck carries no weapon.
- **Holding dominion throughput level.** A trip is `2d/v + load + unload`, `d` the distance to the
  Shelter. Keeping trips as long as at 1.75 takes extra unload of
  `2d · (1/1.75 − 1/2.75) ≈ 0.42 s per cell`: +17 s at 40 cells, +25 s at 60. An unload set for one
  distance breaks even only there: the faster truck then collects *more* than today from Shelters
  farther than that and *less* from nearer ones, so it also shifts which Shelters are worth
  working. This is the
  same model as the Colonial dominion knobs ([proposals](proposals.md) §The model, deferred 1.16).

---

## Income: why losses are cheap today

**Units are disposable when income outpaces what producers can spend.** Spend rate per producer:

| Producer, unit | spend/s |
|---|---|
| CL Production Yard, Matilda | 50 |
| CL Sky Port, Drake | 40 |
| CL Barracks, Badger / Recruit | 20 / 15 |
| AN Chop Shop, Toxin Tractor | 40 |
| AN Redoubt, Shock Trooper | 20 |
| AN Stronghold, Irregular | 12.5 |

On five extractors today (100/s) a Colonial player keeps a Yard, a Sky Port and a Barracks busy
nonstop, so a lost army costs only rebuild time. At the 50% cut (50/s) income covers about one
and a half producers, and a lost 3000-energy army is a minute of income. **Income ÷ producer
spend is the ratio that decides whether preservation matters.**

A pond returns its whole charge (typically ~2400) whatever the rate; the rate only sets how long
it must be held — 60 s today, 120 s at the cut.

---

## Map levers

- **The generator prices sites by rate.** A site's value is
  `site_energy_per_second × value_horizon_seconds`, read from `nt_extractor`. Halving the rate
  without halving `energy_value_per_alliance` (24000) makes it place **twice as many sites**.
- **Map size.** 150–250 between starts needs a play area of ~220–300 cells a side
  (`play_size_max` is 120) — four to six times the area. Site count follows the value budget, not
  area, so sites grow sparser; building count follows area.
- **Sites inside the reinforcement advantage.** By equation 3, a site is safe to the degree that
  `d_att − d_def` is large. "Three extractors is as greedy as it gets" is most naturally a map
  property: two starting sites at home, and every further site progressively farther toward the
  middle, where `H` falls to zero and the ladder above applies.

---

## Tech-tree and build-time options

TODO: each option is a proposal, not a decision.

### Bombard as anti-mech defence

Today the Bombard is ready at ~95 s for 3700 cumulative; the Matilda at 70 s for 4250. What
keeps the Bombard behind the Yard is 25 s and the Ops Centre, not price.

| Option | Ready | What follows |
|---|---|---|
| Status quo (requires Ops Centre) | ~95 s | The Yard is the anti-mech default; the Bombard is a mid-game investment. |
| Requires Barracks, build 40 s | ~80 s, 2500 | Ten seconds behind a Matilda for 1750 less. A defensive Colonial skips the Yard and the Yard becomes an offensive choice; Bombard + spotting Recruits is a map-wide defensive web, on Colonial identity, and Anarchical vehicle harassment loses most of its value. |
| Ops Centre 25 → 15, Bombard 30 → 20 | ~75 s | Earlier, still a three-building path; a tempo buff more than a new decision. |

### Build-time outliers

Energy per second of build: most structures sit at 40–67; the SAM, Bombard and Extractor at
25–33; **both war factories at 133**. A 2000-energy factory in 15 s is why vehicles are the
fastest threat, and at two chunks it is also the budget outlier (equation 5). Lengthening it to
30 s moves every factory threat 15 s later. The Colonial Production Yard's 400 hp is far below
every other production structure (600–1200).

### Anarchical vehicle speed

Deferred 1.7 is also a timing question: at speed 4 an Anarchical vehicle crosses 250 in 72 s, at
3 in 96 s. The whole Anarchical first wave rides on it.

---

## Structure armour

Settled this pass: the Extractor is `MEDIUM MECH` (its BIO frame was an error) and the Bombard is
`MEDIUM`.

Multiplier and single-unit time to kill a 500-hp extractor, by class:

| Unit | cost | LIGHT BIO (before) | MEDIUM MECH (now) | STRONG MECH |
|---|---|---|---|---|
| CL Recruit | 120 | ×1.00, 33 s | ×0.24, 139 s | ×0.10, 333 s |
| CL Sloop | 500 | ×1.00, 7 s | ×0.24, 28 s | ×0.10, 67 s |
| CL Badger | 200 | ×0.15, 125 s | ×1.00, 19 s | ×0.60, 31 s |
| CL Matilda | 750 | ×0.16, 69 s | ×0.75, 15 s | ×1.00, 11 s |
| CL Drake, per 4-shot sortie | 1000 | 24 sorties | 3.6 | 6.0 |
| CL Bombard, from home | 1000 | ×1.00, 10 s | ×0.75, 13 s | ×0.75, 13 s |
| AN Irregular | 100 | ×1.00, 33 s | ×0.24, 139 s | ×0.10, 333 s |
| AN Toxin Tractor | 600 | ×1.00, 28 s | ×0.15, 185 s | ×0.09, 309 s |
| AN Warlord | 250 | ×0.15, 200 s | ×1.00, 30 s | ×0.60, 50 s |
| AN MLRS | 750 | ×0.15, 139 s | ×1.00, 21 s | ×0.60, 35 s |
| AN Kamikaze, one-shot | 300 | 22 units | 3.3 | 5.6 |

TODO: **revisit what STRONG is.** The intent is Zero Hour's `StructureArmorTough`: a class that
makes key targets extra durable against *specific* weapons — ordnance, siege, super-weapons — not
a general step above MEDIUM. It is a defensive choice for command centres (killing all of them
ends the game, so they should damp early volatility) and a late-game choice for high-tech pieces.
The current STRONG column contradicts that intent in two places:

- **HIGH_EXPLOSIVE does 0.75 against STRONG**, the same as against MEDIUM, so a Bombard (250 HE
  per 5 s, global reach with spotting) kills a 3000-hp Citadel in 80 s alone and 40 s with two —
  sniping a command centre from home, which STRONG is meant to prevent. At 0.25 it would take
  240 s per gun.
- **SIEGE does 1.0 against STRONG** — *more* than against MEDIUM (0.75) — so the Matilda is the
  command-centre killer.

Which weapons should still do fine against STRONG is the open calibration. One constraint either
way: whatever damage type STRONG yields to, every faction must field it (M1). Today Anarchical
has no SIEGE, HIGH_EXPLOSIVE, CRYO, LAZER or PLASMA at all.

---

## Anarchical, this pass

- `an_tech1` (Stockpile) was priced in `ore`; now `energy`.
- The Hijacker has no weapon by design; the Sapper's offence is its plant ability; the
  Sharpshooter is deferred.
- TODO: the Juggernaut (STRONG, 90 hp, 1000) is uncalibrated.
- Anti-air comes from infantry garrisoned in the Safehouse (`an_infrastructure`, which admits BIO).
