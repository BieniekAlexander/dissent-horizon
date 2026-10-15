extends GutTest

## SIMULATION MATHS ROUNDS THE SAME ON EVERY PLATFORM. GDScript's sin, exp, atan2 and the rest —
## and the engine methods built on them (Vector2.rotated, randfn, a node's global basis) — call
## the platform's C library, whose last bits differ between macOS and Windows, so a networked
## match between them drifts apart. Simulation code calls DMath instead (native/src/dmath).
## gdd/systems/commands/netplay.md §Decisions, platforms.
##
## Asserted: DMath's output bits over fixed inputs hash to one value (on every platform the suite
## runs on — that is what makes the hash a cross-platform check); its functions and helpers agree
## with the engine's to within the engine's own rounding; and no simulation script calls the
## platform's maths (the SOURCE SCAN).

## The SHA-256 prefix of every DMath function's output bits over _inputs(). Recorded on macOS/arm64
## and Windows/x86_64 alike (2026-10-14); a different hash on any machine means DMath no longer
## computes the same bits everywhere.
const GOLDEN_BITS: String = "02b40b8abf718281"

## Builtins that reach the platform's maths. A bare call (`sin(x)`) or a method call
## (`v.rotated(a)`) of any of these in a simulation script is an offence.
const _BARE_CALLS: Array[String] = [
	"sin",
	"cos",
	"tan",
	"asin",
	"acos",
	"atan",
	"atan2",
	"exp",
	"log",
	"pow",
	"tanh",
	"sinh",
	"cosh",
	"ease"
]
const _METHOD_CALLS: Array[String] = [
	".angle()",
	".angle_to(",
	".angle_to_point(",
	".rotated(",
	".slerp(",
	".from_angle(",
	".get_euler(",
	".randfn(",
	"global_rotation",
	"Basis(Vector3.UP,",
	"rotation.y",
	"rotation.x",
	"rotation.z",
]
## Exact snippets that may name one of the above in simulation code, each for a reason. A
## piece's facing is its Entity.yaw; `rotation.y` is only a bare node's, or a model's.
const _ACKNOWLEDGED_SNIPPETS: Dictionary = {
	"a_owner.rotation.y": "Movement on a bare node, a test rig",
	"(at as Node3D).rotation.y": "VU.yaw_of outside a piece, a test rig",
	"root.rotation.y": "a fixture under a bare node, a test rig",
}

## Scripts that may use the platform's maths, each for a reason that never reaches the simulation.
const _PRESENTATION_ONLY: Dictionary = {
	"res://scripts/entities/components/altitude_indicator.gd": "a ring drawn under an aircraft",
	"res://scripts/entities/components/status_visuals.gd": "a pulsing badge",
	"res://scripts/interface/bot_debug/bot_debug_pen.gd": "debug drawing",
	"res://scripts/interface/hud/charge_dial.gd": "a HUD dial",
	"res://scripts/interface/hud/resource_pressure.gd": "a pulsing HUD bar",
	"res://scripts/interface/producer_affinity_indicator.gd": "a ring drawn on the ground",
	"res://scripts/interface/rts_camera_3d.gd": "the camera",
	"res://scripts/interface/rts_controller.gd": "the build preview's turn",
	"res://scripts/interface/scenario_highlight.gd": "a pulsing highlight",
	"res://scripts/maps/decoration/doodad_library.gd": "decoration, cosmetic only",
	"res://scripts/maps/decoration/map_decorator.gd": "decoration, cosmetic only",
}

## The engine's single-precision rounding, at the magnitudes _inputs() reaches (about 50).
const _ENGINE_TOLERANCE: float = 1e-4


#region DMath computes the same bits everywhere
func test_dmath_output_bits_match_the_golden_hash() -> void:
	assert_eq(_output_hash(), GOLDEN_BITS, "DMath's bits differ from every other platform's")


func test_the_walkable_slope_limit_is_the_dmath_tangent_of_the_view_pitch() -> void:
	assert_eq(TerrainGrid.MAX_SLOPE_DIFF, DMath.tan(deg_to_rad(TerrainGrid.MIN_VIEW_PITCH_DEGREES)))


#endregion


