class_name StructureModels
extends RefCounted

## The low-poly placeholder models of the Colonial and neutral structures, one function per
## piece, each drawing on the piece's in-game name (the spec doc's `title`) for what it should
## look like. Only meant to tell pieces apart at play time: blocky, flat-shaded, three
## materials.
##
## Every model is built from its footprint's HALF-EXTENTS in world units, centred on the
## origin with its base at y = 0 — the piece's own space, since Map.add_structure puts a
## structure's origin on its footprint's centre. A foundation slab covers the footprint, so
## the model reads as standing on exactly the cells it claims.
##
## Heights are held down by the obstruction budget (ObstructionMeasure): from the game camera
## a mass at the edge of the footprint may stand only about as high as a Recruit's shoulder,
## and only what is set back from every edge may rise higher. Hence the stepped and hipped
## shapes, and the thin bars — legs, masts, barrels — that may rise freely because they are too
## narrow to hide half a figure.
##
## The dimensions written inside each model function are that model's geometry — authored
## data, like a table's rows — and are not named; only values shared between models are.

#region Constants
## A model's surfaces. MeshVisual multiplies the team colour over every one, so the albedos
## are light and unsaturated where the tint should show (BODY) and dark where it should not
## matter (TRIM).
enum Slot { BODY, TRIM, ACCENT }

const SLOT_COLOURS: Dictionary = {
	Slot.BODY: Color(0.82, 0.82, 0.85),
	Slot.TRIM: Color(0.34, 0.36, 0.40),
	Slot.ACCENT: Color(0.55, 0.85, 0.95),
}

## The foundation slab every model stands on: inset this far from the footprint's edge, so
## neighbouring structures' slabs do not merge into one, and this high.
const FOUNDATION_INSET: float = 0.05
const FOUNDATION_HEIGHT: float = 0.1

## Sides of a "round" solid. Eight reads as round at game zoom, and is what keeps it low-poly.
const ROUND_SIDES: int = 8

## Thicknesses of the thin bars, shared so that every model's legs and masts read alike.
const THIN_BAR: float = 0.06
const POST: float = 0.1
#endregion

#region Public API


## Piece id → the function that builds its model from footprint half-extents, returning
## `{Slot: PackedVector3Array}` triangle lists.
static func catalog() -> Dictionary:
	return {
		EntityIds.CL_AIR_FIELD: sky_port,
		EntityIds.CL_COMMAND_CENTER: citadel,
		EntityIds.CL_BARRACKS: barracks,
		EntityIds.CL_DEFENSE_ANTI_AIRCRAFT: sam,
		EntityIds.CL_DEFENSE_ANTI_LIGHT: watch_tower,
		EntityIds.CL_DEFENSE_ANTI_STRUCTURE: bombard,
		EntityIds.CL_INFRASTRUCTURE: compound,
		EntityIds.CL_SUPPORT_1: annex,
		EntityIds.CL_SUPPORT_2: supply_beacon,
		EntityIds.CL_SUPPORT_3: storm_cell,
		EntityIds.CL_SUPPORT_4: cryogenic_imploder,
		EntityIds.CL_TECH_1: operations_center,
		EntityIds.CL_TECH_2: academy,
		EntityIds.CL_WAR_FACTORY: production_yard,
		EntityIds.NT_BUILDING_LARGE: large_building,
		EntityIds.NT_BUILDING_LONG: long_building,
		EntityIds.NT_BUILDING_SHACK: shack,
		EntityIds.NT_BUILDING_SQUARE: square_building,
		EntityIds.NT_EXTRACTION_SITE: extraction_site,
		EntityIds.NT_EXTRACTOR: extractor,
		EntityIds.NT_SHELTER: shelter,
		EntityIds.NT_BATTERY_RACK: battery_rack,
		EntityIds.NT_BATTERY_BANK: battery_bank,
	}


## Piece id → `{build, half}` for the environmental TOKENS (environmental-pieces.md): a token
## claims no cells, so its extents are authored here rather than read from a footprint —
## infantry-sized for what a soldier carries, vehicle-sized for what a truck does. `build` is
## called with those half-extents like every other model function. No foundation slab: a token
## stands on the ground, not on cells.
static func token_catalog() -> Dictionary:
	return {
		EntityIds.NT_POWER_CELL: {"build": power_cell, "half": Vector2(0.2, 0.2)},
		EntityIds.NT_CRYO_DEWAR: {"build": cryo_dewar, "half": Vector2(0.45, 0.7)},
		EntityIds.NT_ACTIVATION_CASK: {"build": activation_cask, "half": Vector2(0.5, 0.5)},
		EntityIds.NT_FUEL_CARTRIDGE: {"build": fuel_cartridge, "half": Vector2(0.15, 0.25)},
		EntityIds.NT_FUEL_CACHE: {"build": fuel_cache, "half": Vector2(0.5, 0.7)},
		EntityIds.NT_COURIER_POD: {"build": courier_pod, "half": Vector2(0.45, 0.7)},
		EntityIds.NT_WRECK: {"build": wreck, "half": Vector2(0.45, 0.6)},
	}


## One triangle list per slot as an ArrayMesh with a flat normal per face and one
## StandardMaterial3D per surface — MeshVisual tints only BaseMaterial3D surfaces.
static func to_mesh(parts: Dictionary) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	for slot: Slot in Slot.values():
		var triangles: PackedVector3Array = parts.get(slot, PackedVector3Array())
		if triangles.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = triangles
		arrays[Mesh.ARRAY_NORMAL] = _flat_normals(triangles)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = SLOT_COLOURS[slot]
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		mesh.surface_set_name(mesh.get_surface_count() - 1, Slot.keys()[slot].to_lower())
	return mesh


## Every slot's triangles in one list — what the obstruction measure looks at.
static func all_triangles(parts: Dictionary) -> PackedVector3Array:
	return parts.values().reduce(
		func(all: PackedVector3Array, t: PackedVector3Array) -> PackedVector3Array: return all + t,
		PackedVector3Array()
	)


#endregion

#region Colonial


