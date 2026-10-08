extends RefCounted

## VISUAL DEFAULTS: the geometry the importer bakes into a scene when nobody has decided
## it by hand — a placeholder mesh, a selection shape and an HP bar — each derived from
## what the piece IS and how big its model measures.
##
## Pure by construction. Every function takes numbers and returns a DESCRIPTOR (a type
## name plus .tscn-ready properties); nothing here touches a Node, a scene or the disk.
## That is what lets the importer and the audit report share one definition of "the
## default" rather than drifting apart, and what makes the arithmetic testable without
## booting the engine (tests/test_VisualDefaults.gd).
##
##
## BAKED, NOT DERIVED AT RUNTIME
##
## These values are written INTO the .tscn rather than computed in _ready from the model's
## AABB. The runtime alternative exists and is already in use for the floating badges
## (MeshVisual.model_top_offset), so the choice needs its reason: a baked value is visible
## in the inspector, diffable in review, and adjustable by dragging the node — which is how
## the art side of this project actually works. The cost is that a re-exported model does
## not move its own HP bar, and that cost is accepted deliberately below.
##
##
## CLEARING IS THE ONLY REBAKE SIGNAL
##
## The importer NEVER overwrites a value that is already baked. Once a scene carries an HP
## bar transform, that transform is the author's, whether they typed it or accepted ours —
## so a model that outgrows its bar stays out of sync until a developer CLEARS the baked
## value, and the next import fills the empty slot in.
##
## The alternative — rebake whenever our stamp still matches, on the theory that an
## unmodified default is nobody's opinion — silently moves art in scenes nobody opened,
## and does it on the run AFTER the model changed, so the diff lands in an unrelated
## commit. Requiring an explicit clear costs one deliberate gesture and makes every
## generated write traceable to somebody asking for it.
##
## What each slot's CLEARED state is, since "empty" differs by property:
##   HP bar transform  — absent, or an origin of exactly Vector3.ZERO. A bar at the
##                       entity's own origin is inside the model on every piece in the
##                       game, so it can never be a value somebody meant.
##   Selection shape   — absent, or a null `shape`.
##   Placeholder mesh  — the node is absent.
##
## The stamp (metadata/_visual_default_*) records WHAT was generated, which is not how
## ownership is decided — it is what lets the report separate "still the untouched
## default" from "hand-tuned", and what identifies a placeholder mesh as ours so it can be
## withdrawn once real art arrives.

## Grid cell size (Map.CELL_SIZE), mirrored rather than imported for the same reason
## SpecRules mirrors MELEE_REACH_MAX: referencing Map from the importer drags in the whole
## terrain stack, and a scene-loading side effect during validation is exactly the class of
## thing that makes an import hang. tests/test_VisualDefaults.gd pins the two together.
const CELL_SIZE: float = 1.0

## The eight kinds of piece that get their own placeholder. Aerial units are a class in
## their own right rather than a flavour of BIO/MECH: what a placeholder has to say first
## is "this thing flies", and its frame matters less than that.
enum VisualClass {
	BIO_UNIT,
	MECH_UNIT,
	AERIAL_UNIT,
	STRUCTURE,
	BALLISTIC_PROJECTILE,
	LINEAR_PROJECTILE,
	LOFTED_PROJECTILE,
	HOMING_PROJECTILE,
}

## Human-readable class names, for the audit report's grouping.
const CLASS_NAMES: Dictionary = {
	VisualClass.BIO_UNIT: "bio unit",
	VisualClass.MECH_UNIT: "mech unit",
	VisualClass.AERIAL_UNIT: "aerial unit",
	VisualClass.STRUCTURE: "structure",
	VisualClass.BALLISTIC_PROJECTILE: "ballistic projectile",
	VisualClass.LINEAR_PROJECTILE: "linear projectile",
	VisualClass.LOFTED_PROJECTILE: "lofted projectile",
	VisualClass.HOMING_PROJECTILE: "homing projectile",
}


# --------------------------------------------------------------------------- #
# Classification
# --------------------------------------------------------------------------- #
## Which placeholder a piece takes. Aerial beats frame deliberately (see VisualClass), and
## structure beats both — a building has no frame worth drawing.
static func classify_piece(frame_type: int, movement_mode: int, is_structure: bool) -> VisualClass:
	if is_structure:
		return VisualClass.STRUCTURE
	if movement_mode == Movement.Mode.FLYING or movement_mode == Movement.Mode.HOVERING:
		return VisualClass.AERIAL_UNIT
	return VisualClass.MECH_UNIT if frame_type == Defense.FrameType.MECH else VisualClass.BIO_UNIT


