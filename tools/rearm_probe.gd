extends Node3D

## Headless probe for the airfield docking sequence (Rearm + Movement's pad landing).
##
## GUT cannot cover this: the sequence needs a live Map for terrain heights and a real
## scene tree ticking physics, which is why CLAUDE.md records Rearm as untested end to end.
## This boots a flat test scenario, drops an airfield and one aircraft on it, issues the
## Rearm, and prints the whole flight tick by tick — Rearm's DockState, Movement's
## LandingState, the height offset, the distance to the pad and the clip.
##
## Run with:
##   godot --headless res://tools/rearm_probe.tscn -- [unit_scene] [start_distance]

const SCENARIO: String = "res://scenes/scenarios/test/nav_straight_line.tscn"
const AIRFIELD: String = "res://scenes/entities/structures/cl/cl_airField.tscn"
const MAX_TICKS: int = 1600
const SAMPLE_EVERY: int = 10

var _unit_scene: String = "res://scenes/entities/units/cl/cl_aircraftMedium_antiMech.tscn"
var _start_distance: float = 30.0
## Order the dock on a FULL clip — the case a player hits when they send an aircraft to
## top up before it is dry, and the only case a Drake could reach while Weapon's split
## timer stopped it firing at all.
var _keep_clip: bool = false
## Lateral offset of the aircraft's start from the runway axis, so it has to manoeuvre onto
## the centreline instead of already being on it.
var _offset: float = 0.0
## Ticks to keep watching AFTER the command ends, to see what the aircraft does next.
var _linger: int = 1400
var _fleet: Array[Actor] = []


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("res://"):
			_unit_scene = arg
		elif arg == "--full":
			_keep_clip = true
		elif arg.begins_with("off="):
			_offset = float(arg.substr(4))
		elif arg.is_valid_float():
			_start_distance = float(arg)
	_run.call_deferred()


func _run() -> void:
	var scenario: Node = (load(SCENARIO) as PackedScene).instantiate()
	add_child(scenario)
	await get_tree().physics_frame
	var map: Map = scenario.get_node_or_null("Map") as Map
	var nav: NavManager = map.nav_manager
	var waited: int = 0
	while not nav.is_ready() and waited < 600:
		await get_tree().physics_frame
		waited += 1
	for _i: int in 30:
		await get_tree().physics_frame

	var player: Commander = scenario.call("local_player")
	print("map ready (nav after %d ticks); player commander %d" % [waited, player.id])

	var centre: Vector2 = map.play_area().center

	var field := (load(AIRFIELD) as PackedScene).instantiate() as Actor
	field.initialize(map, player)
	field.global_position = Vector3(centre.x, 0.0, centre.y)
	map.add_structure(field, Vector2(centre.x, centre.y))
	await get_tree().physics_frame
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	print(
		(
			"airfield at %s | built=%s | pads=%d | free=%s"
			% [field.global_position, field.is_built, bay.capacity(), bay.has_free_pad()]
		)
	)
	for pad: DockingPad in _pads(bay):
		print("  pad %s -> %s deck=%.2f" % [pad.name, pad.dock_position(), pad.deck_height])
	for strip: Runway in bay.runways():
		print(
			(
				"  runway %s threshold=%s heading=%s inner=%s"
				% [strip.name, strip.takeoff_point(), strip.heading(), strip.inner_point()]
			)
		)

	var unit := (load(_unit_scene) as PackedScene).instantiate() as Actor
	unit.initialize(map, player)
	unit.global_position = Vector3(centre.x + _start_distance, 0.0, centre.y + _offset)
	await get_tree().physics_frame
	print(
		(
			"unit %s at %s | mode=%s | can_dock=%s | admits=%s | clip=%d/%d"
			% [
				unit.id,
				unit.global_position,
				unit.movement.mode,
				unit.docking != null,
				bay.admits(unit),
				unit.weapon_inventory.charged_ammo(),
				unit.weapon_inventory.charged_clip_size()
			]
		)
	)

	if not _keep_clip:
		# Empty the clip, so the docking actually has something to do.
		for w: Weapon in unit.weapon_inventory.charged_weapons():
			while w.ammo() > 0:
				w.consume_round()

	var message := CommandMessage.new(map, field, null, field.global_position)
	var order := Rearm.new(message)
	unit.update_commands(order)
	print("--- ordered Rearm ---")

	var last: String = ""
	for tick: int in MAX_TICKS:
		await get_tree().physics_frame
		var cmd: MoveCommand = unit.current_command()
		var live := cmd as Rearm
		var label: String = (
			"%s/%s"
			% [
				Rearm.DockState.keys()[live.state] if live != null else "-",
				Aerial.LandingState.keys()[unit.aerial._landing_state],
			]
		)
		if label != last or tick % SAMPLE_EVERY == 0:
			var strip: Runway = bay.runways()[0] if not bay.runways().is_empty() else null
			var fix_d: float = (
				VU.in_xz(unit.global_position).distance_to(VU.in_xz(strip.approach_point(4.77)))
				if strip != null
				else -1.0
			)
			print(
				(
					"t%4d %-22s pos=(%6.2f,%6.2f) h=%5.2f dFix=%6.2f vel=%5.2f rw=%-5s clip=%d"
					% [
						tick,
						label,
						unit.global_position.x,
						unit.global_position.z,
						unit.aerial._current_height_offset,
						fix_d,
						VU.in_xz(unit.velocity).length(),
						unit.docking.claimed_runway != null,
						unit.weapon_inventory.charged_ammo(),
					]
				)
			)
			last = label
		if cmd == null:
			print(
				(
					"--- command finished at tick %d, clip=%d ---"
					% [tick, unit.weapon_inventory.charged_ammo()]
				)
			)
			await _watch_idle(unit, bay)
			break
	get_tree().quit()