## Citadel: a walled fortress — low curtain wall and corner bastions at the edge, a keep
## within, and a spired tower at the heart.
static func citadel(half: Vector2) -> Dictionary:
	var wall_in: Vector2 = half - Vector2(0.3, 0.3)
	var body: PackedVector3Array = _ring_wall(wall_in, 0.25, FOUNDATION_HEIGHT, 0.55)
	var trim: PackedVector3Array = PackedVector3Array()
	for corner: Vector2 in _corners(half - Vector2(0.6, 0.6)):
		body += MeshPrimitives.cylinder(corner, 0.4, 0.0, 0.65, ROUND_SIDES)
		trim += MeshPrimitives.frustum(corner, 0.45, 0.0, 0.65, 0.9, ROUND_SIDES)
	var keep: Vector2 = half * 0.48
	body += MeshPrimitives.box(Vector3(-keep.x, 0.0, -keep.y), Vector3(keep.x, 1.7, keep.y))
	trim += _battlements(keep, 1.7)
	body += MeshPrimitives.cylinder(Vector2.ZERO, 0.85, 1.7, 2.8, ROUND_SIDES)
	trim += MeshPrimitives.frustum(Vector2.ZERO, 0.95, 0.0, 2.8, 3.6, ROUND_SIDES)
	# The gatehouse, in the thickness of the front (+Z) wall.
	trim += MeshPrimitives.box(
		Vector3(-0.5, FOUNDATION_HEIGHT, wall_in.y - 0.35), Vector3(0.5, 0.6, wall_in.y)
	)
	var accent: PackedVector3Array = _flag(Vector3(0.0, 3.4, 0.0), 1.0)
	return _model(half, body, trim, accent)


## Sky Port: a flat apron with one runway down its long (X) axis and two parking pads either
## side of it, a slender control tower at one free corner and a low fuel bunker at another.
## The runway and pads are drawn where the scene's DockingBay markers stand — Runway at the +X
## end of the strip, Pad1..4 at (-1.5 or 0.75, ±1.25) on the 6×4 footprint — so they are
## placed as fractions of the footprint that land on those markers.
static func sky_port(half: Vector2) -> Dictionary:
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(-half.x + 0.1, FOUNDATION_HEIGHT, -0.3), Vector3(half.x - 0.1, 0.12, 0.3)
	)
	var body: PackedVector3Array = PackedVector3Array()
	for pad_x: float in [-half.x * 0.5, half.x * 0.25]:
		for pad_z: float in [-half.y * 0.625, half.y * 0.625]:
			body += MeshPrimitives.box(
				Vector3(pad_x - 0.55, FOUNDATION_HEIGHT, pad_z - 0.55),
				Vector3(pad_x + 0.55, 0.12, pad_z + 0.55)
			)
	# The control tower: a slim column and a small cab, at the +X end beyond the pads.
	var trim: PackedVector3Array = _lookout(Vector2(half.x - 0.6, -half.y + 0.6), 1.6)
	# The fuel bunker, low against the opposite corner.
	var bunker: Vector2 = Vector2(half.x - 0.55, half.y - 0.5)
	body += MeshPrimitives.box(
		Vector3(bunker.x - 0.35, 0.0, bunker.y - 0.3), Vector3(bunker.x + 0.35, 0.4, bunker.y + 0.3)
	)
	trim += MeshPrimitives.cylinder(bunker + Vector2(-0.15, 0.0), 0.12, 0.4, 0.55, 6)
	return _model(half, body, trim, accent)


## Barracks: a long hipped-roof hall with a chimney, and a flag over the drill yard.
static func barracks(half: Vector2) -> Dictionary:
	var hall: Vector2 = Vector2(half.x - 0.6, half.y - 1.1)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-hall.x, 0.0, -hall.y - 0.4), Vector3(hall.x, 0.75, hall.y - 0.4)
	)
	var trim: PackedVector3Array = MeshPrimitives.hip_roof(
		Vector3(-hall.x - 0.1, 0.75, -hall.y - 0.5),
		Vector3(hall.x + 0.1, 0.75, hall.y - 0.3),
		1.25,
		0.6
	)
	trim += MeshPrimitives.box(Vector3(0.6, 0.75, -1.0), Vector3(0.8, 1.45, -0.8))
	# The yard in front: a door and a low parade fence.
	trim += MeshPrimitives.box(
		Vector3(-0.25, 0.0, hall.y - 0.4), Vector3(0.25, 0.55, hall.y - 0.33)
	)
	for x: float in [-hall.x, hall.x]:
		trim += MeshPrimitives.box(
			Vector3(x - 0.05, 0.0, hall.y - 0.3), Vector3(x + 0.05, 0.3, half.y - 0.2)
		)
	var accent: PackedVector3Array = _flag(Vector3(half.x - 0.5, 0.0, half.y - 0.5), 1.9)
	return _model(half, body, trim, accent)


## Sam: a missile launcher — a pedestal and turntable, two launch tubes angled at the sky.
static func sam(half: Vector2) -> Dictionary:
	var body: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, 0.22, 0.0, 0.3, ROUND_SIDES
	)
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-0.2, 0.3, -0.15), Vector3(0.2, 0.42, 0.15)
	)
	var accent: PackedVector3Array = PackedVector3Array()
	for x: float in [-0.1, 0.1]:
		trim += MeshPrimitives.beam(Vector3(x, 0.4, -0.15), Vector3(x, 0.8, 0.25), 0.11)
		accent += MeshPrimitives.beam(Vector3(x, 0.79, 0.24), Vector3(x, 0.83, 0.28), 0.08)
	return _model(half, body, trim, accent)


## Watch Tower: a lookout cab on a single slim column, its gun pointing out. One column, not
## a lattice of legs: seen through the tower, three slanted legs cross a figure behind it and
## between them hide half of it.
static func watch_tower(half: Vector2) -> Dictionary:
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-0.18, 0.0, -0.18), Vector3(0.18, 0.25, 0.18)
	)
	var top: float = 1.75
	trim += _lookout(Vector2.ZERO, top)
	trim += MeshPrimitives.beam(Vector3(0.0, top + 0.08, 0.1), Vector3(0.0, top + 0.08, 0.36), 0.04)
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(-0.08, top + 0.1, 0.11), Vector3(0.08, top + 0.14, 0.14)
	)
	return _model(half, PackedVector3Array(), trim, accent)


