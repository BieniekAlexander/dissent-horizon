#pragma once

// One commander's fog-of-war raster, kept incrementally: a per-pixel count of the vision sources
// covering it, and for each source the stamp it last added, so a tick re-stamps only the sources
// whose stamp changed. Fog (scripts/maps/fog.gd) owns one per commander and keeps the scene-facing
// parts: the registry, the texture upload, and hiding pieces under the shroud.
// See gdd/systems/combat/scan-and-vision-cost.md §The fog of war.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <map>
#include <tuple>
#include <unordered_map>
#include <vector>

namespace godot {
class CollisionShape3D;
}

namespace dissent {

class FogRaster : public godot::RefCounted {
	GDCLASS(FogRaster, godot::RefCounted)

public:
	// Display byte for "explored but not currently visible" (alpha ≈ 0.5 in the L8 texture).
	static constexpr int EXPLORED_ALPHA = 127;
	// An explored-buffer pixel no vision has ever touched.
	static constexpr int UNEXPLORED_BYTE = 255;
	// Three-state terrain visibility, the values of Fog.TerrainVisibility.
	static constexpr int UNSEEN = 0;
	static constexpr int EXPLORED = 1;
	static constexpr int IN_SIGHT = 2;

	// Size the raster and fix its world framing: pixel (0, 0) spans the world unit starting at
	// (center - half) and there are `p_points_per_unit` pixels per world unit (see
	// world_to_pixel). Nothing explored, nothing in sight, every pixel in play.
	void configure(int p_width, int p_height, const godot::Vector2 &p_center, double p_half_w, double p_half_d,
			double p_points_per_unit);
	bool is_configured() const { return width > 0 && height > 0; }
	int image_width() const { return width; }
	int image_height() const { return height; }

	// Hold every pixel where `p_in_play` is 0 out of play: transparent in both byte buffers, never
	// shrouded, explored or in vision. An empty mask puts every pixel in play.
	void set_play_mask(const godot::PackedByteArray &p_in_play);

	godot::Vector2i world_to_pixel(const godot::Vector2 &p_world_xz) const;
	godot::Vector2 pixel_to_world(int p_px, int p_py) const;

	// Bring the sight counts up to date with `p_sources` (the "los" group): re-stamp only a source
	// on `p_viewer_id`'s side (allies share vision) whose pixel or footprint changed, and withdraw
	// any stamp whose source no longer counts. Diffing each tick, rather than hooking each event that changes vision, is
	// what keeps it correct for the event nobody remembered.
	void update_sight(const godot::Array &p_sources, int p_viewer_id);
	// Permanently explore a disc of `p_radius_world` about `p_world_xz`.
	void reveal_region(const godot::Vector2 &p_world_xz, double p_radius_world);
	// The pixel offsets, relative to its centre pixel, that `p_vision_shape` covers in XZ, as
	// Vector2i. What update_sight stamps; exposed for tests that rebuild the fog from scratch.
	godot::Array vision_offsets(godot::CollisionShape3D *p_vision_shape);

	bool fog_clear_at(const godot::Vector2 &p_world_xz) const;
	bool explored_at(const godot::Vector2 &p_world_xz) const;
	int terrain_visibility_at(const godot::Vector2 &p_world_xz) const;
	// The in-play pixel indices under `p_world_points`, skipping points off the raster.
	godot::PackedInt32Array in_play_pixels(const godot::PackedVector2Array &p_world_points) const;
	bool any_in_sight(const godot::PackedInt32Array &p_pixels) const;

	godot::PackedByteArray fog_bytes() const;
	godot::PackedByteArray explored_bytes() const;
	godot::PackedInt32Array sight_counts() const;
	int stamp_count() const { return static_cast<int>(stamps.size()); }
	// True when the display bytes changed since the texture was last marked uploaded.
	bool is_texture_stale() const { return texture_stale; }
	void mark_texture_uploaded() { texture_stale = false; }
	// Overwrite the display bytes. A test seam: a fixture that wants a known pattern in sight
	// without placing vision sources for it.
	void set_fog_bytes(const godot::PackedByteArray &p_bytes);

	// Visibility of the pixel at flat index `p_idx` (which must be on the raster), for the
	// minimap's per-pixel compose.
	int visibility_at_index(int p_idx) const;
	int index_at(const godot::Vector2 &p_world_xz) const;

protected:
	static void _bind_methods();

private:
	struct Stamp {
		int px = 0;
		int py = 0;
		int footprint = -1;
	};

	int width = 0;
	int height = 0;
	godot::Vector2 center;
	double half_w = 0.0;
	double half_d = 0.0;
	double points_per_unit = 1.0;
	bool play_bounds_active = false;
	std::vector<uint8_t> play_mask;
	std::vector<uint8_t> explored;
	std::vector<uint8_t> fog;
	std::vector<int32_t> counts;
	std::unordered_map<uint64_t, Stamp> stamps;
	bool texture_stale = true;
	// (kind, half_x px, half_z px) -> footprint id; footprints[id] its offsets. Equal footprints
	// are one entry, so a stamp compares footprints by id.
	std::map<std::tuple<int, int, int>, int> footprint_ids;
	std::vector<std::vector<godot::Vector2i>> footprints;
	std::unordered_map<int, std::vector<godot::Vector2i>> discs;

	bool on_raster(int p_px, int p_py) const { return p_px >= 0 && p_px < width && p_py >= 0 && p_py < height; }
	bool in_play(int p_idx) const { return !play_bounds_active || play_mask[p_idx] != 0; }
	int footprint_for(godot::CollisionShape3D *p_vision_shape);
	void apply_stamp(const Stamp &p_stamp, int p_delta);
	const std::vector<godot::Vector2i> &disc(int p_radius_px);
};

} // namespace dissent
