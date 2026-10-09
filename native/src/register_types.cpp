// Entry point of the dissent_native GDExtension: registers the native classes with the engine.

#include "fog_raster.h"
#include "minimap_compositor.h"
#include "terrain_cells.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

namespace {

void initialize_dissent_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(dissent::TerrainCells);
	GDREGISTER_CLASS(dissent::FogRaster);
	GDREGISTER_CLASS(dissent::MinimapCompositor);
}

void uninitialize_dissent_native(ModuleInitializationLevel p_level) {
}

} // namespace

extern "C" {

GDExtensionBool GDE_EXPORT dissent_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_dissent_native);
	init_obj.register_terminator(uninitialize_dissent_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
