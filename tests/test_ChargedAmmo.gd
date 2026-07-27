extends GutTest

## Tests for the CHARGED-ammunition half of the rearm mechanic (see Weapon.charged): a
## weapon that empties and stays empty until something recharges it, and the Loadout-level
## questions built on top of it.
##
## The docking half — flying to an airfield, claiming a pad, parking on it — is
## test_DockingBay.gd. These tests deliberately touch no Movement and no Map: the ammo
## model is meant to be independent of how a unit gets to its resupply, which is what lets
## a future non-airfield resupply reuse it unchanged.

func _weapon(a_charged: bool, a_clip: int, a_reload: int) -> Weapon:
	var w := Weapon.new()
	w.name = "TestWeapon"
	w.charged = a_charged
	w.clip_size = a_clip
	w.reload_time_ticks = a_reload
	w.split_time_ticks = 1
	# Weapon._ready asserts on target_mask and seeds a charged clip; add to the tree so
	# both run, rather than reproducing them here.
	var range_shape := CollisionShape3D.new()
	range_shape.name = "AttackRange"
	range_shape.shape = CylinderShape3D.new()
	w.add_child(range_shape)
	add_child_autofree(w)
	return w

func _loadout(a_weapons: Array) -> Loadout:
	var l := Loadout.new()
	l.name = "Loadout"
	add_child_autofree(l)
	for w: Weapon in a_weapons:
		w.reparent(l)
	return l

#region The charged flag
func test_a_charged_weapon_starts_with_a_full_clip() -> void:
	# An ordinary weapon is filled by its first physics tick; a charged one never runs that
	# countdown, so _ready has to seed it or the unit spawns holding one round.
	var w := _weapon(true, 12, 180)
	assert_eq(w.ammo(), 12, "a charged weapon is seeded full at _ready")
	assert_eq(w.ammo_fraction(), 1.0, "and reports itself full")

## THE BUG THIS PINS: _split_timer_ticks counts down every tick, and is_ready() asks for
## EXACTLY zero. An ordinary weapon gets away with it — the reload branch resets the timer
## to 0 every `reload_time_ticks` ticks — but a charged weapon skips that branch entirely, so its
## timer ran on past zero into negatives and never came back. The Drake sat with four
## rockets it could not fire and no way to notice: full clip, no shot, no charge spent.
func test_a_charged_weapon_stays_ready_while_it_waits_for_a_target() -> void:
	var w := _weapon(true, 4, 600)
	assert_true(w.is_ready(), "a full charged weapon starts ready")
	for i: int in 50:
		w._physics_process(0.0)
	assert_eq(w.ammo(), 4, "it has fired nothing, so it still holds four rounds")
	assert_true(w.is_ready(),
		"and it is still ready — idling past its cadence must not disarm it")

## The same latent fault on the ordinary side, where it was merely masked: such a weapon
## recovered on its next reload rather than never, so it looked like an occasional delay.
func test_an_ordinary_weapon_stays_ready_while_it_waits_for_a_target() -> void:
	var w := _weapon(false, 4, 600)
	for i: int in 50:
		w._physics_process(0.0)
	assert_true(w.is_ready(), "no target for fifty ticks does not empty a rifle")

## The between-shots cadence still has to BITE, or split_time_ticks would mean nothing.
func test_firing_still_holds_the_weapon_for_its_split_time() -> void:
	var w := _weapon(true, 4, 600)
	w.split_time_ticks = 5
	w.consume_round()
	assert_false(w.is_ready(), "the tick after a shot it is reloading")
	for i: int in 4:
		w._physics_process(0.0)
	assert_false(w.is_ready(), "still, one tick short of the cadence")
	w._physics_process(0.0)
	assert_true(w.is_ready(), "and ready again exactly on split_time_ticks")
	assert_eq(w.ammo(), 3, "having spent one of its four rounds")

func test_a_charged_weapon_does_not_refill_itself() -> void:
	var w := _weapon(true, 4, 60)
	for i in 4:
		w.consume_round()
	assert_eq(w.ammo(), 0, "four shots empty a four-round clip")
	# Far longer than reload_time_ticks: an ordinary weapon would have refilled several times.
	for i in 300:
		w._physics_process(0.0)
	assert_eq(w.ammo(), 0, "time alone never reloads a charged weapon")
	assert_false(w.is_ready(), "and it cannot fire while dry")

func test_an_ordinary_weapon_still_refills_on_its_timer() -> void:
	# The regression guard for the whole change: charged ammo must be strictly opt-in.
	var w := _weapon(false, 4, 10)
	w._physics_process(0.0)
	assert_eq(w.ammo(), 4, "an ordinary weapon fills on its first tick")
	for i in 4:
		w.consume_round()
	assert_eq(w.ammo(), 0, "and empties when fired")
	for i in 12:
		w._physics_process(0.0)
	assert_eq(w.ammo(), 4, "then reloads itself on reload_time_ticks, with no help")
#endregion

