extends GutTest

## What a piece is doing (ActionTracker), how its kind turns that into clips (AnimationProfile),
## the controller that announces the transitions (AnimationRig), and the action badges that
## stand in for animation until models have any. See gdd/systems/ux/unit-animation.md.

## load() inside each test, never a file-scope preload: a preload of an entity scene runs at
## PARSE time and can fire Tool's static registry initialiser before the registry exists.
const TRUCK: Dictionary = {"speed": 2.0, "vision": 8.0, "garrison": {"capacity": 3}}
const LOW_HEALTH: float = 0.1
const FULL_HEALTH: float = 1.0
const FAR_AWAY: Vector3 = Vector3(30.0, 0.0, 0.0)


## An order that is always in range and always says it is building — the shape of Assemble
## without a structure to assemble.
class AlwaysBuilding:
	extends MoveCommand

	func can_act(_a_actor: Commandable) -> bool:
		return true

	func acting_action(_a_actor: Commandable) -> ActionTracker.Action:
		return ActionTracker.Action.BUILDING

	func fulfill_action(_a_actor: Commandable) -> Variant:
		return self


func _context(
	a_action: ActionTracker.Action,
	a_health: float = FULL_HEALTH,
	a_mode: Movement.Mode = Movement.Mode.GROUNDED
) -> AnimationContext:
	var context: AnimationContext = AnimationContext.new()
	context.action = a_action
	context.health_fraction = a_health
	context.flight_mode = a_mode
	return context


func _clips(a_requests: Array[AnimationRequest]) -> Array:
	return a_requests.map(func(r: AnimationRequest) -> String: return "%s:%s" % [r.layer, r.clip])


#region ActionTracker
func test_a_change_of_action_is_announced_once() -> void:
	var tracker: ActionTracker = ActionTracker.new()
	watch_signals(tracker)
	tracker.observe(ActionTracker.Action.MOVING)
	tracker.observe(ActionTracker.Action.MOVING)
	assert_signal_emit_count(tracker, "action_changed", 1, "an unchanged tick says nothing")
	assert_signal_emitted_with_parameters(
		tracker, "action_changed", [ActionTracker.Action.IDLE, ActionTracker.Action.MOVING]
	)
	assert_eq(tracker.current_action(), ActionTracker.Action.MOVING)


func test_a_cue_changes_nothing_about_the_action() -> void:
	var tracker: ActionTracker = ActionTracker.new()
	tracker.observe(ActionTracker.Action.ATTACKING)
	watch_signals(tracker)
	tracker.cue(ActionTracker.CUE_EMITTED)
	assert_signal_emitted(tracker, "cued")
	assert_eq(tracker.current_action(), ActionTracker.Action.ATTACKING)


#endregion


#region Profiles
func test_the_default_profile_plays_one_body_clip_named_for_the_action() -> void:
	var profile: AnimationProfile = AnimationProfile.new()
	assert_eq(
		_clips(profile.requests_for(_context(ActionTracker.Action.BUILDING))), ["body:building"]
	)
	assert_eq(
		profile.requests_for_cue(ActionTracker.CUE_EMITTED, _context(ActionTracker.Action.IDLE)),
		[],
		"and ignores cues"
	)


func test_a_badly_hurt_biped_runs_wounded() -> void:
	var profile: BipedAnimationProfile = BipedAnimationProfile.new()
	assert_eq(
		_clips(profile.requests_for(_context(ActionTracker.Action.MOVING, LOW_HEALTH))),
		["body:moving_wounded"]
	)
	assert_eq(
		_clips(profile.requests_for(_context(ActionTracker.Action.MOVING))),
		["body:moving"],
		"a healthy one runs normally"
	)
	assert_eq(
		_clips(profile.requests_for(_context(ActionTracker.Action.IDLE, LOW_HEALTH))),
		["body:idle"],
		"only running changes"
	)


func test_rotors_spin_far_faster_in_the_air_than_on_the_ground() -> void:
	var profile: HoverAnimationProfile = HoverAnimationProfile.new()
	var landed: Array[AnimationRequest] = profile.requests_for(
		_context(ActionTracker.Action.IDLE, FULL_HEALTH, Movement.Mode.GROUNDED)
	)
	var hovering: Array[AnimationRequest] = profile.requests_for(
		_context(ActionTracker.Action.IDLE, FULL_HEALTH, Movement.Mode.HOVERING)
	)
	assert_eq(_clips(hovering), ["body:idle", "rotors:spin"], "a layer of their own")
	assert_gt(hovering[1].speed_scale, landed[1].speed_scale)


