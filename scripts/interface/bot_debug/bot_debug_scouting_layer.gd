class_name BotDebugScoutingLayer
extends BotDebugLayer

## SCOUTING: how stale the bot's map knowledge is, where its scouts are going, and what
## another look is worth.
##
## The scout grid: a flat marker at each grid point, green (just scouted) → red (stale, about to
## expire), grey never seen, with a stick so it reads from the iso camera. Each scout: a ring,
## cyan → orange as it goes without progress toward the stall limit (white while it waits for a
## waypoint), and a line to the waypoint it was sent to.

const MARKER_HALF: float = 0.35
const STICK_HEIGHT: float = 0.8
const MARKER_ALPHA: float = 0.55
const COLOR_FRESH: Color = Color(0.2, 1.0, 0.3)
const COLOR_STALE: Color = Color(1.0, 0.2, 0.2)
const COLOR_NEVER: Color = Color(0.45, 0.45, 0.5)

const SCOUT_RING_RADIUS: float = 0.9
const GOAL_HALF: float = 0.5
const COLOR_SCOUT: Color = Color(0.3, 0.9, 1.0)
const COLOR_SCOUT_STALLED: Color = Color(1.0, 0.55, 0.1)
const COLOR_SCOUT_WAITING: Color = Color(1.0, 1.0, 1.0)


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var scout: BotScout = _scout_of(a_bot)
	if scout == null:
		return
	var now: float = a_bot.seconds_elapsed()
	for p: Dictionary in scout.debug_points():
		var color: Color = recency_color(p["last_seen"], p["ever_seen"], now)
		a_pen.quad(p["position"], MARKER_HALF, color)
		color.a = 1.0
		a_pen.stick(p["position"], STICK_HEIGHT, color)
	for s: Dictionary in scout.debug_scouts():
		var unit: Node3D = s["unit"]
		var color: Color = scout_color(s["stalled_for"], s["waiting"])
		a_pen.ring(unit.global_position, SCOUT_RING_RADIUS, color)
		if s["goal"] != null:
			a_pen.line(unit.global_position, s["goal"], color)
			a_pen.square(s["goal"], GOAL_HALF, color)


func readout(a_bot: Bot) -> PackedStringArray:
	var scout: BotScout = _scout_of(a_bot)
	if scout == null:
		return PackedStringArray(["no scout manager yet"])
	var scouts: Array = scout.debug_scouts()
	var waiting: int = scouts.filter(func(s: Dictionary) -> bool: return s["waiting"]).size()
	var stale: float = scout.stale_fraction()
	return PackedStringArray(
		[
			(
				"ever seen: %d%% (%d of %d points)"
				% [
					roundi(scout.observed_fraction() * 100.0),
					scout.observed_point_count(),
					scout.total_point_count()
				]
			),
			"stale now: %d%%" % roundi(stale * 100.0),
			(
				"scouts out: %d of %d allowed, %d waiting for a waypoint"
				% [scouts.size(), scout.unit_budget, waiting]
			),
			"first scout worth: %d energy" % roundi(scout.information_value_energy * stale),
		]
	)


## Green (just scouted) → red (stale at the expiry); grey if never seen.
static func recency_color(last_seen: float, ever_seen: bool, now: float) -> Color:
	if not ever_seen:
		return COLOR_NEVER
	var t: float = clampf((now - last_seen) / BotScout.SCOUT_EXPIRATION_TIMER, 0.0, 1.0)
	var c: Color = COLOR_FRESH.lerp(COLOR_STALE, t)
	c.a = MARKER_ALPHA
	return c


## White while waiting for a waypoint; otherwise cyan → orange as the scout nears the stall limit.
static func scout_color(stalled_for: float, waiting: bool) -> Color:
	if waiting:
		return COLOR_SCOUT_WAITING
	var t: float = clampf(stalled_for / BotScout.SCOUT_STALL_SECONDS, 0.0, 1.0)
	return COLOR_SCOUT.lerp(COLOR_SCOUT_STALLED, t)


static func _scout_of(bot: Bot) -> BotScout:
	var brain: BotBrain = brain_of(bot)
	return brain.get_scout() if brain != null else null