#region Recharging
func test_recharge_takes_reload_time_to_fill_a_clip() -> void:
	# reload_time_ticks means the same thing it does for an ordinary weapon — ticks for a FULL
	# clip — so the two kinds of weapon are balanced against one number.
	var w := _weapon(true, 10, 60)
	for i in 10:
		w.consume_round()
	assert_eq(w.ammo(), 0, "emptied")
	for i in 59:
		w.recharge()
	assert_lt(w.ammo(), 10, "not yet full one tick short of reload_time_ticks")
	w.recharge()
	assert_eq(w.ammo(), 10, "full after exactly reload_time_ticks ticks on the pad")

func test_recharge_advances_below_one_round_per_tick() -> void:
	# The usual shape: a 60-tick reload of a 6-round clip is 0.1 rounds/tick, which without
	# the fractional accumulator would floor to zero every tick and never fill at all.
	var w := _weapon(true, 6, 60)
	for i in 6:
		w.consume_round()
	for i in 10:
		w.recharge()
	assert_eq(w.ammo(), 1, "ten ticks of a 0.1/tick rate is exactly one round")

func test_recharge_reports_completion_and_never_overfills() -> void:
	# Ten ticks to the round, so a single tick is visibly "still filling" — the state the
	# docking sequence sits in while it waits.
	var w := _weapon(true, 3, 30)
	w.consume_round()
	assert_false(w.recharge(), "still filling")
	for i in 9:
		w.recharge()
	assert_true(w.recharge(), "reports done on reaching a full clip")
	for i in 20:
		w.recharge()
	assert_eq(w.ammo(), 3, "and a full clip never grows past clip_size")

func test_a_bay_charge_rate_scales_the_fill() -> void:
	# DockingBay.charge_rate is passed straight through as the tick weighting, so a
	# faster airfield turns the same aircraft around proportionally sooner.
	var w := _weapon(true, 10, 60)
	for i in 10:
		w.consume_round()
	for i in 30:
		w.recharge(2.0)
	assert_eq(w.ammo(), 10, "a 2x bay fills a 60-tick clip in 30 ticks")

func test_recharging_an_ordinary_weapon_is_a_no_op_that_reports_done() -> void:
	# A bay must release an aircraft whose weapons reload themselves rather than holding
	# it on the pad forever waiting for a fill that will never be its job.
	var w := _weapon(false, 4, 10)
	assert_true(w.recharge(), "an uncharged weapon is always 'done' charging")
#endregion

#region Loadout-level questions
func test_needs_recharge_is_the_docking_test_and_out_of_ammo_the_auto_test() -> void:
	# The two are deliberately different strengths: a unit still holding rounds finishes
	# its order, so only a fully dry one sends itself home — but a partly-empty one that
	# has been ORDERED to an airfield still has something to top up.
	var w := _weapon(true, 4, 40)
	var l := _loadout([w])
	assert_false(l.needs_recharge(), "a full clip needs nothing")
	assert_false(l.is_out_of_ammo(), "and is certainly not dry")
	w.consume_round()
	assert_true(l.needs_recharge(), "one round spent is worth topping up")
	assert_false(l.is_out_of_ammo(), "but three rounds left is not out of ammo")
	for i in 3:
		w.consume_round()
	assert_true(l.is_out_of_ammo(), "dry once the last round is gone")

func test_out_of_ammo_needs_every_charged_weapon_dry() -> void:
	# A unit that can still shoot SOMETHING keeps fighting. Two charged weapons, one of
	# them loaded, is not a reason to break off.
	var a := _weapon(true, 2, 20)
	var b := _weapon(true, 2, 20)
	var l := _loadout([a, b])
	a.consume_round()
	a.consume_round()
	assert_true(a.is_out_of_ammo(), "the first weapon is dry")
	assert_false(l.is_out_of_ammo(), "but the unit is not, while the second is loaded")
	b.consume_round()
	b.consume_round()
	assert_true(l.is_out_of_ammo(), "dry only once both are")

func test_a_loadout_with_no_charged_weapons_never_needs_rearming() -> void:
	# is_out_of_ammo() reports FALSE for a unit with nothing charged, which is what keeps
	# the auto-rearm check off every ordinary unit in the game.
	var l := _loadout([_weapon(false, 1, 10)])
	assert_false(l.has_charged_weapons(), "nothing here is charged")
	assert_false(l.is_out_of_ammo(), "so it is never 'out of ammo' in the rearm sense")
	assert_false(l.needs_recharge(), "and never wants a pad")
	assert_eq(l.ammo_fraction(), 1.0, "an ammo readout draws it full unconditionally")

func test_ammo_fraction_tracks_the_emptiest_charged_weapon() -> void:
	# A unit is only rearmed when its emptiest weapon is, so that is what the bar shows.
	var a := _weapon(true, 4, 40)
	var b := _weapon(true, 4, 40)
	var l := _loadout([a, b])
	a.consume_round()
	a.consume_round()
	assert_eq(l.ammo_fraction(), 0.5, "the half-empty weapon sets the reading")

func test_loadout_recharge_fills_every_charged_weapon() -> void:
	var a := _weapon(true, 2, 10)
	var b := _weapon(true, 2, 10)
	var l := _loadout([a, b])
	a.consume_round()
	b.consume_round()
	b.consume_round()
	var done: bool = false
	for i in 10:
		done = l.recharge()
	assert_true(done, "reports complete once all charged weapons are full")
	assert_false(l.needs_recharge(), "and the loadout agrees")
#endregion
