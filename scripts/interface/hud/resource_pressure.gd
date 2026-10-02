class_name ResourcePressure
extends RefCounted

## Shared vocabulary for "does this resource pool need the player's attention right now" —
## the thresholds, colours and pulse maths the persistent resource bars
## (EnergyBar/InfrastructureBar/DominionBar) read, so none of them can invent its own idea of
## what "over capacity" means.
##
## Pure and static, like CommandButtonState: it reads a Commander and returns values, nothing
## here touches a Control.

#region Constants
## Banked energy past which the player is sitting on more than they are using. Also the
## persistent EnergyBar's visual full-scale (see gdd/systems/ux/ui/economy-bars.md).
const ENERGY_SURPLUS_THRESHOLD: int = 5000

## Fraction of infrastructure capacity at which the excess region starts warning. Below the
## strain line, so the warning arrives before the buildings do go dark rather than with them.
const INFRASTRUCTURE_PRESSURE_FRACTION: float = 0.8

## Seconds for one full pulse. Slow enough to read as a STATE rather than as an alarm — a
## HUD that blinks at the player is one they learn to stop looking at.
const PULSE_PERIOD_SECONDS: float = 1.2

const INFRASTRUCTURE_PRESSURE_COLOR: Color = Color(1.0, 0.80, 0.52)
const INFRASTRUCTURE_OVER_COLOR: Color = Color(0.98, 0.58, 0.20)

## The near-opaque backing every persistent economy panel sits on. Opaque enough to read
## against ANY world background: a lower-alpha bar drawn over the map's own dark terrain
## shading is legible against grass and nearly invisible against a shadowed corner, which a
## fixed HUD element cannot afford to be.
const PANEL_COLOR: Color = Color(0.055, 0.067, 0.051, 0.87)
#endregion


#region Pulse maths
## `a_color1` ↔ `a_color2`, on a smooth PULSE_PERIOD_SECONDS cycle.
##
## Driven by the wall clock rather than by accumulated delta, so a paused game keeps pulsing:
## these say what STATE a pool is in, and a pool does not stop being over capacity because
## the player opened a dialog. Self-referential pulses (a colour toward its own `.lightened()`)
## are what the bars use — see EnergyBar/InfrastructureBar — rather than pulsing toward white,
## which would flash to a colour that means nothing on the bar it is drawn on.
static func pulse_between(a_color1: Color, a_color2: Color) -> Color:
	var phase: float = (
		fmod(float(Time.get_ticks_msec()) / 1000.0, PULSE_PERIOD_SECONDS) / PULSE_PERIOD_SECONDS
	)
	return a_color1.lerp(a_color2, 0.5 - 0.5 * cos(phase * TAU))


#endregion


#region Resource states
## Whether the commander's dominion covers the DEAREST cell the sanction grid will currently
## sell them — i.e. whether banking more of it buys anything they cannot already have.
static func can_afford_dearest_sanction(a_commander: Commander) -> bool:
	if a_commander == null or a_commander.sanction_grid == null:
		return false
	var dearest: int = a_commander.sanction_grid.dearest_available_cost()
	return dearest >= 0 and a_commander.dominion >= dearest


## Whether the commander's dominion covers the CHEAPEST cell the grid will currently sell
## them — the DominionBar's first colour threshold.
static func can_afford_cheapest_sanction(a_commander: Commander) -> bool:
	if a_commander == null or a_commander.sanction_grid == null:
		return false
	var cheapest: int = a_commander.sanction_grid.cheapest_available_cost()
	return cheapest >= 0 and a_commander.dominion >= cheapest
#endregion
