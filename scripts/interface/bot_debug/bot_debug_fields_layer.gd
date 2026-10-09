class_name BotDebugFieldsLayer
extends BotDebugLayer

## FIELDS: the bot's spatial model on its lattice (BotFields) — the approach band, how soon the
## believed enemy can reach each cell, where the bot's own armed presence bends the enemy's
## walk, and the post the army stands at. Rules: gdd/systems/ai/world-model/lattice-and-topology.md.
##
## Per lattice cell: a magenta quad on the approach band; otherwise a quad shaded red (the
## enemy could be here within seconds) to blue (near the quiet horizon), and nothing at all on
## quiet ground, so the picture stays readable; a yellow outline where the presence penalty
## stands. The post: a white square with a stick. Everything drawn is a STORED read off the
## ready snapshot — the overlay never triggers a sweep.

## A little under half the pitch, so neighbouring cells read as distinct tiles.
const CELL_HALF: float = BotFields.PITCH * 0.45
const COLOR_BAND: Color = Color(1.0, 0.3, 0.9, 0.35)
const COLOR_SOON: Color = Color(1.0, 0.25, 0.2, 0.3)
const COLOR_LATE: Color = Color(0.3, 0.8, 1.0, 0.18)
const COLOR_PRESENCE: Color = Color(1.0, 0.85, 0.2, 0.6)
const COLOR_POST: Color = Color(1.0, 1.0, 1.0)
const POST_HALF: float = 1.2
const POST_STICK: float = 5.0


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var fields: BotFields = a_bot.fields()
	if fields == null:
		return
	var lattice: Lattice = fields.lattice
	var band: PackedByteArray = fields.approach_band(NavAgentClass.Size.SMALL)
	var penalty: PackedInt32Array = fields.presence_penalty()
	for index: int in lattice.cell_count():
		var xz: Vector2 = lattice.centre_of(lattice.cell_of(index))
		var position: Vector3 = _on_ground(a_bot, xz)
		if not band.is_empty() and band[index] != 0:
			a_pen.quad(position, CELL_HALF, COLOR_BAND)
		else:
			var arrival: float = fields.arrival_seconds_at(xz)
			if arrival < BotFields.QUIET_HORIZON_SECONDS:
				a_pen.quad(position, CELL_HALF, arrival_color(arrival))
		if not penalty.is_empty() and penalty[index] > 0:
			a_pen.square(position, CELL_HALF, COLOR_PRESENCE)
	if a_bot.get_structures().is_empty():
		return
	var home: Vector2 = VU.in_xz(a_bot.base_centroid())
	var post: Variant = fields.approach_post(
		home, a_bot.threat_direction(home), BotMilitary.STAGING_OFFSET
	)
	if post != null:
		var at: Vector3 = _on_ground(a_bot, post)
		a_pen.square(at, POST_HALF, COLOR_POST)
		a_pen.stick(at, POST_STICK, COLOR_POST)


func readout(a_bot: Bot) -> PackedStringArray:
	var fields: BotFields = a_bot.fields()
	if fields == null:
		return PackedStringArray(["no fields yet"])
	var lattice: Lattice = fields.lattice
	var band: int = _count(fields.approach_band(NavAgentClass.Size.SMALL))
	var explored: int = _count(fields.explored_mask())
	var passable: int = _count(fields.passable_mask(NavAgentClass.Size.SMALL))
	var home: Vector2 = VU.in_xz(a_bot.base_centroid())
	var arrival: float = fields.arrival_seconds_at(home)
	return PackedStringArray(
		[
			(
				"lattice %d × %d at pitch %.0f, rebuild %s"
				% [
					lattice.width,
					lattice.depth,
					lattice.pitch,
					"pending" if fields.is_pending() else "ready"
				]
			),
			(
				"explored %d%%, passable %d%% (SMALL)"
				% [
					roundi(100.0 * explored / maxf(1.0, lattice.cell_count())),
					roundi(100.0 * passable / maxf(1.0, lattice.cell_count()))
				]
			),
			(
				"believed sources: %d — approach band: %d cells"
				% [fields._enemy_sources().size(), band]
			),
			(
				"enemy arrival at base: %s"
				% (
					"none can"
					if arrival == INF
					else (
						"%.0f s%s"
						% [arrival, " (quiet)" if arrival > BotFields.QUIET_HORIZON_SECONDS else ""]
					)
				)
			),
		]
	)


## Red for an enemy that could be here now, through to blue at the quiet horizon.
static func arrival_color(seconds: float) -> Color:
	return COLOR_SOON.lerp(COLOR_LATE, clampf(seconds / BotFields.QUIET_HORIZON_SECONDS, 0.0, 1.0))


static func _count(mask: PackedByteArray) -> int:
	var total: int = 0
	for b: int in mask:
		total += b
	return total


## `a_xz` on the terrain, or at ground zero for a bot with no map (a test fixture).
static func _on_ground(bot: Bot, xz: Vector2) -> Vector3:
	var y: float = bot.map.terrain_height_at(xz) if bot.map != null else 0.0
	return Vector3(xz.x, y, xz.y)