## An emission's placeholder class, from the motion of its FIRST phase — the one it is seen
## in flight. Read off the motion scalars rather than a trajectory name, since a name only
## survives as an import-time preset. A steered flight reads as a homing dart before an arc
## does, and a pitched lob before a plain shell.
static func classify_projectile(first_phase: Dictionary) -> VisualClass:
	if float(first_phase.get("turn_rate_degrees_per_second", 0.0)) > 0.0:
		return VisualClass.HOMING_PROJECTILE
	if float(first_phase.get("gravity_mps2", 0.0)) <= 0.0:
		return VisualClass.LINEAR_PROJECTILE
	if float(first_phase.get("launch_pitch_degrees", 0.0)) > 0.0:
		return VisualClass.LOFTED_PROJECTILE
	return VisualClass.BALLISTIC_PROJECTILE


static func is_projectile_class(visual_class: VisualClass) -> bool:
	return visual_class >= VisualClass.BALLISTIC_PROJECTILE


# --------------------------------------------------------------------------- #
# Placeholder meshes
# --------------------------------------------------------------------------- #
## The stand-in model for each class: one Godot primitive apiece, deliberately crude.
## A placeholder's whole job is to be VISIBLE and to say which class it belongs to at a
## glance — it is not concept art, and making it nicer would only make it likelier to
## survive into the build. The shapes read as: an upright figure, a blocky hull, a wedge
## that flies, a shell, a tracer streak, a mortar bomb, a dart.
##
## Sizes are in world units and pitched at the roster's existing models (measured: infantry
## about 0.4 wide by 1.0 tall, vehicles about 1.4 by 2.1 by 0.6), so a placeholder standing
## in a line of finished art is the right order of magnitude rather than a landmark.
## STRUCTURE's size is a base only — structure_mesh() replaces it from the footprint.
const PLACEHOLDER_MESHES: Dictionary = {
	VisualClass.BIO_UNIT:
	{
		"type": "CapsuleMesh",
		"props": {"radius": 0.18, "height": 0.9},
	},
	VisualClass.MECH_UNIT:
	{
		"type": "BoxMesh",
		"props": {"size": Vector3(0.9, 0.6, 1.4)},
	},
	VisualClass.AERIAL_UNIT:
	{
		"type": "PrismMesh",
		"props": {"size": Vector3(1.2, 0.25, 1.4)},
	},
	VisualClass.STRUCTURE:
	{
		"type": "BoxMesh",
		"props": {"size": Vector3(CELL_SIZE, 1.0, CELL_SIZE)},
	},
	VisualClass.BALLISTIC_PROJECTILE:
	{
		"type": "SphereMesh",
		"props": {"radius": 0.09, "height": 0.18},
	},
	VisualClass.LINEAR_PROJECTILE:
	{
		"type": "CylinderMesh",
		"props": {"top_radius": 0.03, "bottom_radius": 0.03, "height": 0.5},
	},
	VisualClass.LOFTED_PROJECTILE:
	{
		"type": "CapsuleMesh",
		"props": {"radius": 0.07, "height": 0.24},
	},
	VisualClass.HOMING_PROJECTILE:
	{
		"type": "CylinderMesh",
		"props": {"top_radius": 0.0, "bottom_radius": 0.07, "height": 0.34},
	},
}

## How tall a placeholder building stands, in world units. Independent of footprint: a
## 6x4 airfield is not six times the height of a 1x1 turret, and the roster's finished
## structures all sit near this.
const STRUCTURE_PLACEHOLDER_HEIGHT: float = 2.0


