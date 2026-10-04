class_name ChargeDial
extends Control

## One circle saying how much of a rechargeable thing a piece has: an ability POOL, a weapon
## whose payload takes long enough to come back that a player plans around it, or a producer's
## current job.
##
## THE CIRCLE IS A PIE OF CHARGES. It is cut into one sector per charge the thing can hold —
## a plain cooldown is one whole disc — and the vocabulary is the same at every sector count:
##
##   saturated sector    a charge you HAVE
##   growing sweep       the next one coming back on its own, clockwise from 12 o'clock
##   desaturated sector  an empty charge that will NOT come back on its own (a charged weapon
##                       waiting to rearm)
##
## Colours and their reasons: gdd/systems/ux/ui/actor-cards.md §The charge dial.

## Every dial is this hue; position on the card, not colour, says which pool or weapon it is.
## Violet because nothing else on a card is: red is hit points, blue training, amber saving
## up, green paid-for and garrison.
const HUE: Color = Color(0.62, 0.42, 0.95)
## What a charge still coming back is drawn in: the dial's hue, part-way to grey, so a sweep
## reads as "not yours yet" beside the saturated charges that are.
const RECHARGING_SATURATION: float = 0.5
## What an empty charge that will not come back on its own is drawn in: almost grey, and
## dimmer, because nothing is happening to it.
const STALLED_SATURATION: float = 0.25
const STALLED_VALUE: float = 0.55
const TRACK_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)
## A weapon earns a dial only when its payload comes back this slowly, or not on its own at
## all. A rifle's sub-second reload changes nothing a player decides; a five-second salvo is
## something they wait for. In SECONDS, as docs author reload_time.
const WEAPON_MIN_RELOAD_SECONDS: float = 5.0
## Arc segments per full turn; enough that an 8-pixel circle has no visible facets.
const ARC_STEPS: int = 32


## What one dial draws, separated from the node so it can be derived and tested without one.
class State:
	extends RefCounted
	## One sector per charge the thing can hold; at least one.
	var sectors: int = 1
	## Charges held — the saturated sectors.
	var full: int = 0
	## How far the recharge has got, 0.0–1.0, across `progress_sectors` sectors past the
	## full ones: one for a pool (a charge comes back at a time), every empty sector for a
	## weapon (its clip refills whole).
	var progress: float = 0.0
	var progress_sectors: int = 1
	## False when an empty charge waits on something outside the piece — drawn desaturated.
	var is_self_recharging: bool = true


var state: State = State.new()


#region Deriving a state
## The dial for pool `index` of `abilities`. Every pool recharges on its own today.
## TODO: a pool HELD by what it put into play (Abilities.hold_recharge — a Sapper's planted
## charge) is not recharging on its own while held, and could draw desaturated like a charged
## weapon. Not built: Alex scoped the stalled state to weapons for now (2026-10-04).
static func pool_state(abilities: Abilities, index: int) -> State:
	var out := State.new()
	out.sectors = maxi(1, abilities.pool_max_charges(index))
	out.full = abilities.pool_charges(index)
	out.progress = abilities.pool_recharge_fraction(index)
	return out


## The dial for a producer: its current job's progress, as a sweep that never becomes a held
## charge — finishing spawns the unit and starts the next. An idle producer is an empty track.
static func production_state(production: Production) -> State:
	var out := State.new()
	out.progress = production.job_progress(0) if production.job_count() > 0 else 0.0
	return out


## The dial for `weapon`: one sector per round in its clip.
static func weapon_state(weapon: Weapon) -> State:
	var out := State.new()
	out.sectors = maxi(1, weapon.clip_size)
	out.full = clampi(weapon.ammo(), 0, out.sectors)
	out.progress = weapon.reload_fraction()
	out.progress_sectors = maxi(1, out.sectors - out.full)
	out.is_self_recharging = not weapon.charged
	return out


## Whether a weapon reloading every `reload_seconds`, charged or not, gets a dial.
static func wants_weapon_dial(reload_seconds: float, is_charged: bool) -> bool:
	return is_charged or reload_seconds >= WEAPON_MIN_RELOAD_SECONDS


## The weapons of `piece` that get a dial, in loadout order.
static func dial_weapons(piece: Entity) -> Array[Weapon]:
	var out: Array[Weapon] = []
	var loadout: Loadout = piece.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return out
	for weapon: Weapon in loadout.get_weapons():
		var reload_seconds: float = (
			float(weapon.reload_time_ticks) / float(TimeUtils.ticks_per_second())
		)
		if wants_weapon_dial(reload_seconds, weapon.charged):
			out.append(weapon)
	return out


#endregion


#region Drawing
func show_state(a_state: State) -> void:
	state = a_state
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0
	if radius <= 0.0:
		return
	draw_circle(center, radius, TRACK_COLOR)
	var sector_angle: float = TAU / float(state.sectors)
	for k: int in state.sectors:
		if k < state.full:
			_draw_pie(center, radius, k * sector_angle, sector_angle, HUE)
		elif not state.is_self_recharging:
			_draw_pie(center, radius, k * sector_angle, sector_angle, stalled_color())
	if state.is_self_recharging and state.progress > 0.0 and state.full < state.sectors:
		var span: float = state.progress * state.progress_sectors * sector_angle
		_draw_pie(center, radius, state.full * sector_angle, span, recharging_color())
	# Hairlines between sectors, so a three-charge pool with two charges reads as two thirds
	# rather than as one odd-shaped wedge.
	if state.sectors > 1:
		for k: int in state.sectors:
			var angle: float = -PI / 2.0 + k * sector_angle
			draw_line(center, center + Vector2.from_angle(angle) * radius, TRACK_COLOR, 1.0)


## A wedge from `start` (radians clockwise from 12 o'clock) spanning `span`.
func _draw_pie(
	a_center: Vector2, a_radius: float, a_start: float, a_span: float, a_color: Color
) -> void:
	if a_span <= 0.0:
		return
	var steps: int = maxi(2, ceili(ARC_STEPS * a_span / TAU))
	var points := PackedVector2Array([a_center])
	for i: int in steps + 1:
		var angle: float = -PI / 2.0 + a_start + a_span * float(i) / float(steps)
		points.append(a_center + Vector2.from_angle(angle) * a_radius)
	draw_colored_polygon(points, a_color)


static func recharging_color() -> Color:
	return Color.from_hsv(HUE.h, HUE.s * RECHARGING_SATURATION, HUE.v)


static func stalled_color() -> Color:
	return Color.from_hsv(HUE.h, HUE.s * STALLED_SATURATION, HUE.v * STALLED_VALUE)
#endregion