## Bombard: a siege mortar in a sandbagged pit, its stubby barrel cocked high.
static func bombard(half: Vector2) -> Dictionary:
	var berm_radius: float = minf(half.x, half.y) - 0.35
	var body: PackedVector3Array = _polygon_wall(berm_radius, 0.35, 0.0, 0.45)
	var trim: PackedVector3Array = MeshPrimitives.cylinder(Vector2.ZERO, 0.9, 0.0, 0.3, ROUND_SIDES)
	trim += MeshPrimitives.box(Vector3(-0.45, 0.3, -0.5), Vector3(0.45, 0.75, 0.3))
	trim += MeshPrimitives.beam(Vector3(0.0, 0.6, -0.15), Vector3(0.0, 1.75, 0.45), 0.36)
	var accent: PackedVector3Array = MeshPrimitives.beam(
		Vector3(0.0, 1.72, 0.43), Vector3(0.0, 1.8, 0.47), 0.42
	)
	# Shells stacked by the gun.
	for z: float in [-1.0, -0.75]:
		accent += MeshPrimitives.cylinder(Vector2(0.9, z), 0.1, 0.0, 0.35, ROUND_SIDES)
	return _model(half, body, trim, accent)


## Compound: a prison yard — a wire fence on posts round the edge, a blockhouse inside, a
## guard post with a searchlight.
static func compound(half: Vector2) -> Dictionary:
	var fence: Vector2 = half - Vector2(0.2, 0.2)
	var trim: PackedVector3Array = _fence(fence, 0.95)
	var block: Vector2 = half * 0.48
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-block.x, 0.0, -block.y - 0.2), Vector3(block.x, 1.05, block.y - 0.2)
	)
	trim += MeshPrimitives.box(
		Vector3(-block.x - 0.05, 1.05, -block.y - 0.25),
		Vector3(block.x + 0.05, 1.15, block.y - 0.15)
	)
	# Barred windows on the front face.
	for x: float in [-0.6, 0.0, 0.6]:
		trim += MeshPrimitives.box(
			Vector3(x - 0.12, 0.55, block.y - 0.22), Vector3(x + 0.12, 0.8, block.y - 0.17)
		)
	var post: Vector2 = Vector2(fence.x - 0.45, fence.y - 0.45)
	body += MeshPrimitives.cylinder(post, 0.22, 0.0, 0.9, ROUND_SIDES)
	trim += MeshPrimitives.frustum(post, 0.26, 0.0, 0.9, 1.15, ROUND_SIDES)
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(post.x - 0.08, 0.95, post.y - 0.3), Vector3(post.x + 0.08, 1.05, post.y - 0.18)
	)
	return _model(half, body, trim, accent)


## Annex: an L-shaped office block with a second storey on its corner.
static func annex(half: Vector2) -> Dictionary:
	var inner: Vector2 = half - Vector2(0.4, 0.4)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-inner.x, 0.0, -inner.y), Vector3(inner.x, 0.62, -0.2)
	)
	body += MeshPrimitives.box(Vector3(-inner.x, 0.0, -0.2), Vector3(-0.2, 0.62, inner.y))
	body += MeshPrimitives.box(
		Vector3(-inner.x + 0.4, 0.62, -inner.y + 0.4), Vector3(-0.1, 1.15, -0.1)
	)
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-inner.x - 0.05, 0.62, -inner.y - 0.05), Vector3(inner.x + 0.05, 0.68, -0.15)
	)
	trim += MeshPrimitives.box(
		Vector3(-inner.x - 0.05, 0.62, -0.15), Vector3(-0.15, 0.68, inner.y + 0.05)
	)
	trim += MeshPrimitives.box(
		Vector3(-inner.x + 0.35, 1.15, -inner.y + 0.35), Vector3(-0.05, 1.21, -0.05)
	)
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(0.4, 0.0, -0.22), Vector3(0.9, 0.55, -0.15)
	)
	return _model(half, body, trim, accent)


## Supply Beacon: a landing pad marked out for drops, a tall mast with a beacon light, and
## supply crates waiting at its foot.
static func supply_beacon(half: Vector2) -> Dictionary:
	var pad_radius: float = minf(half.x, half.y) - 0.3
	var trim: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, pad_radius, pad_radius - 0.1, 0.0, 0.18, ROUND_SIDES, 22.5
	)
	var accent: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, pad_radius * 0.45, pad_radius * 0.4, 0.18, 0.21, ROUND_SIDES, 22.5
	)
	var mast: Vector2 = half - Vector2(0.35, 0.35)
	trim += MeshPrimitives.beam(
		Vector3(mast.x, 0.0, mast.y), Vector3(mast.x, 2.6, mast.y), THIN_BAR
	)
	accent += MeshPrimitives.frustum(mast, 0.08, 0.0, 2.6, 2.85, 4, 45.0)
	var body: PackedVector3Array = PackedVector3Array()
	for crate: Vector3 in [
		Vector3(-1.5, 0.0, 1.5), Vector3(-1.05, 0.0, 1.55), Vector3(-1.5, 0.0, 1.1)
	]:
		body += MeshPrimitives.box(
			crate - Vector3(0.18, 0.0, 0.18), crate + Vector3(0.18, 0.36, 0.18)
		)
	return _model(half, body, trim, accent)


## Storm Cell: a weather engine — a coiled column on a round base, lightning rods at its
## crown, and charged pylons standing round it.
static func storm_cell(half: Vector2) -> Dictionary:
	var base_radius: float = minf(half.x, half.y) - 0.5
	var body: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, base_radius, base_radius - 0.3, 0.0, 0.4, ROUND_SIDES, 22.5
	)
	var crown: float = 1.9
	body += MeshPrimitives.cylinder(Vector2.ZERO, 0.42, 0.4, crown, ROUND_SIDES)
	var trim: PackedVector3Array = PackedVector3Array()
	for y: float in [0.8, 1.15, 1.5]:
		trim += MeshPrimitives.cylinder(Vector2.ZERO, 0.58, y, y + 0.08, ROUND_SIDES)
	var accent: PackedVector3Array = MeshPrimitives.dome(
		Vector3(0.0, crown, 0.0), 0.45, 2, ROUND_SIDES
	)
	for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var tip: Vector3 = Vector3(cos(angle) * 0.22, crown + 0.9, sin(angle) * 0.22)
		trim += MeshPrimitives.beam(Vector3(tip.x, crown + 0.2, tip.z), tip, THIN_BAR)
	for corner: Vector2 in _corners(half - Vector2(0.45, 0.45)):
		trim += MeshPrimitives.beam(
			Vector3(corner.x, 0.0, corner.y), Vector3(corner.x, 1.3, corner.y), POST
		)
		accent += MeshPrimitives.frustum(corner, 0.1, 0.0, 1.3, 1.55, 4, 45.0)
	return _model(half, body, trim, accent)


