#include "minimap_compositor.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

namespace dissent {

namespace {
constexpr int BYTES_PER_PIXEL = 4;
constexpr uint8_t OPAQUE = 255;
} // namespace

void MinimapCompositor::set_pixels(const PackedInt32Array &p_cells, const PackedVector2Array &p_worlds) {
	ERR_FAIL_COND_MSG(p_cells.size() != p_worlds.size(), "MinimapCompositor.set_pixels: cells and worlds differ in size");
	cells = p_cells;
	worlds = p_worlds;
}

void MinimapCompositor::set_layer(const PackedColorArray &p_layer) {
	layer = p_layer;
}

void MinimapCompositor::set_palette(const Color &p_out_of_play, float p_explored_darken) {
	out_of_play = p_out_of_play;
	explored_darken = p_explored_darken;
}

Color MinimapCompositor::fogged(const Color &p_color, int p_visibility) const {
	switch (p_visibility) {
		case FogRaster::IN_SIGHT:
			return p_color;
		case FogRaster::EXPLORED:
			return p_color.darkened(explored_darken);
		default:
			return out_of_play;
	}
}

// Hot loop: every minimap pixel, every render frame.
PackedByteArray MinimapCompositor::compose(const Ref<FogRaster> &p_fog, bool p_reveal_all) const {
	const int64_t count = cells.size();
	PackedByteArray bytes;
	bytes.resize(count * BYTES_PER_PIXEL);
	uint8_t *out = bytes.ptrw();
	const int32_t *cell_at = cells.ptr();
	const Vector2 *world_at = worlds.ptr();
	const Color *layer_at = layer.ptr();
	const int64_t layer_size = layer.size();
	const FogRaster *fog = p_fog.is_valid() && p_fog->is_configured() ? p_fog.ptr() : nullptr;
	for (int64_t i = 0; i < count; i++) {
		Color color = out_of_play;
		const int cell = cell_at[i];
		if (cell >= 0 && cell < layer_size) {
			int visibility = FogRaster::UNSEEN;
			if (p_reveal_all) {
				visibility = FogRaster::IN_SIGHT;
			} else if (fog != nullptr) {
				visibility = fog->terrain_visibility_at(world_at[i]);
			}
			color = fogged(layer_at[cell], visibility);
		}
		out[0] = static_cast<uint8_t>(color.get_r8());
		out[1] = static_cast<uint8_t>(color.get_g8());
		out[2] = static_cast<uint8_t>(color.get_b8());
		out[3] = OPAQUE;
		out += BYTES_PER_PIXEL;
	}
	return bytes;
}

void MinimapCompositor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_pixels", "cells", "worlds"), &MinimapCompositor::set_pixels);
	ClassDB::bind_method(D_METHOD("set_layer", "layer"), &MinimapCompositor::set_layer);
	ClassDB::bind_method(D_METHOD("set_palette", "out_of_play", "explored_darken"), &MinimapCompositor::set_palette);
	ClassDB::bind_method(D_METHOD("compose", "fog", "reveal_all"), &MinimapCompositor::compose);
	ClassDB::bind_method(D_METHOD("fogged", "color", "visibility"), &MinimapCompositor::fogged);
}

} // namespace dissent
