@tool
extends Container

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryView := Namespace.RegistryView
const FuzzySearch := Namespace.FuzzySearch
const FuzzySearchResult := Namespace.FuzzySearchResult

const _SAVED_STATE_PATH := "res://addons/yard/editor_only/state.cfg"

# To be used for PopupMenus items (context menu or the "File" MenuButton)
enum MenuAction {
	NEW = 0,
	OPEN = 1,
	REOPEN_CLOSED = 2,
	OPEN_RECENT = 3,
	
	SAVE = 10,
	SAVE_AS = 11,
	SAVE_ALL = 12,
	CLOSE = 13,
	CLOSE_OTHER_TABS = 14,
	CLOSE_TABS_BELOW = 15,
	CLOSE_ALL = 16,
	
	COPY_PATH = 20,
	COPY_UID = 21,
	SHOW_IN_FILESYSTEM = 22,
	
	MOVE_UP = 30,
	MOVE_DOWN = 31,
	SORT = 32
}

var _opened_registries: Dictionary[String, Registry] = {} # [uid, loaded resource]
var _fuz := FuzzySearch.new()

var _registries_context_menu: PopupMenu
var _current_registry_uid: String = ""

@onready var file_menu_button: MenuButton = %FileMenuButton
@onready var registry_view: RegistryView = %RegistryView
@onready var registries_filter: LineEdit = %RegistriesFilter
@onready var registries_itemlist: ItemList = %RegistriesList


func _ready() -> void:
	registries_filter.right_icon = get_theme_icon(&"Search", &"EditorIcons")
	
	_populate_file_menu()
	file_menu_button.get_popup().id_pressed.connect(_on_file_menu_id_pressed)
	
	_registries_context_menu = PopupMenu.new()
	_populate_context_menu()
	add_child(_registries_context_menu)
	_registries_context_menu.id_pressed.connect(_on_registry_context_menu_id_pressed)
	
	# Fuzzy Search settings
	_fuz.max_results = 20
	_fuz.max_misses = 2
	_fuz.allow_subsequences = true
	_fuz.start_offset = 0


## Open a registry from the filesystem and add it to the list of opened ones
func open_registry(registry: Registry) -> void:
	var filepath := registry.resource_path
	var uid := ResourceUID.path_to_uid(filepath)
	
	if uid not in _opened_registries:
		_opened_registries[uid] = registry
	_update_registries_itemlist()
	select_registry(uid)


## Select a registry on the list and view its content on the right
## UID is supposed to be valid
func select_registry(uid: String) -> void:
	var current_selection := registries_itemlist.get_selected_items()
	var target_already_selected := false
	
	for idx in current_selection:
		if registries_itemlist.get_item_metadata(idx) == uid:
			target_already_selected = true
	
	if not target_already_selected:
		for idx in registries_itemlist.item_count:
			if registries_itemlist.get_item_metadata(idx) == uid:
				registries_itemlist.select(idx)
				break
	
	_current_registry_uid = uid
	
	var registry: Registry = _opened_registries[uid]
	if EditorInterface.get_inspector().get_edited_object() != registry:
		EditorInterface.inspect_object(registry, "", true)
		
	print("registry selected:  ", registry.resource_path, " (", uid, ")")
	registry_view.show_placeholder()


## Update the ItemList of opened registries, based on the filter and avoid
## duplicates (mimicks the Script list behavior, showing path elements if needed)
func _update_registries_itemlist() -> void:
	registries_itemlist.set_block_signals(true)
	registries_itemlist.clear()

	if _opened_registries.is_empty():
		registries_itemlist.set_block_signals(false)
		return

	# Keep a stable iteration order.
	# (In practice, Godot 4 Dictionaries should preserve insertion order)
	var all_uids: Array[String] = _opened_registries.keys()

	# Determine which uids to show using fuzzy search, based on LineEdit filter.
	var display_name_by_uid := _build_registry_display_names(all_uids)
	var filter_text := registries_filter.text.strip_edges()
	var uids_to_show: Array[String] = []
	if filter_text == "":
		uids_to_show = all_uids
	else:
		_fuz.set_query(filter_text)
		var targets := PackedStringArray()
		for uid in all_uids:
			# Fuzzy match on displayed names, mimicking the Godot Editor script list.
			# To match on full resource paths, replace by the following :
			# `targets.append(_opened_registries[uid].resource_path)`
			targets.append(display_name_by_uid[uid])
		var fuzzy_results: Array = []
		_fuz.search_all(targets, fuzzy_results) # sorted by score already
		for res: FuzzySearchResult in fuzzy_results:
			# res.original_index maps back to `targets` (thus to `all_uids`)
			var idx: int = int(res.original_index)
			if idx >= 0 and idx < all_uids.size():
				uids_to_show.append(all_uids[idx])

	for uid in uids_to_show:
		_add_registry_to_itemlist(uid, display_name_by_uid[uid])

	if _current_registry_uid:
		_restore_selection(_current_registry_uid)

	registries_itemlist.set_block_signals(false)


