extends RefCounted

## CALIBRATION RULES: relationships BETWEEN a piece's numbers that have to hold for the
## piece to work, checked at import alongside the per-key type validation in SpecRegistry.
##
## The two passes answer different questions and that is why this is its own module.
## SpecRegistry asks "is this value well-formed" — is the radius a number, is the enum name
## real, is the ratio inside 0..1 — and every answer is local to one key. A rule here asks
## "do these values make a unit", which is never local: an aggro radius is fine on its own
## and wrong beside a longer weapon reach, a turn rate is fine until you divide a speed by
## it and compare against what the thing is trying to shoot.
##
##
## THREE VERDICTS, NOT TWO
##
## A calibration rule is a NORM, and a roster with no exceptions to its norms is a roster
## with no artillery in it. So a violation is not automatically a failure:
##
##   ACCEPTED    the rule holds. Silent.
##   EXCEPTIONAL the rule is violated AND the doc declares the exception, with a stated
##               reason. Listed in the import summary, never an error.
##   UNACCEPTED  the rule is violated and nothing declares it. HARD ERROR.
##   STALE       the doc declares an exception to a rule it does not violate. HARD ERROR.
##
## STALE is the one that keeps the mechanism honest. Without it a declaration is free to
## outlive the value that needed it, and a year later the `exceptions:` block is a list of
## things that used to be true — which is worse than no list, because it still reads as
## deliberate. Declaring an exception therefore costs something on both sides: you must
## write it when you break the norm, and delete it when you stop.
##
## Declared in the doc's own frontmatter, so the justification lives beside the numbers it
## justifies rather than in an allowlist somewhere else:
##
##     exceptions:
##       reach_within_vision: Artillery — fires on ground its spotters see, not its own.
##
##
## STRUCTURAL RULES CANNOT BE DECLARED AWAY
##
## Some of these are not norms at all: they describe a unit that cannot physically do the
## thing it was built to do — an aircraft whose turning circle is wider than its weapon's
## reach can never point at a stationary target, however deliberate the numbers were.
## Declaring an exception to that would only record the intent to ship a broken piece, so
## STRUCTURAL rules refuse the declaration and a violation is always an error.
##
## The dividing line is "is this a balance opinion, or is it geometry".
##
##
## ASSET RULES ARE REPORTED, NEVER FAILED
##
## A third severity says a piece is expected to CARRY something — a model, a voice. The
## importer assumes every such slot is wanted: an unfilled one is INCOMPLETE, printed in the
## import summary with its AssetState and never an error, because a missing asset crashes
## nothing. This report is the one place a missing asset is surfaced — the game stays silent
## about it at runtime. A doc that means "this piece has none" waives the rule like a norm,
## and the waiver goes STALE the day the slot is filled. Why the slot vocabulary exists:
## gdd/systems/ux/README.md.

enum Verdict { ACCEPTED, EXCEPTIONAL, UNACCEPTED, STALE, NOT_APPLICABLE, INCOMPLETE }

## How far an ASSET rule's slot is filled. PLACEHOLDER is a stand-in the importer supplies;
## MISSING is nothing at all; EXEMPT is a waiver saying nothing belongs there.
enum AssetState { FILLED, PLACEHOLDER, MISSING, EXEMPT }

## A rule whose violation is a fact about physics rather than a choice about balance. Cannot
## be waived with an `exceptions:` entry — see the header.
const STRUCTURAL: String = "structural"
## A rule that states how pieces are USUALLY built. Waivable, with a reason.
const NORMATIVE: String = "normative"
## A rule that a piece carries an asset. Waivable, with a reason; unwaived, it is INCOMPLETE
## rather than an error — see the header. Each carries `unfilled`, the AssetState it reports.
const ASSET: String = "asset"

