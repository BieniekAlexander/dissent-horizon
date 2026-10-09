#include "terrain_cells.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace dissent {

namespace {

// GDScript's is_equal_approx(float, float), in the double precision GDScript floats carry.
// Mirrored exactly because the segment walk branches on it and replays must not drift.
constexpr double CMP_EPSILON = 0.00001;

bool is_equal_approx(double p_a, double p_b) {
	if (p_a == p_b) {
		return true; // also the infinities, which the tolerance test below cannot equate
	}
	const double tolerance = std::max(CMP_EPSILON * std::abs(p_a), CMP_EPSILON);
	return std::abs(p_a - p_b) < tolerance;
}

int floor_to_int(float p_value) {
	return static_cast<int>(std::floor(static_cast<double>(p_value)));
}

} // namespace

void TerrainCells::setup(int p_width, int p_depth) {
	ERR_FAIL_COND_MSG(p_width < 0 || p_depth < 0, "TerrainCells.setup: negative grid size");
	width = p_width;
	depth = p_depth;
	const size_t count = static_cast<size_t>(width) * depth;
	state.assign(count, 0);
	clearance.assign(count, 0);
	dist.assign(count, 0);
	component.assign(count, -1);
	component_sizes.clear();
	fields_dirty = true;
	has_dirty_rect = false;
	components_dirty = true;
}

void TerrainCells::mark_steep(const PackedFloat32Array &p_heights, double p_max_spread) {
	const int corners_wide = width + 1;
	ERR_FAIL_COND_MSG(p_heights.size() != static_cast<int64_t>(corners_wide) * (depth + 1),
			"TerrainCells.mark_steep: heights must be (width + 1) x (depth + 1)");
	const float *heights = p_heights.ptr();
	for (int z = 0; z < depth; z++) {
		for (int x = 0; x < width; x++) {
			const double h00 = heights[z * corners_wide + x];
			const double h10 = heights[z * corners_wide + x + 1];
			const double h01 = heights[(z + 1) * corners_wide + x];
			const double h11 = heights[(z + 1) * corners_wide + x + 1];
			const double spread = std::max(std::max(h00, h10), std::max(h01, h11)) -
					std::min(std::min(h00, h10), std::min(h01, h11));
			if (spread > p_max_spread) {
				state[index(x, z)] |= STEEP;
			}
		}
	}
}

bool TerrainCells::is_in_bounds(const Vector2i &p_cell) const {
	return in_bounds(p_cell.x, p_cell.y);
}

bool TerrainCells::is_passable(const Vector2i &p_cell) const {
	return in_bounds(p_cell.x, p_cell.y) && state[index(p_cell.x, p_cell.y)] == 0;
}

bool TerrainCells::has_reason(const Vector2i &p_cell, int p_reason) const {
	return in_bounds(p_cell.x, p_cell.y) && (state[index(p_cell.x, p_cell.y)] & p_reason) != 0;
}

void TerrainCells::set_reason(const Vector2i &p_cell, int p_reason, bool p_on) {
	ERR_FAIL_COND_MSG(!in_bounds(p_cell.x, p_cell.y), "TerrainCells.set_reason: cell out of bounds");
	uint8_t &cell = state[index(p_cell.x, p_cell.y)];
	cell = p_on ? (cell | p_reason) : (cell & ~p_reason);
}

Array TerrainCells::set_reason_mask(int p_reason, const PackedByteArray &p_mask) {
	Array changed;
	ERR_FAIL_COND_V_MSG(!p_mask.is_empty() && p_mask.size() != static_cast<int64_t>(state.size()), changed,
			"TerrainCells.set_reason_mask: mask must be empty or one byte per cell");
	const uint8_t *mask = p_mask.is_empty() ? nullptr : p_mask.ptr();
	for (int z = 0; z < depth; z++) {
		for (int x = 0; x < width; x++) {
			const int idx = index(x, z);
			const bool was = (state[idx] & p_reason) != 0;
			const bool now = mask != nullptr && mask[idx] != 0;
			if (was != now) {
				state[idx] = now ? (state[idx] | p_reason) : (state[idx] & ~p_reason);
				changed.push_back(Vector2i(x, z));
			}
		}
	}
	return changed;
}

PackedByteArray TerrainCells::reason_mask(int p_reasons) const {
	PackedByteArray mask;
	mask.resize(state.size());
	uint8_t *out = mask.ptrw();
	for (size_t i = 0; i < state.size(); i++) {
		out[i] = (state[i] & p_reasons) != 0 ? 1 : 0;
	}
	return mask;
}