## What the aircraft does once the order is done: an idle FLYING unit orbits its anchor,
## so this is where "it flew off into the distance" would show up.
func _watch_idle(a_unit: Actor, a_bay: DockingBay) -> void:
	# Parked and full. Now give it somewhere to be, which is the ONLY thing that gets an
	# aircraft off a pad — and watch it taxi out to the threshold before it climbs.
	for _i: int in 20:
		await get_tree().physics_frame
	# Two MORE aircraft rolled out onto their own pads, then every one of them ordered off at
	# the same instant: the contended-runway case.
	var fleet: Array[Actor] = [a_unit]
	var production: Production = a_bay.get_parent().get_node("Production") as Production
	for i: int in 2:
		var extra := (load(_unit_scene) as PackedScene).instantiate() as Actor
		extra.initialize(a_unit.map, a_unit.commander)
		if production._spawn_on_pad(a_bay.get_parent(), extra):
			fleet.append(extra)
		await get_tree().physics_frame
	var away := Vector3(a_unit.global_position.x - 40.0, 0.0, a_unit.global_position.z + 40.0)
	for plane: Actor in fleet:
		plane.update_commands(MoveCommand.new(CommandMessage.new(plane.map, null, null, away)))
	print("--- ordered %d aircraft to %s ---" % [fleet.size(), away])
	_fleet = fleet
	for tick: int in _linger:
		await get_tree().physics_frame
		if tick % 10 == 0:
			var parts: PackedStringArray = PackedStringArray()
			for plane: Actor in _fleet:
				parts.append(
					(
						"%s h=%4.1f v=%4.1f %s%s"
						% [
							_state_of(plane),
							plane.height_offset(),
							VU.in_xz(plane.velocity).length(),
							"cmd" if plane.current_command() != null else "---",
							"R" if plane.docking.claimed_runway != null else " "
						]
					)
				)
			print("go+%3d  %s" % [tick, " | ".join(parts)])


func _pads(a_bay: DockingBay) -> Array[DockingPad]:
	var out: Array[DockingPad] = []
	for c: Node in a_bay.get_children():
		if c is DockingPad:
			out.append(c as DockingPad)
	return out


func _pad_distance(a_unit: Actor, a_bay: DockingBay) -> float:
	var best: float = INF
	for pad: DockingPad in _pads(a_bay):
		best = minf(
			best, VU.in_xz(a_unit.global_position).distance_to(VU.in_xz(pad.dock_position()))
		)
	return best


func _state_of(a_plane: Actor) -> String:
	if a_plane.aerial.is_docked():
		return "PARK"
	if a_plane.aerial.is_taxiing():
		return "TAXI"
	return "AIR " if a_plane.aerial.is_airborne() else "CLMB"