## The reach at or below which a weapon is MELEE — it must be in contact with what it is
## hitting. One terrain cell (Map.CELL_SIZE), which is the smallest distance this game
## measures anything in: a weapon that cannot reach across a single cell is not shooting
## across a gap, it is touching.
##
## Stated as a constant here rather than read off Map because referencing Map from the
## importer drags the whole terrain stack — and a scene-loading side effect during
## validation is exactly the class of thing that makes an import hang.
const MELEE_REACH_MAX: float = 1.0

## Cruise altitude for aerial units (Aerial.AERIAL_HEIGHT). Mirrored for the same reason
## as MELEE_REACH_MAX; the importer's coverage pass checks the two against the engine so they cannot
## drift.
const AERIAL_HEIGHT: float = 6.0

## Every rule, in report order. `what` is the norm stated positively — it is what the
## summary prints for an EXCEPTIONAL piece, so it reads as the thing being departed from.
const SpecSchema := preload("res://tools/spec_import/schema.gd")

const RULES: Array = [
	{
		"id": "turn_radius_within_reach",
		"severity": STRUCTURAL,
		"what": "a fixed wing can turn tightly enough to point at what it shoots",
	},
	{
		"id": "grounded_air_attack_not_melee",
		"severity": STRUCTURAL,
		"what": "a ground unit that shoots at aircraft does so at range",
	},
	{
		"id": "detection_within_vision",
		"severity": NORMATIVE,
		"what": "a piece detects stealth no further than it can see",
	},
	{
		"id": "reach_within_vision",
		"severity": NORMATIVE,
		"what": "a piece can see what it shoots at",
	},
	{
		"id": "bio_pivots_in_place",
		"severity": NORMATIVE,
		"what": "infantry turns on the spot rather than swinging round",
	},
	{
		"id": "braking_outpaces_acceleration",
		"severity": NORMATIVE,
		"what": "a ground vehicle stops harder than it starts",
	},
	{
		"id": "aerial_weapons_not_melee",
		"severity": NORMATIVE,
		"what": "a fixed wing strikes from range rather than by ramming",
	},
	{
		"id": "has_mesh_visual",
		"severity": ASSET,
		"what": "a piece carries a visible model",
		"unfilled": AssetState.PLACEHOLDER,
	},
	{
		"id": "has_voice_lines",
		"severity": ASSET,
		"what": "a unit answers when it is selected or ordered",
		"unfilled": AssetState.MISSING,
	},
	{
		"id": "has_death_sound",
		"severity": ASSET,
		"what": "a piece makes a sound when it is destroyed",
		"unfilled": AssetState.MISSING,
	},
	{
		"id": "clip_outlasts_reload",
		"severity": NORMATIVE,
		"what": "a clip takes longer to refill than to empty",
	},
]


## Runs every rule against one piece spec. Returns one entry per rule that had something to
## say — `{id, severity, verdict, detail, reason}` — omitting NOT_APPLICABLE and ACCEPTED,
## so an ordinary piece produces an empty array.
##
## Callers turn UNACCEPTED and STALE into errors, EXCEPTIONAL and INCOMPLETE into summary
## lines; nothing here writes to the registry, so the rules stay testable on a bare dictionary.
##
## `facts` carries what the ASSET rules judge that lives outside the doc — the scene's art
## (`has_authored_mesh`) and the sound tables (`missing_line_types`, `has_death_clip`). An
## asset rule whose fact was not supplied has nothing to say, so a doc-only caller hears
## only the calibration rules.
static func evaluate(spec: Dictionary, facts: Dictionary = {}) -> Array:
	var declared: Dictionary = _declared_exceptions(spec)
	var out: Array = []
	for rule: Dictionary in RULES:
		var id: String = str(rule["id"])
		var detail: Variant = _check(id, spec, facts)
		var violated: bool = detail is String
		var has_declaration: bool = declared.has(id)
		if detail == null:
			# The rule had nothing to say about this piece. A declaration against it is stale in
			# exactly the same way a satisfied rule's is — a spotter-dependence waiver on a piece
			# with no weapons is a claim about a unit that does not exist.
			if has_declaration:
				out.append(_entry(rule, Verdict.STALE, "the rule does not apply to this piece", declared[id]))
			continue
		if not violated:
			if has_declaration:
				out.append(_entry(rule, Verdict.STALE, "the rule is satisfied", declared[id]))
			continue
		var severity: String = str(rule["severity"])
		if has_declaration and severity != STRUCTURAL:
			out.append(_entry(rule, Verdict.EXCEPTIONAL, str(detail), declared[id]))
		elif severity == ASSET:
			out.append(_entry(rule, Verdict.INCOMPLETE, str(detail), ""))
		else:
			out.append(_entry(rule, Verdict.UNACCEPTED, str(detail), ""))
	return out


