#pragma once

// The terrain grid's per-cell state and the fields derived from it, held natively because every
// moving unit's path-straightening test and every navmesh chunk rebuild walks it cell by cell.
// TerrainGrid (scripts/maps/terrain/terrain_grid.gd) owns one and keeps the scene-facing parts:
// the heightmap, the cells_changed signal and building ownership.
//
// Passability is one byte per cell (index z * width + x), a bitmask of impassability reasons; a
// cell is passable iff its byte is 0. Clearance, obstacle distance and region labels are derived
// from it lazily, and only around what changed.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <vector>

namespace dissent {

class TerrainCells : public godot::RefCounted {
	GDCLASS(TerrainCells, godot::RefCounted)

public:
	// Impassability reasons, one bit each, so clearing one reason leaves any other standing.
	static constexpr int STEEP = 1 << 0; // corner-height spread past the walkable slope (static)
	static constexpr int BUILDING = 1 << 1; // a structure occupies the cell
	static constexpr int BLOCKED = 1 << 2; // tile type, out of play, scripted no-go
	static constexpr int SUBMERGED = 1 << 3; // under a water body past wading depth

	// Where the distance and clearance fields saturate, in cells. Capping them is what lets a
	// change be absorbed locally: a cell further than this from every changed cell cannot see its
	// capped value move. It must be at least the largest value any reader compares against — the
	// erosion rings and corridor tiers (NavAgentClass, at most 3) and the bot's placement corridor
	// cap (4); 8 leaves room for a wider class.
	static constexpr int FIELD_CAP_CELLS = 8;

	void setup(int p_width, int p_depth);
	int grid_width() const { return width; }
	int grid_depth() const { return depth; }
	godot::Rect2i bounds_rect() const { return godot::Rect2i(0, 0, width, depth); }

	// Set STEEP on every cell whose four corner heights spread more than `p_max_spread`.
	// `p_heights` is the heightmap's corner grid, (width + 1) x (depth + 1), row-major.
	void mark_steep(const godot::PackedFloat32Array &p_heights, double p_max_spread);

	bool is_in_bounds(const godot::Vector2i &p_cell) const;
	bool is_passable(const godot::Vector2i &p_cell) const;
	bool has_reason(const godot::Vector2i &p_cell, int p_reason) const;
	// Set or clear one reason on one cell. Does not mark the fields stale: the caller batches
	// its cells into one mark_changed.
	void set_reason(const godot::Vector2i &p_cell, int p_reason, bool p_on);
	// Replace one reason across the whole grid from a cell-indexed mask (non-zero sets it; empty
	// clears it everywhere). Returns the cells whose bit flipped, as Vector2i.
	godot::Array set_reason_mask(int p_reason, const godot::PackedByteArray &p_mask);
	// One byte per cell, 1 where any of `p_reasons` is set.
	godot::PackedByteArray reason_mask(int p_reasons) const;
	// Every passable cell as Vector2i, x-major (all of column 0, then column 1, ...).
	godot::Array passable_cells() const;

	// Record that `p_cells` (Vector2i) changed state: the fields go stale around them, the
	// region labels everywhere.
	void mark_changed(const godot::Array &p_cells);

	godot::PackedByteArray navigable_mask(const godot::Rect2i &p_rect, int p_rings, int p_admit_k);
	bool is_navigable_for(const godot::Vector2i &p_cell, int p_rings, int p_admit_k);
	bool is_segment_navigable_for(const godot::Vector2 &p_from, const godot::Vector2 &p_to, int p_rings, int p_admit_k);
	int clearance_at(const godot::Vector2i &p_cell);
	int distance_to_obstacle(const godot::Vector2i &p_cell);

	int component_at(const godot::Vector2i &p_cell);
	int component_size(int p_component);
	int component_count();
	int largest_component();
	// Whether occupying `p_footprint` (Vector2i cells) leaves the passable cells in no more
	// 4-connected pieces than they are in now.
	bool preserves_connectivity(const godot::Array &p_footprint);

protected:
	static void _bind_methods();

private:
	int width = 0;
	int depth = 0;
	std::vector<uint8_t> state;
	std::vector<int32_t> clearance;
	std::vector<int32_t> dist;
	std::vector<int32_t> component;
	std::vector<int32_t> component_sizes;
	// True until the fields are first built over the whole grid; afterwards a change widens
	// dirty_rect and only that is recomputed.
	bool fields_dirty = true;
	godot::Rect2i dirty_rect;
	bool has_dirty_rect = false;
	// Labels have their own flag: they are read only by placement checks, in bursts, while the
	// fields are read by every navmesh bake, so sharing one would make every bake relabel.
	bool components_dirty = true;

	int index(int p_x, int p_z) const { return p_z * width + p_x; }
	bool in_bounds(int p_x, int p_z) const { return p_x >= 0 && p_x < width && p_z >= 0 && p_z < depth; }
	bool navigable_at(int p_x, int p_z, int p_rings, int p_admit_k) const;
	bool coverable(int p_x, int p_z, int p_admit_k) const;
	void ensure_fields();
	void ensure_components();
	void recompute_clearance(const godot::Rect2i &p_area);
	void recompute_distance(const godot::Rect2i &p_area);
	void recompute_components();
	int count_components(const std::vector<uint8_t> &p_extra_blocked) const;
};

} // namespace dissent
