---
title: Persistent economy bars
type: system-note
---

# Persistent economy bars

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Three always-visible, non-text readouts of the commander's economy — `DominionBar` (top-left),
`EnergyBar` and `InfrastructureBar` (stacked, Energy above Infrastructure, above the command
card). They replaced `EconomyStack`, the old top-left panel that showed the same three pools
as text: once the bars existed the text view was pure duplication, so it was deleted rather
than kept alongside them. The one piece of its behaviour with no replacement, the
committed-energy readout, is now the pending slice of the energy fill (§Energy).

**One shared source of truth.** All three bars read `Commander` directly (`energy`,
`dominion`, `infrastructure_required`/`_provided`, the rate methods) and colour their "needs
attention" states off `ResourcePressure` — thresholds and pulse maths extracted so no bar can
invent its own idea of what "over capacity" means. `Commander._refresh_resource_bars()`
pushes a repaint to whichever of the three exist on `resources_changed`, the same push
`EconomyStack` used to receive, so a resource change is reflected the frame it happens rather
than the next one.

## Why the command card moved

The idle-selector row (`SelectorPanel`, three buttons: Army / Builders / Producers) used to
share `InfoSection`'s rect, centred at the bottom of the screen. The task asked for it to move
to where the command card lives — bottom-LEFT (`CommandsSection`, x 0–324).

**No node actually had to move.** `SelectorPanel` is visible exactly when `CommandsSection` is
not (`_selector_panel.visible = not has_selection` against `$CommandsSection.visible =
has_selection`), so the two already alternate in the same screen region without ever being on
screen together — that is the whole reason `SelectorPanel` was built as InfoSection's SIBLING
in the first place (see hud-layout.md §The HUD is split persistent / selection-owned). Giving
`Selectors` the identical anchor block `CommandsSection` already used was the entire change:
with nothing selected, the selector row now draws where the command card would; with something
selected, the command card draws there instead, exactly as before. `InfoSection` and its own
rect (bottom-centre) are untouched.

## A bar's fill is one or more flat regions

`EconomyBar._fill_regions()` returns `{start_frac, end_frac, color}` dictionaries, in
fractions of `_capacity()`; `_draw_fill()` paints each as a solid rect and then the segment
dividers (`_segment_size()`, 0 = none) across the whole bar. The default implementation is
ONE region, `[0, value/capacity]`, coloured by `_fill_color()` at the OVERALL fraction — a
single flat colour chosen from where the fill sits on a ramp, not a ramp painted across the
fill itself. Energy and Dominion use this default unchanged; Infrastructure overrides
`_fill_regions()` for its two-region picture (§Infrastructure below), which is why it needs
no `_fill_color()` override at all.

## Energy

- **Fill** is `Commander.energy`, one flat colour. **Capacity** (what "full" means) is
  `ResourcePressure.ENERGY_SURPLUS_THRESHOLD` (5000).
- **Colour** is picked off a tiffany-blue → seafoam-green → canary-gold `Gradient`, sampled at
  the fill's OVERALL fraction — the same idiom `HealthBarGradient` already samples its HP ramp
  in (`scripts/rendering/health_bar_gradient.gd`) rather than a second hand-rolled
  interpolator. `BarGradient.with_saturation_ramp` boosts HSV saturation toward the gold end on
  top of the sampled hue, per the task's "generally increase in saturation" note. Because the
  whole fill is one colour, a half-full bar reads as one uniform blue-green shade, not a
  gradient frozen partway across — the ramp is in TIME (as the pool grows), not in SPACE.
- **Past the threshold**, the fill oscillates — `ResourcePressure.pulse_between` blending the
  sampled colour toward a lightened version of ITSELF, never toward white: a self-referential
  pulse reads as "this colour, brighter", where pulsing toward white would flash to a colour
  the ramp never otherwise shows.
- **Energy the queue has promised** is the right-hand end of the fill, drawn in the pending
  style (see [UX](../README.md) §Pending pieces are shown, as pending): banked but spoken for by
  purchases not yet paid. When the queue owes more than is banked, the whole fill is pending.
  A standing entry promises nothing; each copy it issues does.
- **Production rate** (`energy_collection_rate()`) and **consumption rate**
  (`energy_spend_rate()`) each get a small non-text bar in a `RateIndicator` beside the value
  label — green rising with income, amber rising with spend. `RateIndicator.RATE_VISUAL_SCALE`
  (50 energy/s) is an authored placeholder, on the same footing as the difficulty ramp's
  numbers: nothing in the project answers "what counts as a fast rate" yet. The production
  bar carries what pending extractors will add, stacked on top in the pending style.