## Cryogenic Imploder: a frosted containment dome fed by coolant tanks at its corners, a
## spike through its crown.
static func cryogenic_imploder(half: Vector2) -> Dictionary:
	var dome_radius: float = minf(half.x, half.y) - 0.9
	var accent: PackedVector3Array = MeshPrimitives.dome(
		Vector3(0.0, FOUNDATION_HEIGHT, 0.0), dome_radius, 3, ROUND_SIDES
	)
	var body: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, dome_radius + 0.15, 0.0, 0.25, ROUND_SIDES
	)
	var trim: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, 0.22, 0.0, dome_radius, dome_radius + 1.2, ROUND_SIDES
	)
	for corner: Vector2 in _corners(half - Vector2(0.55, 0.55)):
		body += MeshPrimitives.cylinder(corner, 0.3, 0.0, 0.75, ROUND_SIDES)
		trim += MeshPrimitives.cylinder(corner, 0.32, 0.75, 0.82, ROUND_SIDES)
		var toward: Vector2 = corner.normalized() * (dome_radius * 0.75)
		trim += MeshPrimitives.beam(
			Vector3(corner.x, 0.5, corner.y), Vector3(toward.x, 0.5, toward.y), 0.1
		)
	return _model(half, body, trim, accent)


## Operations Center: a sloped-wall command bunker under a radar dish and an antenna mast.
static func operations_center(half: Vector2) -> Dictionary:
	var bunker: float = minf(half.x, half.y) - 0.3
	var body: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, bunker * sqrt(2.0), (bunker - 0.45) * sqrt(2.0), 0.0, 0.75, 4, 45.0
	)
	var roof: float = 0.82
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-bunker + 0.4, 0.75, -bunker + 0.4), Vector3(bunker - 0.4, roof, bunker - 0.4)
	)
	trim += MeshPrimitives.box(
		Vector3(-0.35, 0.0, bunker - 0.25), Vector3(0.35, 0.5, bunker + 0.05)
	)
	var dish_at: Vector2 = Vector2(0.45, 0.2)
	trim += MeshPrimitives.cylinder(dish_at, 0.06, roof, 1.25, ROUND_SIDES)
	var dish: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, 0.06, 0.38, 0.0, 0.14, ROUND_SIDES
	)
	var tilt: Transform3D = Transform3D(
		Basis(Vector3.RIGHT, deg_to_rad(-35.0)), Vector3(dish_at.x, 1.2, dish_at.y)
	)
	var accent: PackedVector3Array = MeshPrimitives.transformed(dish, tilt)
	trim += MeshPrimitives.beam(Vector3(-0.6, roof, -0.6), Vector3(-0.6, 2.3, -0.6), 0.04)
	return _model(half, body, trim, accent)


## Academy: a columned hall under a hipped roof, a small dome over its middle.
static func academy(half: Vector2) -> Dictionary:
	var hall: Vector2 = Vector2(half.x - 0.7, half.y - 1.1)
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-hall.x - 0.3, 0.0, -hall.y - 0.5), Vector3(hall.x + 0.3, 0.22, hall.y + 0.9)
	)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-hall.x, 0.0, -hall.y - 0.3), Vector3(hall.x, 0.85, hall.y + 0.2)
	)
	# The portico: a row of columns before the front (+Z) face.
	var columns: int = 6
	for i: int in range(columns):
		var x: float = lerpf(-hall.x + 0.1, hall.x - 0.1, float(i) / (columns - 1))
		body += MeshPrimitives.cylinder(Vector2(x, hall.y + 0.6), 0.08, 0.22, 0.85, 6)
	trim += MeshPrimitives.hip_roof(
		Vector3(-hall.x - 0.12, 0.85, -hall.y - 0.42),
		Vector3(hall.x + 0.12, 0.85, hall.y + 0.75),
		1.3,
		0.5
	)
	body += MeshPrimitives.cylinder(Vector2.ZERO, 0.45, 1.0, 1.4, ROUND_SIDES)
	var accent: PackedVector3Array = MeshPrimitives.dome(
		Vector3(0.0, 1.4, 0.0), 0.45, 2, ROUND_SIDES
	)
	return _model(half, body, trim, accent)


## Production Yard: a sawtooth-roofed workshop along the back, an open yard in front spanned
## by a gantry crane, and a vehicle chassis on the stand.
static func production_yard(half: Vector2) -> Dictionary:
	var back: float = -half.y + 0.25
	var shop_front: float = back + 1.1
	var shop_x: float = half.x - 0.25
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-shop_x, 0.0, back), Vector3(shop_x, 0.6, shop_front)
	)
	var trim: PackedVector3Array = PackedVector3Array()
	# Sawtooth roof: three wedges, each rising toward the yard.
	var teeth: int = 3
	for i: int in range(teeth):
		var x0: float = lerpf(-shop_x, shop_x, float(i) / teeth)
		var x1: float = lerpf(-shop_x, shop_x, float(i + 1) / teeth)
		trim += _shed_roof(Vector3(x0, 0.6, back), Vector3(x1, 0.6, shop_front), 0.95)
	# The gantry: two legs either side of the yard, a girder across.
	var gantry_z: float = 0.7
	for x: float in [-shop_x + 0.1, shop_x - 0.1]:
		trim += MeshPrimitives.beam(Vector3(x, 0.0, gantry_z), Vector3(x, 1.7, gantry_z), THIN_BAR)
	trim += MeshPrimitives.beam(
		Vector3(-shop_x + 0.05, 1.7, gantry_z), Vector3(shop_x - 0.05, 1.7, gantry_z), THIN_BAR
	)
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(0.34, 1.3, gantry_z - 0.06), Vector3(0.46, 1.67, gantry_z + 0.06)
	)
	# The chassis on the stand below the crane.
	body += MeshPrimitives.box(Vector3(-0.5, 0.1, 0.3), Vector3(0.5, 0.45, 1.0))
	trim += MeshPrimitives.box(Vector3(-0.2, 0.45, 0.45), Vector3(0.2, 0.65, 0.8))
	return _model(half, body, trim, accent)


#endregion

#region Neutral


