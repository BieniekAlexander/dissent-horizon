class_name WorldSound

## WHETHER, AND HOW LOUDLY, THE PLAYER HEARS A SOUND THE WORLD MAKES. A sound that is a
## consequence of what happens on the map — a death today; weapon fire and impacts when they get
## sounds — is heard only near the camera, and only where the viewer could see it happen. A sound
## that answers the player (a selection bark, an alert) is not a world sound and never asks here.
## Decided 2026-10-18 (Alex), when every death on the map was heard everywhere.
##
## Two rules:
## - NEAR THE CAMERA: full volume on screen, fading linearly to silence over a margin
##   MARGIN_FRACTION of the viewport's shorter side past each edge. Measured on screen rather
##   than in world units, so zooming out hears more of the map, as it shows more.
## - NOT UNDER FOG: a sound at a point the displayed fog hides is silent, or a death would tell
##   the player where an unseen enemy stands. The viewer's own pieces are always heard
##   (Fog.active_sight_test), and a lifted fog hides nothing.
##
## Presentation only: it reads the camera and the displayed fog, never the simulation, and draws
## no simulation randomness. gdd/systems/ux/README.md §World sounds.

#region Constants
## The fade band past each screen edge, as a fraction of the viewport's shorter side.
const MARGIN_FRACTION: float = 0.15
#endregion


#region Public API
## The gain (0 … 1, linear amplitude) a sound at world point `a_at`, made by a piece of commander
## `a_owner_id`, is heard at through `a_viewport`'s camera. 0 when there is no camera — nobody is
## listening (a headless run).
static func gain_at(a_at: Vector3, a_owner_id: int, a_viewport: Viewport) -> float:
	if a_viewport == null:
		return 0.0
	var camera: Camera3D = a_viewport.get_camera_3d()
	if camera == null or camera.is_position_behind(a_at):
		return 0.0
	var sight: Callable = Fog.active_sight_test(a_owner_id)
	if sight.is_valid() and not bool(sight.call(Vector2(a_at.x, a_at.z))):
		return 0.0
	return screen_gain(camera.unproject_position(a_at), a_viewport.get_visible_rect().size)


## The near-the-camera rule alone: 1 for a screen point inside a `a_viewport_size` viewport,
## falling linearly to 0 at MARGIN_FRACTION of its shorter side outside. Pure, for tests.
static func screen_gain(a_screen_point: Vector2, a_viewport_size: Vector2) -> float:
	var margin: float = minf(a_viewport_size.x, a_viewport_size.y) * MARGIN_FRACTION
	if margin <= 0.0:
		return 0.0
	var outside_x: float = maxf(maxf(-a_screen_point.x, a_screen_point.x - a_viewport_size.x), 0.0)
	var outside_y: float = maxf(maxf(-a_screen_point.y, a_screen_point.y - a_viewport_size.y), 0.0)
	var outside: float = Vector2(outside_x, outside_y).length()
	return clampf(1.0 - outside / margin, 0.0, 1.0)


## A one-shot of `a_stream` at gain `a_gain`, under `a_tree`'s current scene, freeing itself when
## done. Nothing is made for a gain of 0.
static func play(a_stream: AudioStream, a_gain: float, a_tree: SceneTree) -> void:
	if a_stream == null or a_gain <= 0.0 or a_tree == null or a_tree.current_scene == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = a_stream
	player.volume_db = linear_to_db(a_gain)
	player.finished.connect(player.queue_free)
	a_tree.current_scene.add_child(player)
	player.play()
#endregion
