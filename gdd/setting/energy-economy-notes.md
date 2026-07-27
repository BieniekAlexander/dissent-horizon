# Energy Economy — Design Notes

## Core decision

The primary resource of the game is **fusion fuel**, referred to generically in-game
as **energy**. It replaces the previous "ore" resource. All factions thematically
produce energy over time via fusion reactors; the differences between factions lie in
how they acquire and exploit fuel sources, not in what the resource is.

Extraction never uses harvester units. Players acquire energy by **constructing a
building on a site** — no unit-based collection loop anywhere in the economy.

## Confirmed fuel representations

### 1. Lithium ponds — fast, limited yield

Brine evaporation ponds. Fixed installations placed on designated map sites.

- **Yield profile:** high rate, finite total. Depletes and is gone.
- **Role:** early-game tempo and contested map objectives. Rewards aggression and
  early expansion; creates timed pressure since the resource has an expiry.
- **Scientific grounding:** real lithium is extracted from brine evaporation ponds —
  large, static installations that concentrate brine in place. This is a building on
  a site, not a mining operation, so it fits the no-harvester constraint natively.
  Lithium itself is stable and safe to handle.

### 2. Underground lake extraction — slow, unlimited yield

Drilled aquifer access points. Extraction of heavy water from groundwater.

- **Yield profile:** low rate, no cap, never depletes.
- **Role:** the economic backbone. Steady, reliable, worth defending long-term.
  Balances the lithium ponds' burst-and-vanish profile.
- **Scientific grounding:** deuterium occurs at roughly 1 atom per 6,400 hydrogen
  atoms in ordinary water. It is effectively inexhaustible — the constraint is
  **throughput**, not supply. You must process enormous volumes of water to
  concentrate a meaningful amount of deuterium. An aquifer has a natural recharge
  rate, so a slow but permanently sustainable extraction rate is exactly what the
  real physics predicts. "Slow and unlimited" is the scientifically correct profile
  for groundwater, not a gameplay concession.
- **Note on caps:** if per-site extraction caps are ever wanted, they are fully
  defensible — the limit is pumping/processing throughput, and multiple extractors
  on one water body compete for the same flow.

### 3. Deuterium tanks — NPC infrastructure

Pre-existing cryogenic storage belonging to the settlement's inhabitants, not built
by players. Part of the broader principle that the game world is populated with
civilizational infrastructure the players did not create.

- **Interactions:** players can **steal** the stored fuel (one-time energy payout) or
  **destroy** it for a large explosion.
- **Role:** contested map objects that reward map awareness. Creates a real decision —
  take the fuel for yourself, or deny it to the enemy and turn the site into a hazard.
  Also gives raiding factions something to do with map presence they can't hold.
- **Scientific grounding:** bulk cryogenic hydrogen-isotope storage is genuinely,
  violently explosive. Large volumes of liquid or gaseous hydrogen rupturing is a
  well-documented and severe failure mode. The explosion framing is accurate here.

## Key scientific finding: where explosions belong

Tritium storage does **not** support a large-explosion framing:

- Tritium is stored in gram-to-kilogram quantities, typically absorbed into metal
  hydride beds rather than held as pressurized gas — specifically to avoid energetic
  release.
- There is no criticality concept for fusion fuel. A container cannot be made to
  undergo fusion by damaging it.

What tritium *does* support is **contamination**:

- Tritium is a weak beta emitter with a ~12-year half-life. External exposure is
  nearly harmless (the radiation doesn't penetrate skin), but it readily forms
  tritiated water vapor that is hazardous when **inhaled or ingested**.
- It also permeates metal, making containment leaks a genuine engineering problem.

This yields a clean and accurate split, should tritium be added later:

| Substance          | Failure mode        | Affects                     |
| ------------------ | ------------------- | --------------------------- |
| Deuterium (bulk)   | Large blast         | Everything nearby           |
| Tritium (vault)    | Lingering plume     | Bio only — Mech is immune   |

The tritium half maps directly onto the existing **Frame** split (Bio / Mech) and
would give the all-mechanical Warden a scientifically earned immunity — the C&C3
Tiberium asymmetry, without inventing anything.

## Deferred / rejected

- **Power grid modeling** — transmission/distribution hierarchy, substations, EM
  interference, blackouts. Ruled out as too much mechanical depth. Note that grid
  connection for a fusion plant is conventional anyway (heat → steam → turbine), so
  nothing thematic is lost.
- **Tritium and lithium-6 breeding chain** — scientifically rich (tritium must be bred
  from lithium-6 in a reactor blanket and cannot be gathered from nature), but not
  currently part of the resource model. Available later if a scarce, decaying,
  tactical secondary resource is ever wanted.
- **Surface water bodies (rivers/lakes) as extraction sites** — superseded by
  underground lake extraction points.

## Open questions

- Whether lithium ponds and underground extraction should feed the same energy pool
  or be distinguishable in any way to the player.
- How many of each site type per map, and whether lithium pond placement should be
  symmetric (competitive fairness) or asymmetric (map identity).
- Whether stolen deuterium tanks should be re-stealable, or one-time only.
- Whether destroying a deuterium tank should leave lasting terrain effects or only a
  one-time blast.
- Per-faction interactions with each site type — currently unspecified.