Array TerrainCells::passable_cells() const {
	Array cells;
	for (int x = 0; x < width; x++) {
		for (int z = 0; z < depth; z++) {
			if (state[index(x, z)] == 0) {
				cells.push_back(Vector2i(x, z));
			}
		}
	}
	return cells;
}

void TerrainCells::mark_changed(const Array &p_cells) {
	components_dirty = true;
	if (p_cells.is_empty()) {
		return;
	}
	Vector2i lo = p_cells[0];
	Vector2i hi = lo;
	for (int64_t i = 1; i < p_cells.size(); i++) {
		const Vector2i cell = p_cells[i];
		lo = lo.min(cell);
		hi = hi.max(cell);
	}
	const Rect2i changed(lo, hi - lo + Vector2i(1, 1));
	dirty_rect = has_dirty_rect ? dirty_rect.merge(changed) : changed;
	has_dirty_rect = true;
}

// ── Navigability for an agent class ─────────────────────────────────────────────────────────
// A cell survives the erosion for a class iff it is passable, more than `rings` cells from the
// nearest obstacle, and inside some admit_k x admit_k passable block. navigable_mask and the
// single-cell queries all go through navigable_at, so the navmesh and the string-pull line test
// cannot disagree.

bool TerrainCells::coverable(int p_x, int p_z, int p_admit_k) const {
	for (int az = std::max(0, p_z - p_admit_k + 1); az <= p_z; az++) {
		if (az + p_admit_k > depth) {
			continue;
		}
		for (int ax = std::max(0, p_x - p_admit_k + 1); ax <= p_x; ax++) {
			if (ax + p_admit_k > width) {
				continue;
			}
			if (clearance[index(ax, az)] >= p_admit_k) {
				return true;
			}
		}
	}
	return false;
}

bool TerrainCells::navigable_at(int p_x, int p_z, int p_rings, int p_admit_k) const {
	if (!in_bounds(p_x, p_z)) {
		return false;
	}
	const int idx = index(p_x, p_z);
	if (state[idx] != 0) {
		return false;
	}
	if (p_rings > 0 && dist[idx] <= p_rings) {
		return false;
	}
	return p_admit_k <= 1 || coverable(p_x, p_z, p_admit_k);
}

PackedByteArray TerrainCells::navigable_mask(const Rect2i &p_rect, int p_rings, int p_admit_k) {
	PackedByteArray mask;
	ERR_FAIL_COND_V_MSG(!bounds_rect().encloses(p_rect), mask, "TerrainCells.navigable_mask: rect outside the grid");
	ensure_fields();
	mask.resize(static_cast<int64_t>(p_rect.size.x) * p_rect.size.y);
	uint8_t *out = mask.ptrw();
	for (int z = p_rect.position.y; z < p_rect.position.y + p_rect.size.y; z++) {
		for (int x = p_rect.position.x; x < p_rect.position.x + p_rect.size.x; x++) {
			*out++ = navigable_at(x, z, p_rings, p_admit_k) ? 1 : 0;
		}
	}
	return mask;
}

bool TerrainCells::is_navigable_for(const Vector2i &p_cell, int p_rings, int p_admit_k) {
	if (!in_bounds(p_cell.x, p_cell.y)) {
		return false;
	}
	ensure_fields();
	return navigable_at(p_cell.x, p_cell.y, p_rings, p_admit_k);
}

