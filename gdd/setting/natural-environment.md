---
title: Natural environment
type: setting-note
---

# Natural environment

*Setting note for [Dissent Horizon](../../CLAUDE.md).* What the battlefields are made of — the
planets, their ground, their growth and their settlements — and the game constraints every
worldbuilding choice has to fit. Drafted 2026-10-21 from a worldbuilding Q&A session.

Faction lore lives in [world-building.md](../world-building.md); resources and their lore in
[resources.md](resources.md) and [energy-economy-notes.md](energy-economy-notes.md); the aesthetic
pillars in [art-direction.md](../systems/ux/aesthetics/art-direction.md).

**Scope (Alex, 2026-10-21):** this repository touches planets and species only lightly, as far
as that tells a reader why a module is built the way it is — why visual assets are
parameterized, why a palette follows a star. Fuller worldbuilding (species backstories, planet
histories, anything that drives no code) is out of scope here and belongs in the external
worldbuilding vault that [art-direction.md](../systems/ux/aesthetics/art-direction.md) names.

---

## Hard constraints

These come from the game's mechanics and override any worldbuilding idea that conflicts with them.

1. **Every play space has extraction sites and surface lithium ponds.** The economy assumes
   both. Any fuel or planet idea that would preclude either is out.
2. **Terrain is flat and open, with discrete plateaus.** Obstruction comes from large features
   (plateaus, chasms, ridges, basins). Small details — rocks, trees, native growth — are
   decoration that navmesh baking ignores ([visual-facets.md](../systems/terrain-and-navigation/visual-facets.md)).
3. **Terrain visuals never reveal resources.** Nothing about ground, foliage or props may let a
   player infer what is under the fog of war. Colour and form vary by planet, never by what is
   buried nearby.
4. **Nothing looks hazardous unless it is.** Generated maps carry no hazard mechanics, so no
   basin fill, scar or prop may read as dangerous. What reads as hazard is the TREATMENT —
   glow, emission, bubbling, smoke, molten texture — not the hue: a red or orange brine is
   allowed when its surface and shading say still water (§Lithium ponds are cultivated). Past
   faction presence and battle damage are cosmetic.
5. **No verticality.** The isometric camera rules out tall structures that would hide pieces,
   and also rules out horizon silhouettes and skybox elements — the camera never sees a horizon.
6. **Readability first.** Time of day, weather and haze are welcome only where they never cost
   readability. Time of day is a low-priority nice-to-have.
7. **Nothing looks like Earth.** Every biome is alien, placeholders included. Today's doodads
   (conifers, broadleaf trees, flowers) are Earth placeholders to be replaced, not a baseline.

---

## Why these planets

**The factions fight over ideology, not fuel.** Belligerents fight to enforce or defend their
paradigms — the Anarchists to free others from government, and so on. A planet is contested
because people live on it, not because it is uniquely rich.

**Fusion fuel is everywhere it needs to be.** Deuterium comes from any water; lithium (bred into
tritium for D-T fusion) comes from the ponds. Helium-3 may exist in lore as an off-map source —
gas-giant skimming, airless-moon regolith — explaining why the economy is interplanetary, as long
as it never displaces the two on-map site types.

**A planet's fuel profile may shape its look** — bright salt flats on a lithium-heavy world, ice
on a water-heavy one — at the scale of the whole planet, so it never becomes a local resource tell
(constraint 3).

---

## Who lives there

- **No humans.** The populations are anthropomorphic species, each with a native homeworld.
- **Factions are multi-species.** Ideology, not species, divides them.
- **Belligerents and neutral inhabitants are the same species** — the people fought over are the
  people fighting.
- **Species barely affects unit design.** Silhouettes vary little, so piece sizes read
  consistently; species may become a cosmetic option for infantry. PLANNED, unscoped.
- **Atmospheres are breathable** for the settling species, which is what justifies standing
  settlements. TODO: species tolerant of non-Earthlike atmospheres are being considered as an
  alternate justification on some worlds.

**Battlefields are both homeworlds and colonies — one group's colony is another's homeworld.**
A single map can therefore mix the planet's native flora with crops, architecture and palette
imported from the settlers' homeworld.