func _add_registry_to_itemlist(uid: String, display_name: String, icon: Texture2D = null) -> int:
	var registry := _opened_registries[uid]
	var path := registry.resource_path
	if icon == null:
		icon = get_theme_icon(&"FileList", &"EditorIcons")

	var idx := registries_itemlist.add_item(display_name, icon, true)
	registries_itemlist.set_item_tooltip(idx, path)
	registries_itemlist.set_item_metadata(idx, uid)
	return idx


func _restore_selection(uid: String) -> void:
	for i in range(registries_itemlist.item_count):
		if str(registries_itemlist.get_item_metadata(i)) == uid:
			registries_itemlist.select(i)
			return


## Returns: uid -> display name in list.
## Show basename; if duplicates, prepend parent folders until unique within that duplicate set.
func _build_registry_display_names(uids: Array[String]) -> Dictionary:
	var parts_by_uid: Dictionary = {} # uid -> Array[String] (path components, without "res://")
	var groups: Dictionary = {} # basename -> Array[String] of uids
	var result: Dictionary = {} # uid -> display name
	
	# 1) Collect path parts and group by basename
	for uid in uids:
		var path := _opened_registries[uid].resource_path
		var rel := path
		if rel.begins_with("res://"):
			rel = rel.substr(6)
		
		var parts := rel.split("/", false)
		parts_by_uid[uid] = parts
		
		var base := parts[parts.size() - 1] if parts.size() > 0 else rel
		if not groups.has(base):
			groups[base] = []
		groups[base].append(uid)
	
	# 2) Disambiguate only the duplicate basenames (keep unique ones as plain filename)
	for base: String in groups.keys():
		var group: Array = groups[base]
		
		if group.size() == 1:
			result[group[0]] = base
			continue
		
		# Compute how deep we might need to go for this group.
		var max_depth := 0
		for uid: String in group:
			var parts: Array = parts_by_uid[uid]
			max_depth = max(max_depth, parts.size())
		
		# Increase suffix depth until names are unique within the group.
		var level := 1 # 1 parent folder + filename
		while true:
			var seen: Dictionary = {}
			var all_unique := true
			
			for uid: String in group:
				var parts: Array = parts_by_uid[uid]
				var take: int = min(parts.size(), 1 + level)
				var start := parts.size() - take
				var label := "/".join(parts.slice(start, parts.size()))
				result[uid] = label
				
				if seen.has(label):
					all_unique = false
				else:
					seen[label] = true
			
			if all_unique:
				break
			
			level += 1
			if 1 + level >= max_depth:
				# Fallback: full relative path (still the best you can do if identical)
				for uid: String in group:
					var parts: Array = parts_by_uid[uid]
					result[uid] = "/".join(parts)
				break
				
	return result


func _populate_file_menu() -> void:
	var file_menu := file_menu_button.get_popup()
	file_menu.name = "FileMenu"
	file_menu.add_item("New Registry...", MenuAction.NEW)
	file_menu.add_item("Open...", MenuAction.OPEN)
	file_menu.add_item("Reopen Closed Registry", MenuAction.REOPEN_CLOSED)
	file_menu.add_item("Open Recent", MenuAction.OPEN_RECENT)
	file_menu.add_separator()
	file_menu.add_item("Save", MenuAction.SAVE)
	file_menu.add_item("Save as...", MenuAction.SAVE_AS)
	file_menu.add_item("Save all", MenuAction.SAVE_ALL)
	file_menu.add_separator()
	file_menu.add_item("Copy Registry Path", MenuAction.COPY_PATH)
	file_menu.add_item("Copy Registry UID", MenuAction.COPY_UID)
	file_menu.add_item("Show in FileSystem", MenuAction.SHOW_IN_FILESYSTEM)
	file_menu.add_separator()
	file_menu.add_item("Close", MenuAction.CLOSE)
	file_menu.add_item("Close All", MenuAction.CLOSE_ALL)
	file_menu.add_item("Close Other Tabs", MenuAction.CLOSE_OTHER_TABS)
	file_menu.add_item("Close Tabs Below", MenuAction.CLOSE_TABS_BELOW)
	
	# TODO: implement "previous" logic
	var recent := PopupMenu.new()
	recent.add_item("previously_used.reg")
	recent.add_item("placeholder.reg")
	file_menu.set_item_submenu_node(
		file_menu.get_item_index(MenuAction.OPEN_RECENT), recent
	)