## Large building: a stepped tower block, its top tier carrying a water tank.
static func large_building(half: Vector2) -> Dictionary:
	var body: PackedVector3Array = PackedVector3Array()
	var trim: PackedVector3Array = PackedVector3Array()
	var tiers: Array[Vector2] = [Vector2(0.2, 0.6), Vector2(0.8, 1.25), Vector2(1.5, 1.85)]
	var floor_y: float = 0.0
	for tier: Vector2 in tiers:
		var extent: Vector2 = half - Vector2(tier.x, tier.x)
		body += MeshPrimitives.box(
			Vector3(-extent.x, floor_y, -extent.y), Vector3(extent.x, tier.y, extent.y)
		)
		trim += _window_bands(extent, (floor_y + tier.y) * 0.5)
		floor_y = tier.y
	var tank_at: Vector2 = Vector2(half.x * 0.35, 0.0)
	trim += MeshPrimitives.cylinder(tank_at, 0.3, floor_y, floor_y + 0.45, ROUND_SIDES)
	return _model(half, body, trim, PackedVector3Array())


## Long building: a long low hall under a hipped roof.
static func long_building(half: Vector2) -> Dictionary:
	var walls: Vector2 = half - Vector2(0.15, 0.15)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-walls.x, 0.0, -walls.y), Vector3(walls.x, 0.6, walls.y)
	)
	var trim: PackedVector3Array = MeshPrimitives.hip_roof(
		Vector3(-walls.x - 0.05, 0.6, -walls.y - 0.05),
		Vector3(walls.x + 0.05, 0.6, walls.y + 0.05),
		1.45,
		walls.x + 0.05
	)
	trim += _window_bands(walls, 0.35)
	return _model(half, body, trim, PackedVector3Array())


## Shack: a single room under a low roof, a stovepipe, a crate by the door.
static func shack(half: Vector2) -> Dictionary:
	var walls: Vector2 = half - Vector2(0.2, 0.2)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-walls.x, 0.0, -walls.y), Vector3(walls.x, 0.55, walls.y - 0.25)
	)
	var trim: PackedVector3Array = MeshPrimitives.hip_roof(
		Vector3(-walls.x - 0.08, 0.55, -walls.y - 0.08),
		Vector3(walls.x + 0.08, 0.55, walls.y - 0.17),
		0.9,
		0.3
	)
	trim += MeshPrimitives.cylinder(Vector2(0.35, -0.3), 0.05, 0.6, 1.2, 6)
	trim += MeshPrimitives.box(
		Vector3(-0.15, 0.0, walls.y - 0.27), Vector3(0.15, 0.45, walls.y - 0.22)
	)
	body += MeshPrimitives.box(Vector3(0.3, 0.0, walls.y - 0.15), Vector3(0.6, 0.25, walls.y + 0.1))
	return _model(half, body, trim, PackedVector3Array())


## Building: a square two-storey block with a parapet and rooftop plant.
static func square_building(half: Vector2) -> Dictionary:
	var lower: Vector2 = half - Vector2(0.2, 0.2)
	var upper: Vector2 = half - Vector2(0.75, 0.75)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-lower.x, 0.0, -lower.y), Vector3(lower.x, 0.65, lower.y)
	)
	body += MeshPrimitives.box(Vector3(-upper.x, 0.65, -upper.y), Vector3(upper.x, 1.25, upper.y))
	var trim: PackedVector3Array = _ring_wall(lower, 0.08, 0.65, 0.75)
	trim += _window_bands(lower, 0.35) + _window_bands(upper, 0.95)
	trim += MeshPrimitives.box(Vector3(-0.4, 1.25, -0.3), Vector3(0.2, 1.5, 0.2))
	return _model(half, body, trim, PackedVector3Array())


## Extraction Site: an outcrop of energy crystals breaking through a scorched patch.
static func extraction_site(half: Vector2) -> Dictionary:
	var trim: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, minf(half.x, half.y) - 0.1, minf(half.x, half.y) - 0.3, 0.0, 0.06, ROUND_SIDES
	)
	var accent: PackedVector3Array = PackedVector3Array()
	var crystals: Array[Vector4] = [
		Vector4(0.0, 0.0, 0.22, 0.95),
		Vector4(0.35, 0.2, 0.15, 0.6),
		Vector4(-0.3, 0.25, 0.14, 0.5),
		Vector4(-0.15, -0.35, 0.17, 0.7),
		Vector4(0.3, -0.3, 0.12, 0.45),
	]
	for crystal: Vector4 in crystals:
		accent += MeshPrimitives.frustum(
			Vector2(crystal.x, crystal.y), crystal.z, 0.0, 0.0, crystal.w, 5, crystal.x * 90.0
		)
	return {Slot.TRIM: trim, Slot.ACCENT: accent}


## Extractor: a drilling derrick over the deposit, with a pump house and a storage tank.
static func extractor(half: Vector2) -> Dictionary:
	var trim: PackedVector3Array = PackedVector3Array()
	var top: float = 2.0
	# Three legs, each hairline thin: a figure behind the derrick sees through it.
	for leg: int in range(3):
		var foot: Vector2 = Vector2.from_angle(TAU * leg / 3.0) * (minf(half.x, half.y) - 0.3)
		trim += MeshPrimitives.beam(
			Vector3(foot.x, 0.0, foot.y), Vector3(foot.x * 0.15, top, foot.y * 0.15), 0.04
		)
	trim += MeshPrimitives.box(Vector3(-0.08, top, -0.08), Vector3(0.08, top + 0.15, 0.08))
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-0.45, 0.0, 0.15), Vector3(-0.05, 0.3, 0.5)
	)
	var accent: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2(0.35, -0.45), 0.15, 0.0, 0.35, ROUND_SIDES
	)
	return _model(half, body, trim, accent)


## Shelter: a turfed-over bunker mound with a doorway and vent pipes.
static func shelter(half: Vector2) -> Dictionary:
	var mound: float = minf(half.x, half.y) - 0.15
	var body: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, mound, mound * 0.55, 0.0, 0.7, ROUND_SIDES, 22.5
	)
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-0.3, 0.0, mound * 0.55), Vector3(0.3, 0.5, mound - 0.05)
	)
	for vent: Vector2 in [Vector2(-0.35, -0.3), Vector2(0.3, -0.4)]:
		trim += MeshPrimitives.cylinder(vent, 0.07, 0.6, 1.05, 6)
		trim += MeshPrimitives.cylinder(vent, 0.11, 1.05, 1.12, 6)
	return _model(half, body, trim, PackedVector3Array())


#endregion

#region Environmental pieces