---

## What the land looks like

### Overdeveloped, recent and unstable

- **Recent colonies.** Deep historical tradition is not a focus of the setting.
- **Constant regime change.** Worlds have passed between governments repeatedly; instability
  from war is part of the storytelling.
- **Overdeveloped land.** Maps should look inhabited, with little wilderness. Native flora between
  built zones is minimal — a thin fringe, ignored by navigation. Sporadic trees and rock piles,
  as the decoration pass scatters them today, fit this; **dense brush that looks impassable to a
  walking creature does not**, because it would contradict the navmesh it stands on (the same
  reason [visual-facets.md](../systems/terrain-and-navigation/visual-facets.md) keeps tall props
  off walkable ground).

That suggests a visual vocabulary of prefab and modular buildings, patchwork construction from
successive regimes, half-finished projects, re-flagged signage, and clean geometric cultivated
plots. Instability reads as layering — each regime building on or over the last — rather than as
age.

### Land-use zones

Rather than a wilderness biome layer (forest, meadow, …), the land is painted in **land-use zones**:

- farmland and terraces (more common on some maps)
- industrial
- residential
- infrastructure corridors — roads, canals, pipelines
- cultivated lithium ponds
- leftover native strips along chasm edges and plateau rims

The biome only re-skins the zones: what the crops look like, what the native growth looks like,
and the palette. Zone placement may follow believable logic — farmland near water, industry near
ponds, housing along corridors — as a cosmetic nice-to-have, like waterfalls where a river chasm
changes elevation. PLANNED: zoning as an input to the decoration pass; not yet scoped against
[map-generation.md](../systems/terrain-and-navigation/map-generation.md) pass 7.

### Lithium ponds are cultivated

The ponds are explained as cultivated by inhabitants (not necessarily the only explanation).
That matches the real thing: lithium evaporation ponds are engineered grids, colourful, obviously
artificial, and telling a player nothing they cannot already see once the pond is scouted.

**A pond's hue must be one real brine could plausibly take; the palette is otherwise broad**
(Alex, 2026-10-21). On Earth two mechanisms colour evaporation ponds, and both carry over:

- **Brine chemistry** — lithium brine runs blue and turquoise early and yellow as it
  concentrates.
- **Halophile life** — at low salinity green algae dominate (green, sometimes orange); at high
  salinity haloarchaea turn ponds pink, red and orange, and the saltiest crystallizer brine
  deep red.

So green, turquoise, yellow, orange, pink and red are all grounded. The life-driven hues follow
the planet's star exactly as foliage does (§Foliage colour has a scientific basis), so one
world's halophile reds are another's purples or near-blacks; the chemical hues do not. Red and
orange stay non-hazardous by treatment — a flat, still, glossy surface, a pale evaporite crust
at the rim, berms in a grid, never glow or motion (constraint 4).

**Colour carries no physics.** A hue need not encode what it would on Earth (concentration,
richness). The game's own signal — a charged pond fading back toward plain water as it drains
([water-bodies.md](../systems/terrain-and-navigation/water-bodies.md) §How the surface is drawn)
— is the only thing a pond's colour reports. TODO: `WaterBody.CHARGE_COLORS` is pink, ochre and
green today; replace it with a set drawn from the grounded hues above, chosen per planet, and
check the drain fade still reads when the charged hue is close to plain water's blue
(turquoise is).

### Megastructures, sparingly

Low, wide megastructures are allowed occasionally but are not a staple: dams, aqueducts, canal
locks, radiator fields, landing grids, demolished-arcology foundations, a toppled tower lying
across the map, terraced farmland. They can serve as plateaus or chasms with a built-up look.
Tall monoliths are rejected (constraint 5) — the earlier idea of buildings covering ~10% of a map
also clashed with the scale of player-built structures.

### Geology

Real formations are shaped by gravity (heavier worlds hold lower relief), erosion, tectonics,
volcanism, impacts and glaciation. The game does not need to justify each formation: like most
RTSes, maps conveniently have plateaus, chasms, ridges and ramps. Believable geology is a
nice-to-have and always cosmetic. Arid lithium basins are a happy fit — real brine flats are among
the flattest landscapes on Earth.

