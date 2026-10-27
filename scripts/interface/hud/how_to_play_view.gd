class_name HowToPlayView
extends HBoxContainer

## How to Play: the tutorial library (TutorialLibrary) browsed by category — a list on the left,
## the chosen note on the right. The title screen shows the library alone. In a scenario
## (show_notes_shown) the library notes it has popped up so far are highlighted, and its own
## notes, the ones only it needs, join a category of their own at the end (Alex, 2026-10-26).

## Width of the list of notes.
const LIST_WIDTH: float = 260.0
## Height of the reader; the note scrolls within it.
const READER_HEIGHT: float = 420.0
## A DialogPage's default content_width, plus room for the scroll bar.
const PAGE_WIDTH: float = 540.0
const MISSION_CATEGORY: String = "This mission"
const SHOWN_MARK: String = "●"
const SHOWN_COLOR: Color = Color(1.0, 0.85, 0.15)

var _library: TutorialLibrary = null
## The notes the scenario has shown, oldest first; empty outside one.
var _shown: Array[PackedScene] = []
var _tree: Tree
var _page_frame: ScrollContainer
var _selected: PackedScene = null
## Note titles by file, read once from each page scene: instantiating a page to read its title
## for every rebuild would build every note's labels each time.
var _titles: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_tree = Tree.new()
	_tree.name = "Notes"
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(LIST_WIDTH, READER_HEIGHT)
	_tree.item_selected.connect(_on_item_selected)
	add_child(_tree)
	_page_frame = ScrollContainer.new()
	_page_frame.name = "Reader"
	_page_frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_frame.custom_minimum_size = Vector2(PAGE_WIDTH, READER_HEIGHT)
	add_child(_page_frame)
	if _library == null:
		bind_library(TutorialLibrary.instantiate_default())
	_rebuild()


## Read `a_library` instead of the shipped one. The view takes ownership.
func bind_library(a_library: TutorialLibrary) -> void:
	if _library != null and _library != a_library:
		_library.queue_free()
	_library = a_library
	if _library.get_parent() == null:
		add_child(_library)
	if _tree != null:
		_rebuild()


## The notes a scenario has shown so far, oldest first: library notes among them are
## highlighted, the rest are listed under MISSION_CATEGORY. Opens on the newest.
func show_notes_shown(a_shown: Array[PackedScene]) -> void:
	_shown = a_shown.duplicate()
	_selected = _shown.back() if not _shown.is_empty() else null
	if _tree != null:
		_rebuild()


## The list as plain text, top to bottom: a category's title, then its notes indented, a shown
## note marked. What the view draws, for tests.
func entries() -> Array[String]:
	var out: Array[String] = []
	for group: Array in _groups():
		out.append(group[0])
		for note: PackedScene in group[1]:
			var mark: String = SHOWN_MARK + " " if _is_shown(note) else ""
			out.append("  %s%s" % [mark, _title_of(note)])
	return out


func selected_note() -> PackedScene:
	return _selected


func select_note(a_page: PackedScene) -> void:
	_selected = a_page
	_show_page(a_page)
	var item: TreeItem = _item_for(a_page)
	if item != null:
		item.select(0)


## [title, notes] per category, the mission's own last when it has any.
func _groups() -> Array:
	var out: Array = []
	if _library != null:
		for category: TutorialCategory in _library.categories():
			out.append([category.title, category.valid_notes()])
	var own: Array[PackedScene] = []
	for note: PackedScene in _shown:
		if _library == null or not _library.has_note(note):
			own.append(note)
	if not own.is_empty():
		out.append([MISSION_CATEGORY, own])
	return out


func _rebuild() -> void:
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	for group: Array in _groups():
		var heading: TreeItem = _tree.create_item(root)
		heading.set_text(0, group[0])
		heading.set_selectable(0, false)
		heading.set_custom_color(0, Color.WHITE)
		for note: PackedScene in group[1]:
			var item: TreeItem = _tree.create_item(heading)
			var shown: bool = _is_shown(note)
			item.set_text(
				0, ("%s %s" % [SHOWN_MARK, _title_of(note)]) if shown else _title_of(note)
			)
			if shown:
				item.set_custom_color(0, SHOWN_COLOR)
			item.set_metadata(0, note)
	if _selected == null:
		_selected = _first_note()
	select_note(_selected)


func _first_note() -> PackedScene:
	for group: Array in _groups():
		if not (group[1] as Array).is_empty():
			return group[1][0]
	return null


func _is_shown(a_note: PackedScene) -> bool:
	return _shown.any(func(p: PackedScene) -> bool: return p.resource_path == a_note.resource_path)


func _item_for(a_page: PackedScene) -> TreeItem:
	if a_page == null or _tree.get_root() == null:
		return null
	for heading: TreeItem in _tree.get_root().get_children():
		for item: TreeItem in heading.get_children():
			var note: PackedScene = item.get_metadata(0)
			if note != null and note.resource_path == a_page.resource_path:
				return item
	return null


func _title_of(a_note: PackedScene) -> String:
	if not _titles.has(a_note.resource_path):
		var page := a_note.instantiate()
		_titles[a_note.resource_path] = (page as DialogPage).title if page is DialogPage else ""
		page.free()
	return _titles[a_note.resource_path]


func _on_item_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	var note: PackedScene = item.get_metadata(0) if item != null else null
	if note != null and note != _selected:
		_selected = note
		_show_page(note)


func _show_page(a_page: PackedScene) -> void:
	for child: Node in _page_frame.get_children():
		_page_frame.remove_child(child)
		child.queue_free()
	if a_page != null:
		_page_frame.add_child(a_page.instantiate())