#region DMath computes what the engine computes
func test_scalar_functions_agree_with_the_platform() -> void:
	for x: float in _inputs():
		assert_almost_eq(DMath.sin(x), sin(x), 1e-12)
		assert_almost_eq(DMath.cos(x), cos(x), 1e-12)
		assert_almost_eq(DMath.atan2(x, 7.3), atan2(x, 7.3), 1e-12)
		assert_almost_eq(DMath.exp(x * 0.1), exp(x * 0.1), 1e-12 * exp(x * 0.1))
		assert_almost_eq(DMath.log(absf(x) + 0.001), log(absf(x) + 0.001), 1e-12)
		assert_almost_eq(DMath.pow(absf(x), 0.37), pow(absf(x), 0.37), 1e-12)
		assert_almost_eq(DMath.tanh(x * 0.1), tanh(x * 0.1), 1e-12)
		assert_almost_eq(DMath.acos(x / 50.0), acos(x / 50.0), 1e-12)


func test_vector_helpers_agree_with_the_engine_methods() -> void:
	var axis: Vector3 = Vector3(0.0, 0.6, 0.8)
	for x: float in _inputs():
		var a: Vector2 = Vector2(x, 3.0)
		var b: Vector2 = Vector2(-2.0, x * 0.5)
		assert_almost_eq(DMath.angle_to(a, b), a.angle_to(b), _ENGINE_TOLERANCE)
		assert_almost_eq(
			DMath.rotated(a, x * 0.2), a.rotated(x * 0.2), Vector2.ONE * _ENGINE_TOLERANCE
		)
		assert_almost_eq(DMath.slerp(a, b, 0.3), a.slerp(b, 0.3), Vector2.ONE * _ENGINE_TOLERANCE)
		assert_almost_eq(
			DMath.from_angle(x), Vector2.from_angle(x), Vector2.ONE * _ENGINE_TOLERANCE
		)
		var v: Vector3 = Vector3(x, 1.0, 2.0)
		var w: Vector3 = Vector3(-1.0, x, 0.5)
		assert_almost_eq(
			DMath.rotated_3d(v, axis, x * 0.2),
			v.rotated(axis, x * 0.2),
			Vector3.ONE * _ENGINE_TOLERANCE
		)
		assert_almost_eq(DMath.angle_to_3d(v, w), v.angle_to(w), _ENGINE_TOLERANCE)
		assert_almost_eq(VU.slerp_3d(v, w, 0.3), v.slerp(w, 0.3), Vector3.ONE * _ENGINE_TOLERANCE)
		assert_almost_eq(
			VU.yaw_basis(x) * v, Basis(Vector3.UP, x) * v, Vector3.ONE * _ENGINE_TOLERANCE
		)


## Godot's YXZ Euler order, both ways, including straight up and straight down.
func test_euler_helpers_agree_with_the_engine() -> void:
	for x: float in _inputs():
		var angles := Vector3(x * 0.03, x * 0.1, -x * 0.02)
		var built: Basis = VU.euler_basis(angles)
		var engine: Basis = Basis.from_euler(angles)
		for column: int in 3:
			assert_almost_eq(built[column], engine[column], Vector3.ONE * _ENGINE_TOLERANCE)
		assert_almost_eq(VU.euler_of(engine), engine.get_euler(), Vector3.ONE * _ENGINE_TOLERANCE)
	for pitch: float in [PI / 2.0, -PI / 2.0]:
		var locked := Basis.from_euler(Vector3(pitch, 0.6, 0.0))
		assert_almost_eq(VU.euler_of(locked), locked.get_euler(), Vector3.ONE * _ENGINE_TOLERANCE)


## Setting a node's rotation.y keeps its pitch, roll and scale; with_yaw does the same.
func test_with_yaw_turns_only_the_yaw() -> void:
	var node := Node3D.new()
	node.rotation = Vector3(0.2, 0.5, -0.1)
	node.scale = Vector3(0.45, 0.45, 0.45)
	var rest: Basis = node.basis
	node.rotation.y = 1.3
	var turned: Basis = VU.with_yaw(rest, 1.3)
	for column: int in 3:
		assert_almost_eq(turned[column], node.basis[column], Vector3.ONE * _ENGINE_TOLERANCE)
	node.free()


