extends GutTest

## The fog-of-war gate on sanction deployment: a commander may only call a vision-requiring
## sanction down where it currently HAS VISION. Having explored a spot at some point is not
## enough — a unit, structure or scout must be lighting it up right now — so a sanction can
## never be dropped blind into the shroud.
##
## The gate is the DEFAULT, not the rule: a sanction whose job is to see (a scan) sets
## `needs_vision = false` and opts out of it, which is the last group of tests below.
##
## The gate lives in Sanction.activate(), the single choke point every deployment path goes
## through (the player's click in RTSController, the bot in BotSanction), which is why it is
## tested here on Sanction rather than at either call site.
##
## Vision is faked with Commander subclasses rather than a real Fog: fog_clear_at needs a
## Map, a heightmap and a physics frame to mean anything, and none of that would make these
## assertions stronger. Commander.has_vision_at's own coverage is test_ScoutVision.gd.

class SeeingCommander extends Commander:
	func has_vision_at(_a_world_pos: Vector3) -> bool:
		return true


class BlindCommander extends Commander:
	func has_vision_at(_a_world_pos: Vector3) -> bool:
		return false


const TARGET: Vector3 = Vector3(12.0, 0.0, -4.0)

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)


## A sanction whose event scene is a bare AbstractEvent — a no-op execute(), which is all
## these tests need: what matters is WHETHER activate() reaches the event, not what it does.
func _sanction() -> Sanction:
	var event := AbstractEvent.new()
	var scene := PackedScene.new()
	scene.pack(event)
	event.free()
	var sanction := Sanction.new()
	sanction.sanction_name = "Test Sanction"
	sanction.cooldown_duration = 60.0
	sanction.event_scene = scene
	return sanction


func _commander(a_script: GDScript) -> Commander:
	var commander: Commander = a_script.new()
	add_child_autofree(commander)
	return commander


func test_can_target_follows_the_commanders_vision() -> void:
	assert_true(_sanction().can_target(TARGET, _commander(SeeingCommander)),
		"a commander with vision of the spot may target it")
	assert_false(_sanction().can_target(TARGET, _commander(BlindCommander)),
		"a commander with the spot under fog may not target it")


func test_can_target_is_unrestricted_without_a_commander() -> void:
	# Matches Commander.has_vision_at's own no-fog fallback, so tests and editor-driven
	# scripted events aren't blocked by a rig that has no fog of war at all.
	assert_true(_sanction().can_target(TARGET, null),
		"a null commander is unrestricted")


func test_activate_fires_on_a_visible_target() -> void:
	var sanction := _sanction()
	assert_true(sanction.activate(TARGET, _manager, _commander(SeeingCommander)),
		"activating on a visible spot should fire")


func test_activate_refuses_a_fogged_target() -> void:
	var sanction := _sanction()
	assert_false(sanction.activate(TARGET, _manager, _commander(BlindCommander)),
		"activating on a fogged spot should be refused")


func test_a_refused_activation_does_not_spend_the_cooldown() -> void:
	# The charge must survive a click into the fog: the sanction is still armed and ready
	# for a target the commander can actually see.
	var sanction := _sanction()
	sanction.activate(TARGET, _manager, _commander(BlindCommander))
	assert_true(sanction.activate(TARGET, _manager, _commander(SeeingCommander)),
		"a refused activation costs nothing — it still fires at a visible target")



# --- Opting out of the gate (needs_vision) ---------------------------------------

func test_the_vision_gate_is_on_by_default() -> void:
	# The fog gate is what scouting is FOR, so a sanction has to opt out of it rather
	# than into it — an un-authored one must not be droppable into the shroud.
	assert_true(Sanction.new().needs_vision,
		"a fresh sanction requires vision")


func test_an_sanction_that_does_not_need_vision_targets_the_shroud() -> void:
	var sanction := _sanction()
	sanction.needs_vision = false
	assert_true(sanction.can_target(TARGET, _commander(BlindCommander)),
		"a scan may be aimed at ground the commander cannot see")


func test_an_sanction_that_does_not_need_vision_fires_into_the_shroud() -> void:
	# The gate lives in activate(), so opting out has to reach the deployment path and
	# not just the predicate — otherwise a scan would still be refused where it matters.
	var sanction := _sanction()
	sanction.needs_vision = false
	assert_true(sanction.activate(TARGET, _manager, _commander(BlindCommander)),
		"activating a scan on a fogged spot should fire")



func test_needs_vision_survives_the_per_commander_duplicate() -> void:
	# SanctionGrid duplicates each Sanction so cooldowns are per-commander; the flag
	# has to come along or every actual player's scan would be fog-gated again.
	var template := Sanction.new()
	template.needs_vision = false
	assert_false((template.duplicate() as Sanction).needs_vision)


func test_the_colonial_scan_family_opts_out() -> void:
	# The authored case this flag exists for: every Scan reveals fog, so requiring vision
	# of the spot first would leave it useful only where it is not needed. Its siblings
	# in the same sanction grid must NOT have been swept along with it.
	var faction: Node = preload("res://scenes/factions/colonial.tscn").instantiate()
	autofree(faction)
	var scans: int = 0
	for unlock: SanctionUnlock in (faction as Faction).sanction_unlocks:
		if unlock == null or unlock.sanction == null:
			continue
		if unlock.sanction.sanction_name.begins_with("Scan"):
			scans += 1
			assert_false(unlock.sanction.needs_vision,
				"%s does not need vision" % unlock.sanction.sanction_name)
		else:
			assert_true(unlock.sanction.needs_vision,
				"%s still needs vision" % unlock.sanction.sanction_name)
	assert_eq(scans, 3, "all three Scan cells were checked")


# --- Sanctions with no aim point (needs_target) ----------------------------------

func test_sanctions_are_aimed_by_default() -> void:
	# A sanction is normally a thing you place; not needing an aim point is the
	# exception and has to be authored.
	assert_true(Sanction.new().needs_target)


func test_an_unaimed_sanction_waives_the_fog_gate_entirely() -> void:
	# There is no point to check, so the vision question cannot arise — and must not be
	# answerable "no", which would leave an un-aimable sanction permanently unusable.
	var sanction := _sanction()
	sanction.needs_target = false
	sanction.needs_vision = true
	assert_true(sanction.can_target(TARGET, _commander(BlindCommander)),
		"needs_target false short-circuits the gate even with needs_vision on")


func test_an_unaimed_sanction_still_fires() -> void:
	# It is deliberately NOT a passive: it is deployed on purpose and costs a charge —
	# the charge belonging to the CASTER that fires it, not to this shared resource.
	var sanction := _sanction()
	sanction.needs_target = false
	assert_true(sanction.activate(Vector3.ZERO, _manager, _commander(BlindCommander)))


func test_the_anarchical_global_emp_is_the_unaimed_one() -> void:
	# The authored case: it reaches every unit on the map, so asking where to put it
	# would be theatre — and would leave it armed, waiting on a click that cannot mean
	# anything. Every other cell in both grids is aimed.
	for path: String in ["res://scenes/factions/anarchical.tscn",
			"res://scenes/factions/colonial.tscn"]:
		var faction: Node = load(path).instantiate()
		autofree(faction)
		for unlock: SanctionUnlock in (faction as Faction).sanction_unlocks:
			var sanction: Sanction = unlock.sanction
			if sanction.sanction_name == "Global EMP":
				assert_false(sanction.needs_target, "Global EMP has nowhere to be pointed")
			else:
				assert_true(sanction.needs_target,
					"%s is aimed" % sanction.sanction_name)