func _populate_context_menu() -> void:
	_registries_context_menu.name = "RegistriesContextMenu"
	_registries_context_menu.add_item("Save", MenuAction.SAVE)
	_registries_context_menu.add_item("Save as...", MenuAction.SAVE_AS)
	_registries_context_menu.add_item("Close", MenuAction.CLOSE)
	_registries_context_menu.add_item("Close Other Tabs", MenuAction.CLOSE_OTHER_TABS)
	_registries_context_menu.add_item("Close Tabs Below", MenuAction.CLOSE_TABS_BELOW)
	_registries_context_menu.add_item("Close All", MenuAction.CLOSE_ALL)
	_registries_context_menu.add_separator()
	_registries_context_menu.add_item("Copy Registry Path", MenuAction.COPY_PATH)
	_registries_context_menu.add_item("Copy Registry UID", MenuAction.COPY_UID)
	_registries_context_menu.add_item("Show in FileSystem", MenuAction.SHOW_IN_FILESYSTEM)
	_registries_context_menu.add_separator()
	_registries_context_menu.add_item("Move Up", MenuAction.MOVE_UP)
	_registries_context_menu.add_item("Move Down", MenuAction.MOVE_DOWN)
	_registries_context_menu.add_item("Sort", MenuAction.SORT)


func _toggle_selection_related_menu_items(disabled: bool) -> void:
	var file_menu := file_menu_button.get_popup()
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.SAVE), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.SAVE_AS), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.SAVE_ALL), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.COPY_PATH), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.COPY_UID), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.SHOW_IN_FILESYSTEM), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.COPY_UID), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE_ALL), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE_OTHER_TABS), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE_TABS_BELOW), disabled)


func _do_menu_action(action_id: int) -> void:
	# TODO: implement actions logic
	match action_id:
		MenuAction.NEW:
			_warn_unimplemented()
		MenuAction.OPEN:
			_warn_unimplemented()
		MenuAction.REOPEN_CLOSED:
			_warn_unimplemented()
		MenuAction.SAVE:
			_warn_unimplemented()
		MenuAction.SAVE_AS:
			_warn_unimplemented()
		MenuAction.SAVE_ALL:
			_warn_unimplemented()
		MenuAction.CLOSE:
			_warn_unimplemented()
		MenuAction.CLOSE_OTHER_TABS:
			_warn_unimplemented()
		MenuAction.CLOSE_TABS_BELOW:
			_warn_unimplemented()
		MenuAction.CLOSE_ALL:
			_warn_unimplemented()
		MenuAction.COPY_PATH:
			_warn_unimplemented()
		MenuAction.COPY_UID:
			_warn_unimplemented()
		MenuAction.SHOW_IN_FILESYSTEM:
			_show_in_filesystem(_current_registry_uid)
		MenuAction.MOVE_UP:
			_warn_unimplemented()
		MenuAction.MOVE_DOWN:
			_warn_unimplemented()
		MenuAction.SORT:
			_warn_unimplemented()


func _show_in_filesystem(uid: String) -> void:
	var path := ResourceUID.uid_to_path(uid)
	var fs := EditorInterface.get_file_system_dock()
	fs.navigate_to_path(path)


func _warn_unimplemented() -> void:
	push_warning("This feature is not implemented yet. Demand to see my manager !")


# TODO: implement drag-and-drop
# https://forum.godotengine.org/t/how-to-drag-and-drop-data-in-editor/50337


func _on_registries_filter_text_changed(_new_text: String) -> void:
	_update_registries_itemlist()


func _on_registries_list_item_selected(idx: int) -> void:
	var selection_uid: String = registries_itemlist.get_item_metadata(idx)
	select_registry(selection_uid)


func _on_registries_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return

	var clicked_registry_uid := str(registries_itemlist.get_item_metadata(index))
	select_registry(clicked_registry_uid)
	
	var pos := DisplayServer.mouse_get_position()
	_registries_context_menu.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))


func _on_file_menu_button_about_to_popup() -> void:
	_toggle_selection_related_menu_items(_current_registry_uid.is_empty())


func _on_file_menu_id_pressed(id: int) -> void:
	_do_menu_action(id)


func _on_registry_context_menu_id_pressed(id: int) -> void:
	_do_menu_action(id)