static func _entry(rule: Dictionary, verdict: Verdict, detail: String, reason: String) -> Dictionary:
	var entry: Dictionary = {
		"id": str(rule["id"]),
		"severity": str(rule["severity"]),
		"what": str(rule["what"]),
		"verdict": verdict,
		"detail": detail,
		"reason": reason,
	}
	if rule.has("unfilled"):
		entry["asset_state"] = asset_state_of(rule, verdict)
	return entry


## The AssetState an ASSET rule's verdict reports. ACCEPTED is filled, EXCEPTIONAL is a waiver,
## INCOMPLETE is whatever the rule says an unfilled slot holds; STALE — a waiver on a filled
## slot — reports what is really there.
static func asset_state_of(rule: Dictionary, verdict: Verdict) -> AssetState:
	match verdict:
		Verdict.EXCEPTIONAL:
			return AssetState.EXEMPT
		Verdict.INCOMPLETE:
			return rule["unfilled"] as AssetState
	return AssetState.FILLED


## The `exceptions:` block, normalised to `{rule_id: reason}`. Shape problems (an unknown
## rule id, a blank reason, an exception against a STRUCTURAL rule) are reported by
## validate_exceptions_block, which the registry calls separately — this accessor is
## deliberately forgiving so one malformed entry does not suppress every real verdict.
static func _declared_exceptions(spec: Dictionary) -> Dictionary:
	var raw: Variant = spec.get("exceptions")
	if not (raw is Dictionary):
		return {}
	var out: Dictionary = {}
	for key in raw:
		out[str(key)] = str(raw[key])
	return out


## Shape check for the `exceptions:` block itself. Returns a list of complaint strings.
##
## An unknown rule id is an error rather than an ignored key for the same reason an unknown
## `movement:` key is: a waiver that names nothing waives nothing, and the doc that carries
## it believes it is licensed. Renaming a rule therefore breaks every doc that cited it,
## which is correct — those docs are asserting something about a rule that no longer exists.
static func validate_exceptions_block(spec: Dictionary) -> Array:
	var raw: Variant = spec.get("exceptions")
	if raw == null:
		return []
	if not (raw is Dictionary):
		return ["exceptions must be a mapping of rule_id: reason"]
	var complaints: Array = []
	for key in raw:
		var id: String = str(key)
		var rule: Variant = rule_by_id(id)
		if rule == null:
			complaints.append("exceptions names unknown rule '%s' (known: %s)" % [id, rule_ids()])
			continue
		if str((rule as Dictionary)["severity"]) == STRUCTURAL:
			complaints.append("exceptions cannot waive '%s' — it is STRUCTURAL: %s. A piece that breaks it cannot do its job at all, so the numbers have to change" % [id, (rule as Dictionary)["what"]])
		if str(raw[key]).strip_edges().is_empty():
			complaints.append("exceptions['%s'] needs a reason — the whole point of declaring one is the sentence saying why" % id)
	return complaints


static func rule_by_id(id: String) -> Variant:
	for rule: Dictionary in RULES:
		if str(rule["id"]) == id:
			return rule
	return null


static func rule_ids() -> Array:
	var ids: Array = []
	for rule: Dictionary in RULES:
		ids.append(str(rule["id"]))
	return ids