// Amanatides–Woo walk over exactly the cells the segment crosses, stopping at the first refusal.
// Where the segment passes exactly through a cell corner both side cells are tested too, so a
// diagonal cannot slip between two blocked cells.
//
// The arithmetic deliberately mixes precisions the way GDScript does — Vector2 components are
// single precision, script-level float expressions double — because the corner test branches on
// it, and a native walk that crossed a corner the script one did not would change paths and so
// desync replays recorded before the port.
bool TerrainCells::is_segment_navigable_for(const Vector2 &p_from, const Vector2 &p_to, int p_rings, int p_admit_k) {
	ensure_fields();
	int cx = floor_to_int(p_from.x);
	int cz = floor_to_int(p_from.y);
	const int ex = floor_to_int(p_to.x);
	const int ez = floor_to_int(p_to.y);
	const float dx = p_to.x - p_from.x;
	const float dz = p_to.y - p_from.y;
	const int sx = dx > 0.0f ? 1 : -1;
	const int sz = dz > 0.0f ? 1 : -1;
	// Parameter t along the segment (0..1) at which it next crosses a vertical / horizontal cell
	// boundary, and how much t one whole cell advances. Infinite on an axis it does not move on.
	float t_next_x = std::numeric_limits<float>::infinity();
	float t_next_z = std::numeric_limits<float>::infinity();
	float t_cell_x = std::numeric_limits<float>::infinity();
	float t_cell_z = std::numeric_limits<float>::infinity();
	if (dx != 0.0f) {
		t_next_x = static_cast<float>((static_cast<double>(cx + (sx > 0 ? 1 : 0)) - p_from.x) / static_cast<double>(dx));
		t_cell_x = static_cast<float>(std::abs(1.0 / static_cast<double>(dx)));
	}
	if (dz != 0.0f) {
		t_next_z = static_cast<float>((static_cast<double>(cz + (sz > 0 ? 1 : 0)) - p_from.y) / static_cast<double>(dz));
		t_cell_z = static_cast<float>(std::abs(1.0 / static_cast<double>(dz)));
	}
	// Every crossing moves one axis one cell, so the walk is at most this long; the bound also
	// ends it if float error ever carried it past the end cell.
	const int crossings = std::abs(ex - cx) + std::abs(ez - cz);
	for (int i = 0; i <= crossings; i++) {
		if (!navigable_at(cx, cz, p_rings, p_admit_k)) {
			return false;
		}
		if (cx == ex && cz == ez) {
			return true;
		}
		if (is_equal_approx(t_next_x, t_next_z)) {
			if (!navigable_at(cx + sx, cz, p_rings, p_admit_k) || !navigable_at(cx, cz + sz, p_rings, p_admit_k)) {
				return false;
			}
			cx += sx;
			cz += sz;
			t_next_x += t_cell_x;
			t_next_z += t_cell_z;
		} else if (t_next_x < t_next_z) {
			cx += sx;
			t_next_x += t_cell_x;
		} else {
			cz += sz;
			t_next_z += t_cell_z;
		}
	}
	// Only reachable if float error walked the line off the end cell: refuse, which only costs the
	// caller a straighter path, never a unit steered through something.
	return false;
}

int TerrainCells::clearance_at(const Vector2i &p_cell) {
	if (!in_bounds(p_cell.x, p_cell.y)) {
		return 0;
	}
	ensure_fields();
	return clearance[index(p_cell.x, p_cell.y)];
}

int TerrainCells::distance_to_obstacle(const Vector2i &p_cell) {
	if (!in_bounds(p_cell.x, p_cell.y)) {
		return 0;
	}
	ensure_fields();
	return dist[index(p_cell.x, p_cell.y)];
}

// ── Space-erosion fields ────────────────────────────────────────────────────────────────────

void TerrainCells::ensure_fields() {
	Rect2i area;
	if (fields_dirty) {
		area = bounds_rect();
	} else if (has_dirty_rect) {
		area = dirty_rect.grow(FIELD_CAP_CELLS).intersection(bounds_rect());
	} else {
		return;
	}
	fields_dirty = false;
	has_dirty_rect = false;
	recompute_clearance(area);
	recompute_distance(area);
}

// Anchored largest-square clearance (top-left corner), capped at FIELD_CAP_CELLS: bottom-up DP,
// clearance = 0 if impassable, else 1 + min(right, down, down-right). Neighbours outside the area
// are read as already stored, which is exact because the caller grew the area past everything
// the change can reach.
void TerrainCells::recompute_clearance(const Rect2i &p_area) {
	for (int z = p_area.position.y + p_area.size.y - 1; z >= p_area.position.y; z--) {
		for (int x = p_area.position.x + p_area.size.x - 1; x >= p_area.position.x; x--) {
			const int idx = index(x, z);
			if (state[idx] != 0) {
				clearance[idx] = 0;
				continue;
			}
			const int right = x + 1 < width ? clearance[idx + 1] : 0;
			const int down = z + 1 < depth ? clearance[idx + width] : 0;
			const int diag = (x + 1 < width && z + 1 < depth) ? clearance[idx + width + 1] : 0;
			clearance[idx] = std::min(FIELD_CAP_CELLS, 1 + std::min(right, std::min(down, diag)));
		}
	}
}