## Same formula and the same two draws, so the generator is left where the engine's draw would
## leave it — swapping one for the other moves no later draw in the stream.
func test_randfn_draws_as_the_engine_does_and_leaves_the_stream_where_it_would() -> void:
	var ours := RandomNumberGenerator.new()
	var engine := RandomNumberGenerator.new()
	ours.seed = 31
	engine.seed = 31
	for _i: int in 200:
		assert_almost_eq(DMath.randfn(ours, 2.0, 0.5), engine.randfn(2.0, 0.5), 1e-5)
		assert_eq(ours.state, engine.state)


#endregion


#region No simulation script uses the platform's maths
func test_no_simulation_script_calls_the_platforms_maths() -> void:
	var offenders: Array[String] = []
	for path: String in _gd_scripts_under("res://scripts"):
		if _PRESENTATION_ONLY.has(path):
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var code: String = _code_of(lines[i])
			if _calls_platform_maths(code):
				offenders.append("%s:%d" % [path, i + 1])
	assert_eq(
		offenders,
		[] as Array[String],
		"platform maths in simulation code — call DMath, or list a presentation-only script"
	)


#endregion


#region Helpers
## Fixed inputs over the range simulation code feeds these functions: angles, distances, scores.
func _inputs() -> PackedFloat64Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var xs := PackedFloat64Array()
	for _i: int in 500:
		xs.append(rng.randf_range(-50.0, 50.0))
	return xs


func _output_hash() -> String:
	var bits := PackedFloat64Array()
	var axis: Vector3 = Vector3(0.0, 0.6, 0.8)
	for x: float in _inputs():
		var a: Vector2 = Vector2(x, 3.0)
		var b: Vector2 = Vector2(-2.0, x * 0.5)
		var rotated: Vector2 = DMath.rotated(a, x * 0.2)
		var turned: Vector3 = DMath.rotated_3d(Vector3(x, 1.0, 2.0), axis, x * 0.2)
		(
			bits
			. append_array(
				[
					DMath.sin(x),
					DMath.cos(x),
					DMath.tan(x),
					DMath.asin(x / 50.0),
					DMath.acos(x / 50.0),
					DMath.atan(x),
					DMath.atan2(x, 7.3),
					DMath.exp(x * 0.1),
					DMath.log(absf(x) + 0.001),
					DMath.pow(absf(x), 0.37),
					DMath.tanh(x * 0.1),
					DMath.angle_to(a, b),
					rotated.x,
					rotated.y,
					turned.x,
					turned.y,
					turned.z,
					DMath.angle_to_3d(Vector3(x, 1.0, 2.0), Vector3(-1.0, x, 0.5)),
				]
			)
		)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in 100:
		bits.append(DMath.randfn(rng, 0.0, 1.0))
	return bits.to_byte_array().hex_encode().sha256_text().substr(0, 16)


func _gd_scripts_under(a_root: String) -> Array[String]:
	var found: Array[String] = []
	for entry: String in DirAccess.get_directories_at(a_root):
		found.append_array(_gd_scripts_under("%s/%s" % [a_root, entry]))
	for entry: String in DirAccess.get_files_at(a_root):
		if entry.ends_with(".gd"):
			found.append("%s/%s" % [a_root, entry])
	return found


## `a_line` with string literals blanked and any comment dropped: a doc comment naming sin() is
## not a call to it.
func _code_of(a_line: String) -> String:
	var out: String = ""
	var quote: String = ""
	for ch: String in a_line:
		if quote != "":
			if ch == quote:
				quote = ""
			continue
		if ch == '"' or ch == "'":
			quote = ch
			continue
		if ch == "#":
			break
		out += ch
	return out


func _calls_platform_maths(a_code_line: String) -> bool:
	# DMath's own functions share the builtins' names.
	var a_code: String = a_code_line.replace("DMath.", "DMath_")
	for snippet: String in _ACKNOWLEDGED_SNIPPETS:
		a_code = a_code.replace(snippet, "")
	for method: String in _METHOD_CALLS:
		if a_code.contains(method):
			return true
	for name: String in _BARE_CALLS:
		var at: int = a_code.find(name + "(")
		while at >= 0:
			var before: String = a_code[at - 1] if at > 0 else " "
			if not (before == "." or before == "_" or before.is_valid_identifier()):
				return true
			at = a_code.find(name + "(", at + 1)
	return false
#endregion
