---
title: Proposals — undecided designs
type: design-note
---

# Proposals

Designs under consideration. Nothing here is built. Goals are numbered as in the
[framework](README.md).

---

## Command-center win condition

TODO: adopt or reject. Today a commander loses on having nothing left, or on losing every
structure and queued purchase.

A commander loses when every command center is destroyed.

- Command centers are very resilient to early-game units, so a single rush cannot end the game.
- Late-game units are progressively more effective against them — sudden finishes, but only late (G3).
- Extra command centers are expensive: a lot of longevity, little marginal utility (weak units, economic units, weak faction abilities).
- An attacker focusing a command center is exposed to defenders while doing so, as in a MOBA.

**Armour: STRONG plus high HP** (settled if adopted). Vulnerability is not an armour class but
a relationship between unit cost, exposure and tech depth:

- **Sappers** do real damage but are very vulnerable alone and can be staggered, so any unit is
  a reasonable defense. TODO: give the Sapper an EXPLOSIVE weapon with a sizable cooldown
  (it has no weapon today).
- **Kamikazes** are already EXPLOSIVE; they are self-sacrificing and valued mostly for their
  area damage.
- **Low-tier tank shells** hurt command centers, but low-tier tanks are very cost-ineffective
  against anti-tank options (Zero Hour's rocket troopers).
- **Massing** either Sappers or Kamikazes into a command center may end the game; the investment
  justifies it.
- **Bombards** need the Spot investment, and a much longer cooldown (TODO), so sniping a command
  center takes several.

---

## Colonial dominion

**The caravan direction with sentences is now a written plan** — the mechanics live in
[systems/combat/colonial-dominion](../systems/combat/colonial-dominion.md) and the tasking it
needs in [systems/commands/unit-tasking](../systems/commands/unit-tasking.md). What stays here
is the model below and the knobs nobody has set.

**Chosen for the first implementation: sentences.** Pay-per-delivery stays recorded below as the
alternative it was picked over. Settled constraints: no enclosure, no gated build areas, no
energy-income variance, no distance-scaled rate; depending on Shelters is fine.

### Stock Trucks as caravans

A Stock Truck is tasked on a Shelter and cycles to a Compound on its own, like an AoE4 trade
caravan (G1).

**Proximity only matters if dominion depends on throughput.** If every captive pays over time
for as long as it is held, a delivery is a one-time fill and the route length stops mattering
once the Compound is full. Two ways to make it a flow:

1. **Pay per delivery.** The caravan model directly; occupancy stops being the dominion source.
2. **Sentences (chosen).** A captive pays over time, but only for a term, and is consumed at the
   end of it. The steady-state rate is still deliveries × value per captive, so throughput
   matters, while payout stays smooth and a Compound still holds live value (destroying it frees
   internees mid-term). Thematically this is Haustoria consuming what it takes.

**What limits the rate.** The Shelter's regeneration, per Shelter, unchanged. More Shelters
worked means more dominion; a longer route means more trucks to saturate one Shelter, each of
them exposed on the road. Payout per captive stays flat, so distance costs trucks and exposure
rather than scaling income.

#### The model

One Shelter feeding one set of Compounds. Times in seconds, distances in cells.

| Symbol | Knob | Family |
|---|---|---|
| `λ` | Shelter spawn rate (captives/s) | source |
| `P` | Shelter population cap | source |
| `c` | truck capacity | transport |
| `v` | truck speed | transport |
| `t_l` | load time per captive | transport |
| `t_u` | unload time per trip | transport |
| `n` | trucks working the Shelter | transport (investment) |
| `d` | route length, Shelter ↔ Compound | transport (placement) |
| `μ` | captives a Compound can process per second | sink |
| `K` | Compound occupancy | sink |
| `m` | Compounds | sink (investment) |
| `r`, `τ` | dominion/s per occupant, sentence length | payout |

```
truck cycle        T(d) = 2d/v + c·t_l + t_u
flow (captives/s)  Φ    = min( λ,  n·c/T(d),  m·μ )          source · transport · sink
occupancy          O(t) = min( Φ·min(t, τ),  m·K )           sentences ramp linearly over τ
dominion rate      D    = r · O
ceiling / Shelter  D_max = r · min( λ·τ, m·K )
```

(`P` does not appear in the flow: it is a BUFFER. It sets how long a Shelter tolerates absent
trucks, `P/λ`, before spawns are wasted. It also caps a single visit's take at `min(c, P)`, so
`c` in `n·c/T` is really `min(c, P)`.)

**Proximity matters only where transport is the binding term.** The saturation index is the
number of trucks needed before the Shelter, not the road, limits the flow:

```
S(d) = n* = λ · T(d) / min(c, P)
```

If `S < 1` at every distance a map offers, one truck saturates any Shelter and placement is
irrelevant.

**A load time is a distance floor.** `c·t_l` is indistinguishable from the route being
`d_eq = v·c·t_l / 2` cells longer, so a Compound hugging a Shelter behaves as one `d_eq` away.
This is the per-truck rate limiter: it bounds one truck at `≈ 1/t_l` captives/s however close
the Compound is.

**Deriving the knobs from targets rather than typing them.** Pick the truck count wanted at two
characteristic distances — `S_near` at a Compound built against the Shelter (`d_near`), `S_far`
at a typical Shelter-to-home distance (`d_far`) — and solve:

```
λ / min(c,P) = v · (S_far − S_near) / (2 · (d_far − d_near))
t_l          = ( S_near · min(c,P) / λ  −  2·d_near / v ) / c
```

Then choose `τ` (or `r`) for the per-Shelter ceiling, `K` for how many Shelters one Compound can
serve (`K ≥ λτ` means one each), and `μ` only if Compound count should gate separately.

#### What tempers an immediate high rate

The first Compound is mandatory — it is the Colonial infrastructure building and the barracks
prerequisite — and the first truck is a starting unit. Neither investment gate bites on the
opening, so the opening is tempered by:

1. **The ceiling `r·λ·τ`** against the other factions' opening dominion rates. "High" needs a
   reference curve.
2. **The ramp `τ`.** Under sentences the rate climbs linearly to its ceiling over `τ` after the
   first delivery; under pay-per-delivery there is no ramp.
3. **The distance floor `t_l`.** With `S_near > 1`, even an adjacent Compound needs more than the
   starting truck to reach the ceiling.
4. **Position, not arithmetic.** How many Shelters map generation puts in the near band (possibly
   none), and the positional bonus pulling the Compound against the buildings it supports while
   the Shelter pulls it away.

TODO: pick payout model, then targets `S_near`, `S_far`, `d_near`, `d_far` and the opening
ceiling; derive the rest.

**Truck speed: slow, decided.** The truck now sits just above infantry speed, which puts the
Colonial "slow to traverse the map" identity on the dominion route itself. The accepted costs are
the ones a fast truck was keeping: it is no longer a scout, and capturing an enemy soldier is
opportunistic rather than a chase. Its armour rises a step to pay for the roads it now lives on.

**Warlord interaction: unchanged.** Both factions draw on the same Shelter population, so an
Anarchist liberating Terrestrials starves the Colonial trucks working that Shelter — the
Shelter becomes a contested prize between them.

### A Compound benefit that varies with position

**Superseded**: the positional bonus is now a per-sentence cooldown reduction to adjacent
structures — see [systems/combat/colonial-dominion](../systems/combat/colonial-dominion.md). The
four ideas below are parked, not chosen.

Themes to draw on, from the Haustoria lore: incorporation by force, rigid hierarchy with
nominal meritocracy, consuming faster than replenishing, psychic powers and brainwashing.

1. **Penal levy.** A Compound can release an internee as a conscript at its own location,
   giving up that internee's dominion. A forward Compound is a forward reinforcement point,
   which is exactly what compensates the Colonial slow-traversal departure; internees become a
   burst-meter choice between dominion and bodies at the front (G6).
2. **Psychic surveillance.** Interned minds relay what they sense: the Compound spots ground in
   a radius scaled by occupants, so a forward Compound opens contested ground to Bombards. This
   is the thematic grounding the earlier spotting idea lacked.
3. **Haustorium reach.** Terrestrials from a Shelter within a Compound's reach walk in on their
   own, slowly; trucks remain faster and are still needed for distant Shelters and enemy
   captures. The incentive to build forward is direct. Risk: it pre-empts the Warlord at that
   Shelter, and thins out the truck's role.
4. **Searchlights.** The Compound reveals stealthed units in a radius. Small, and mostly
   matters against stealth-heavy factions.

Leaning: 1, alone or with sentences — a sentence served early becomes a conscript.