### Energy consumption is one rate, not two (yet)

TODO: the task asked for the consumption side to be "composed by fallback energy commitments
and non-fallback queued energy commitments" — a decomposition into two components, not the
single `energy_spend_rate()` figure built here. Neither `PurchaseTransaction.FailurePolicy`
(REJECT/WAIT) nor `Commander.energy_committed()`/`energy_spend_rate()` names a "fallback"
concept, and which existing figures (if any) the two terms refer to is genuinely undetermined
— see `gdd/tasks.md` T-069. Once answered, the fix is local to
`EnergyBar._verbose_text()` and the consumption entry in its `RateIndicator.bars`.

## Infrastructure

Stacked directly below Energy. Unlike Energy and Dominion, the fill is not one growing
region — its two regions TOGETHER always cover the bar's whole visible length, because the
bar itself represents a COMPARISON (used against provided) rather than a single pool filling
up:

- **The bar's length** is `max(infrastructure_required, infrastructure_provided)`, floored at
  `InfrastructureBar.DEFAULT_VISUAL_THRESHOLD` (500) so a light commitment doesn't rescale the
  bar to near-invisible slivers.
- **Left region, USED (light orange):** `min(required, provided)` of that scale.
- **Right region, the remainder up to the bar's length:**
  - **light grey** when `provided > required` — genuine spare capacity.
  - **`ResourcePressure.INFRASTRUCTURE_PRESSURE_COLOR`**, steady, once `required` reaches
    `ResourcePressure.INFRASTRUCTURE_PRESSURE_FRACTION` (80%) of `provided` but has not
    passed it — the same "approaching" warning `EconomyStack`'s row used to carry.
  - **`ResourcePressure.INFRASTRUCTURE_OVER_COLOR`**, pulsing (self-referential, per Energy's
    reasoning above), once `required > provided` — the "over" warning.
- **No separate capacity marker.** The boundary between the two regions already IS the
  capacity line; the earlier version drew a white marker line on top of a flat used/unused
  fill, which is redundant once the regions themselves carry that meaning.
- **Segments.** Both regions are divided at one grant of the faction's DEDICATED
  infrastructure provider (named on the faction scene), whether or not one stands yet. Other
  pieces provide too — a command centre, often a different amount — and a segment that resized
  as they came and went would stop meaning "one more provider". The grant is read off the
  provider's piece, since `TechnologySpec` does not carry it.
- **Pending.** What ordered pieces will add, in the pending style over the real regions: upkeep
  eating into spare capacity, capacity arriving past the edge, and a deficit an order will open
  or close. It is drawn wherever the future picture differs from today's, and never pulses — a
  pending deficit has not happened. The bar grows to fit it.

Per-faction colouring is explicitly deferred (the task said "choose something generic for
now"); `InfrastructureBar.USED_COLOR`/`SPARE_COLOR` are the values to branch a faction
override from.

## Dominion

- **Fill** is `Commander.dominion`. **Capacity** is `SanctionGrid.dearest_available_cost()`
  when the grid offers anything, else `DominionBar.DEFAULT_VISUAL_SCALE` — a placeholder for
  the state where every tier is still locked.
- **Colour is three DISCRETE states**, not a gradient, because the task asked for a switch at
  each affordability line rather than a blend: pale yellow, then a saturated orange the instant
  `SanctionGrid.cheapest_available_cost()` is affordable (mirrors `dearest_available_cost()`),
  then a saturated orange-red — oscillating, self-referential — the instant the dearest
  available one is (`ResourcePressure.can_afford_dearest_sanction`).
- **Income rate** is drawn INSIDE the bar itself, not as a separate `RateIndicator` widget —
  see §Rate projection. It includes what a dominion route pays on its own sweep (the
  Libertarian Opticons), not only generator components.
- **Pending income** — what ordered generators and Opticons will add — continues past the
  projection over the same minute, in the pending style.

## Rate projection

DominionBar's income rate is a translucent region inside the bar, not a box beside it (that
was the first version; revisited once it shipped — see §Rate projection replaced a widget).
`EconomyBar._rate_regions()` is the hook: a PERSISTENT region (unlike §Hover previews below,
which only exists while the pointer is over something), same shape as `_fill_regions()`.