## The placeholder mesh descriptor for one piece: {"type": String, "props": Dictionary}.
## `footprint_cells` is read only for STRUCTURE, whose box takes the authored grid
## footprint rather than a fixed size — Fixture.dimensions is a better statement of how
## big a building is than any guess from its class.
static func placeholder_mesh(visual_class: VisualClass, footprint_cells: Vector2i) -> Dictionary:
	var entry: Dictionary = PLACEHOLDER_MESHES[visual_class]
	if visual_class != VisualClass.STRUCTURE:
		return entry.duplicate(true)
	var cells: Vector2i = _at_least_one_cell(footprint_cells)
	return {
		"type": entry["type"],
		"props":
		{
			"size":
			Vector3(
				float(cells.x) * CELL_SIZE, STRUCTURE_PLACEHOLDER_HEIGHT, float(cells.y) * CELL_SIZE
			)
		},
	}


## A footprint of zero cells is a scene that never set `dimensions`; one cell is what
## Structure itself defaults to, so degenerate input lands on the same answer rather than
## producing a zero-size box (see §5.1 — handle the degenerate case, don't assert it).
static func _at_least_one_cell(footprint_cells: Vector2i) -> Vector2i:
	return Vector2i(maxi(footprint_cells.x, 1), maxi(footprint_cells.y, 1))


# --------------------------------------------------------------------------- #
# Selection shape
# --------------------------------------------------------------------------- #
## The smallest a unit's click target may get, whatever its model measures. A floor rather
## than a tight fit: the roster's infantry are 0.31 to 0.48 world units wide, and a
## selection shape that honest makes them fiddly to click and nearly impossible to
## drag-select. The overhang this leaves on small models is the accepted cost.
const MIN_CLICK_RADIUS: float = 0.45
const MIN_CLICK_HEIGHT: float = 0.6


## The selection shape for one piece: {"type": String, "props": Dictionary}.
##
## Only ever a trivial primitive — a cylinder for units, a box for structures. A convex
## hull of the model would fit better and is deliberately not used: selection is a CLICK
## TARGET, not a silhouette, and a shape the player cannot predict from looking is worse
## than one that is slightly too generous.
##
## Structures take their box from the authored grid footprint, not from the mesh: the
## footprint is what the building actually occupies, and a mesh that overhangs it (a roof,
## a radar dish) should not become clickable ground.
static func selection_shape(
	visual_class: VisualClass, model_size: Vector3, footprint_cells: Vector2i
) -> Dictionary:
	if visual_class == VisualClass.STRUCTURE:
		var cells: Vector2i = _at_least_one_cell(footprint_cells)
		return {
			"type": "BoxShape3D",
			"props":
			{
				"size":
				Vector3(
					float(cells.x) * CELL_SIZE,
					maxf(model_size.y, MIN_CLICK_HEIGHT),
					float(cells.y) * CELL_SIZE
				)
			}
		}
	return {
		"type": "CylinderShape3D",
		"props":
		{
			"radius": maxf(_horizontal_radius(model_size), MIN_CLICK_RADIUS),
			"height": maxf(model_size.y, MIN_CLICK_HEIGHT),
		}
	}


## Half the model's larger horizontal extent — the radius of the smallest upright cylinder
## that contains it. The LARGER of the two axes, so a long vehicle stays fully clickable
## when it turns side-on.
static func _horizontal_radius(model_size: Vector3) -> float:
	return maxf(model_size.x, model_size.z) / 2.0


# --------------------------------------------------------------------------- #
# Hurtbox
# --------------------------------------------------------------------------- #
## The smallest hurtbox, so a sliver of a model stays hittable, in world units. Tighter than
## the click minimums: a hurtbox is what a shot strikes and every range is measured from, so
## padding it would lengthen every reach to the piece.
const MIN_HURTBOX_RADIUS: float = 0.1
const MIN_HURTBOX_HEIGHT: float = 0.2


