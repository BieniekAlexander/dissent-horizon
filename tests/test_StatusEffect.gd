extends GutTest

## Unit tests for the status-effect system (StatusEffect + subclasses, EffectApplicator,
## EntitySelectorAttribute).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_StatusEffect.gd
##
## A full Commandable needs a Map/scene to _ready (see test_Mine notes), so we use a
## StubCommandable that skips that heavy init and hand-sets only the fields the effects
## touch (movement, defense, attributes, receive_damage). The per-tick lifecycle is
## driven by calling _physics_process directly rather than waiting on the physics loop.


## A Commandable that records damage instead of routing it through the (uninitialised)
## command receiver. Crucially the stub is NEVER added to the scene tree: Commandable's
## @onready vars (@implicit_ready, which runs on tree-entry even if _ready is overridden)
## hard-reference $Ownership / $AvoidanceObstacle / $HPBar etc., which don't exist on a
## bare instance and would spew errors. None of the effect logic needs the host in the
## tree — effects are attached as children and ticked manually — so we keep it out.
class StubCommandable extends Commandable:
	var damage_taken: float = 0.0
	func receive_damage(_from: Commandable, amount: float) -> void:
		damage_taken += amount


func _make_unit(speed: float = 1.0, attrs: Array = []) -> StubCommandable:
	var u := StubCommandable.new()
	autofree(u)  # out-of-tree; free at test end (also frees attached effect children)
	var mv := Movement.new()
	autofree(mv)
	u.movement = mv
	mv.speed = speed
	var def := Defense.new()
	autofree(def)
	u.defense = def
	u.attributes = Set.new(attrs)
	return u


func _tick(effect: StatusEffect, n: int) -> void:
	for i in n:
		if is_instance_valid(effect) and effect.get_parent() != null:
			effect._physics_process(0.0)


func _status_children(u: Node) -> Array:
	return u.get_children().filter(func(c: Node) -> bool: return c is StatusEffect)


## Apply a fresh slow of the given mode/potency, returning the node actually live on `u`
## (a reapply discards the new node and reuses the existing one, so re-resolve it).
func _apply_slow(u: StubCommandable, mult: float, mode: StatusEffect.ReapplyMode,
		max_stacks: int = 1, duration: int = 0) -> SlowStatusEffect:
	var s := SlowStatusEffect.new()
	s.slow_multiplier = mult
	s.reapply_mode = mode
	s.max_stacks = max_stacks
	s.duration_ticks = duration
	s.apply_to(u)
	var live := _status_children(u)
	return live[0] as SlowStatusEffect if not live.is_empty() else null


#region SlowStatusEffect — single application
func test_slow_applies_and_restores_on_expiry() -> void:
	var u := _make_unit(1.0)
	var slow := SlowStatusEffect.new()
	slow.slow_multiplier = 0.5
	slow.duration_ticks = 3
	slow.apply_to(u)
	assert_almost_eq(u.movement.speed, 0.5, 0.0001, "slow halves speed on apply")
	_tick(slow, 3)
	assert_almost_eq(u.movement.speed, 1.0, 0.0001, "speed restored after duration")
	assert_false(slow.is_active(), "effect inactive after expiry")
#endregion


#region Reapplication: REFRESH
func test_refresh_does_not_stack_and_resets_timer() -> void:
	var u := _make_unit(1.0)
	var a := _apply_slow(u, 0.5, StatusEffect.ReapplyMode.REFRESH, 1, 5)
	assert_almost_eq(u.movement.speed, 0.5, 0.0001, "one stack of slow")
	_tick(a, 3)  # _elapsed = 3 of 5

	# Reapply: should refresh `a`'s timer, not add a second instance.
	_apply_slow(u, 0.5, StatusEffect.ReapplyMode.REFRESH, 1, 5)
	assert_eq(_status_children(u).size(), 1, "refresh keeps a single instance")
	assert_almost_eq(u.movement.speed, 0.5, 0.0001, "refresh does not stack potency")

	# Timer was reset, so it now survives a full 5 more ticks.
	_tick(a, 4)
	assert_almost_eq(u.movement.speed, 0.5, 0.0001, "still active 4 ticks after refresh")
	_tick(a, 1)
	assert_almost_eq(u.movement.speed, 1.0, 0.0001, "expires 5 ticks after the refresh")
#endregion


#region Reapplication: STACK
func test_stack_mode_scales_potency_and_caps() -> void:
	var u := _make_unit(1.0)
	var a := _apply_slow(u, 0.5, StatusEffect.ReapplyMode.STACK, 3, 0)
	assert_almost_eq(u.movement.speed, 0.5, 0.0001, "1 stack → ×0.5")
	_apply_slow(u, 0.5, StatusEffect.ReapplyMode.STACK, 3, 0)
	assert_almost_eq(u.movement.speed, 0.25, 0.0001, "2 stacks → ×0.25")
	_apply_slow(u, 0.5, StatusEffect.ReapplyMode.STACK, 3, 0)
	assert_almost_eq(u.movement.speed, 0.125, 0.0001, "3 stacks → ×0.125")
	assert_eq(_status_children(u).size(), 1, "stacks-as-data: still one node")
	assert_eq(a.stacks, 3, "stack count tracked on the node")

	# Beyond max_stacks: no further effect.
	_apply_slow(u, 0.5, StatusEffect.ReapplyMode.STACK, 3, 0)
	assert_almost_eq(u.movement.speed, 0.125, 0.0001, "capped at max_stacks = 3")
	assert_eq(a.stacks, 3, "stack count does not exceed max_stacks")

	a.remove()
	assert_almost_eq(u.movement.speed, 1.0, 0.0001, "remove undoes all stacks")


