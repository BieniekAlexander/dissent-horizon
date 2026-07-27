class_name ScenarioDialog
extends RefCounted

## One pop-up the scenario wants the player to read and acknowledge.
##
## It is a REQUEST, not a window: an EventShowDialog builds one and emits it on
## ScenarioTriggerManager.dialog_requested, and whatever is listening (ScenarioDialogView in
## a real session, a test double in GUT) decides how to draw it. That indirection is what
## keeps the trigger system free of any reference to the HUD — the same split
## message_requested / game_over already use.
##
## It carries the page as a PackedScene rather than as an instance: the VIEW instantiates
## when it actually displays, and frees when it moves on. That way a request nobody draws
## (headless test, spectator session) allocates nothing to leak, and the request stays a
## plain value that can be queued, dropped, or re-emitted without owning a Node.
##
## The dialog also owns the SIMULATION HOLD, not the view. Whoever raised the dialog takes
## the hold and connects `acknowledged` to release it; that way a dialog nobody draws still
## can't wedge the world, because dismissing the request is what resumes it, not closing a
## window.

#region Signals
## Emitted once, when the player accepts the dialog. Listeners release simulation holds and
## tear the window down here.
signal acknowledged

## Emitted when the player takes the SECONDARY option, just before the dialog resolves. What
## that option means is the raiser's business — EventShowDialog uses it to leave for the
## title screen.
signal secondary_chosen
#endregion

#region Properties
## The DialogPage scene to show. See scenes/dialogs/.
var page: PackedScene = null

## Label for an optional SECOND button. Empty (the default) means the usual one-button
## dialog. It lives on the REQUEST rather than on the page because the page is reusable copy
## and the choice is not: the same victory text raised by a different trigger might offer
## nothing but "continue". Whoever raises the dialog sets this and connects secondary_chosen.
var secondary_text: String = ""

## True once acknowledge() has run. Guards against a second click, and lets a view that
## opens late (the dialog was raised before the HUD existed) see it is already resolved.
var _acknowledged: bool = false
#endregion

#region Lifecycle
func _init(a_page: PackedScene = null) -> void:
	page = a_page
#endregion

#region Public API
## Accept the dialog. Idempotent — the second call does nothing, so a double-click on the
## button can't release a simulation hold twice.
func acknowledge() -> void:
	if _acknowledged:
		return
	_acknowledged = true
	acknowledged.emit()


func is_acknowledged() -> bool:
	return _acknowledged


## Whether this dialog offers a second option.
func has_secondary() -> bool:
	return not secondary_text.is_empty()


## Take the secondary option: announce it, then RESOLVE exactly as acknowledge() does. Going
## through acknowledge() is what guarantees a simulation hold is released down either path —
## the hold is bound to `acknowledged`, and a secondary that bypassed it would leave a world
## frozen behind whatever the choice led to.
func choose_secondary() -> void:
	if _acknowledged:
		return
	secondary_chosen.emit()
	acknowledge()


## Whether this request has a page to show. A dialog without one would open an empty window,
## so the view skips it.
func has_page() -> bool:
	return page != null
#endregion