## The volume weapons hit, and what every piece-to-piece range is measured from (Entity.hull):
## fitted to the model and STANDING ON the origin, never reaching below it — the origin is the
## piece's base, where navigation places it. Returns `{type, props, center_y}`, `center_y`
## being where the shape's centre sits above the origin (a shape is centred on its node).
##
## A FIXTURE takes a cuboid of its authored grid footprint, as its selection box does: the
## footprint is what it occupies. A MECH unit takes a cuboid of the model's extent, which
## turns with it, so its reach varies with its facing (decided 2026-10-06). A BIO unit and an
## aircraft take an upright cylinder around the model. Rules:
## gdd/systems/ux/ui/generated-visual-defaults.md §The hurtbox.
static func hurtbox_shape(
	visual_class: VisualClass,
	model_size: Vector3,
	model_top: float,
	footprint_cells: Vector2i,
	is_fixture: bool
) -> Dictionary:
	var bottom: float = maxf(model_top - model_size.y, 0.0)
	var height: float = maxf(model_top - bottom, MIN_HURTBOX_HEIGHT)
	var center_y: float = bottom + height / 2.0
	if is_fixture:
		var cells: Vector2i = _at_least_one_cell(footprint_cells)
		return _box(
			Vector3(float(cells.x) * CELL_SIZE, height, float(cells.y) * CELL_SIZE), center_y
		)
	var least: float = MIN_HURTBOX_RADIUS * 2.0
	if visual_class == VisualClass.MECH_UNIT:
		return _box(Vector3(maxf(model_size.x, least), height, maxf(model_size.z, least)), center_y)
	return {
		"type": "CylinderShape3D",
		"props":
		{"radius": maxf(_horizontal_radius(model_size), MIN_HURTBOX_RADIUS), "height": height},
		"center_y": center_y,
	}


static func _box(size: Vector3, center_y: float) -> Dictionary:
	return {"type": "BoxShape3D", "props": {"size": size}, "center_y": center_y}


# --------------------------------------------------------------------------- #
# HP bar
# --------------------------------------------------------------------------- #
## How much of the model's width the bar spans. Two thirds reads as belonging to the piece
## without implying it is as wide as the piece — at 1.0 the bar becomes a second silhouette
## and, on the roster's infantry, a wider one than the unit itself.
const HP_BAR_WIDTH_RATIO: float = 2.0 / 3.0

## The floor, so the smallest pieces still show a readable bar. Below about this the fill
## gradient stops being legible at the game's default zoom.
const HP_BAR_MIN_WIDTH: float = 0.35

## Gap between the top of the model and the bar, in world units. Non-zero so the bar clears
## its own model rather than z-fighting the highest polygon — the failure the whole baked
## position exists to prevent.
const HP_BAR_CLEARANCE: float = 0.12


## Bar width in WORLD UNITS. The scene stores a Sprite3D scale instead, which is this
## divided by the sprite's own texture-width-times-pixel-size; that conversion belongs at
## the scene boundary and is expressed exactly once there, never duplicated here.
static func hp_bar_width(model_width: float) -> float:
	return maxf(model_width * HP_BAR_WIDTH_RATIO, HP_BAR_MIN_WIDTH)


## Where the bar sits in the entity's own local space: centred over the model, clear of its
## highest point. Never Vector3.ZERO for any real model, which is what lets an origin of
## exactly zero mean "cleared, please rebake" (see the module header).
static func hp_bar_origin(model_top: float) -> Vector3:
	return Vector3(0.0, model_top + HP_BAR_CLEARANCE, 0.0)


## The bounding size of a placeholder descriptor, so the caller can derive a selection
## shape and an HP bar for a model that does not exist on disk yet. Every Godot primitive
## used here is centred on its own origin, which is why the writer lifts a grounded
## placeholder by half its height and a projectile's not at all.
static func placeholder_size(mesh_descriptor: Dictionary) -> Vector3:
	var props: Dictionary = mesh_descriptor["props"]
	match String(mesh_descriptor["type"]):
		"BoxMesh", "PrismMesh":
			return props["size"]
		"CapsuleMesh", "SphereMesh":
			var diameter: float = 2.0 * float(props["radius"])
			return Vector3(diameter, float(props["height"]), diameter)
		"CylinderMesh":
			var widest: float = maxf(float(props["top_radius"]), float(props["bottom_radius"]))
			return Vector3(2.0 * widest, float(props["height"]), 2.0 * widest)
	return Vector3.ZERO


## The stand-in for a projectile's POST-IMPACT state. Deliberately not the trajectory's own
## mesh: a burst that looks identical to the shell that caused it tells the player nothing
## happened, and the whole point of a post-impact visual is to mark the moment of impact.
## One shape for all four trajectories, because what it has to say ("this went off here")
## does not vary with how the thing arrived.
const IMPACT_BURST_RADIUS: float = 0.22


static func impact_burst_mesh() -> Dictionary:
	return {
		"type": "SphereMesh",
		"props": {"radius": IMPACT_BURST_RADIUS, "height": 2.0 * IMPACT_BURST_RADIUS},
	}
