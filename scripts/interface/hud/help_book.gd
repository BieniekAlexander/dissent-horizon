class_name HelpBook
extends Node

## The pages the HUD's help button flips through: a scenario's reference copy, usually the
## same control explanations its tutorial dialogs use.
##
## Add one as a child of the Scenario, named "HelpBook", and list DialogPage scenes in order.
## A scenario without one simply has no help button.
##
## Deliberately UNRELATED to what the trigger system has raised. The book is an authored
## list, not a log of dialogs the player has seen: it is available from the first frame, it
## reads in the order you wrote it rather than the order play happened to take, and it does
## not grow duplicates when a trigger repeats. Keeping the two in sync — listing the same
## page scenes here that the tutorial's EventShowDialogs point at — is an authoring choice,
## and pointing both at one scene is what makes that cheap.

#region Properties
## DialogPage scenes, in reading order.
@export var pages: Array[PackedScene] = []
#endregion

#region Public API
## Whether there is anything to show. The help button hides itself when there isn't.
func is_empty() -> bool:
	return _valid_pages().is_empty()


func page_count() -> int:
	return _valid_pages().size()


## The page at `index`, or null when the book is empty or the index is out of range.
func page_at(a_index: int) -> PackedScene:
	var valid: Array[PackedScene] = _valid_pages()
	if a_index < 0 or a_index >= valid.size():
		return null
	return valid[a_index]
#endregion

#region Internal
## The authored list with empty slots dropped — an Array[PackedScene] export shows a blank
## row whenever you grow it in the inspector, and a null there would otherwise become a
## missing page in the middle of the book.
func _valid_pages() -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	for page: PackedScene in pages:
		if page != null:
			result.append(page)
	return result
#endregion