## Battery Rack: an open frame of posts and two shelves, each holding a row of storage cells,
## a bus bar running along the top.
static func battery_rack(half: Vector2) -> Dictionary:
	var frame: Vector2 = half - Vector2(0.18, 0.18)
	var trim: PackedVector3Array = PackedVector3Array()
	for corner: Vector2 in _corners(frame):
		trim += MeshPrimitives.box(
			Vector3(corner.x - POST * 0.5, 0.0, corner.y - POST * 0.5),
			Vector3(corner.x + POST * 0.5, 0.8, corner.y + POST * 0.5)
		)
	var body: PackedVector3Array = PackedVector3Array()
	for shelf: float in [0.26, 0.54]:
		trim += MeshPrimitives.box(
			Vector3(-frame.x, shelf, -frame.y), Vector3(frame.x, shelf + 0.04, frame.y)
		)
		for x: float in [-0.2, 0.0, 0.2]:
			for z: float in [-0.12, 0.12]:
				body += MeshPrimitives.cylinder(Vector2(x, z), 0.06, shelf + 0.04, shelf + 0.24, 6)
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(-frame.x, 0.8, -0.04), Vector3(frame.x, 0.86, 0.04)
	)
	return _model(half, body, trim, accent)


## Battery Bank: a shielded block with cooling fins down its back and a conduit along its side,
## a charge strip glowing on its face.
static func battery_bank(half: Vector2) -> Dictionary:
	var block: Vector2 = half - Vector2(0.25, 0.25)
	var body: PackedVector3Array = MeshPrimitives.box(
		Vector3(-block.x, 0.0, -block.y), Vector3(block.x, 0.7, block.y)
	)
	var trim: PackedVector3Array = PackedVector3Array()
	for x: float in _spaced(-block.x + 0.15, block.x - 0.15, 0.3):
		trim += MeshPrimitives.box(
			Vector3(x - 0.04, 0.7, -block.y + 0.1), Vector3(x + 0.04, 0.95, -0.1)
		)
	trim += MeshPrimitives.cylinder(
		Vector2(block.x - 0.3, block.y - 0.3), 0.2, 0.7, 1.0, ROUND_SIDES
	)
	trim += MeshPrimitives.beam(
		Vector3(-block.x - 0.12, 0.3, -block.y), Vector3(-block.x - 0.12, 0.3, block.y), 0.08
	)
	var accent: PackedVector3Array = MeshPrimitives.box(
		Vector3(-block.x + 0.2, 0.3, block.y), Vector3(block.x - 0.2, 0.4, block.y + 0.03)
	)
	return _model(half, body, trim, accent)


## Power Cell: a man-portable storage canister — an upright drum between two end caps, a coil
## band glowing round its middle and a terminal post on top.
static func power_cell(half: Vector2) -> Dictionary:
	var radius: float = minf(half.x, half.y) - 0.03
	var body: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, radius, 0.06, 0.78, ROUND_SIDES
	)
	var trim: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, radius + 0.02, 0.0, 0.06, ROUND_SIDES
	)
	trim += MeshPrimitives.cylinder(Vector2.ZERO, radius + 0.02, 0.78, 0.84, ROUND_SIDES)
	trim += MeshPrimitives.cylinder(Vector2.ZERO, 0.04, 0.84, 0.95, 6)
	var accent: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, radius + 0.015, 0.36, 0.5, ROUND_SIDES
	)
	return {Slot.BODY: body, Slot.TRIM: trim, Slot.ACCENT: accent}


## Cryo Dewar: a horizontal tank on a cradle, frosted end caps and a valve stack on top.
static func cryo_dewar(half: Vector2) -> Dictionary:
	var radius: float = half.x - 0.08
	var length: float = half.y * 2.0 - 0.3
	var lying: Transform3D = Transform3D(
		Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, radius + 0.15, 0.0)
	)
	var body: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.cylinder(Vector2.ZERO, radius, -length * 0.5, length * 0.5, ROUND_SIDES),
		lying
	)
	var accent: PackedVector3Array = MeshPrimitives.transformed(
		(
			MeshPrimitives.cylinder(
				Vector2.ZERO, radius + 0.02, -length * 0.5 - 0.06, -length * 0.5, ROUND_SIDES
			)
			+ MeshPrimitives.cylinder(
				Vector2.ZERO, radius + 0.02, length * 0.5, length * 0.5 + 0.06, ROUND_SIDES
			)
		),
		lying
	)
	var trim: PackedVector3Array = PackedVector3Array()
	for z: float in [-length * 0.3, length * 0.3]:
		trim += MeshPrimitives.box(Vector3(-half.x, 0.0, z - 0.06), Vector3(half.x, 0.2, z + 0.06))
	trim += MeshPrimitives.cylinder(
		Vector2(0.0, 0.0), 0.06, radius * 2.0 + 0.1, radius * 2.0 + 0.35, 6
	)
	trim += MeshPrimitives.beam(
		Vector3(-0.15, radius * 2.0 + 0.3, 0.0), Vector3(0.15, radius * 2.0 + 0.3, 0.0), 0.05
	)
	return {Slot.BODY: body, Slot.TRIM: trim, Slot.ACCENT: accent}


## Activation Cask: a squat thick-walled drum on a pallet, cooling fins round it, a hazard band
## below its lid.
static func activation_cask(half: Vector2) -> Dictionary:
	var radius: float = minf(half.x, half.y) - 0.1
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.1, half.y)
	)
	var body: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, radius, 0.1, 0.75, ROUND_SIDES
	)
	trim += MeshPrimitives.frustum(
		Vector2.ZERO, radius + 0.04, radius - 0.1, 0.75, 0.88, ROUND_SIDES
	)
	for fin: int in range(4):
		var direction: Vector2 = Vector2.from_angle(TAU * fin / 4.0)
		var start: Vector3 = Vector3(direction.x, 0.2, direction.y) * (radius - 0.02)
		var end: Vector3 = Vector3(direction.x, 0.2, direction.y) * (radius + 0.08)
		trim += MeshPrimitives.beam(start, end, 0.08)
		trim += MeshPrimitives.beam(start + Vector3.UP * 0.4, end + Vector3.UP * 0.4, 0.08)
	var accent: PackedVector3Array = MeshPrimitives.cylinder(
		Vector2.ZERO, radius + 0.01, 0.6, 0.7, ROUND_SIDES
	)
	return {Slot.BODY: body, Slot.TRIM: trim, Slot.ACCENT: accent}


