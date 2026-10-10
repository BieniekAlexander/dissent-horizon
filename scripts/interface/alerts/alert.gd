class_name Alert
extends RefCounted
## ONE ALERT, ADDRESSED TO ONE COMMANDER. The same happening raises one Alert per commander it
## concerns (an enemy superweapon: one per other commander), because what each may be told —
## above all, WHERE — differs. gdd/systems/ux/ui/alerts.md.

#region Properties
var type: AlertCatalog.Type
## The commander this alert is addressed to.
var viewer_id: int = 0
## The commander the alert is ABOUT, where that is someone else (whose superweapon). -1 = none.
var about_id: int = -1
## The simulation tick it was raised on (Scenario.tick).
var tick: int = 0
var text: String = ""
## Whether `position` may be shown to the viewer. False is a promise: the viewer is never told
## where, so the toast is not clickable and the jump key skips it.
var has_position: bool = false
var position: Vector3 = Vector3.ZERO
## The piece it is about, weakly — it may die before anyone looks. Null when there is none.
var _subject: WeakRef = null
## A key that identifies "the same thing again" for keyed (non-spatial) throttling — the
## caster's instance id for a superweapon, the commander id for a state.
var key: int = 0
#endregion


#region Public API
static func make(
	a_type: AlertCatalog.Type, a_viewer_id: int, a_tick: int, a_text: String = ""
) -> Alert:
	var alert := Alert.new()
	alert.type = a_type
	alert.viewer_id = a_viewer_id
	alert.tick = a_tick
	alert.text = a_text if a_text != "" else AlertCatalog.text_of(a_type)
	return alert


## Say where. Ignored for a type that may never be located, so a source cannot leak a
## position the catalog forbids.
func located_at(a_position: Vector3) -> Alert:
	if AlertCatalog.may_locate(type):
		has_position = true
		position = a_position
	return self


func about(a_subject: Node) -> Alert:
	_subject = weakref(a_subject) if a_subject != null else null
	return self


func subject() -> Node:
	return _subject.get_ref() as Node if _subject != null else null


func xz() -> Vector2:
	return Vector2(position.x, position.z)
#endregion
