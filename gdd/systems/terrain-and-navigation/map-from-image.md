---
title: Maps from images
type: system-note
---

# Maps from images — a palette-coded drawing seeds a map

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Built 2026-10-22 (`gdd/tasks.md` T-127): the core is `scripts/maps/image_import/`, the dock tab
`addons/map_generator/map_image_mode.gd`.

A map can be drawn as pixel art in a fixed palette and imported into a `Map`: terrain levels,
cliffs and ramps, water, lithium ponds, chasms, neutral structures and start points. The
prototype is the prologue mission 1 topology draft (`tools/missions/prologue_m1_topology_draft.gd`),
which this replaces (§Retiring the draft tool).

---

## The image is a one-shot SEED

**Importing writes a map; the map, not the image, is then primary.** After an import the terrain
is sculpted, ponds tuned and pieces moved in the editor as on any map. Re-importing replaces the
terrain with the image's, so it is a deliberate act behind the same warning as generating
(§Where it lives). There is no sidecar file of per-feature numbers: what the palette cannot say
(a pond's exact charge, a water level) is edited in the scene afterwards.

Superseded: keeping the image primary with a sidecar for those numbers, which would have made
every hand edit to the terrain a change lost on the next import.

## Where it lives

A second mode of the **Map Generator dock** ([map-generation](map-generation.md) §The dock). The
importer builds the same `GeneratedMap` the generator does, so `GeneratedMapWriter.build_map`
turns it into a `Map`. The dock's existing behaviour carries over unchanged: it imports into the
open Scenario, warns before replacing a map the Scenario already has, leaves the scene unsaved,
and offers Save map as scene.

The dock shows **the palette**: every colour, its hex code and its meaning, from the palette's
one definition in code, so the view and the importer cannot disagree.

## The palette

The meanings, layer by layer; the exact colours are in the dock's palette view, which lists the
palette's one definition in code (`MapImagePalette`), so this note carries no hex codes to fall
out of step with it.

| Layer | Meanings |
|---|---|
| terrain | levels 1 … 6, chasm, out of play |
| water | deep, shallow, lithium poor / standard / rich |
| cliffs | cliff (black, full alpha), ramp (black, half alpha: exactly 128), rough (rust) |
| structures | shelter, building, start point |

The first five levels are the swatches of the prologue sketch, so it reads the same. The colours
were proposed while scoping (2026-10-22) for Alex to change; TODO — Alex to confirm or change them (an edit to the
palette's definition moves the importer and the view together).

## The image's frame

**Pixels are grid cells.** The author draws the map turned 45° so that each pixel is one cell of
the square corner grid ([map-and-terrain-grid](map-and-terrain-grid.md)); there is no resampling.

**The play area is painted, not assumed.** An *out of play* colour marks everything beyond the
map's edge, and the play size is derived from the painted extent, so maps need not be square.
The engine's play area is a rectangle on screen (`TerrainData.play_size`), which is a diamond in
the drawing: **a painted extent that is not exactly such a diamond fails the import**, and the
report shows where its edge leaves the nearest one (Alex, 2026-10-22).

## Layers and formats

Layers by fixed name: **terrain**, **water**, **cliffs**, **structures**. A file may omit any but
terrain. **A layer with any other name fails the import** rather than being skipped, so a renamed
"Terrain 2" is never silently ignored; a reference layer has to be deleted or kept in another file.
A layer's opacity, blend mode and visibility are view settings and are ignored — pixels are read as
stored.

- **`.ora` (OpenRaster)** is the format read: a zip of one PNG per layer and an XML list of them,
  which Godot can open directly.
- **`.aseprite`** is converted to `.ora` by the importer first, written beside the source; Aseprite
  cannot export `.ora` itself. Its cels are zlib-compressed and decoded in the importer, so no
  Aseprite install is needed.
- **Flat `.png`**: one file per layer, named by suffix (`map.terrain.png`, `map.water.png`, …).

**Colours are exact.** A pixel whose colour is not in its layer's palette fails the import and
the report names where. Drawing tools that antialias must not be used.

## Terrain: levels, smoothing, cliffs and ramps

**Six levels, a level step apart**: a dock parameter defaulting to the map generator's own
`MapGenerationParams.LEVEL_STEP`, 1.0 (Alex, 2026-10-22), so imported and generated maps share
relief ([map-generation](map-generation.md) §6). The smoothing grades a step into a ramp; with
the default blur two levels apart are still walkable and three are a cliff.

Superseded: a 0.5 step, which flattened a drawing's relief to a quarter of the prologue draft's
(1.8 a level), whose look Alex preferred.

**Everything is smoothed** except where the cliffs layer says otherwise: a box blur whose radius
is a dock parameter. Smoothing eats features narrower than about two radii, which the import
report flags (§The report).

**The cliffs layer:**

| Paint | Meaning |
|---|---|
| black, full alpha | **cliff**: the region keeps its unsmoothed step — a sheer face |
| black, half alpha | **ramp**: the height is graded linearly across the region instead of blurred |
| rust | **rough**: broken ground nothing walks, at its cell's own level |

**Rough ground** (Alex, 2026-10-23) is unwalkable ground on one level — a ridge, a rough band, a
cliff's talus — which a cliff cannot draw, since a cliff needs a drop. Every corner only rough
cells share is pushed alternately up and down past the slope limit and held out of the
smoothing, the chasm floor's roughness without the sinking. A corner shared with any other cell is
left alone, so rough ground never makes its neighbours steep — and a rough patch must be two
cells wide somewhere to be built at all; a line one cell wide stays level.

**A cliff or ramp that contradicts its own geometry fails the import.** Each painted region is
checked against the drop it spans: a cliff whose drop across its width would be walkable (a
"cliff" ten cells wide) and a ramp too steep to walk (`TerrainGrid.MAX_SLOPE_DIFF`) are both
errors, named in the report.

**How that is measured: a cliff and a ramp are the same plane with opposite verdicts.** Each
8-connected region is graded linearly from the lowest height on its rim to the highest, along the
line from its low rim to its high rim, and the cell spread that grade gives is the verdict: a ramp
must come out walkable, a cliff must not. "Keeps its unsmoothed step" is what the cliff gets that
a ramp does not — the blur neither moves its corners nor samples them, so the ground at its lip and
foot is not pulled into the drop. The reading follows from the ten-cells-wide example: a raw
painted step would be sheer however wide the paint, so width only matters if the drop is spread
across it. It also means **a cliff between adjacent levels always fails**: one `elevation_step`
is under the slope limit, so it is walkable however sheer it is drawn; a cliff needs two levels.

**Seeded edge noise** displaces region edges slightly so terrain does not read as ruled
polygons, with its amplitude and seed as dock parameters (zero turns it off). Its job is the
look; an author who wants exact edges sets it to zero or sculpts afterwards.

## Water

On the water layer: **deep**, **shallow**, and **lithium** in three richness shades.

- **A body's level is its lowest bank minus a fixed offset**, the only rule that never floods
  past a bank. Each connected patch is one `WaterBody`, seeded at its lowest cell
  ([water-bodies](water-bodies.md)).
- **Deep** beds are set well past `WaterBasin.WADE_DEPTH` below the level; **shallow** beds
  within it. Shallow water between banks of two levels takes its bed from the lower bank.
- **Smoothing never decides where water is.** The level is the lowest bank's DRAWN level, not
  its smoothed height, and beds are held out of the blur: a bank beside a deep bed sags once
  smoothed, and a level read off it left every shallow ford beside a deep lake dry (found
  2026-10-22). Every shore corner is held just under its water, so each drawn water cell is wet —
  a cell-wide stream included — while a straight bank stays dry; a bank cell wedged into a
  concave corner of water, with three shore corners, floods with it. Where two beds meet, the
  shallower wins, so a ford beside deep water stays wadeable to its edge.
- **Lithium ponds** take their charge from size and richness exactly as the generator's do
  ([map-generation](map-generation.md) §3): `cell_count × richness`, capped at `pond_charge_max`,
  with the shades poor, standard and rich (60, 90, 120 per cell). The charge is edited in the
  scene afterwards when it needs to be.
- **Waterfalls** — water drawn across a level change — are deferred (Alex, 2026-10-21). Such
  water is skipped: built as dry ground at its level and listed in the report. TODO — a body has
  one surface level, so water falling between levels needs a mechanism of its own.

## Chasms

A **chasm** colour on the terrain layer sinks the ground below its rim. **Nothing may walk or land
on its floor** (Alex, 2026-10-22): a flat dry floor is passable, and a Land order sets down on any
passable cell, so troops could be flown in. The map generator never leaves a dry chasm for this
reason — every chasm is flooded with deep water, and a stretch that cannot hold water is raised
as a ridge ([map-generation](map-generation.md) §5).

**So the chasm is dry and rough** (Alex, 2026-10-22): its floor is broken into alternating high
and low corners further apart than `TerrainGrid.MAX_SLOPE_DIFF`, the ridge's crest roughness
turned downward, so every floor cell is steep — visibly broken ground that nothing walks on or
lands on. Every corner touching a chasm cell is floor, as the generator sinks a chasm, so a chasm
drawn a cell wide is still one; its walls fall in the ground cells beside it. Flooding it, as the generator does, was the alternative; deep water has its own colour
for that.

## Structures

Only **neutral shelters**, **neutral buildings** and **start points**; faction and commander
structures are placed in the scene.

- **Shelters** have a colour of their own, and each must be drawn at the shelter's exact
  footprint.
- **Buildings** have one colour; the footprint drawn picks the piece among the neutral building
  family by its dimensions (shack, square, long, large), its orientation by which way round it
  is drawn. A drawn footprint matching no building fails the import.
- **Shapes are separated**: two structures may not touch, diagonally included, so each connected
  patch is one structure.
- **A start point** is one pixel, for maps played under HEGEMONY.

Footprints are read from the piece scenes, as `GeneratedMapWriter.apply_piece_facts` does, so no
size is typed twice.

**A structure stands on one dry level**: a footprint drawn across two levels, in water or on the
cliffs layer fails the import, and an imported footprint's ground is held flat through the
smoothing. A start point must be on dry ground too. Start points are numbered in the drawing's
reading order — rows, then columns.

## Re-importing a map that has been worked on

**What the importer placed is tagged, and replaced.** Structures, start points and water bodies
from the image carry a tag (node metadata, so it saves with the scene); a re-import removes every
tagged node and places the image's afresh. Every other node on the old map — a piece placed by
hand, anything the author added — moves onto the new one. Pieces a GENERATED map placed carry no
tag, so a drawing imported over a generated map keeps them as if hand-placed.

**Hand-placed pieces the new terrain breaks are flagged, not moved.** The report lists each:
- one no longer on a valid position — the ground under it changed (a structure on a slope, or in
  water);
- one an imported structure now overlaps — the two are left overlapping, for the author to move
  the piece or change the image.

## The report

Every import ends with a report in the dock and a top-down readout image: levels, steep cells,
deep and shallow water, structures, and what failed or was flagged. Narrow features smoothing
ate, unreachable walkable components and bodies that hold no water are listed. A failed import
changes nothing in the open Scenario.

**The readout shows where each issue is** (Alex, 2026-10-23: a report line's pixel coordinates
were hard to find). Each error is numbered and named by a colour in the report, and its pixels are
marked in that colour on the readout. The readout is drawn as wide as the dock, a whole number of
screen pixels a cell, and names what lies under the pointer — the drawing pixel, what each layer
says there, and the issue marking it; **Open larger** shows it in a window of its own, zoomed with
the wheel. It is held in memory only. A drawing refused before it is fitted to the grid — a colour
not in the palette — is shown as drawn, pixel for pixel. The importer stops at the first stage
that fails, so fixing one stage's issues can show the next stage's.

> **REJECTED — writing the refused drawing back marked**, as `<name>.issues.ora` with an extra
> layer (built and removed 2026-10-23): opening a second file for every refusal was slower than
> looking in the dock.

## Testing

The importer is a pure core with a thin dock around it: palette classification, the level-to-
height pass with smoothing, cliffs and ramps, water levels and seeds, structure segmentation and
matching, and the `.ora` and `.aseprite` readers are each unit-tested against small synthetic
images (`tests/test_MapImageImporter.gd`). The dock's image tab is driven against a stand-in
Scenario in `tests/test_MapGeneratorDock.gd`: install, tagging, a failed import changing nothing,
and a re-import keeping a hand-placed node.

## Scope

Missions only for now. TODO — importing skirmish maps would add the generator's balance and
reachability checks to the import (resources and starts per player); not wanted yet.

## Retiring the draft tool

TODO — not retired yet: the importer reads the strict palette, but the sketch has not been
redrawn in it, and the retirement waits on Alex's say-so. The prologue mission 1 topology draft
is retired once the importer can read its map, with the sketch redrawn in the strict palette (`gdd/campaigns/01-prologue/m1_topology_sketch.png` carries
marks over its terrain, which only the draft tool's vote tolerates).

## Exporting a map to a drawing

The reverse of the import, built 2026-10-23: **Export map as drawing…** on
the dock's image tab writes the open Scenario's map as an `.ora` in this palette and these layers,
for an author to edit and import again. The core is `MapImageExporter`.

**An export is a fresh starting drawing** (Alex, 2026-10-22). Importing it replaces the terrain
like any import (§The image is a one-shot SEED): **sculpting does not survive**, and the export
says so. A save dialog asks for the file name and confirms before replacing a file.

> **REJECTED — an editing loop**, where a re-import keeps the map's own heights wherever the
> drawing did not change: it breaks the one-shot rule, and hand-sculpted mission terrain stays
> primary by not round-tripping it.

What the palette cannot carry, and how each is read:

- **Levels are the map's own terraces** (Alex, 2026-10-23): each height a large share of its flat
  ground stands at is a level, lowest first, so the export needs no step and the Level step
  field only matters for importing. Every other cell takes its nearest flat ground's level, so a
  slope comes back as the two levels it joined and the import's smoothing rebuilds it. The gaps
  between terraces are not kept: the lowest is level 1 whatever its height, and a drop of two
  steps comes back as one level — with its cliff where the map is steep. Past six terraces, the
  top ones are drawn as level 6 and listed.
- **Cliffs** are drawn wherever a step between levels falls across ground too steep to walk, on
  that steep cell — the lower one, where the import's corner rule puts a step. A step the map
  grades into a walkable slope gets none. **Every other steep cell of dry ground is drawn rough**:
  a ridge, a sculpted bank, the rest of a cliff's band. It comes back unwalkable but broken, not
  the smooth slope the map had.

> **REJECTED — reading heights by the Level step field** (built 2026-10-23, the same day): on a map
> built at another step it read terraces as the wrong levels without a word. The prologue draft,
> 1.8 a level, exported at the dock's 1.0 with every boundary a cliff and its plateaus at level 5.
- **An export always imports cleanly**: it imports its own drawing, removes the cliff pixels and
  structures the import refuses, and lists them.
- **Passage changes are reported** (`MapImagePassability`). The export compares where a unit can
  walk on the map with where it can on the drawing's re-import, and lists each passage the
  re-import opens between ground the map kept apart, or closes between ground it joined, at the
  patch of cells responsible; the dock shows them on a readout. An edge that only moved by a cell
  or two, and a sliver of ground under 25 cells, is not a change. A passage is for the author to
  fix in the drawing.
- **Water** reads off each body's basin as the game floods it. **Shallow means walkable**: wading
  depth over a bed no steeper than walkable ground, because the import lays shallow water on a
  flat bed. Water only wading-deep over a steep bed — the foot of a bank sculpted straight into a
  lake — is drawn deep; drawn shallow, it came back as a wadeable shelf all round its lake
  (Alex, 2026-10-23). **A lithium pond** takes the richness shade nearest its charge
  per cell, and the report lists each whose charge would change on re-import.
- **Chasms** are recognised by shape: steep dry ground sunk well below the flat ground around it.
- **Structures and start points**: only those a previous import placed (tagged), since a
  re-import keeps hand-placed pieces and would bring them back twice. Everything else is
  counted in the report as not exported.
- **Missions only**, as the import is (§Scope).

Pixelorama, which Alex expects to edit in, opens `.ora` but cannot save it; it saves `.aseprite`,
which the importer reads. TODO — not yet tried on a file Pixelorama or Aseprite itself wrote; the `.aseprite` reader is tested only on files the tests build.

**Testing.** `tests/test_MapImageExporter.gd`: a synthetic drawing imported with smoothing off
and exported again comes back as drawn away from the play area's edge — a cell there shares
corners with ground out of play — plus one test per loss above. The dock's tests export an
imported map, re-import it, and read a placed shelter back onto its drawn cells.