// Chebyshev distance to the nearest impassable / out-of-bounds cell, capped at FIELD_CAP_CELLS:
// a forward and a backward pass. Out-of-bounds neighbours count as obstacles, so map-edge cells
// erode like building-edge cells. A neighbour outside the area but on the grid is read as
// stored: a cell's true distance is to an obstacle inside, or through a rim cell the change
// could not have moved.
void TerrainCells::recompute_distance(const Rect2i &p_area) {
	const int x0 = p_area.position.x;
	const int z0 = p_area.position.y;
	const int x1 = x0 + p_area.size.x;
	const int z1 = z0 + p_area.size.y;
	for (int z = z0; z < z1; z++) {
		for (int x = x0; x < x1; x++) {
			const int idx = index(x, z);
			dist[idx] = state[idx] != 0 ? 0 : FIELD_CAP_CELLS;
		}
	}
	for (int z = z0; z < z1; z++) {
		for (int x = x0; x < x1; x++) {
			const int idx = index(x, z);
			if (dist[idx] == 0) {
				continue;
			}
			int best = dist[idx];
			best = std::min(best, (x > 0 ? dist[idx - 1] : 0) + 1);
			best = std::min(best, (z > 0 ? dist[idx - width] : 0) + 1);
			best = std::min(best, (x > 0 && z > 0 ? dist[idx - width - 1] : 0) + 1);
			best = std::min(best, (x + 1 < width && z > 0 ? dist[idx - width + 1] : 0) + 1);
			dist[idx] = best;
		}
	}
	for (int z = z1 - 1; z >= z0; z--) {
		for (int x = x1 - 1; x >= x0; x--) {
			const int idx = index(x, z);
			if (dist[idx] == 0) {
				continue;
			}
			int best = dist[idx];
			best = std::min(best, (x + 1 < width ? dist[idx + 1] : 0) + 1);
			best = std::min(best, (z + 1 < depth ? dist[idx + width] : 0) + 1);
			best = std::min(best, (x + 1 < width && z + 1 < depth ? dist[idx + width + 1] : 0) + 1);
			best = std::min(best, (x > 0 && z + 1 < depth ? dist[idx + width - 1] : 0) + 1);
			dist[idx] = best;
		}
	}
}

// ── Region labels ───────────────────────────────────────────────────────────────────────────
// Region ids are opaque and renumbered on every change; they are only compared for equality.

void TerrainCells::ensure_components() {
	if (!components_dirty) {
		return;
	}
	components_dirty = false;
	recompute_components();
}

// Label every passable cell with its 4-connected region, matching how the navmesh stitches
// adjacent cells. Ids are assigned in row-major order of each region's first cell.
void TerrainCells::recompute_components() {
	constexpr int UNLABELLED = -2;
	const int count = width * depth;
	component.assign(count, -1);
	component_sizes.clear();
	for (int i = 0; i < count; i++) {
		if (state[i] == 0) {
			component[i] = UNLABELLED;
		}
	}
	std::vector<int32_t> queue;
	queue.reserve(count);
	for (int start = 0; start < count; start++) {
		if (component[start] != UNLABELLED) {
			continue;
		}
		const int id = static_cast<int>(component_sizes.size());
		queue.clear();
		queue.push_back(start);
		component[start] = id;
		for (size_t head = 0; head < queue.size(); head++) {
			const int idx = queue[head];
			const int x = idx % width;
			const int neighbours[4] = { x > 0 ? idx - 1 : -1, x + 1 < width ? idx + 1 : -1, idx - width,
				idx + width < count ? idx + width : -1 };
			for (int nb : neighbours) {
				if (nb >= 0 && component[nb] == UNLABELLED) {
					component[nb] = id;
					queue.push_back(nb);
				}
			}
		}
		component_sizes.push_back(static_cast<int32_t>(queue.size()));
	}
}

int TerrainCells::component_at(const Vector2i &p_cell) {
	if (!in_bounds(p_cell.x, p_cell.y)) {
		return -1;
	}
	ensure_components();
	return component[index(p_cell.x, p_cell.y)];
}

int TerrainCells::component_size(int p_component) {
	ensure_components();
	if (p_component < 0 || p_component >= static_cast<int>(component_sizes.size())) {
		return 0;
	}
	return component_sizes[p_component];
}

int TerrainCells::component_count() {
	ensure_components();
	return static_cast<int>(component_sizes.size());
}

int TerrainCells::largest_component() {
	ensure_components();
	int best = -1;
	int best_size = 0;
	for (size_t i = 0; i < component_sizes.size(); i++) {
		if (component_sizes[i] > best_size) {
			best_size = component_sizes[i];
			best = static_cast<int>(i);
		}
	}
	return best;
}

