#pragma once

// Draws the minimap's map layer through the fog, every render frame: each minimap pixel shows
// its terrain cell's layer colour unchanged in sight, darkened when explored, and the
// out-of-play colour when unseen. Minimap (scripts/maps/minimap.gd) owns one, feeds it the
// pixel framing and the layer, and draws pieces and markers over the result.

#include "fog_raster.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace dissent {

class MinimapCompositor : public godot::RefCounted {
	GDCLASS(MinimapCompositor, godot::RefCounted)

public:
	// Per minimap pixel, row-major: the layer cell under its centre (-1 outside the play area)
	// and the world XZ of that centre, for the fog lookup.
	void set_pixels(const godot::PackedInt32Array &p_cells, const godot::PackedVector2Array &p_worlds);
	// The map layer, one colour per terrain cell.
	void set_layer(const godot::PackedColorArray &p_layer);
	// The colour of an unseen or out-of-play pixel, and how far an explored one is darkened
	// (Color.darkened's amount).
	void set_palette(const godot::Color &p_out_of_play, float p_explored_darken);

	// RGBA8 bytes for the whole minimap. With no fog (null) and no reveal, every pixel is unseen.
	godot::PackedByteArray compose(const godot::Ref<FogRaster> &p_fog, bool p_reveal_all) const;
	// One layer colour as the fog shows it at `p_visibility` (a FogRaster visibility value).
	godot::Color fogged(const godot::Color &p_color, int p_visibility) const;

protected:
	static void _bind_methods();

private:
	godot::PackedInt32Array cells;
	godot::PackedVector2Array worlds;
	godot::PackedColorArray layer;
	godot::Color out_of_play;
	float explored_darken = 0.0f;
};

} // namespace dissent
