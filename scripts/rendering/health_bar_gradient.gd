class_name HealthBarGradient

## Single source of truth for HP-bar fill color: green at full health, through
## yellow at half, to red as it empties. Sampled by Commandable._on_hp_changed and
## applied as the fill Sprite3D's `modulate`, which is why every HPBarFill texture in
## the entity scenes is WHITE — the color lives here, not in the scenes, so changing
## the ramp takes effect project-wide without touching a .tscn.
##
## Held as a real Gradient (rather than hand-rolled lerps) so the palette can later
## become an authored/exported Resource: swap what _build() returns, or assign over
## `gradient`, and every bar follows. Adding stops needs no other change.

## The ramp, keyed by REMAINING health fraction — offset 0.0 is empty, 1.0 is full.
static var gradient: Gradient = _build()


## Fill color for a health fraction. Out-of-range values clamp, so an overhealed or
## already-dead entity still reads as a solid end-of-ramp color rather than black.
static func color_for(fraction: float) -> Color:
	return gradient.sample(clampf(fraction, 0.0, 1.0))


static func _build() -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray(
		[
			Color(0.85, 0.16, 0.16),  # empty  — red
			Color(0.93, 0.86, 0.18),  # half   — yellow
			Color(0.25, 0.78, 0.28),  # full   — green
		]
	)
	return g
