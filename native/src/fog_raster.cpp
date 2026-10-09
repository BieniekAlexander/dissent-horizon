#include "fog_raster.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/cylinder_shape3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shape3d.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <cmath>
#include <unordered_set>

using namespace godot;

namespace dissent {

namespace {

// The script-side members update_sight reads off each vision source (Entity). Whose side a source
// is on stays the script's rule (Entity.is_on_side_of), asked rather than re-derived here.
const StringName &is_on_side_of_name() {
	static const StringName name("is_on_side_of");
	return name;
}
const StringName &grants_vision_name() {
	static const StringName name("grants_vision");
	return name;
}
const StringName &vision_shape_name() {
	static const StringName name("vision_range_shape");
	return name;
}

// Footprint kinds: an ellipse in XZ (cylinder, sphere, capsule) or a rectangle (box, and the
// bounding box of any other shape).
constexpr int ELLIPSE = 0;
constexpr int RECTANGLE = 1;

} // namespace

void FogRaster::configure(int p_width, int p_height, const Vector2 &p_center, double p_half_w, double p_half_d,
		double p_points_per_unit) {
	ERR_FAIL_COND_MSG(p_width < 0 || p_height < 0, "FogRaster.configure: negative size");
	ERR_FAIL_COND_MSG(p_points_per_unit <= 0.0, "FogRaster.configure: points_per_unit must be positive");
	width = p_width;
	height = p_height;
	center = p_center;
	half_w = p_half_w;
	half_d = p_half_d;
	points_per_unit = p_points_per_unit;
	const size_t count = static_cast<size_t>(width) * height;
	explored.assign(count, UNEXPLORED_BYTE);
	fog = explored;
	counts.assign(count, 0);
	play_mask.clear();
	play_bounds_active = false;
	stamps.clear();
	texture_stale = true;
}

void FogRaster::set_play_mask(const PackedByteArray &p_in_play) {
	if (p_in_play.is_empty()) {
		play_mask.clear();
		play_bounds_active = false;
		return;
	}
	ERR_FAIL_COND_MSG(p_in_play.size() != static_cast<int64_t>(explored.size()),
			"FogRaster.set_play_mask: mask must be one byte per pixel");
	play_mask.assign(p_in_play.ptr(), p_in_play.ptr() + p_in_play.size());
	play_bounds_active = true;
	for (size_t i = 0; i < play_mask.size(); i++) {
		if (play_mask[i] == 0) {
			explored[i] = 0; // out of play: fully transparent, never shrouded
			fog[i] = 0;
		}
	}
	texture_stale = true;
}

// Pixel p covers the world span [p, p + 1) / points_per_unit from (center - half): the span the
// terrain shader draws its texel over, and with the one-cell margin Fog frames with, exactly
// one terrain cell. The mapping is FLOOR, never round: a point on a pixel boundary (every cell
// centre, under round) would otherwise resolve toward +x and +z on both halves of a mirrored
// map, and two commanders in mirrored positions then read different pixels at the edge of the
// same vision disc. Measured 2026-10-09 as a start-side bias the bots carried on a map that was
// exactly its own image (gdd/systems/ai/bot-architecture.md §The start-position bias).
// Script float arithmetic is double precision, so the mapping is done in doubles even though the
// inputs arrive as single-precision Vector2s; a pixel boundary must fall where script put it.
Vector2i FogRaster::world_to_pixel(const Vector2 &p_world_xz) const {
	const double px = std::floor((static_cast<double>(p_world_xz.x) - center.x + half_w) * points_per_unit);
	const double py = std::floor((static_cast<double>(p_world_xz.y) - center.y + half_d) * points_per_unit);
	return Vector2i(static_cast<int>(px), static_cast<int>(py));
}

// The centre of pixel (px, py)'s span: the inverse of world_to_pixel.
Vector2 FogRaster::pixel_to_world(int p_px, int p_py) const {
	return Vector2(static_cast<float>((p_px + 0.5) / points_per_unit - half_w + center.x),
			static_cast<float>((p_py + 0.5) / points_per_unit - half_d + center.y));
}

int FogRaster::index_at(const Vector2 &p_world_xz) const {
	const Vector2i pixel = world_to_pixel(p_world_xz);
	return on_raster(pixel.x, pixel.y) ? pixel.y * width + pixel.x : -1;
}

// ── Sight counts ────────────────────────────────────────────────────────────────────────────

// Add (+1) or withdraw (-1) one stamp, touching the display bytes only where a pixel enters or
// leaves sight. Hot loop: every re-stamp walks a whole footprint, twice for a move.
void FogRaster::apply_stamp(const Stamp &p_stamp, int p_delta) {
	for (const Vector2i &offset : footprints[p_stamp.footprint]) {
		const int px = p_stamp.px + offset.x;
		const int py = p_stamp.py + offset.y;
		if (!on_raster(px, py)) {
			continue;
		}
		const int idx = py * width + px;
		if (!in_play(idx)) {
			continue; // out of play: keep it transparent, don't shroud or explore it
		}
		const int count = counts[idx] + p_delta;
		counts[idx] = count;
		if (count == 1 && p_delta > 0) {
			fog[idx] = 0;
			explored[idx] = EXPLORED_ALPHA;
			texture_stale = true;
		} else if (count == 0) {
			fog[idx] = explored[idx];
			texture_stale = true;
		}
	}
}

void FogRaster::update_sight(const Array &p_sources, int p_viewer_id) {
	if (!is_configured()) {
		return;
	}
	std::unordered_set<uint64_t> live;
	live.reserve(p_sources.size());
	for (int64_t i = 0; i < p_sources.size(); i++) {
		Object *entity = p_sources[i];
		if (entity == nullptr) {
			continue;
		}
		if (!static_cast<bool>(entity->call(is_on_side_of_name(), p_viewer_id)) ||
				!static_cast<bool>(entity->call(grants_vision_name()))) {
			continue;
		}
		CollisionShape3D *vision_shape = Object::cast_to<CollisionShape3D>(entity->get(vision_shape_name()));
		ERR_CONTINUE_MSG(vision_shape == nullptr, "FogRaster.update_sight: a vision source has no vision_range_shape");
		const uint64_t key = entity->get_instance_id();
		live.insert(key);
		// Centred on the shape, which may be offset from the entity origin.
		const Vector3 at = vision_shape->get_global_position();
		const Vector2i pixel = world_to_pixel(Vector2(at.x, at.z));
		const int footprint = footprint_for(vision_shape);
		auto found = stamps.find(key);
		if (found != stamps.end()) {
			const Stamp &old = found->second;
			if (old.px == pixel.x && old.py == pixel.y && old.footprint == footprint) {
				continue;
			}
			apply_stamp(old, -1);
		}
		const Stamp stamp{ pixel.x, pixel.y, footprint };
		apply_stamp(stamp, 1);
		stamps[key] = stamp;
	}
	for (auto it = stamps.begin(); it != stamps.end();) {
		if (live.count(it->first) == 0) {
			apply_stamp(it->second, -1);
			it = stamps.erase(it);
		} else {
			++it;
		}
	}
}

// The footprint id for a vision shape's XZ cross-section. The fog is a flat plane, so only that
// cross-section matters. Handles the shapes in use — cylinder, sphere and capsule (a circle, or
// an ellipse under non-uniform scale) and box (a rectangle) — and falls back to any other shape's
// bounding box, so a new shape type over-reveals at worst rather than failing. Shapes are assumed
// axis-aligned. Products are taken in double and stored single, as the script did.
int FogRaster::footprint_for(CollisionShape3D *p_vision_shape) {
	const Ref<Shape3D> shape = p_vision_shape->get_shape();
	const Basis basis = p_vision_shape->get_global_transform().basis;
	// Axis-aligned: the X and Z columns carry only horizontal scale, no rotation.
	const double scale_x = Vector2(basis.rows[0][0], basis.rows[2][0]).length();
	const double scale_z = Vector2(basis.rows[0][2], basis.rows[2][2]).length();

	int kind = RECTANGLE;
	float half_x = 0.0f;
	float half_z = 0.0f;
	if (const CylinderShape3D *cylinder = Object::cast_to<CylinderShape3D>(shape.ptr())) {
		kind = ELLIPSE;
		half_x = static_cast<float>(cylinder->get_radius() * scale_x);
		half_z = static_cast<float>(cylinder->get_radius() * scale_z);
	} else if (const SphereShape3D *sphere = Object::cast_to<SphereShape3D>(shape.ptr())) {
		kind = ELLIPSE;
		half_x = static_cast<float>(sphere->get_radius() * scale_x);
		half_z = static_cast<float>(sphere->get_radius() * scale_z);
	} else if (const CapsuleShape3D *capsule = Object::cast_to<CapsuleShape3D>(shape.ptr())) {
		kind = ELLIPSE;
		half_x = static_cast<float>(capsule->get_radius() * scale_x);
		half_z = static_cast<float>(capsule->get_radius() * scale_z);
	} else if (const BoxShape3D *box = Object::cast_to<BoxShape3D>(shape.ptr())) {
		const Vector3 size = box->get_size();
		half_x = static_cast<float>(size.x * 0.5 * scale_x);
		half_z = static_cast<float>(size.z * 0.5 * scale_z);
	} else if (shape.is_valid()) {
		const AABB aabb = shape->get_debug_mesh()->get_aabb();
		half_x = static_cast<float>(aabb.size.x * 0.5 * scale_x);
		half_z = static_cast<float>(aabb.size.z * 0.5 * scale_z);
	}
	const int hx = static_cast<int>(half_x * points_per_unit);
	const int hz = static_cast<int>(half_z * points_per_unit);

	const auto key = std::make_tuple(kind, hx, hz);
	const auto found = footprint_ids.find(key);
	if (found != footprint_ids.end()) {
		return found->second;
	}
	std::vector<Vector2i> offsets;
	for (int dz = -hz; dz <= hz; dz++) {
		for (int dx = -hx; dx <= hx; dx++) {
			bool inside = true;
			if (kind == ELLIPSE) {
				// Normalised ellipse test (a circle when hx == hz).
				const double nx = hx > 0 ? static_cast<double>(dx) / hx : 0.0;
				const double nz = hz > 0 ? static_cast<double>(dz) / hz : 0.0;
				inside = nx * nx + nz * nz <= 1.0;
			}
			if (inside) {
				offsets.push_back(Vector2i(dx, dz));
			}
		}
	}
	const int id = static_cast<int>(footprints.size());
	footprints.push_back(std::move(offsets));
	footprint_ids[key] = id;
	return id;
}

Array FogRaster::vision_offsets(CollisionShape3D *p_vision_shape) {
	Array out;
	ERR_FAIL_NULL_V(p_vision_shape, out);
	for (const Vector2i &offset : footprints[footprint_for(p_vision_shape)]) {
		out.push_back(offset);
	}
	return out;
}

const std::vector<Vector2i> &FogRaster::disc(int p_radius_px) {
	auto found = discs.find(p_radius_px);
	if (found != discs.end()) {
		return found->second;
	}
	std::vector<Vector2i> offsets;
	const int r2 = p_radius_px * p_radius_px;
	for (int dx = -p_radius_px; dx <= p_radius_px; dx++) {
		for (int dy = -p_radius_px; dy <= p_radius_px; dy++) {
			if (dx * dx + dy * dy <= r2) {
				offsets.push_back(Vector2i(dx, dy));
			}
		}
	}
	return discs.emplace(p_radius_px, std::move(offsets)).first->second;
}

void FogRaster::reveal_region(const Vector2 &p_world_xz, double p_radius_world) {
	if (!is_configured()) {
		return;
	}
	const Vector2i pixel = world_to_pixel(p_world_xz);
	const int radius_px = std::max(1, static_cast<int>(p_radius_world * points_per_unit));
	for (const Vector2i &offset : disc(radius_px)) {
		const int px = pixel.x + offset.x;
		const int py = pixel.y + offset.y;
		if (!on_raster(px, py)) {
			continue;
		}
		const int idx = py * width + px;
		if (!in_play(idx)) {
			continue; // out of play: stays transparent
		}
		explored[idx] = EXPLORED_ALPHA;
		if (counts[idx] == 0) {
			fog[idx] = EXPLORED_ALPHA;
			texture_stale = true;
		}
	}
}

// ── Lookups ─────────────────────────────────────────────────────────────────────────────────

// Out of play is not in vision: the mask is tested before the byte, because byte 0 means both
// "revealed" and "outside the play rectangle". Why: gdd/systems/combat/target-acquisition.md
// §Out of play is not in vision.
bool FogRaster::fog_clear_at(const Vector2 &p_world_xz) const {
	const int idx = index_at(p_world_xz);
	return idx >= 0 && in_play(idx) && fog[idx] == 0;
}

bool FogRaster::explored_at(const Vector2 &p_world_xz) const {
	const int idx = index_at(p_world_xz);
	return idx >= 0 && explored[idx] != UNEXPLORED_BYTE;
}

int FogRaster::visibility_at_index(int p_idx) const {
	if (!in_play(p_idx) || explored[p_idx] == UNEXPLORED_BYTE) {
		return UNSEEN; // out of play is not real terrain
	}
	return fog[p_idx] == 0 ? IN_SIGHT : EXPLORED;
}

int FogRaster::terrain_visibility_at(const Vector2 &p_world_xz) const {
	const int idx = index_at(p_world_xz);
	return idx >= 0 ? visibility_at_index(idx) : UNSEEN;
}

PackedInt32Array FogRaster::in_play_pixels(const PackedVector2Array &p_world_points) const {
	PackedInt32Array pixels;
	for (int64_t i = 0; i < p_world_points.size(); i++) {
		const int idx = index_at(p_world_points[i]);
		if (idx >= 0 && in_play(idx)) {
			pixels.push_back(idx);
		}
	}
	return pixels;
}

bool FogRaster::any_in_sight(const PackedInt32Array &p_pixels) const {
	for (int64_t i = 0; i < p_pixels.size(); i++) {
		const int idx = p_pixels[i];
		if (idx >= 0 && idx < static_cast<int>(fog.size()) && fog[idx] == 0) {
			return true;
		}
	}
	return false;
}

namespace {

template <typename T>
PackedByteArray to_bytes(const std::vector<T> &p_values) {
	PackedByteArray out;
	out.resize(p_values.size());
	uint8_t *w = out.ptrw();
	for (size_t i = 0; i < p_values.size(); i++) {
		w[i] = static_cast<uint8_t>(p_values[i]);
	}
	return out;
}

} // namespace

PackedByteArray FogRaster::fog_bytes() const {
	return to_bytes(fog);
}

PackedByteArray FogRaster::explored_bytes() const {
	return to_bytes(explored);
}

PackedInt32Array FogRaster::sight_counts() const {
	PackedInt32Array out;
	out.resize(counts.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < counts.size(); i++) {
		w[i] = counts[i];
	}
	return out;
}

void FogRaster::set_fog_bytes(const PackedByteArray &p_bytes) {
	ERR_FAIL_COND_MSG(p_bytes.size() != static_cast<int64_t>(fog.size()), "FogRaster.set_fog_bytes: size mismatch");
	fog.assign(p_bytes.ptr(), p_bytes.ptr() + p_bytes.size());
	texture_stale = true;
}

void FogRaster::_bind_methods() {
	BIND_CONSTANT(EXPLORED_ALPHA);
	BIND_CONSTANT(UNEXPLORED_BYTE);
	BIND_CONSTANT(UNSEEN);
	BIND_CONSTANT(EXPLORED);
	BIND_CONSTANT(IN_SIGHT);

	ClassDB::bind_method(D_METHOD("configure", "width", "height", "center", "half_w", "half_d", "points_per_unit"),
			&FogRaster::configure);
	ClassDB::bind_method(D_METHOD("is_configured"), &FogRaster::is_configured);
	ClassDB::bind_method(D_METHOD("image_width"), &FogRaster::image_width);
	ClassDB::bind_method(D_METHOD("image_height"), &FogRaster::image_height);
	ClassDB::bind_method(D_METHOD("set_play_mask", "in_play"), &FogRaster::set_play_mask);
	ClassDB::bind_method(D_METHOD("world_to_pixel", "world_xz"), &FogRaster::world_to_pixel);
	ClassDB::bind_method(D_METHOD("pixel_to_world", "px", "py"), &FogRaster::pixel_to_world);
	ClassDB::bind_method(D_METHOD("update_sight", "sources", "viewer_id"), &FogRaster::update_sight);
	ClassDB::bind_method(D_METHOD("reveal_region", "world_xz", "radius_world"), &FogRaster::reveal_region);
	ClassDB::bind_method(D_METHOD("vision_offsets", "vision_shape"), &FogRaster::vision_offsets);
	ClassDB::bind_method(D_METHOD("fog_clear_at", "world_xz"), &FogRaster::fog_clear_at);
	ClassDB::bind_method(D_METHOD("explored_at", "world_xz"), &FogRaster::explored_at);
	ClassDB::bind_method(D_METHOD("terrain_visibility_at", "world_xz"), &FogRaster::terrain_visibility_at);
	ClassDB::bind_method(D_METHOD("in_play_pixels", "world_points"), &FogRaster::in_play_pixels);
	ClassDB::bind_method(D_METHOD("any_in_sight", "pixels"), &FogRaster::any_in_sight);
	ClassDB::bind_method(D_METHOD("fog_bytes"), &FogRaster::fog_bytes);
	ClassDB::bind_method(D_METHOD("explored_bytes"), &FogRaster::explored_bytes);
	ClassDB::bind_method(D_METHOD("sight_counts"), &FogRaster::sight_counts);
	ClassDB::bind_method(D_METHOD("stamp_count"), &FogRaster::stamp_count);
	ClassDB::bind_method(D_METHOD("is_texture_stale"), &FogRaster::is_texture_stale);
	ClassDB::bind_method(D_METHOD("mark_texture_uploaded"), &FogRaster::mark_texture_uploaded);
	ClassDB::bind_method(D_METHOD("set_fog_bytes", "bytes"), &FogRaster::set_fog_bytes);
}

} // namespace dissent