- **Width**: `PROJECTION_SECONDS` (60) of `Commander.projected_dominion_rate()` — not
  `dominion_collection_rate()`, the instantaneous rate the "+X.X/s" text still reads. A
  sentence-based Compound's occupancy DECAYS as terms complete (see
  [combat/colonial-dominion](../../combat/colonial-dominion.md) §A captive serves a sentence),
  so "if the current rate held" would overstate the next minute whenever arrivals lag
  consumption — which, before tasking existed, was always. `projected_dominion_rate()`
  answers "if my tasked trucks keep working these Shelters at this distance, what does that
  sustain" instead, derived from live `TaskShelter` state rather than from occupancy history:
  round-trip time at the trucks' own speed against each Shelter's regeneration, capped by the
  captives the receiving Compound sentences at once (`Garrison.SENTENCES_AT_ONCE`, one) — the
  steady-state half of
  [design-framework/proposals](../../../design-framework/proposals.md) §The model
  (`min(Φ·τ, K)`), with `c`/`t_l`/`t_u`/`μ`/`m` dropped as negligible for now. Starts exactly
  where the real fill ends and runs rightward.
- **Colour**: `_fill_color()` at reduced alpha (`EconomyBar.RATE_BAR_ALPHA`, 0.5) — the SAME
  colour the real fill is drawn in, so the projection reads as a translucent continuation of
  the same bar rather than a second indicator. Plain alpha, not `_dimmed()`'s mix-toward-
  background: a rate region sits PAST the real fill, never on top of an identically-coloured
  one, so it has no self-cancelling composite to guard against (contrast §Hover previews,
  where that distinction is load-bearing).
- **Clamped to the bar's own scale, never growing it.** A very high income rate fills the
  rest of the bar and stops — unlike an expensive hover preview, which grows `_capacity()`
  to fit. The two situations differ: a preview is answering "how far away is this", where
  showing the true distance is the point; a rate projection is answering "how full will I
  be soon", where the bar's own scale is what "full" already means.

Tests: `tests/test_EconomyBars.gd` §The income-rate PROJECTION.

### Rate projection replaced a widget

The first version put the income rate in a small `RateIndicator` box beside the bar — the
same treatment EnergyBar's production/consumption rates still get. Revisited on request: the
in-bar region answers a more specific question ("how much more, and by when") that the boxes
never could, since a box only encodes a rate's MAGNITUDE against an arbitrary visual scale
with no time axis. `DominionBar.RATE_VISUAL_SCALE`/`INCOME_COLOR` and its own
`_rate_indicator` are gone; `RateIndicator` itself stays, since EnergyBar still uses it and
nothing here asked to change that.

## Hover previews

Hovering a command-grid button that costs a resource dims a preview of that cost against the
matching bar — the purchase's effect BEFORE it is committed, not yet real, drawn on top of
everything else via `EconomyBar._dimmed()`.

**`_dimmed()` mixes toward `BAR_BG_COLOR` and draws OPAQUE, not the same colour at reduced
alpha.** The obvious approach — alpha is what "not real yet" usually means — is a no-op for
Energy/Dominion's affordable case specifically: that preview region ends exactly where the
real fill already ends, in the exact colour `_fill_color()` gives that same position, and
compositing a translucent colour over an OPAQUE identical colour cannot change the pixel
(`c·a + c·(1−a) = c` for any `a`) — the region was being drawn, correctly, and was invisible.
Mixing toward the background first actually moves the RGB, so the preview reads as a dimmer
shade of the real colour whether it lands on top of the real fill (affordable) or on bare
background past it (unaffordable) — see `tests/test_EconomyBars.gd`'s
`test_dimming_a_colour_that_matches_the_real_fill_still_changes_something_visible`, which
pins exactly this.

