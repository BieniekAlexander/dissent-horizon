@tool
class_name TutorialLibrary
extends Node

## The game's tutorial notes, read by the player as How to Play: a manual that stands on its own,
## grouped into TutorialCategory children, readable from the title screen and the pause menu
## anywhere in the game (Alex, 2026-10-26). A scenario REFERS to these notes — an EventShowDialog
## pops one up when it is relevant — and never owns them; a note only one scenario needs lives in
## that scenario instead. gdd/systems/scenario-scripting/dialogs-and-pause.md §How to Play.

## The one library the game ships.
const SCENE: String = "res://scenes/tutorial/tutorial_library.tscn"


## A fresh instance of the shipped library; the caller owns it.
static func instantiate_default() -> TutorialLibrary:
	return (load(SCENE) as PackedScene).instantiate() as TutorialLibrary


func categories() -> Array[TutorialCategory]:
	var out: Array[TutorialCategory] = []
	for child: Node in get_children():
		if child is TutorialCategory:
			out.append(child as TutorialCategory)
	return out


## Whether `a_page` is one of the library's notes, by its file: a scenario's own note is not.
func has_note(a_page: PackedScene) -> bool:
	if a_page == null:
		return false
	for category: TutorialCategory in categories():
		for note: PackedScene in category.valid_notes():
			if note.resource_path == a_page.resource_path:
				return true
	return false