# --------------------------------------------------------------------------- #
# The rules
# --------------------------------------------------------------------------- #
## Returns null when the rule has nothing to say about this piece, true when it holds, and
## a String describing the violation when it does not. Three-valued rather than a bool
## because "does not apply" and "holds" are different facts: only the first makes a
## declaration stale for the reason given in evaluate().
static func _check(id: String, spec: Dictionary, facts: Dictionary = {}) -> Variant:
	match id:
		"has_mesh_visual":
			return _check_has_mesh_visual(facts)
		"has_voice_lines":
			return _check_has_voice_lines(spec, facts)
		"has_death_sound":
			return _check_has_death_sound(facts)
		"turn_radius_within_reach":
			return _check_turn_radius(spec)
		"grounded_air_attack_not_melee":
			return _check_grounded_air_melee(spec)
		"detection_within_vision":
			return _check_detection_within_vision(spec)
		"reach_within_vision":
			return _check_reach_within_vision(spec)
		"bio_pivots_in_place":
			return _check_bio_pivots(spec)
		"braking_outpaces_acceleration":
			return _check_braking(spec)
		"aerial_weapons_not_melee":
			return _check_aerial_melee(spec)
		"clip_outlasts_reload":
			return _check_clip(spec)
	return null


## A piece carries a visible model. Unwaived and without art, it wears the generated
## placeholder, which is what its INCOMPLETE reports. The waiver is how a piece opts out of a
## model — the importer then removes the placeholder — and it goes STALE the day the scene holds
## authored art, which is why it is a waiver rather than a flag.
static func _check_has_mesh_visual(facts: Dictionary) -> Variant:
	if not facts.has("has_authored_mesh"):
		return null
	if bool(facts["has_authored_mesh"]):
		return true
	return "has no authored model"


## A unit — a commandable piece that moves — has a clip for every voice line. A structure or a
## token has no voice, so the rule does not apply to it.
static func _check_has_voice_lines(spec: Dictionary, facts: Dictionary) -> Variant:
	if not facts.has("missing_line_types") or not _is_unit(spec):
		return null
	var missing: Array = facts["missing_line_types"]
	if missing.is_empty():
		return true
	return "has no voice lines for %s" % ", ".join(missing)


## Every piece has a death sound — a structure's collapse is its death, not a separate event.
## Asked of pieces only: the registry supplies the fact for no emission.
static func _check_has_death_sound(facts: Dictionary) -> Variant:
	if not facts.has("has_death_clip"):
		return null
	if bool(facts["has_death_clip"]):
		return true
	return "has no death sound"


## A fixed wing must be able to turn tightly enough to bring its weapon to bear.
##
## Minimum turn radius is speed / turn_rate (radians), and a FLYING unit cannot stop to aim,
## so if that circle is wider than the weapon's reach the aircraft orbits its victim at arm's
## length forever — it can never be both pointed at the target and close enough to fire. This
## is not hypothetical: it is why Movement.dive_turn_rate_multiplier exists, and the kamikaze
## clears the bar only because of it.
static func _check_turn_radius(spec: Dictionary) -> Variant:
	if not _has_weapons(spec) or _mode(spec) != "FLYING":
		return null
	var m: Dictionary = _movement(spec)
	var speed: float = float(m.get("speed", 0.0))
	var turn_deg: float = float(m.get("turn_rate", 0.0))
	if speed <= 0.0 or turn_deg <= 0.0:
		return null   # an unbounded turn rate has no radius, and a parked piece has no arc
	var radius: float = speed / deg_to_rad(turn_deg)
	var reach: float = _max_reach(spec)
	if reach < 0.0:
		return null
	# A ramming airframe pulls harder on the run in, which is the whole reason that multiplier
	# exists — so the rule has to measure the circle it will actually fly, not its cruise one.
	var boosted: bool = _has_melee_weapon(spec)
	var effective: float = radius / (_dive_turn_multiplier(spec) if boosted else 1.0)
	if effective < reach:
		return true
	return "turns in %s at best (speed %s / %s deg/s%s) but reaches only %s — it can never point at a stationary target" \
		% [_num(effective), _num(speed), _num(turn_deg),
				", diving" if boosted else "", _num(reach)]


