class_name ScenarioEntry
extends Resource

## One row of the title screen's scenario list: the label to put on a button, and the scene
## that button opens. MainMenu builds one button per entry.
##
## A Resource rather than a plain path string so a row can grow — a description, a preview
## image, an unlock rule — without changing how the list is authored or breaking the entries
## already filled in. Same shape as PlayerSlot: authored config, exported as an Array on the
## node that consumes it.

## Appended to the label of a mission that is named but not built.
const WIP_SUFFIX: String = " (WIP)"

## Button label. Optional — an entry that names only a scene still gets a readable button
## (see button_text).
@export var title: String = ""

## The scene the button opens. An entry with a title but no scene is a mission not built yet:
## its button is greyed out and marked WIP. One with neither is skipped and reported, since a
## button that reads as nothing is worse than no button at all.
@export var scene: PackedScene


## True when this entry can actually produce a working button.
func is_valid() -> bool:
	return scene != null


## True for a mission that is named but not built: a title and no scene yet.
func is_wip() -> bool:
	return scene == null and not title.is_empty()


## The label to draw. Falls back to the scene's file name ("s1.tscn" → "s1") so a row that
## names a scene but no title reads as something rather than as an empty button — which is
## what you want while wiring up a new scenario and haven't written the copy yet.
func button_text() -> String:
	if is_wip():
		return title + WIP_SUFFIX
	if not title.is_empty():
		return title
	if scene != null and not scene.resource_path.is_empty():
		return scene.resource_path.get_file().get_basename()
	return ""