## Fuel Cartridge: a hydride cartridge lying on the ground — a short capped cylinder with a grip.
static func fuel_cartridge(half: Vector2) -> Dictionary:
	var radius: float = half.x - 0.02
	var length: float = half.y * 2.0 - 0.12
	var lying: Transform3D = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, radius, 0.0))
	var body: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.cylinder(Vector2.ZERO, radius, -length * 0.5, length * 0.5, ROUND_SIDES),
		lying
	)
	var accent: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.cylinder(Vector2.ZERO, radius * 0.7, length * 0.5, length * 0.5 + 0.05, 6),
		lying
	)
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-0.03, radius * 2.0 - 0.02, -0.08), Vector3(0.03, radius * 2.0 + 0.05, 0.08)
	)
	return {Slot.BODY: body, Slot.TRIM: trim, Slot.ACCENT: accent}


## Fuel Cache: a pallet of cartridges, two layers deep, strapped down.
static func fuel_cache(half: Vector2) -> Dictionary:
	var trim: PackedVector3Array = MeshPrimitives.box(
		Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.08, half.y)
	)
	var radius: float = 0.13
	var length: float = half.y * 2.0 - 0.2
	var body: PackedVector3Array = PackedVector3Array()
	for layer: int in range(2):
		for x: float in [-0.3, 0.0, 0.3]:
			var lying: Transform3D = Transform3D(
				Basis(Vector3.RIGHT, -PI * 0.5),
				Vector3(x, 0.08 + radius + layer * radius * 2.0, 0.0)
			)
			body += MeshPrimitives.transformed(
				MeshPrimitives.cylinder(Vector2.ZERO, radius, -length * 0.5, length * 0.5, 6), lying
			)
	var top: float = 0.08 + radius * 4.0
	var accent: PackedVector3Array = PackedVector3Array()
	for z: float in [-length * 0.3, length * 0.3]:
		accent += MeshPrimitives.box(
			Vector3(-half.x + 0.05, 0.0, z - 0.03), Vector3(half.x - 0.05, top + 0.03, z + 0.03)
		)
	return {Slot.BODY: body, Slot.TRIM: trim, Slot.ACCENT: accent}


## Courier Pod: a drop capsule that came down nose-first and leans where it landed — a tapered
## shell on three fins, its beacon still lit, on a scorched patch.
static func courier_pod(half: Vector2) -> Dictionary:
	var scorch: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO,
		minf(half.x, half.y) - 0.02,
		minf(half.x, half.y) - 0.15,
		0.0,
		0.03,
		ROUND_SIDES
	)
	# Leaning along +Z: the nose is in the ground at the -Z end, the tail up over +Z.
	var lean: Transform3D = Transform3D(Basis(Vector3.RIGHT, PI * 0.33), Vector3(0.0, 0.05, -0.3))
	var shell: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.frustum(Vector2.ZERO, 0.08, 0.26, 0.0, 0.95, ROUND_SIDES), lean
	)
	var fins: PackedVector3Array = PackedVector3Array()
	for fin: int in range(3):
		var direction: Vector2 = Vector2.from_angle(TAU * fin / 3.0 + PI * 0.5)
		fins += MeshPrimitives.transformed(
			MeshPrimitives.beam(
				Vector3(direction.x, 0.75, direction.y) * 0.26,
				Vector3(direction.x, 0.9, direction.y) * 0.4,
				0.05
			),
			lean
		)
	var accent: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.cylinder(Vector2.ZERO, 0.06, 0.95, 1.05, 6), lean
	)
	return {Slot.BODY: shell, Slot.TRIM: scorch + fins, Slot.ACCENT: accent}


## Wreck: what a destroyed vehicle leaves — a hull slewed nose-down on a scorched patch, its
## turret knocked askew, a road wheel thrown clear and the fire still glowing inside.
static func wreck(half: Vector2) -> Dictionary:
	var scorch: PackedVector3Array = MeshPrimitives.frustum(
		Vector2.ZERO, minf(half.x, half.y) - 0.02, minf(half.x, half.y) - 0.12, 0.0, 0.03, ROUND_SIDES
	)
	# Slewed about Y and pitched nose-down, so it reads as fallen rather than parked.
	var slew: Transform3D = Transform3D(
		Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.12), Vector3(0.0, 0.03, 0.0)
	)
	var hull: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.box(Vector3(-0.22, 0.0, -0.36), Vector3(0.22, 0.2, 0.32)), slew
	)
	var turret: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.box(Vector3(-0.1, 0.2, -0.08), Vector3(0.14, 0.31, 0.14)),
		slew * Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.FORWARD, 0.25), Vector3.ZERO)
	)
	var lying_wheel: Transform3D = Transform3D(
		Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.32, 0.03, 0.38)
	)
	var wheel: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.cylinder(Vector2.ZERO, 0.08, -0.04, 0.04, 6), lying_wheel
	)
	var embers: PackedVector3Array = MeshPrimitives.transformed(
		MeshPrimitives.box(Vector3(-0.12, 0.2, -0.3), Vector3(0.08, 0.23, -0.14)), slew
	)
	return {Slot.BODY: hull + turret, Slot.TRIM: scorch + wheel, Slot.ACCENT: embers}


#endregion

#region Private helpers