## A ground unit that shoots at aircraft must do so at range.
##
## Reach is measured on XZ against a very tall cylinder, so a melee weapon nominally CAN
## connect with something cruising six units overhead — which is the problem: it reads as an
## infantryman stabbing at the sky, and it is reach the piece was never designed to have.
## Ramming is a legitimate way to kill an aircraft; doing it from the ground is not.
static func _check_grounded_air_melee(spec: Dictionary) -> Variant:
	if _is_aerial(spec):
		return null
	var offenders: Array = []
	for w: Dictionary in _weapons(spec):
		if not _hits(w).has("air"):
			continue
		var reach: float = _reach_for(w, "air")
		if reach >= 0.0 and reach <= MELEE_REACH_MAX:
			offenders.append("%s (%s)" % [str(w.get("name", "?")), _num(reach)])
	if offenders.is_empty():
		return true
	return "is not aerial, but %s hits air at melee reach — an aircraft cruises at %s, so this is a ground unit swinging at the sky" \
		% [", ".join(offenders), _num(AERIAL_HEIGHT)]


## Detection should not out-reach vision.
##
## Detection reveals a stealthed unit; vision is what clears the fog it is standing in. Past
## the vision radius the reveal has nothing to reveal it TO, so the extra radius is inert.
##
## Normative rather than structural because it stops being true the moment vision is shared:
## with allied or spotter vision feeding the same fog, a detector genuinely can matter beyond
## its own sight. This game has no such sharing today, so the rule holds — and it is a norm
## so that the piece which first needs it can simply say so.
static func _check_detection_within_vision(spec: Dictionary) -> Variant:
	if not spec.has("detection") or float(spec["detection"]) <= 0.0:
		return null
	if not spec.has("vision"):
		return null
	var detection: float = float(spec["detection"])
	var vision: float = float(spec["vision"])
	if detection <= vision:
		return true
	return "detects stealth to %s but sees only %s — the outer %s reveals units the fog still hides" \
		% [_num(detection), _num(vision), _num(detection - vision)]


## A piece can usually see what it shoots at.
##
## The exception is the whole point of the rule: artillery that out-ranges its own eyes is a
## deliberate design, and it is what makes spotters worth fielding. So this rule exists to
## keep that set SMALL and NAMED rather than to forbid it — every piece in it has said out
## loud that it depends on someone else's vision.
static func _check_reach_within_vision(spec: Dictionary) -> Variant:
	if not _has_weapons(spec) or not spec.has("vision"):
		return null
	var reach: float = _max_reach(spec)
	var vision: float = float(spec["vision"])
	if reach < 0.0 or reach <= vision:
		return true
	return "reaches %s but sees %s — it depends on another unit's vision for the outer %s" \
		% [_num(reach), _num(vision), _num(reach - vision)]


## Infantry pivots on the spot.
##
## min_turn_speed_ratio is how much of its speed a unit keeps WHILE turning: 0 pivots in
## place, 1 arcs at full speed without ever slowing. A person changing direction does the
## former, and a squad that swings round like a truck reads as vehicles wearing infantry
## models.
static func _check_bio_pivots(spec: Dictionary) -> Variant:
	if str(spec.get("frame", "BIO")) != "BIO":
		return null
	var m: Dictionary = _movement(spec)
	if not m.has("min_turn_speed_ratio"):
		return null
	var ratio: float = float(m["min_turn_speed_ratio"])
	if is_zero_approx(ratio):
		return true
	return "is BIO but keeps %s of its speed through a turn — infantry pivots in place (0.0)" % _num(ratio)


