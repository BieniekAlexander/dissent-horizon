extends "res://tools/selfplay/run_match.gd"

## TEMPORARY scouting-diagnosis runner (delete me). Adds, per brain sample:
##   • every owned unit's command class + whether the scout module holds it
##   • _scout_score for every candidate, and which candidate would win
##   • _scouting_is_worth_it's two terms
##   • each live scout's waypoint, distance to it, and distance to the ENEMY start point
##   • how close the ever-seen set has got to the enemy start point
## Nothing here issues a command; it only observes.

var _starts: Array[Node3D] = []
var _slot_of_brain: Dictionary = {}


func _cache_starts() -> void:
	if not _starts.is_empty():
		return
	_starts = _start_point_markers()
	for i: int in _scenario.player_slots.size():
		var c: Commander = _scenario.player_slots[i].commander
		if c != null:
			_slot_of_brain[c.get_instance_id()] = i


func _enemy_start_for(a_slot: int) -> Vector3:
	if _starts.size() < 2:
		return Vector3.ZERO
	return _starts[1 - a_slot].global_position


func _cmd_name(a_u: Commandable) -> String:
	if not a_u.has_command():
		return "IDLE"
	var c: MoveCommand = a_u.current_command()
	return c.get_script().resource_path.get_file().replace(".gd", "")


func _brain_sample(a_brain: BotBrain) -> Dictionary:
	var base: Dictionary = super._brain_sample(a_brain)
	if a_brain == null or a_brain.bot == null:
		return base
	_cache_starts()
	var bot: Bot = a_brain.bot
	var sc: BotScout = a_brain.get_scout()
	var mil: BotMilitary = a_brain._military
	var slot: int = _slot_of_brain.get(bot.get_instance_id(), 0)
	var enemy_start: Vector3 = _enemy_start_for(slot)
	base["enemy_start"] = str(enemy_start.round())
	if mil != null:
		base["objective"] = str(mil._objective.round())
		base["combat_units"] = mil._combat_units(bot.get_units()).size()
	if sc == null:
		return base

	# ── candidate scoring ────────────────────────────────────────────────────
	var all_units: Array = bot.get_units()
	var scales: Dictionary = sc._score_scales(
		all_units.filter(func(u: Commandable) -> bool: return u.movement != null)
	)
	var rows: Array = []
	var best_id: String = ""
	var best_score: float = -INF
	for u: Commandable in all_units:
		if u.movement == null:
			continue
		var score: float = sc._scout_score(u, scales)
		var avail: bool = sc._unit_is_available(u)
		var held: bool = sc._scouts.has(u)
		var resp: int = sc._applicable_responsibility_count(u)
		rows.append(
			(
				"%s score=%.2f resp=%d avail=%s held=%s cmd=%s spd=%.1f vis=%.0f cost=%d"
				% [
					u.id,
					score,
					resp,
					str(avail),
					str(held),
					_cmd_name(u),
					u.movement.speed,
					bot.vision_radius(u),
					bot.unit_cost(u.id)
				]
			)
		)
		# what _pick_best_scout would actually see
		if avail and not held and not bot.is_suicide_aoe_unit(u) and score > best_score:
			best_score = score
			best_id = String(u.id)
	base["candidates"] = rows
	base["pick"] = "%s score=%.2f" % [best_id, best_score] if best_id != "" else "NONE_AVAILABLE"

	# ── worth-it terms ───────────────────────────────────────────────────────
	var stale: float = sc.stale_fraction()
	var value: float = BotScout.INFORMATION_VALUE_ENERGY * stale / float(sc._scouts.size() + 1)
	base["worth"] = "stale=%.2f value=%.0f scouts=%d" % [stale, value, sc._scouts.size()]

	# ── live scouts ──────────────────────────────────────────────────────────
	var slines: Array = []
	for entry: Variant in sc._scouts:
		if not is_instance_valid(entry) or (entry as Commandable).is_garrisoned():
			slines.append("<gone>")
			continue
		var u: Commandable = entry
		var dest: String = "-"
		var to_dest: float = -1.0
		if u.has_command() and u.current_command().message != null:
			var p: Vector3 = u.current_command().message.position
			dest = str(p.round())
			to_dest = u.global_position.distance_to(p)
		slines.append(
			(
				"%s pos=%s cmd=%s dest=%s d_dest=%.1f d_enemy_start=%.1f"
				% [
					u.id,
					str(u.global_position.round()),
					_cmd_name(u),
					dest,
					to_dest,
					u.global_position.distance_to(enemy_start)
				]
			)
		)
	base["scouts"] = slines

	# ── frontier geometry ────────────────────────────────────────────────────
	var nearest_seen: float = INF
	var unseen: int = 0
	var unseen_expired: int = 0
	var thr: float = bot.seconds_elapsed() - BotScout.SCOUT_EXPIRATION_TIMER
	var enemy_xz: Vector2 = VU.inXZ(enemy_start)
	for idx: Vector2i in sc._scout_grid:
		var pxz: Vector2 = VU.inXZ(sc._scout_grid_positions[idx])
		if sc._ever_seen.has(idx):
			nearest_seen = minf(nearest_seen, pxz.distance_to(enemy_xz))
		else:
			unseen += 1
			if sc._scout_grid[idx] < thr:
				unseen_expired += 1
	base["grid"] = (
		"unseen=%d unseen_expired=%d total=%d nearest_seen_to_enemy=%.1f"
		% [
			unseen,
			unseen_expired,
			sc._scout_grid.size(),
			0.0 if nearest_seen == INF else nearest_seen
		]
	)
	return base
