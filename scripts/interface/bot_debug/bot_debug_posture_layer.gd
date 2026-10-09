class_name BotDebugPostureLayer
extends BotDebugLayer

## POSTURE: the four dials, the signals they read, the economy signals behind the commitment
## dial, and the clock's opening prior (gdd/systems/ai/debug-signals.md §Posture). Text only:
## a posture has no place on the map — it is what every mark in the other categories is
## tilted by.


func readout(a_bot: Bot) -> PackedStringArray:
	var brain: BotBrain = brain_of(a_bot)
	var posture: BotPosture = brain.get_posture() if brain != null else null
	if posture == null:
		return PackedStringArray(["no posture layer yet"])
	var now: float = a_bot.seconds_elapsed()
	var lines: PackedStringArray = PackedStringArray(["dials (held → target, ×factor):"])
	for dial: Dictionary in posture.debug_state(now):
		lines.append(
			(
				"  %s %.2f → %.2f, ×%.2f%s"
				% [
					dial["name"],
					dial["held"],
					dial["target"],
					dial["factor"],
					"" if dial["snaps_in"] < 0.0 else " (snaps in %.0f s)" % dial["snaps_in"]
				]
			)
		)
	lines.append("dead band %.2f, hold %.0f s" % [posture.dead_band, posture.hold_seconds])
	lines.append("signals:")
	lines.append_array(signal_lines(brain.posture_signals()))
	lines.append_array(income_lines(brain.get_income()))
	lines.append_array(prior_lines(a_bot, brain))
	return lines


static func signal_lines(signals: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for key: String in signals:
		lines.append("  %s %.2f" % [key, float(signals[key])])
	return lines


## Own income against the estimate, and the estimate's terms: the prior and each band's
## coverage and observation (lattice-and-topology has the bands' geometry).
static func income_lines(income: BotIncome) -> PackedStringArray:
	if income == null:
		return PackedStringArray()
	var terms: Dictionary = income.terms()
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"income %.1f/s own, enemy est. %.1f/s (prior %.1f/s, stale %d%%)"
				% [
					terms["own"],
					BotIncome.estimate(
						terms["prior"], terms["bands"], terms["elsewhere"], terms["stale"]
					),
					terms["prior"],
					roundi(float(terms["stale"]) * 100.0)
				]
			),
		]
	)
	for band: Dictionary in terms["bands"]:
		var centre: Vector2 = band["centre"]
		lines.append(
			(
				"  band at %d,%d: scouted %d%%, seen %.1f/s"
				% [
					roundi(centre.x),
					roundi(centre.y),
					roundi(float(band["coverage"]) * 100.0),
					band["observed"]
				]
			)
		)
	if float(terms["elsewhere"]) > 0.0:
		lines.append("  outside every band: %.1f/s" % float(terms["elsewhere"]))
	return lines


## The first-contact estimate and what the fields read for an arrival while nothing is believed.
static func prior_lines(bot: Bot, brain: BotBrain) -> PackedStringArray:
	var contact: float = brain.first_contact_seconds()
	if contact == INF:
		return PackedStringArray(["opening prior: none (no enemy force to come, or not asked)"])
	var fields: BotFields = bot.fields()
	var assumed: String = (
		"a source is believed"
		if fields == null or fields.has_enemy_sources()
		else "assumed arrival in %.0f s" % fields.prior_arrival_seconds
	)
	var phantom: PackedStringArray = PackedStringArray()
	for type: StringName in bot.phantom_force:
		phantom.append("%d %s" % [bot.phantom_force[type], type])
	var stands: bool = not bot.phantom_force_clocked(bot.fastest_answer_seconds()).is_empty()
	return PackedStringArray(
		[
			"opening prior: first contact %.0f s; %s" % [contact, assumed],
			(
				"phantom force: %s — %s"
				% [
					", ".join(phantom) if not phantom.is_empty() else "none",
					"weighed on the clock" if stands else "lapsed (an enemy unit was seen)"
				]
			),
		]
	)
