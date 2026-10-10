@tool
class_name MapDecorationInput
extends RefCounted

## Everything pass 7 (visual facets) reads, in one plain form, so the SAME planner runs on a
## freshly generated map and on a map scene loaded from disk — and gives the same answer
## (gdd/systems/terrain-and-navigation/visual-facets.md §Derived, never saved).
##
## Two adapters build it: from_generated (inside MapGenerator, from its own result) and
## from_map (at load, from the Map node and the pieces under it). Starts are deliberately NOT
## an input: spawn points are hidden from the players, and dressing laid around them would
## give them away.

#region Enums
## What a fixture is, as far as decoration cares. A neutral building or a shelter is
## settlement; a site is industry; anything else only keeps doodads off its cells.
enum FixtureKind { BUILDING, SHELTER, SITE, OTHER }
#endregion

#region Properties
var terrain: TerrainData = null
## One {seed_cell: Vector2i, level: float} per body of water — WaterBody's own two numbers.
var waters: Array[Dictionary] = []
## One {kind: FixtureKind, cells: Array[Vector2i]} per placed fixture.
var fixtures: Array[Dictionary] = []
## The decoration seed. Derived from the terrain's own content (decoration_seed), so a map
## needs no stored seed and two loads of one map always agree.
var rng_seed: int = 0
#endregion


#region Adapters
## The input for a generator result. Ponds and flooded chasms are its waters; every placement
## of every feature is a fixture.
static func from_generated(generated: GeneratedMap) -> MapDecorationInput:
	var input := MapDecorationInput.new()
	input.terrain = generated.terrain
	input.rng_seed = decoration_seed(generated.terrain)
	for feature: MapFeature in generated.features:
		if feature.kind == MapFeature.Kind.POND:
			input.waters.append({"seed_cell": feature.pond_seed_cell, "level": feature.pond_level})
			continue
		for placement: Dictionary in feature.placements:
			var piece: MapPiece = placement.piece
			var rect: Rect2i = MapFeature.placement_rect(placement)
			(
				input
				. fixtures
				. append(
					{
						"kind": kind_of_piece(piece.id),
						"cells": footprint(rect.position, rect.size),
					}
				)
			)
	for water: Dictionary in generated.chasm_waters:
		input.waters.append({"seed_cell": water.seed_cell, "level": water.level})
	return input


## The input for a Map node, read from the WaterBodies and pieces under it. Works whether or
## not the map is in the tree, so the generator's writer and the runtime read it the same way.
static func from_map(map: Map) -> MapDecorationInput:
	var input := MapDecorationInput.new()
	input.terrain = map.terrain_data
	if input.terrain == null:
		return input
	input.rng_seed = decoration_seed(input.terrain)
	var grid_half := Vector2(input.terrain.grid_width(), input.terrain.grid_depth()) * 0.5
	for node: Node in map.find_children("*", "", true, false):
		if node is WaterBody:
			var body := node as WaterBody
			input.waters.append({"seed_cell": body.seed_cell, "level": body.level})
		elif node is Entity:
			var structure := node.get_node_or_null("Fixture") as Fixture
			if structure == null:
				continue
			# Read from the yaw, not Fixture.quarter_turns: a piece out of the tree, or not yet
			# registered, has not taken its turn from the yaw yet (Entity._auto_initialize).
			var dims: Vector2i = Fixture.oriented_dimensions(
				structure.dimensions, Fixture.quarter_turns_of_yaw((node as Node3D).rotation.y)
			)
			var xz: Vector2 = _map_local_xz(node as Node3D, map) + grid_half
			var origin := Vector2i(roundi(xz.x - dims.x * 0.5), roundi(xz.y - dims.y * 0.5))
			(
				input
				. fixtures
				. append(
					{
						"kind": kind_of_piece((node as Entity).id),
						"cells": footprint(origin, dims),
					}
				)
			)
	return input


#endregion


#region Helpers
## A stable seed from what the map IS: the same heights and ground materials always decorate
## the same way, and an edit to either re-rolls it.
static func decoration_seed(data: TerrainData) -> int:
	if data == null:
		return 0
	return hash([data.heights, data.tile_types, data.play_size])


static func kind_of_piece(id: StringName) -> FixtureKind:
	if id == EntityIds.NT_SHELTER:
		return FixtureKind.SHELTER
	if id == EntityIds.NT_EXTRACTION_SITE:
		return FixtureKind.SITE
	if PieceFamilies.is_member(id, PieceFamilies.NEUTRAL_BUILDING):
		return FixtureKind.BUILDING
	return FixtureKind.OTHER


static func footprint(origin: Vector2i, dims: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in dims.x:
		for z: int in dims.y:
			cells.append(origin + Vector2i(x, z))
	return cells


## A node's XZ in its Map's local frame, from the transform chain alone — global_position is
## unavailable while the map is being built out of the tree.
static func _map_local_xz(node: Node3D, map: Map) -> Vector2:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != map:
		if parent is Node3D:
			transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return Vector2(transform.origin.x, transform.origin.z)
#endregion
