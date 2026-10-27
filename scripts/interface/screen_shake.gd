class_name ScreenShake
extends Resource

## One kind of screen shake: how hard, how long, how fast. Authored as a `.tres` under
## resources/screen_shake/ and named by whatever raises it — an EmissionPhase's `screen_shake`,
## a deployment drop (Deployment.DROP_SHAKES). Nothing shakes that does not name one, so a
## source opts in per case, and a source is retuned by editing its resource alone.
##
## PRESENTATION ONLY. A shake moves the camera's lens (RTSCamera3D.shake), never the camera's
## position, a piece, or anything the simulation reads, so a replay or a networked peer that
## shakes differently — another view, another fog — plays the same match.
##
## Rules: gdd/systems/ux/screen-shake.md

## How far the view is thrown at the start, as a FRACTION OF THE VISIBLE HEIGHT: 0.02 moves the
## picture by 2% of the screen. Measured against the view rather than in world units so a shake
## reads the same at every zoom — the player feels the screen move, not the ground.
@export_range(0.0, 0.2, 0.001) var magnitude: float = 0.02
## How long it lasts. The throw fades to nothing over this, fastest at the start.
@export_range(0.0, 5.0, 0.01, "suffix:s") var duration_seconds: float = 0.4
## How often it changes direction. Low rolls; high rattles.
@export_range(1.0, 60.0, 0.5, "suffix:Hz") var frequency_hz: float = 20.0


## The throw `a_elapsed` seconds in, as a fraction of the visible height: `magnitude` at the
## start, falling quadratically to 0 at `duration_seconds` and staying there.
func amplitude_at(a_elapsed: float) -> float:
	if duration_seconds <= 0.0 or a_elapsed >= duration_seconds or a_elapsed < 0.0:
		return 0.0
	var left: float = 1.0 - a_elapsed / duration_seconds
	return magnitude * left * left


## Shake the player's screen with `a_shake`, raised by `a_source`, if the player can see it:
## `a_source` is inside the camera's view AND in the sight of the fog on screen (see is_seen).
## True when it shook. A null shake, a source out of the tree, or a viewport whose camera is not
## an RTSCamera3D (a headless test, an editor preview) is no shake.
static func play(a_shake: ScreenShake, a_source: Node3D) -> bool:
	if a_shake == null or a_source == null or not a_source.is_inside_tree():
		return false
	var camera := a_source.get_viewport().get_camera_3d() as RTSCamera3D
	if camera == null or not is_seen(camera, a_source):
		return false
	camera.shake(a_shake)
	return true


## Whether the player watching through `a_camera` sees `a_source`: on screen, and not under the
## fog. A shake from something the player cannot see would tell them it happened.
static func is_seen(a_camera: Camera3D, a_source: Node3D) -> bool:
	return a_camera.is_position_in_frustum(a_source.global_position) and is_in_sight(a_source)


## Whether `a_source` is in the sight of the fog on screen — the same fog that decides what is
## drawn (Fog.get_active_fog), so a spectator shakes for what THEY see. Lifted fog, or none,
## hides nothing. A structure is in sight when any cell of its footprint is, as the fog draws it;
## any other piece by its own pixel and its stealth (Entity.is_visible_to); a plain node by the
## pixel under it.
static func is_in_sight(a_source: Node3D) -> bool:
	if Fog.is_lifted():
		return true
	var active: Variant = Fog.get_active_fog()
	if not (active is Fog):
		return true
	var fog: Fog = active
	if a_source.is_in_group("fixture"):
		return fog.structure_in_vision(a_source)
	if a_source is Entity:
		return (a_source as Entity).is_visible_to(fog.viewer_commander_id())
	return fog.fog_clear_at(VU.in_xz(a_source.global_position))