## One outward normal per vertex, shared by its triangle's three: flat shading. Triangles are
## clockwise seen from outside (MeshPrimitives), so (c - a) × (b - a) points out.
static func _flat_normals(triangles: PackedVector3Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in range(0, triangles.size(), 3):
		var a: Vector3 = triangles[i]
		var normal: Vector3 = (triangles[i + 2] - a).cross(triangles[i + 1] - a).normalized()
		out.append_array(PackedVector3Array([normal, normal, normal]))
	return out


## A model's slots, standing on its foundation slab.
static func _model(
	half: Vector2, body: PackedVector3Array, trim: PackedVector3Array, accent: PackedVector3Array
) -> Dictionary:
	var slab: Vector2 = half - Vector2(FOUNDATION_INSET, FOUNDATION_INSET)
	var foundation: PackedVector3Array = MeshPrimitives.box(
		Vector3(-slab.x, 0.0, -slab.y), Vector3(slab.x, FOUNDATION_HEIGHT, slab.y)
	)
	return {Slot.BODY: body, Slot.TRIM: foundation + trim, Slot.ACCENT: accent}


## The four corners of a rectangle of half-extents `half`.
static func _corners(half: Vector2) -> Array[Vector2]:
	return [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	]


## Four walls of `thickness` standing just inside the rectangle of half-extents `outer`.
static func _ring_wall(
	outer: Vector2, thickness: float, bottom: float, top: float
) -> PackedVector3Array:
	var inner: Vector2 = outer - Vector2(thickness, thickness)
	return (
		MeshPrimitives.box(Vector3(-outer.x, bottom, -outer.y), Vector3(outer.x, top, -inner.y))
		+ MeshPrimitives.box(Vector3(-outer.x, bottom, inner.y), Vector3(outer.x, top, outer.y))
		+ MeshPrimitives.box(Vector3(-outer.x, bottom, -inner.y), Vector3(-inner.x, top, inner.y))
		+ MeshPrimitives.box(Vector3(inner.x, bottom, -inner.y), Vector3(outer.x, top, inner.y))
	)


## Merlons along the edge of a flat roof at `height`.
static func _battlements(half: Vector2, height: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var merlon: float = 0.25
	var spacing: float = 0.6
	for x: float in _spaced(-half.x + merlon * 0.5, half.x - merlon * 0.5, spacing):
		for z: float in [-half.y, half.y - merlon]:
			out += MeshPrimitives.box(
				Vector3(x - merlon * 0.5, height, z),
				Vector3(x + merlon * 0.5, height + 0.2, z + merlon)
			)
	for z: float in _spaced(-half.y + merlon * 1.5, half.y - merlon * 1.5, spacing):
		for x: float in [-half.x, half.x - merlon]:
			out += MeshPrimitives.box(
				Vector3(x, height, z - merlon * 0.5),
				Vector3(x + merlon, height + 0.2, z + merlon * 0.5)
			)
	return out


## A ring of `ROUND_SIDES` wall segments of `thickness` centred on `radius` round the
## origin — a sandbag berm.
static func _polygon_wall(
	radius: float, thickness: float, bottom: float, top: float
) -> PackedVector3Array:
	var outer: PackedVector2Array = MeshPrimitives.regular_polygon(
		Vector2.ZERO, radius + thickness * 0.5, ROUND_SIDES, 22.5
	)
	var inner: PackedVector2Array = MeshPrimitives.regular_polygon(
		Vector2.ZERO, radius - thickness * 0.5, ROUND_SIDES, 22.5
	)
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in range(ROUND_SIDES):
		var j: int = (i + 1) % ROUND_SIDES
		out += MeshPrimitives.prism(
			PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]), bottom, top
		)
	return out


## A wire fence on posts round the rectangle of half-extents `half`: posts, and a top and a
## middle rail.
static func _fence(half: Vector2, height: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var spacing: float = 0.6
	var corners: Array[Vector2] = _corners(half)
	for i: int in range(corners.size()):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var posts: int = maxi(1, ceili(a.distance_to(b) / spacing))
		for k: int in range(posts):
			var p: Vector2 = a.lerp(b, float(k) / posts)
			out += MeshPrimitives.beam(Vector3(p.x, 0.0, p.y), Vector3(p.x, height, p.y), THIN_BAR)
		for rail: float in [height * 0.5, height - 0.03]:
			out += MeshPrimitives.beam(Vector3(a.x, rail, a.y), Vector3(b.x, rail, b.y), 0.03)
	return out


## A lookout: a slim column from the ground to `height` at `at`, a small cab on it and a
## pointed roof. Kept this slim because a figure behind it sees past the column on both sides.
static func _lookout(at: Vector2, height: float) -> PackedVector3Array:
	return (
		MeshPrimitives.cylinder(at, 0.045, 0.0, height, 6)
		+ MeshPrimitives.cylinder(at, 0.14, height, height + 0.16, ROUND_SIDES)
		+ MeshPrimitives.frustum(at, 0.17, 0.0, height + 0.16, height + 0.28, ROUND_SIDES)
	)


## A pole of `height` standing on `foot`, with a small flag at its head.
static func _flag(foot: Vector3, height: float) -> PackedVector3Array:
	var head: Vector3 = foot + Vector3(0.0, height, 0.0)
	return (
		MeshPrimitives.beam(foot, head, 0.04)
		+ MeshPrimitives.box(head + Vector3(0.0, -0.3, -0.01), head + Vector3(0.4, -0.05, 0.01))
	)


## A shed roof over the rectangle `from`–`to` at eaves height `from.y`, rising to `peak` along
## its +Z edge — one tooth of a sawtooth roof.
static func _shed_roof(from: Vector3, to: Vector3, peak: float) -> PackedVector3Array:
	var outline: PackedVector2Array = PackedVector2Array(
		[Vector2(from.z, from.y), Vector2(to.z, from.y), Vector2(to.z, peak)]
	)
	# A triangle in the (z, y) plane, extruded along X: built as a prism whose axes are then
	# rotated (x, y, z) -> (y, z, x) — a cyclic swap, so the winding survives it.
	var triangles: PackedVector3Array = MeshPrimitives.prism(outline, from.x, to.x)
	return PackedVector3Array(
		Array(triangles).map(func(v: Vector3) -> Vector3: return Vector3(v.y, v.z, v.x))
	)


## Dark window strips just proud of each face of a block of half-extents `half`, centred at
## height `y`.
static func _window_bands(half: Vector2, y: float) -> PackedVector3Array:
	var band: float = 0.08
	var proud: float = 0.02
	return (
		MeshPrimitives.box(
			Vector3(-half.x + 0.1, y - band, half.y),
			Vector3(half.x - 0.1, y + band, half.y + proud)
		)
		+ MeshPrimitives.box(
			Vector3(-half.x + 0.1, y - band, -half.y - proud),
			Vector3(half.x - 0.1, y + band, -half.y)
		)
		+ MeshPrimitives.box(
			Vector3(half.x, y - band, -half.y + 0.1),
			Vector3(half.x + proud, y + band, half.y - 0.1)
		)
		+ MeshPrimitives.box(
			Vector3(-half.x - proud, y - band, -half.y + 0.1),
			Vector3(-half.x, y + band, half.y - 0.1)
		)
	)


## Points from `start` to `end` no more than `spacing` apart, both ends included.
static func _spaced(start: float, end: float, spacing: float) -> Array[float]:
	var count: int = maxi(1, ceili((end - start) / spacing))
	var out: Array[float] = []
	for i: int in range(count + 1):
		out.append(lerpf(start, end, float(i) / count))
	return out

#endregion
