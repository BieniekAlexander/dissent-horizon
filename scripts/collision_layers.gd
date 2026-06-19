@tool
class_name CollisionLayers
extends EditorScript

#region Constants
enum Mask {
	MOVEMENT_OBSTRUCTION = 1 << 0,  ## Units only. Governs physical push-back during move_and_slide.
	TARGETABLE_GROUND    = 1 << 1,  ## Ground units + all structures. Queried by aggro, vision, projectiles, AoE, and bot scans.
	TARGETABLE_AIR       = 1 << 2,  ## Aerial / hovering units. The anti-air counterpart of TARGETABLE_GROUND (kept adjacent to it).
	STRUCTURE_BLOCKER    = 1 << 3,  ## Structures only. Queried by Attack line-of-fire raycasts.
	STEALTH              = 1 << 4,  ## Set at runtime by Stealth component. Queried by detection-range checks.
	TERRAIN              = 1 << 7,  ## Terrain StaticBody. Queried by ground-click raycasts.
	SELECTION            = 1 << 8,  ## Selectable Area3D. Queried by click-to-select raycasts.
}

## Both targetable layers OR'd together — the "find every attackable entity" mask
## for broad scans (aggro, vision, AoE, proximity, bot scans). Which of these layers
## a specific weapon may actually hit is filtered separately via Weapon.target_mask.
const TARGETABLE_ANY: int = Mask.TARGETABLE_GROUND | Mask.TARGETABLE_AIR
#endregion

#region Lifecycle
func _run():
	apply_to_project_settings()
#endregion

#region Public API
func apply_to_project_settings():
	for layer_num: int in range(1, 32+1):
		ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num, "Layer %s" % layer_num)

	for key in Mask.keys():
		var val: int = Mask[key]
		var layer_num: int = 1 + int(log(val) / log(2))  # 1-based Godot layer index
		ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num, key)

	ProjectSettings.save()
	print("CollisionLayers: project settings updated.")
#endregion
