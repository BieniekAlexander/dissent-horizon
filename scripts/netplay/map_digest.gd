class_name MapDigest
extends RefCounted

## A short hash of the map a scenario was loaded with: its terrain — heights, ground tiles, cells
## with no ground — and every piece standing on it before the match starts. Each peer generates
## the map from the recipe's seed, and the peers compare this before tick 0, so a map that
## generated differently on one machine is refused rather than played.
## gdd/systems/commands/netplay.md §Decisions (the map).
##
## Positions are rounded, as SimulationDigest's are (SimulationDigest.fixed): two machines
## agreeing to the millimetre have built the same map, and a hash of raw floats would not say
## where they differ anyway.


static func of(scenario: Scenario) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var terrain: TerrainData = scenario.map.terrain_data if scenario.map != null else null
	if terrain != null:
		# HashingContext.update refuses an empty array, and a map with no void cells is common.
		for bytes: PackedByteArray in [
			terrain.heights.to_byte_array(), terrain.tile_types, terrain.void_cells
		]:
			if not bytes.is_empty():
				context.update(bytes)
	var pieces: PackedStringArray = []
	for node: Node in scenario.find_children("*", "Entity", true, false):
		var entity: Entity = node as Entity
		var at: Vector3 = entity.global_position if entity.is_inside_tree() else entity.position
		pieces.append("%s@%s" % [entity.id, SimulationDigest.fixed_vector(at, 3)])
	pieces.sort()
	context.update("|".join(pieces).to_utf8_buffer())
	return context.finish().hex_encode().substr(0, SimulationDigest.DIGEST_LENGTH)
