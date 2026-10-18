class_name CU


## Single-linkage agglomerative clustering.
## Merges clusters whose minimum inter-node distance is below the threshold.
## Returns an Array of Arrays, each subarray being one cluster.
## `position_of` (node -> Vector3) is where each node is taken to stand; empty means its live
## global_position. A belief-limited caller passes last-known positions (AlliancePerspective).
static func get_nodes_clustered(
	nodes: Array, distance_threshold: float, position_of: Callable = Callable()
) -> Array:
	var clusters: Array = []
	for node in nodes:
		clusters.append([node])

	var merged: bool = true
	while merged:
		merged = false
		var n: int = clusters.size()
		for i in range(n):
			for j in range(i + 1, n):
				if _min_distance(clusters[i], clusters[j], position_of) <= distance_threshold:
					clusters[i].append_array(clusters[j])
					clusters.remove_at(j)
					merged = true
					break
			if merged:
				break

	return clusters


static func _min_distance(a: Array, b: Array, position_of: Callable) -> float:
	var min_dist: float = INF
	for node_a in a:
		for node_b in b:
			var d: float = _at(node_a, position_of).distance_to(_at(node_b, position_of))
			if d < min_dist:
				min_dist = d
	return min_dist


static func _at(node: Variant, position_of: Callable) -> Vector3:
	return position_of.call(node) if position_of.is_valid() else node.global_position
