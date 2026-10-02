class_name BlockMaskGenerator
extends RefCounted

## Produces a per-cell blocked mask (water / hazard / scripted no-go) for
## TerrainGrid.set_blocked_mask().  Impassable blobs are placed on otherwise
## passable terrain, but each blob is only kept if the remaining passable surface
## stays a SINGLE connected component — so blocks never strand part of the map.
##
## This models the user's "otherwise-flat regions that are impassable for reasons
## beyond the heightmap."  It reads only the height data, so it is independent of
## how the terrain was generated.
##
## Output is cell-indexed (index = z*(width-1)+x), 1 = blocked, matching
## TerrainGrid's mask layout.

#region Constants
const MAX_SLOPE_DIFF: float = 0.5

const _NEIGHBOURS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
#endregion

#region Properties
@export var seed: int = 0

## How many blobs to attempt.  Some may be rejected for breaking connectivity.
@export var blob_count: int = 6

@export var min_blob_size: int = 4
@export var max_blob_size: int = 18

## When true, only flat cells are blocked (hazard fields on plateaus); ramps and
## slopes stay clear.  Keeping the connectors open makes blocks far less likely
## to disconnect the map.
@export var flat_only: bool = true
#endregion


#region Public API
func generate(a_heights: PackedFloat32Array, a_width: int, a_depth: int) -> PackedByteArray:
	var gw: int = a_width - 1
	var gh: int = a_depth - 1
	var blocked := PackedByteArray()
	if gw <= 0 or gh <= 0:
		return blocked
	blocked.resize(gw * gh)  # zero-initialised

	# Precompute per-cell passability and flatness from the heightmap.
	var passable := PackedByteArray()
	var flat := PackedByteArray()
	passable.resize(gw * gh)
	flat.resize(gw * gh)
	for z: int in gh:
		for x: int in gw:
			var h00: float = a_heights[z * a_width + x]
			var h10: float = a_heights[z * a_width + x + 1]
			var h01: float = a_heights[(z + 1) * a_width + x]
			var h11: float = a_heights[(z + 1) * a_width + x + 1]
			var hi: float = maxf(maxf(h00, h10), maxf(h01, h11))
			var lo: float = minf(minf(h00, h10), minf(h01, h11))
			var idx: int = z * gw + x
			if (hi - lo) <= MAX_SLOPE_DIFF:
				passable[idx] = 1
			if is_equal_approx(hi, lo):
				flat[idx] = 1

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for _attempt: int in blob_count:
		var start: Vector2i = _pick_candidate(rng, gw, gh, passable, flat, blocked)
		if start.x < 0:
			continue
		var target: int = rng.randi_range(min_blob_size, max_blob_size)
		var blob: Array = _grow_blob(rng, start, target, gw, gh, passable, flat, blocked)

		# Tentatively apply, keep only if the passable surface stays connected.
		for c: Vector2i in blob:
			blocked[c.y * gw + c.x] = 1
		if not _passable_connected(gw, gh, passable, blocked):
			for c: Vector2i in blob:
				blocked[c.y * gw + c.x] = 0

	return blocked


#endregion


#region Private helpers
func _is_eligible(
	a_cell: Vector2i,
	a_gw: int,
	a_gh: int,
	a_passable: PackedByteArray,
	a_flat: PackedByteArray,
	a_blocked: PackedByteArray
) -> bool:
	if a_cell.x < 0 or a_cell.x >= a_gw or a_cell.y < 0 or a_cell.y >= a_gh:
		return false
	var idx: int = a_cell.y * a_gw + a_cell.x
	if a_passable[idx] == 0 or a_blocked[idx] == 1:
		return false
	return a_flat[idx] == 1 if flat_only else true


func _pick_candidate(
	a_rng: RandomNumberGenerator,
	a_gw: int,
	a_gh: int,
	a_passable: PackedByteArray,
	a_flat: PackedByteArray,
	a_blocked: PackedByteArray
) -> Vector2i:
	for _try: int in 60:
		var cell := Vector2i(a_rng.randi_range(0, a_gw - 1), a_rng.randi_range(0, a_gh - 1))
		if _is_eligible(cell, a_gw, a_gh, a_passable, a_flat, a_blocked):
			return cell
	return Vector2i(-1, -1)


## Random-frontier flood growth — gives organic blob shapes rather than discs.
func _grow_blob(
	a_rng: RandomNumberGenerator,
	a_start: Vector2i,
	a_target: int,
	a_gw: int,
	a_gh: int,
	a_passable: PackedByteArray,
	a_flat: PackedByteArray,
	a_blocked: PackedByteArray
) -> Array:
	var blob: Array = []
	var visited: Dictionary = {a_start: true}
	var frontier: Array = [a_start]
	while not frontier.is_empty() and blob.size() < a_target:
		var i: int = a_rng.randi_range(0, frontier.size() - 1)
		var cell: Vector2i = frontier[i]
		frontier.remove_at(i)
		blob.append(cell)
		for d: Vector2i in _NEIGHBOURS:
			var nb: Vector2i = cell + d
			if not visited.has(nb) and _is_eligible(nb, a_gw, a_gh, a_passable, a_flat, a_blocked):
				visited[nb] = true
				frontier.append(nb)
	return blob


## True iff the cells that are height-passable AND not blocked form one connected
## component (4-neighbour).  Early-outs as soon as a second component appears.
func _passable_connected(
	a_gw: int, a_gh: int, a_passable: PackedByteArray, a_blocked: PackedByteArray
) -> bool:
	var seen := PackedByteArray()
	seen.resize(a_gw * a_gh)
	var components: int = 0
	for z: int in a_gh:
		for x: int in a_gw:
			var idx: int = z * a_gw + x
			if a_passable[idx] == 1 and a_blocked[idx] == 0 and seen[idx] == 0:
				components += 1
				if components > 1:
					return false
				var stack: Array = [Vector2i(x, z)]
				seen[idx] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					for d: Vector2i in _NEIGHBOURS:
						var nx: int = c.x + d.x
						var nz: int = c.y + d.y
						if nx >= 0 and nx < a_gw and nz >= 0 and nz < a_gh:
							var ni: int = nz * a_gw + nx
							if a_passable[ni] == 1 and a_blocked[ni] == 0 and seen[ni] == 0:
								seen[ni] = 1
								stack.append(Vector2i(nx, nz))
	return components <= 1
#endregion