// 4-connected pieces among passable cells, treating each cell flagged in `p_extra_blocked` as
// occupied.
int TerrainCells::count_components(const std::vector<uint8_t> &p_extra_blocked) const {
	const int count = width * depth;
	std::vector<uint8_t> seen(count, 0);
	std::vector<int32_t> stack;
	int pieces = 0;
	for (int start = 0; start < count; start++) {
		if (state[start] != 0 || p_extra_blocked[start] || seen[start]) {
			continue;
		}
		pieces++;
		seen[start] = 1;
		stack.push_back(start);
		while (!stack.empty()) {
			const int idx = stack.back();
			stack.pop_back();
			const int x = idx % width;
			const int neighbours[4] = { x > 0 ? idx - 1 : -1, x + 1 < width ? idx + 1 : -1, idx - width,
				idx + width < count ? idx + width : -1 };
			for (int nb : neighbours) {
				if (nb >= 0 && state[nb] == 0 && !p_extra_blocked[nb] && !seen[nb]) {
					seen[nb] = 1;
					stack.push_back(nb);
				}
			}
		}
	}
	return pieces;
}

bool TerrainCells::preserves_connectivity(const Array &p_footprint) {
	std::vector<uint8_t> extra(static_cast<size_t>(width) * depth, 0);
	const int before = count_components(extra);
	for (int64_t i = 0; i < p_footprint.size(); i++) {
		const Vector2i cell = p_footprint[i];
		if (in_bounds(cell.x, cell.y)) {
			extra[index(cell.x, cell.y)] = 1;
		}
	}
	return count_components(extra) <= before;
}

void TerrainCells::_bind_methods() {
	BIND_CONSTANT(STEEP);
	BIND_CONSTANT(BUILDING);
	BIND_CONSTANT(BLOCKED);
	BIND_CONSTANT(SUBMERGED);
	BIND_CONSTANT(FIELD_CAP_CELLS);

	ClassDB::bind_method(D_METHOD("setup", "width", "depth"), &TerrainCells::setup);
	ClassDB::bind_method(D_METHOD("grid_width"), &TerrainCells::grid_width);
	ClassDB::bind_method(D_METHOD("grid_depth"), &TerrainCells::grid_depth);
	ClassDB::bind_method(D_METHOD("mark_steep", "heights", "max_spread"), &TerrainCells::mark_steep);
	ClassDB::bind_method(D_METHOD("is_in_bounds", "cell"), &TerrainCells::is_in_bounds);
	ClassDB::bind_method(D_METHOD("is_passable", "cell"), &TerrainCells::is_passable);
	ClassDB::bind_method(D_METHOD("has_reason", "cell", "reason"), &TerrainCells::has_reason);
	ClassDB::bind_method(D_METHOD("set_reason", "cell", "reason", "on"), &TerrainCells::set_reason);
	ClassDB::bind_method(D_METHOD("set_reason_mask", "reason", "mask"), &TerrainCells::set_reason_mask);
	ClassDB::bind_method(D_METHOD("reason_mask", "reasons"), &TerrainCells::reason_mask);
	ClassDB::bind_method(D_METHOD("passable_cells"), &TerrainCells::passable_cells);
	ClassDB::bind_method(D_METHOD("mark_changed", "cells"), &TerrainCells::mark_changed);
	ClassDB::bind_method(D_METHOD("navigable_mask", "rect", "rings", "admit_k"), &TerrainCells::navigable_mask);
	ClassDB::bind_method(D_METHOD("is_navigable_for", "cell", "rings", "admit_k"), &TerrainCells::is_navigable_for);
	ClassDB::bind_method(D_METHOD("is_segment_navigable_for", "from", "to", "rings", "admit_k"),
			&TerrainCells::is_segment_navigable_for);
	ClassDB::bind_method(D_METHOD("clearance_at", "cell"), &TerrainCells::clearance_at);
	ClassDB::bind_method(D_METHOD("distance_to_obstacle", "cell"), &TerrainCells::distance_to_obstacle);
	ClassDB::bind_method(D_METHOD("component_at", "cell"), &TerrainCells::component_at);
	ClassDB::bind_method(D_METHOD("component_size", "component"), &TerrainCells::component_size);
	ClassDB::bind_method(D_METHOD("component_count"), &TerrainCells::component_count);
	ClassDB::bind_method(D_METHOD("largest_component"), &TerrainCells::largest_component);
	ClassDB::bind_method(D_METHOD("preserves_connectivity", "footprint"), &TerrainCells::preserves_connectivity);
}

} // namespace dissent