### Basin fills

Basins and chasms may hold things other than water — mechanically they are interchangeable with
any other navigation and placement obstruction ([water-bodies.md](../systems/terrain-and-navigation/water-bodies.md)).
Fills that read as harmless: fresh water, brine, ice sheets, salt crust, mudflats, reed or algae
marsh, fused-glass sand pans. Lithium ponds stay on the surface; other water is optional.

### Native life

- **Flora varies in form as well as colour** — broad leaves, fungal mats, succulents, crystalline
  growths. Form costs far more doodad-authoring effort than colour does, so **colour comes
  first**: the existing doodad meshes are recoloured from the biome palette (Alex, 2026-10-21).
  PLANNED, unscoped: new forms, possibly generated procedurally rather than authored —
  Spore's procedural alien flora is the reference to study first. Deferred.
- **Fauna is deferred**, possibly as an ambient easter egg. PLANNED, unscoped.

---

## Foliage colour has a scientific basis

Why Earth plants are green is not fully settled; leading explanations involve competition and the
stability of energy capture. Models of photosynthesis on other worlds predict that pigment colour
follows the host star's spectrum and how the atmosphere filters it:

- **Cool red dwarfs** — plants may absorb broadly and look dark, even near-black.
- **Sun-like stars** — green, or close to it; but purple (below) fits the same star, and green
  foliage is ruled out here anyway (constraint 7).
- **Hotter, bluer stars** — plants may reflect blue or look yellow-orange.
- The "purple Earth" hypothesis (early microbes using retinal, which absorbs green) supports purple
  as another plausible palette.

So **the star sets the palette for the whole planet**, and variation within a map is random
cosmetic noise (constraint 3). Imported crops beside native growth can carry the settlers'
homeworld palette.

---

## Biomes and palettes

### Map parameters and aesthetic parameters are separate

Decided 2026-10-21 (Alex): **a map is generated from map parameters M and dressed from aesthetic
parameters A, and the same M gives the same playable map whatever A is.** Terrain belongs to
the map because it must reproduce from the generator; a palette, lighting tint or doodad
colouring is post-processing over it. So A never feeds anything with gameplay effect —
heights, passability, sites, navigation, vision — and changing A never changes a seeded match.
This is the same line [visual-facets.md](../systems/terrain-and-navigation/visual-facets.md)
draws for decoration (cosmetic only, derived, never saved).

Where A lives — the map, the scenario, or a resource either one names — is left to whoever
builds the palette resource (Alex is agnostic; gdd/tasks.md T-117).

### Long term: a parameterized palette

PLANNED: a palette generated from the aesthetic parameters (above), from physical inputs:

| Input | Drives |
|---|---|
| Star temperature | light tint, foliage pigment |
| Atmosphere density and composition | sky tint, haze strength (capped for readability) |
| Crust composition | rock and soil hue |
| Basin fill | liquid or surface colour |

### Short term: three hand-made biomes

Built from the same inputs, so the later generator is a matter of randomizing them. The biomes
vary on several axes at once. The rows are placeholders and may be arbitrary (Alex,
2026-10-21), but **none may resemble Earth** (constraint 7): biome B's Sun-like star does not
license green foliage or an Atacama look-alike.

| | Light / star | Climate | Native flora form | Dominant land use |
|---|---|---|---|---|
| A | cool red dwarf, dim warm light | temperate, humid | dark, broad-leafed and fungal mats | farmland and terraces |
| B | Sun-like star | arid, salt basins | sparse, succulent and crystalline | lithium ponds and industry |
| C | hot blue-white star | cold, high altitude | pale yellow-orange, short and dense | residential sprawl and infrastructure |


---

## The war's footprint

Past faction presence may be pre-placed map flavour — Marxist burn scars, Anarchist
fission-contaminated ground — as long as nothing reads as a hazard (constraint 4). Battle damage
during a match (craters, scorch marks) is cosmetic only, in line with the decoration pass.
