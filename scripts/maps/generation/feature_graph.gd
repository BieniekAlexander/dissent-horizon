@tool
class_name FeatureGraph
extends RefCounted

## The neighbourhood graph pass 4 decides topology on: one node per start and per placed
## feature, edges from the Delaunay triangulation of their positions. That triangulation is the
## only cartesian step; cutting and carving are decisions about edges
## (map-generation.md §4). Pure.

#region Properties
var positions := PackedVector2Array()
## Each edge as Vector2i(a, b), a < b.
var edges: Array[Vector2i] = []
#endregion


static func build(points: PackedVector2Array) -> FeatureGraph:
	var graph := FeatureGraph.new()
	graph.positions = points
	var seen: Dictionary = {}
	var triangles: PackedInt32Array = Geometry2D.triangulate_delaunay(points)
	for t: int in range(0, triangles.size(), 3):
		for k: int in 3:
			var a: int = triangles[t + k]
			var b: int = triangles[t + (k + 1) % 3]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			if not seen.has(edge):
				seen[edge] = true
				graph.edges.append(edge)
	return graph


## How many vertex-disjoint paths join `source` and `sink` over `open_edges`, counted up to
## `enough` — max-flow on the node-split graph, stopping once the count is reached.
func disjoint_paths(source: int, sink: int, open_edges: Array[Vector2i], enough: int) -> int:
	# Node i splits into in = 2i and out = 2i + 1, joined by a unit arc (infinite for the ends,
	# which may be shared by every path). Each open edge is a pair of unit arcs out -> in.
	var capacity: Dictionary = {}
	var neighbours: Dictionary = {}
	var unlimited: int = enough + 1
	for node: int in positions.size():
		var through: int = unlimited if node == source or node == sink else 1
		_add_arc(capacity, neighbours, 2 * node, 2 * node + 1, through)
	for edge: Vector2i in open_edges:
		_add_arc(capacity, neighbours, 2 * edge.x + 1, 2 * edge.y, 1)
		_add_arc(capacity, neighbours, 2 * edge.y + 1, 2 * edge.x, 1)
	var flow: int = 0
	while flow < enough:
		var parent: Dictionary = _augmenting_path(capacity, neighbours, 2 * source + 1, 2 * sink)
		if parent.is_empty():
			break
		var at: int = 2 * sink
		while at != 2 * source + 1:
			var from: int = parent[at]
			capacity[Vector2i(from, at)] -= 1
			capacity[Vector2i(at, from)] = capacity.get(Vector2i(at, from), 0) + 1
			at = from
		flow += 1
	return flow


static func _add_arc(
	capacity: Dictionary, neighbours: Dictionary, from: int, to: int, amount: int
) -> void:
	capacity[Vector2i(from, to)] = capacity.get(Vector2i(from, to), 0) + amount
	if not capacity.has(Vector2i(to, from)):
		capacity[Vector2i(to, from)] = 0
	for pair: Vector2i in [Vector2i(from, to), Vector2i(to, from)]:
		if not neighbours.has(pair.x):
			neighbours[pair.x] = []
		if not (neighbours[pair.x] as Array).has(pair.y):
			neighbours[pair.x].append(pair.y)


## Breadth-first search for a path with spare capacity; node -> predecessor, empty if none.
static func _augmenting_path(
	capacity: Dictionary, neighbours: Dictionary, source: int, sink: int
) -> Dictionary:
	var parent: Dictionary = {source: source}
	var queue: Array[int] = [source]
	var head: int = 0
	while head < queue.size():
		var node: int = queue[head]
		head += 1
		for next: int in neighbours.get(node, []):
			if parent.has(next) or capacity[Vector2i(node, next)] <= 0:
				continue
			parent[next] = node
			if next == sink:
				return parent
			queue.append(next)
	return {}