## A ground vehicle stops harder than it starts.
##
## Brakes out-perform engines on anything with wheels or tracks — a road car pulls about
## 3 m/s^2 and stops at nearer 9 — and the asymmetry is most of what makes a vehicle feel
## heavy: it commits to getting moving and can still bail out of it.
##
## Deliberately GROUNDED-only. A fixed wing is the honest counterexample: thrust accelerates
## it and almost nothing sheds that speed again, so accel > |decel| is CORRECT for an
## aircraft, and `an_aircraftLight_antiMech` is already authored that way (5.0 / -2.0).
static func _check_braking(spec: Dictionary) -> Variant:
	if _mode(spec) != "GROUNDED":
		return null
	var m: Dictionary = _movement(spec)
	if not m.has("max_acceleration") or not m.has("max_deceleration"):
		return null
	var accel: float = float(m["max_acceleration"])
	var brake: float = absf(float(m["max_deceleration"]))
	if accel <= brake:
		return true
	return "accelerates at %s but brakes at only %s — a ground chassis should stop at least as hard as it starts" \
		% [_num(accel), _num(brake)]


## A fixed wing strikes from range rather than by ramming.
##
## The exception IS the mechanic for the one airframe built around it: a FLYING unit with a
## melee-reach weapon is a rammer, and that is how the dive attack is now recognised (see
## Weapon.is_melee_ranged) rather than by an authored `dive:` flag. Declaring the exception
## is therefore the same act as declaring the unit a kamikaze — which is why it is a norm
## with a named departure rather than something the schema silently permits.
##
## FLYING only, NOT aerial generally: a HOVERING unit with a melee weapon lands and strikes,
## which Attack.fulfill_action supports outright ("a HOVERING unit attacking a grounded
## target with a melee weapon must land first"). It is a helicopter setting down, not a
## suicide run, so it is not a departure from anything. Widening this to `_is_aerial` caught
## `tc_bioLight_builder` — a hovering technician with a 0.375-reach tool — and called it a rammer.
static func _check_aerial_melee(spec: Dictionary) -> Variant:
	if _mode(spec) != "FLYING" or not _has_weapons(spec):
		return null
	var offenders: Array = []
	for w: Dictionary in _weapons(spec):
		var reach: float = _max_reach_of(w)
		if reach >= 0.0 and reach <= MELEE_REACH_MAX:
			offenders.append("%s (%s)" % [str(w.get("name", "?")), _num(reach)])
	if offenders.is_empty():
		return true
	return "is aerial and carries a melee-reach weapon: %s — it can only attack by flying into its target" \
		% ", ".join(offenders)


## A clip should take longer to refill than to empty.
##
## The two rates are what matter, not the two times: firing consumes a round every
## `split_time`, while the clip regenerates `clip_size` rounds every `reload_time`. The clip
## is only real if consumption outpaces regeneration — `reload_time_ticks > split_time_ticks * clip_size`
## — and at or below that the weapon fires forever without ever depleting, so its clip size
## does nothing at all.
##
## CHARGED weapons are excluded, and not as a courtesy: a charged clip does not refill in the
## field at all, so its `reload_time` is time spent parked on an airfield pad and comparing
## it against a burst duration compares two unrelated quantities. The Clipper (12 rounds,
## 0.5s split, 6s dock) tripped exactly that.
static func _check_clip(spec: Dictionary) -> Variant:
	var offenders: Array = []
	var applicable: bool = false
	for w: Dictionary in _weapons(spec):
		var clip: int = int(w.get("clip_size", 1))
		if clip <= 1 or bool(w.get("charged", false)) \
				or not w.has("split_time") or not w.has("reload_time"):
			continue
		applicable = true
		var burst: float = float(w["split_time"]) * float(clip)
		var reload: float = float(w["reload_time"])
		if reload <= burst:
			offenders.append("%s (empties in %ss, refills in %ss)" % [str(w.get("name", "?")), _num(burst), _num(reload)])
	if not applicable:
		return null
	if offenders.is_empty():
		return true
	return "refills faster than it fires: %s — the clip never runs out, so its size does nothing" % ", ".join(offenders)