**How the hover reaches the bars.** `RTSController.hovered_command_button` is set/cleared by
every grid button's `mouse_entered`/`mouse_exited` (wired in `ButtonSpec.create_button_from_spec`
— a HUD button has no other reason to know about the resource bars, so the bars poll the
controller rather than the reverse). It is a NODE reference rather than a bare command-name
string specifically so a stale hover (the grid rebuilds while the pointer hasn't moved) is
caught by `is_instance_valid()` in `hovered_command_name()` instead of pointing at a freed
button.

**Hovering wins outright over an ARMED tool; the two never combine.**
`RTSController.previewed_tool()` is what every bar actually asks: `Tool.for_name` on the
hover if that resolves to a real purchase, else `command_message.tool` — the tool a player
has ARMED by clicking a Build/Train button and not yet placed or cancelled, which is exactly
as pending a purchase as a hovered one and previews the same way. A hover that doesn't name a
Tool (a verb, empty space) falls straight through to the armed tool rather than blanking the
preview — the rule is "hover wins when it names something", not "hover wins by existing".
`EconomyBar._previewed_tool()` is the per-bar entry point; `_hovered_spec()` (Energy/Dominion)
and `_hovered_infrastructure_delta()` (Infrastructure) both read through it, so all three bars
get the armed-tool fallback for free from the one shared method.

**Energy and Dominion share one algorithm** (`EconomyBar._preview_regions()`'s default):
given a cost against the pool's current value, the dim region is `[value − cost, value]` when
affordable (the slice that would be SPENT, eating into the existing fill) or `[value, cost]`
when not (the slice still MISSING, extending past it) — the same interval either way, just
read from whichever side of `value` the cost falls on. Both ends are coloured by the bar's own
`_fill_color()` at the region's end fraction, dimmed, so the preview reads as a continuation of
the same ramp rather than a foreign colour. `_preview_cost()` is the one-line hook each bar
supplies (`TechnologySpec.energy_cost` / `.dominion_cost`); both bars' `_capacity()` also grows
to fit a cost bigger than the normal scale, so an expensive purchase's shortfall is never
clipped off the edge of the bar. EnergyBar's oscillation trigger deliberately reads the REAL
threshold constant rather than `_capacity()`, so hovering something expensive cannot silently
stop (or start) the pulse a genuinely-over/under-threshold bar should show.

**Infrastructure previews differently, because there is no afford/can't-afford split to key
off** — "energy is the only hard gate on my ability to build or purchase" (the task), so the
preview always shows the same shape regardless of whether the commander could actually pay.
`InfrastructureBar._hovered_infrastructure_delta()` reads the hovered piece's OWN ongoing
`Commandable.infrastructure` export off `Commander.get_build_preview_instance(tool)` — the
existing out-of-tree preview-instance cache (CLAUDE.md §Things NOT to break: it must never
enter the SceneTree) — since `TechnologySpec` does not carry this figure at all.

**Dominion is the one bar that reads a SECOND hover source.** No piece in the current content
costs dominion to train or build — `TechnologySpec.dominion_cost` is 0 everywhere — because
dominion is spent entirely through the sanction grid's UNLOCK buttons, built by
`RTSController._build_sanction_button` rather than `ButtonSpec` (the sanction menu is its own
dialog, a different button-building path with no reason to share the command grid's wiring).
Its own `mouse_entered`/`mouse_exited` set `RTSController.hovered_sanction_unlock` — only on
the UNLOCK button, never the deploy/cast one beside it, since casting an already-unlocked
sanction spends a charge, not dominion. `DominionBar._preview_cost()` checks
`hovered_sanction_unlock` first and falls through to the Tool-based path (kept for
completeness / future pieces) only when nothing is unlock-hovered.

- **Providing** (`delta > 0`): one dim SPARE_COLOR region appended past the bar's current
  right edge, `delta` wide — literally "how much more I will have".
- **Consuming** (`delta < 0`): the increment is split at the bar's CURRENT right edge (where a
  real deficit would begin). The part that still fits inside existing spare capacity previews
  as dim USED_COLOR; any part past it previews in the dim "deficit" colour
  (`ResourcePressure.INFRASTRUCTURE_OVER_COLOR`) — but as a flat constant, never through
  `pulse_between`, so it cannot oscillate. The task was explicit about this: "the oscillation
  is not in effect yet", because oscillation is a statement about a state that has actually
  happened, and hovering hasn't made it happen.
- `_capacity()` grows to fit either direction's preview too, same reasoning as Energy/Dominion.

## Rates get a shallow tier too

`RateIndicator` is the shallow-tier picture of a number that used to be TEXT-ONLY under
`ui_verbose`: not a value the player reads, a shape they glance at — taller bar, more income,
no arithmetic required. It draws two independent bars rather than one net figure because
production and consumption answer different questions ("is this pool growing", "is this pool
being spent") and collapsing them into a delta would hide which is true when both are large.
The verbose text line under each bar still prints the exact numbers, for whoever wants them.

## What was deliberately not built

- **The energy-consumption decomposition** — see §Energy consumption is one rate, not two
  (yet) above.
- **Per-faction infrastructure and dominion styling** — see each section above.
- **Tuned rate-visual scales.** `EnergyBar.RATE_VISUAL_SCALE` and `DominionBar.RATE_VISUAL_SCALE`
  are round numbers picked with no data behind them, same footing as the bot difficulty ramp —
  worth checking against real matches before relying on them for balance reading.
