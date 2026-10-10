class_name AlertCatalog
extends RefCounted
## WHAT EACH ALERT IS — its wording, urgency, whether it may say where, and how it is throttled.
## One table, so a designer retuning "how often am I told my base is under attack" edits one
## row rather than hunting through the sources that raise it.
##
## An alert is raised for EVERY commander it concerns (AlertCenter.alert_raised: the game keeps
## track of all of them) and only a throttled subset is PRESENTED (AlertCenter.alert_presented).
## The throttle reads its numbers from here. gdd/systems/ux/ui/alerts.md.

#region Constants
enum Type {
	UNITS_ATTACKED,
	STRUCTURES_ATTACKED,
	STEALTH_DETECTED,
	ENERGY_FLOATING,
	INFRASTRUCTURE_STRAINED,
	SUPERWEAPON_BEGUN,
	SUPERWEAPON_BUILT,
	SUPERWEAPON_READY,
	SUPERWEAPON_LAUNCHED,
	SUPERWEAPON_LOST,
}

## EVENT: something happened. STATE: something is true, and keeps being true until it is not —
## raised on entry, then repeated at `repeat_seconds` while it holds (AlertLatch).
enum Kind { EVENT, STATE }

## How loud it is: the sound it plays and the toast's accent. Ordered, so a louder alert may
## interrupt a quieter one's sound.
enum Tone { ROUTINE, WARNING, URGENT }

## One row per Type. Keys:
##   kind            Kind
##   tone            Tone
##   priority        int — within one suppression `group`, a higher priority alert breaks through
##                   (and replaces) a lower one's suppression (0 A.D.'s livestock rule)
##   group           StringName — alerts that suppress one another spatially. "" = keyed only
##   located         bool — may it carry a position? False = the viewer is never told where,
##                   whatever the source knew (the superweapon convention)
##   suppress_seconds    float — how long an admitted alert holds off the next of its group/key
##   suppress_radius     float — cells; a group alert inside this of a held one is swallowed
##   transfer_radius     float — cells; a swallowed alert this close MOVES the hold to itself and
##                       restarts its clock, so one ongoing fight stays one alert
##   repeat_seconds      float — STATE only: the reminder period while the state holds
##   sustain_seconds     float — STATE only: how long it must hold before the first alert
##   text            String — the toast's copy; `%s` takes the subject's title where there is one
##
## TODO: every number below is a first guess, not a tuned value — see alerts.md §Tuning.
static var DEFINITIONS: Dictionary = {
	Type.UNITS_ATTACKED:
	{
		"kind": Kind.EVENT,
		"tone": Tone.WARNING,
		"priority": 1,
		"group": &"attack",
		"located": true,
		"suppress_seconds": 30.0,
		"suppress_radius": 30.0,
		"transfer_radius": 15.0,
		"text": "Our units are under attack",
	},
	Type.STRUCTURES_ATTACKED:
	{
		"kind": Kind.EVENT,
		"tone": Tone.URGENT,
		"priority": 2,
		"group": &"attack",
		"located": true,
		"suppress_seconds": 30.0,
		"suppress_radius": 30.0,
		"transfer_radius": 15.0,
		"text": "Our base is under attack",
	},
	Type.STEALTH_DETECTED:
	{
		"kind": Kind.EVENT,
		"tone": Tone.WARNING,
		"priority": 1,
		"group": &"stealth",
		"located": true,
		"suppress_seconds": 20.0,
		"suppress_radius": 20.0,
		"transfer_radius": 10.0,
		"text": "Stealthed enemy detected",
	},
	Type.ENERGY_FLOATING:
	{
		"kind": Kind.STATE,
		"tone": Tone.ROUTINE,
		"priority": 0,
		"group": &"",
		"located": false,
		"suppress_seconds": 0.0,
		"sustain_seconds": 10.0,
		"repeat_seconds": 60.0,
		"text": "Unspent energy is piling up",
	},
	Type.INFRASTRUCTURE_STRAINED:
	{
		"kind": Kind.STATE,
		"tone": Tone.WARNING,
		"priority": 0,
		"group": &"",
		"located": false,
		"suppress_seconds": 0.0,
		"sustain_seconds": 1.0,
		"repeat_seconds": 45.0,
		"text": "Infrastructure over capacity",
	},
	Type.SUPERWEAPON_BEGUN:
	{
		"kind": Kind.EVENT,
		"tone": Tone.WARNING,
		"priority": 0,
		"group": &"",
		"located": false,
		"suppress_seconds": 10.0,
		"text": "Enemy %s under construction",
	},
	Type.SUPERWEAPON_BUILT:
	{
		"kind": Kind.EVENT,
		"tone": Tone.WARNING,
		"priority": 0,
		"group": &"",
		"located": false,
		"suppress_seconds": 10.0,
		"text": "Enemy %s detected",
	},
	Type.SUPERWEAPON_READY:
	{
		"kind": Kind.EVENT,
		"tone": Tone.URGENT,
		"priority": 0,
		"group": &"",
		# Located for its OWNER (AlertCenter decides per viewer); an enemy is never told where.
		"located": true,
		"suppress_seconds": 10.0,
		"text": "%s ready",
	},
	Type.SUPERWEAPON_LAUNCHED:
	{
		"kind": Kind.EVENT,
		"tone": Tone.URGENT,
		"priority": 0,
		"group": &"",
		"located": false,
		"suppress_seconds": 0.0,
		"text": "Enemy %s launched",
	},
	Type.SUPERWEAPON_LOST:
	{
		"kind": Kind.EVENT,
		"tone": Tone.ROUTINE,
		"priority": 0,
		"group": &"",
		"located": false,
		"suppress_seconds": 0.0,
		"text": "Enemy %s destroyed",
	},
}
#endregion


#region Public API
static func definition(a_type: Type) -> Dictionary:
	return DEFINITIONS[a_type]


static func kind_of(a_type: Type) -> Kind:
	return definition(a_type)["kind"]


static func tone_of(a_type: Type) -> Tone:
	return definition(a_type)["tone"]


static func priority_of(a_type: Type) -> int:
	return int(definition(a_type)["priority"])


static func group_of(a_type: Type) -> StringName:
	return StringName(definition(a_type)["group"])


## Whether this type may ever carry a position. AlertCenter may still raise a located type
## WITHOUT one for a particular viewer (an enemy's superweapon coming ready).
static func may_locate(a_type: Type) -> bool:
	return bool(definition(a_type)["located"])


static func suppress_ticks(a_type: Type) -> int:
	return TimeUtils.ticks_from_seconds(float(definition(a_type).get("suppress_seconds", 0.0)))


static func suppress_radius(a_type: Type) -> float:
	return float(definition(a_type).get("suppress_radius", 0.0))


static func transfer_radius(a_type: Type) -> float:
	return float(definition(a_type).get("transfer_radius", 0.0))


static func sustain_ticks(a_type: Type) -> int:
	return TimeUtils.ticks_from_seconds(float(definition(a_type).get("sustain_seconds", 0.0)))


static func repeat_ticks(a_type: Type) -> int:
	return TimeUtils.ticks_from_seconds(float(definition(a_type).get("repeat_seconds", 0.0)))


## The toast's copy, with `a_subject` (a piece or ability title) in place of `%s` when the row
## has one.
static func text_of(a_type: Type, a_subject: String = "") -> String:
	var text: String = str(definition(a_type)["text"])
	return text % a_subject if text.contains("%s") else text
#endregion
