extends "res://tools/selfplay/run_match.gd"

## TEMPORARY debug runner (delete me). Adds per-unit and objective detail to each brain sample.


func _brain_sample(a_brain: BotBrain) -> Dictionary:
	var base: Dictionary = super._brain_sample(a_brain)
	if a_brain == null or a_brain.bot == null:
		return base
	var bot: Bot = a_brain.bot
	var military: BotMilitary = a_brain._military
	var target: Actor = bot.nearest_enemy_structure_to_base()
	base["enemy_commanders"] = bot._enemy_commanders().map(func(c: Commander): return c.id)
	base["n_enemy_structures"] = bot.get_enemy_structures().size()
	base["n_enemy_units"] = bot.get_enemy_units().size()
	base["n_visible_enemies"] = bot.visible_enemies().size()
	base["base_centroid"] = str(bot.base_centroid().round())
	base["army_centroid"] = str(bot.army_centroid().round())
	if target != null:
		base["attack_target"] = (
			"%s cmd=%d pos=%s"
			% [target.id, target.commander_id, str(target.global_position.round())]
		)
	if military != null:
		base["objective"] = str(military._objective.round())
		base["has_objective"] = military._has_objective
		base["wave_active"] = military._wave_active
		base["combat_units"] = military._combat_units(bot.get_units()).size()
	var probe: Actor = target
	var lines: Array = []
	for u: Actor in bot.get_units():
		var cmd: Variant = u.current_command() if u.has_command() else null
		var armed: bool = u.weapon_inventory != null and u.weapon_inventory.has_weapons()
		var canhit: String = "-"
		if armed and probe != null:
			canhit = "vs_struct=%s" % str(u.weapon_inventory.weapon_for_target(probe) != null)
		var ammo: String = "ammo=%s" % str(u.can_use_weapons())
		var aggro_res: String = "-"
		if armed:
			var a1: MoveCommand = u.get_aggro_near_position()
			var a2: MoveCommand = u.get_aggro_near_position(
				null, null, Entity.TargetPriority.NON_COMBAT_STRUCTURES
			)
			var raw: Array = u.hostiles_in_aggro(10)
			var near: Array = bot.get_enemies_near(u.global_position, 6.0)
			aggro_res = (
				"aggroDef=%s aggroStruct=%s inShape=%d near6=%d built=%s idle=%s canuse=%s"
				% [
					str(a1 != null),
					str(a2 != null),
					raw.size(),
					near.size(),
					str(u.is_built),
					str(u.command_receiver.is_idle()),
					str(u.can_use_weapons())
				]
			)
		lines.append(
			(
				"%s armed=%s %s %s aggro=%s pos=%s cmd=%s dest=%s"
				% [
					u.id,
					armed,
					canhit,
					ammo + " " + aggro_res,
					str(u.aggro_radius()),
					str(u.global_position.round()),
					cmd.get_script().resource_path.get_file() if cmd != null else "IDLE",
					(
						str(cmd.message.position.round())
						if cmd != null and cmd.message != null and cmd.message.position != null
						else "-"
					)
				]
			)
		)
	base["units"] = lines
	var sc: BotScout = a_brain.get_scout()
	if sc != null:
		var unseen: int = 0
		var unseen_expired: int = 0
		var thr: float = bot.seconds_elapsed() - BotScout.SCOUT_EXPIRATION_TIMER
		for idx: Vector2i in sc._scout_grid:
			if not sc._ever_seen.has(idx):
				unseen += 1
				if sc._scout_grid[idx] < thr:
					unseen_expired += 1
		var sl2: Array = []
		for u2: Actor in sc._scouts:
			var c2: Variant = u2.current_command() if u2.has_command() else null
			sl2.append(
				(
					"%s pos=%s cmd=%s dest=%s"
					% [
						u2.id,
						str(u2.global_position.round()),
						c2.get_script().resource_path.get_file() if c2 != null else "IDLE",
						(
							str(c2.message.position.round())
							if c2 != null and c2.message != null
							else "-"
						)
					]
				)
			)
		base["scout"] = (
			"unseen=%d unseen_expired=%d stale=%.2f scouts=%s"
			% [unseen, unseen_expired, sc.stale_fraction(), str(sl2)]
		)
	var fog: Fog = Fog.for_commander(bot.id)
	base["fog"] = (
		"null"
		if fog == null
		else (
			"bytes=%d tex=%s clear_at_self=%s"
			% [
				fog._fog_bytes.size(),
				str(fog._fog_texture != null),
				str(fog.fog_clear_at(VU.in_xz(bot.base_centroid())))
			]
		)
	)
	base["current_scene"] = str(bot.get_tree().current_scene)
	return base
