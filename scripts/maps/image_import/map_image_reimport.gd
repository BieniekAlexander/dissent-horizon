@tool
class_name MapImageReimport
extends RefCounted

## Re-importing a drawing into a Scenario whose map has been worked on (map-from-image.md
## §Re-importing a map that has been worked on).
##
## **What the importer placed is tagged, and replaced**: every structure, start point and water
## body an import writes carries TAG, and a re-import drops all of them with the old terrain.
## Anything else the old Map holds — a piece placed by hand, a node the author added — is moved
## onto the new Map untouched. **Pieces the new terrain breaks are flagged, not moved**: one now
## on ground it cannot stand on, and one an imported structure now overlaps.

#region Constants
## The metadata key an imported node carries. Metadata rather than a group, so it is saved with
## the scene and cannot be mistaken for one of the groups the piece scenes derive.
const TAG: StringName = &"image_import"
## The Map's own terrain plumbing, which every map rebuilds and none carries over.
const MAP_STRUCTURE: Array[StringName] = [&"NavigationRegion"]
#endregion


## Tag every node an import put on `map`, which is all of it but the terrain plumbing.
static func tag(map: Map) -> void:
	for child: Node in map.get_children():
		if not MAP_STRUCTURE.has(child.name):
			child.set_meta(TAG, true)


static func is_imported(node: Node) -> bool:
	return node.has_meta(TAG)


## Every untagged, saved child of `old_map`, with which of its nodes `owner` owns: {node,
## owned}. Read while `old_map` is still in the scene — taking a node out of it clears every
## owner that is no longer its ancestor — and handed to move_onto once the new map is in.
## A child with no owner is derived at load and rebuilt by the new map itself.
static func hand_placed_children(old_map: Map, owner: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child: Node in old_map.get_children():
		if MAP_STRUCTURE.has(child.name) or is_imported(child) or child.owner == null:
			continue
		out.append({node = child, owned = _owned_by(child, owner)})
	return out


## Move what hand_placed_children collected onto `new_map`, giving `owner` its nodes back.
## Returns the nodes moved.
static func move_onto(kept: Array[Dictionary], new_map: Map, owner: Node) -> Array[Node]:
	var moved: Array[Node] = []
	for entry: Dictionary in kept:
		var node: Node = entry.node
		# Cleared first, so the move never holds an owner that is not its ancestor.
		for owned: Node in entry.owned:
			owned.owner = null
		node.get_parent().remove_child(node)
		new_map.add_child(node, true)
		for owned: Node in entry.owned:
			owned.owner = owner
		moved.append(node)
	return moved


## Every hand-placed piece under `root` — untagged Entities — as {name, rect, is_fixture},
## `rect` being the cells it stands on in `map`'s grid.
static func hand_placed_pieces(root: Node, map: Map) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var terrain: TerrainData = map.terrain_data
	var grid_half := Vector2(terrain.grid_width(), terrain.grid_depth()) * 0.5
	var entities: Array[Node] = _entities(root)
	if entities.is_empty():
		return out
	var to_map: Transform3D = _within(root, map).affine_inverse()
	for node: Node in entities:
		var entity := node as Node3D
		if is_imported(entity):
			continue
		var local: Vector3 = to_map * _within(root, entity).origin
		var centre := Vector2(local.x, local.z) + grid_half
		var fixture := entity.get_node_or_null("Fixture") as Fixture
		var size: Vector2i = Vector2i.ONE
		if fixture != null:
			size = Fixture.oriented_dimensions(
				fixture.dimensions, Fixture.quarter_turns_of_yaw((entity as Entity).yaw)
			)
		var origin := Vector2i((centre - Vector2(size) * 0.5).round())
		if fixture == null:
			origin = Vector2i(centre.floor())
		out.append(
			{name = String(entity.name), rect = Rect2i(origin, size), is_fixture = fixture != null}
		)
	return out


## `a_node`'s transform in `a_root`'s space, composed parent by parent rather than read from the
## global transform, which a node out of the scene tree does not have.
static func _within(a_root: Node, a_node: Node) -> Transform3D:
	var out := Transform3D.IDENTITY
	var node: Node = a_node
	while node != null and node != a_root:
		if node is Node3D:
			out = (node as Node3D).transform * out
		node = node.get_parent()
	return out


## The flags for `pieces` (as hand_placed_pieces gives them) on the new `terrain`, with water
## `depth_by_cell` and the imported structures' `imported` footprints: {lines, cells}.
##
## A fixture needs every cell of its footprint in play, level and dry; any other piece needs its
## cell in play, walkable, and no deeper than wading.
static func flag(
	terrain: TerrainData,
	depth_by_cell: Dictionary,
	imported: Array[Rect2i],
	pieces: Array[Dictionary]
) -> Dictionary:
	var lines := PackedStringArray()
	var cells: Array[Vector2i] = []
	for piece: Dictionary in pieces:
		var rect: Rect2i = piece.rect
		var reasons: PackedStringArray = PackedStringArray()
		var bad: Array[Vector2i] = []
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, z)
				var why: String = _ground_fault(terrain, depth_by_cell, cell, piece.is_fixture)
				if not why.is_empty():
					bad.append(cell)
					if not reasons.has(why):
						reasons.append(why)
		for footprint: Rect2i in imported:
			if footprint.intersects(rect):
				reasons.append("overlaps an imported structure at cells %s" % footprint)
				bad.append(rect.position)
		if reasons.is_empty():
			continue
		lines.append("%s at cells %s: %s" % [piece.name, rect, "; ".join(reasons)])
		cells.append_array(bad)
	return {lines = lines, cells = cells}


static func _ground_fault(
	terrain: TerrainData, depth_by_cell: Dictionary, cell: Vector2i, is_fixture: bool
) -> String:
	if not terrain.is_cell_in_bounds(cell) or not terrain.is_cell_in_play(cell):
		return "out of play"
	var depth: float = depth_by_cell.get(cell, 0.0)
	if is_fixture:
		if depth > 0.0:
			return "in water"
		if not terrain.cell_is_flat(cell):
			return "on a slope"
		return ""
	if depth > WaterBasin.WADE_DEPTH:
		return "in deep water"
	if not terrain.cell_supports_entity(cell):
		return "on ground too steep to stand on"
	return ""


static func _entities(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		if child is Entity:
			out.append(child)
		else:
			out.append_array(_entities(child))
	return out


static func _owned_by(node: Node, owner: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node.owner == owner:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_owned_by(child, owner))
	return out