# --------------------------------------------------------------------------- #
# Spec accessors
# --------------------------------------------------------------------------- #
static func _movement(spec: Dictionary) -> Dictionary:
	var m: Variant = spec.get("movement")
	return m if m is Dictionary else {}


## A piece that flies names its mode under `aerial:`; one that moves and does not fly is
## GROUNDED; a piece with neither is a structure — reported as "" so mode-keyed rules skip it
## rather than treating a building as a ground vehicle.
static func _mode(spec: Dictionary) -> String:
	if spec.get("aerial") is Dictionary:
		return str((spec["aerial"] as Dictionary).get("mode", ""))
	return "GROUNDED" if spec.get("movement") is Dictionary else ""


static func _is_aerial(spec: Dictionary) -> bool:
	var mode: String = _mode(spec)
	return mode == "HOVERING" or mode == "FLYING"


## Cannot close distance: a structure (no `movement:`) or a piece parked at zero speed (the
## recon drone). Both are stuck with whatever is already inside their aggro radius.
static func _is_unit(spec: Dictionary) -> bool:
	return spec.has("movement") and SpecSchema.is_commandable(spec)


static func _is_immobile(spec: Dictionary) -> bool:
	if not (spec.get("movement") is Dictionary):
		return true
	return float(_movement(spec).get("speed", 0.0)) <= 0.0


static func _dive_turn_multiplier(_spec: Dictionary) -> float:
	# Movement.dive_turn_rate_multiplier is not doc-governed: it is 4.0 on every piece in the
	# game, and a value that never varies is not a configuration. It is mirrored here because
	# this rule genuinely depends on it — the importer's coverage pass checks the pair.
	return 4.0


static func _weapons(spec: Dictionary) -> Array:
	var raw: Variant = spec.get("weapons")
	if not (raw is Array):
		return []
	var out: Array = []
	for w in raw:
		if w is Dictionary:
			out.append(w)
	return out


static func _has_weapons(spec: Dictionary) -> bool:
	return not _weapons(spec).is_empty()


static func _has_melee_weapon(spec: Dictionary) -> bool:
	for w: Dictionary in _weapons(spec):
		var reach: float = _max_reach_of(w)
		if reach >= 0.0 and reach <= MELEE_REACH_MAX:
			return true
	return false


## What a weapon says it can shoot at. An unstated `hits:` is ground-only, matching
## Weapon.target_mask's default.
static func _hits(weapon: Dictionary) -> Array:
	var raw: Variant = weapon.get("hits")
	if not (raw is Array) or (raw as Array).is_empty():
		return ["ground"]
	var out: Array = []
	for h in raw:
		out.append(str(h))
	return out


## The radius this weapon reaches that layer with, read from `_reach_radii` — the shape-library
## ids of `reach:` already resolved by SpecRegistry._resolve_reach. Returns -1.0 when this
## weapon states no reach for that layer.
static func _reach_for(weapon: Dictionary, layer: String) -> float:
	var radii: Dictionary = weapon.get("_reach_radii", {})
	return float(radii.get(layer, -1.0))


static func _max_reach_of(weapon: Dictionary) -> float:
	var best: float = -1.0
	for layer: String in _hits(weapon):
		best = maxf(best, _reach_for(weapon, layer))
	return best


## The longest reach anything on this piece has, across every weapon and both layers.
## -1.0 when the piece is unarmed or states no reach at all.
static func _max_reach(spec: Dictionary) -> float:
	var best: float = -1.0
	for w: Dictionary in _weapons(spec):
		best = maxf(best, _max_reach_of(w))
	return best


## Trims the trailing zeros off a float so a message reads "7.5" and "12" rather than
## "7.500000" and "12.000000".
static func _num(value: float) -> String:
	return String.num(value, 3).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")