func test_a_turret_recoils_once_per_emission() -> void:
	var profile: TurretAnimationProfile = TurretAnimationProfile.new()
	var recoil: Array[AnimationRequest] = profile.requests_for_cue(
		ActionTracker.CUE_EMITTED, _context(ActionTracker.Action.ATTACKING)
	)
	assert_eq(_clips(recoil), ["turret:recoil"])
	assert_true(recoil[0].is_one_shot, "played once, not held")
	assert_eq(
		profile.requests_for_cue(&"something_else", _context(ActionTracker.Action.ATTACKING)), []
	)


#endregion


#region AnimationRig
func test_the_rig_announces_a_change_and_only_a_change() -> void:
	var rig: AnimationRig = AnimationRig.new()
	autofree(rig)
	rig.profile = BipedAnimationProfile.new()
	watch_signals(rig)
	rig.refresh(_context(ActionTracker.Action.MOVING))
	rig.refresh(_context(ActionTracker.Action.MOVING))
	assert_signal_emit_count(rig, "requests_changed", 1)
	rig.refresh(_context(ActionTracker.Action.MOVING, LOW_HEALTH))
	assert_signal_emit_count(rig, "requests_changed", 2, "a variant is a transition too")
	assert_eq(_clips(rig.held_requests()), ["body:moving_wounded"])


#endregion


#region What each command says it is doing
func test_commands_name_their_action() -> void:
	var message: CommandMessage = CommandMessage.new(null, null, null, Vector3.ZERO)
	assert_eq(
		MoveCommand.new(message).acting_action(null),
		ActionTracker.Action.ACTING,
		"a command that has not said"
	)
	assert_eq(Assemble.new(message).acting_action(null), ActionTracker.Action.BUILDING)
	assert_eq(Build.new(message).acting_action(null), ActionTracker.Action.BUILDING)
	assert_eq(Repair.new(message).acting_action(null), ActionTracker.Action.REPAIRING)
	assert_eq(Attack.new(message).acting_action(null), ActionTracker.Action.ATTACKING)


#endregion


#region Reported by the command tick
func _truck() -> Commandable:
	var commander: Commander = Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var truck: Commandable = FakePieces.unit(TRUCK)
	add_child_autofree(truck)
	truck.ownership.commander = commander
	return truck


func _tick(a_actor: Commandable) -> void:
	a_actor.command_receiver._update_state()
	a_actor._process_commands()


func test_an_acting_tick_reports_the_command_action() -> void:
	var truck: Commandable = _truck()
	truck.update_commands(
		(
			[AlwaysBuilding.new(CommandMessage.new(null, null, null, truck.global_position))]
			as Array[MoveCommand]
		)
	)
	_tick(truck)
	assert_eq(truck.action_tracker.current_action(), ActionTracker.Action.BUILDING)


func test_a_travelling_tick_reports_moving_and_an_empty_one_idle() -> void:
	var truck: Commandable = _truck()
	truck.update_commands(
		[MoveCommand.new(CommandMessage.new(null, null, null, FAR_AWAY))] as Array[MoveCommand]
	)
	_tick(truck)
	assert_eq(truck.action_tracker.current_action(), ActionTracker.Action.MOVING)
	truck.clear_command()
	_tick(truck)
	assert_eq(truck.action_tracker.current_action(), ActionTracker.Action.IDLE)


#endregion


#region Action badges
func test_building_and_unloading_carry_badges_and_nothing_else_does() -> void:
	assert_eq(
		StatusVisuals.action_badge(ActionTracker.Action.BUILDING), StatusVisuals.ACTION_BUILD_ICON
	)
	assert_eq(
		StatusVisuals.action_badge(ActionTracker.Action.UNLOADING), StatusVisuals.ACTION_UNLOAD_ICON
	)
	for action: int in ActionTracker.Action.values():
		if action not in [ActionTracker.Action.BUILDING, ActionTracker.Action.UNLOADING]:
			assert_null(StatusVisuals.action_badge(action), ActionTracker.Action.keys()[action])
#endregion