func test_dot_stacks_scale_damage() -> void:
	var u := _make_unit()
	var dot := DamageOverTimeStatusEffect.new()
	dot.damage_per_tick = 10.0
	dot.tick_rate = 10
	dot.duration_ticks = 100
	dot.reapply_mode = StatusEffect.ReapplyMode.STACK
	dot.max_stacks = 3
	dot.apply_to(u)

	# Add one stack (reapply) before the first damage tick.
	var dot2 := DamageOverTimeStatusEffect.new()
	dot2.apply_to(u)
	assert_eq(dot.stacks, 2, "reapply added a stack")

	_tick(dot, 10)
	assert_almost_eq(u.damage_taken, 20.0, 0.0001, "2 stacks → 20 damage per tick boundary")
#endregion


#region DamageOverTimeStatusEffect — single application
func test_dot_deals_periodic_damage() -> void:
	var u := _make_unit()
	var dot := DamageOverTimeStatusEffect.new()
	dot.damage_per_tick = 10.0
	dot.tick_rate = 10
	dot.duration_ticks = 100
	dot.apply_to(u)
	_tick(dot, 100)
	assert_almost_eq(u.damage_taken, 100.0, 0.0001, "10 damage every 10 ticks over 100 ticks = 100")


func test_dot_no_free_hit_on_first_tick() -> void:
	var u := _make_unit()
	var dot := DamageOverTimeStatusEffect.new()
	dot.damage_per_tick = 5.0
	dot.tick_rate = 10
	dot.duration_ticks = 100
	dot.apply_to(u)
	_tick(dot, 9)
	assert_eq(u.damage_taken, 0.0, "no damage before the first tick_rate boundary")
	_tick(dot, 1)
	assert_almost_eq(u.damage_taken, 5.0, 0.0001, "first hit lands exactly at tick 10")
#endregion


#region max_stacks read-only validation
func test_max_stacks_forced_and_readonly_outside_stack_mode() -> void:
	var e := SlowStatusEffect.new()
	autofree(e)
	e.reapply_mode = StatusEffect.ReapplyMode.REFRESH
	e.max_stacks = 5
	var prop := {"name": "max_stacks", "usage": 0}
	e._validate_property(prop)
	assert_eq(e.max_stacks, 1, "max_stacks forced to 1 outside STACK mode")
	assert_ne(prop.usage & PROPERTY_USAGE_READ_ONLY, 0, "max_stacks made read-only")


func test_max_stacks_editable_in_stack_mode() -> void:
	var e := SlowStatusEffect.new()
	autofree(e)
	e.reapply_mode = StatusEffect.ReapplyMode.STACK
	e.max_stacks = 5
	var prop := {"name": "max_stacks", "usage": PROPERTY_USAGE_READ_ONLY}
	e._validate_property(prop)
	assert_eq(e.max_stacks, 5, "max_stacks preserved in STACK mode")
	assert_eq(prop.usage & PROPERTY_USAGE_READ_ONLY, 0, "max_stacks editable in STACK mode")
#endregion


#region EntitySelectorAttribute
func test_selector_keeps_units_with_attribute() -> void:
	var mech := _make_unit(1.0, [Entity.Attribute.MECH])
	var bio := _make_unit(1.0, [Entity.Attribute.BIO])
	var sel := EntitySelectorAttribute.new()
	autofree(sel)
	sel.attribute = Entity.Attribute.MECH
	sel.require_present = true
	var kept: Array[Commandable] = sel.filter([mech, bio], null)
	assert_eq(kept, [mech] as Array[Commandable], "keeps only the MECH unit")


func test_selector_keeps_units_without_attribute() -> void:
	var mech := _make_unit(1.0, [Entity.Attribute.MECH])
	var bio := _make_unit(1.0, [Entity.Attribute.BIO])
	var sel := EntitySelectorAttribute.new()
	autofree(sel)
	sel.attribute = Entity.Attribute.MECH
	sel.require_present = false
	var kept: Array[Commandable] = sel.filter([mech, bio], null)
	assert_eq(kept, [bio] as Array[Commandable], "keeps only the non-MECH unit")
#endregion


#region EffectApplicator
func test_applicator_applies_template_to_selected_recipients() -> void:
	var mech := _make_unit(1.0, [Entity.Attribute.MECH])
	var bio := _make_unit(1.0, [Entity.Attribute.BIO])

	var applicator := EffectApplicator.new()
	autofree(applicator)
	var template := SlowStatusEffect.new()
	template.slow_multiplier = 0.5
	template.duration_ticks = 0
	applicator.add_child(template)
	var sel := EntitySelectorAttribute.new()
	sel.attribute = Entity.Attribute.MECH
	applicator.add_child(sel)

	applicator.apply([mech, bio], null)

	assert_almost_eq(mech.movement.speed, 0.5, 0.0001, "selected MECH unit slowed")
	assert_almost_eq(bio.movement.speed, 1.0, 0.0001, "filtered-out BIO unit untouched")
	# The template itself stays inert under the applicator (it was duplicated, not consumed).
	assert_almost_eq(template.slow_multiplier, 0.5, 0.0001, "template preserved")
#endregion
