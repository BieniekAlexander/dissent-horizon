class_name BotFirstContact
extends RefCounted

## WHEN THE UNSEEN ENEMY'S OPENING FORCE COULD FIRST ARRIVE: the threat clock's reading before
## any sighting (gdd/systems/ai/objective-selection.md §The opening prior). Before the first
## sighting there is no believed source to measure an arrival from, so the clock reads a
## prior instead — estimated, as decided 2026-10-09, from the map's dimensions, the start
## placement parameters, and the opposing faction's opening force, and from nothing richer:
## the lattice was offered and declined as more complexity than the estimate is worth.
##
## The separation is what the generator's start placement implies: starts lie on a ring
## between `start_min_center_fraction` of the side and the edge margin, so two of them stand
## about twice the ring's mean radius apart, and never closer than the separation floor. The
## walk is the straight line at the fastest GROUND speed in the enemy's starting units —
## aircraft start grounded and the opening raid walks. A map does not carry the parameters it
## was generated with, so the generator's defaults stand for every map (BotIncome has the same
## assumption for the shelter band).


## Seconds from match start until that force could stand at the bot's door; INF with no
## enemy force to walk, or no map.
static func estimate_seconds(
	bounds: Rect2, params: MapGenerationParams, fastest_ground_speed: float
) -> float:
	if fastest_ground_speed <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return INF
	return separation(bounds, params) / fastest_ground_speed


## The expected straight-line distance between two starts on a map of `bounds`, world units.
static func separation(bounds: Rect2, params: MapGenerationParams) -> float:
	var side: float = (bounds.size.x + bounds.size.y) * 0.5
	var nearest: float = params.start_min_center_fraction * side
	var farthest: float = maxf(nearest, side * 0.5 - params.start_edge_margin_cells * Map.CELL_SIZE)
	var mean_radius: float = (nearest + farthest) * 0.5
	var floor_distance: float = params.start_separation_diagonal_fraction * bounds.size.length()
	return maxf(2.0 * mean_radius, floor_distance)


## Piece id → how many of it the scenes field: the opening force as a composition, for the
## phantom the bot counters before it has seen anything (Bot.phantom_force). Scenes that are
## not pieces, or carry no id, are skipped.
static func starting_unit_counts(scenes: Array) -> Dictionary:
	var counts: Dictionary = {}
	for scene: PackedScene in scenes:
		if scene == null:
			continue
		var piece: Node = scene.instantiate()
		var entity: Entity = piece as Entity
		if entity != null and entity.id != &"":
			counts[entity.id] = int(counts.get(entity.id, 0)) + 1
		piece.free()
	return counts


## The fastest speed among the ground units in `scenes` (a faction's starting units); 0 when
## none of them walks. Each scene is instantiated out of tree and freed, as a build preview is.
static func fastest_ground_speed(scenes: Array) -> float:
	var best: float = 0.0
	for scene: PackedScene in scenes:
		if scene == null:
			continue
		var piece: Node = scene.instantiate()
		var movement: Movement = piece.get_node_or_null("Locomotion") as Movement
		if movement != null and piece.get_node_or_null("Aerial") == null:
			best = maxf(best, movement.speed)
		piece.free()
	return best
