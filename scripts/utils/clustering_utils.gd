class_name CU

## Single-linkage agglomerative clustering.
## Merges clusters whose minimum inter-node distance is below the threshold.
## Returns an Array of Arrays, each subarray being one cluster.
static func get_nodes_clustered(a_nodes: Array, distance_threshold: float) -> Array:
	var clusters: Array = []
	for node in a_nodes:
		clusters.append([node])

	var merged: bool = true
	while merged:
		merged = false
		var n: int = clusters.size()
		for i in range(n):
			for j in range(i + 1, n):
				if _min_distance(clusters[i], clusters[j]) <= distance_threshold:
					clusters[i].append_array(clusters[j])
					clusters.remove_at(j)
					merged = true
					break
			if merged:
				break

	return clusters

static func _min_distance(a: Array, b: Array) -> float:
	var min_dist: float = INF
	for node_a in a:
		for node_b in b:
			var d: float = node_a.global_position.distance_to(node_b.global_position)
			if d < min_dist:
				min_dist = d
	return min_dist
