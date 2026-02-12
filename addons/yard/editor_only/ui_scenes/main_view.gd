@tool
extends Container

# To be used for PopupMenus items (context menu or the "File" MenuButton)
enum MenuAction {
	NONE = -1,
	NEW = 0,
	OPEN = 1,
	REOPEN_CLOSED = 2,
	OPEN_RECENT = 3,
	CLOSE = 13,
	CLOSE_OTHER_TABS = 14,
	CLOSE_TABS_BELOW = 15,
	CLOSE_ALL = 16,
	COPY_PATH = 20,
	COPY_UID = 21,
	SHOW_IN_FILESYSTEM = 22,
	MOVE_UP = 30,
	MOVE_DOWN = 31,
	SORT = 32,
}

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const PluginCFG := Namespace.PluginCFG
const RegistriesItemList := Namespace.RegistriesItemList
const RegistryView := Namespace.RegistryView
const NewRegistryDialog := Namespace.NewRegistryDialog
const AnyIcon := Namespace.AnyIcon
const FuzzySearch := Namespace.FuzzySearch
const FuzzySearchResult := Namespace.FuzzySearchResult
const _SAVED_STATE_PATH := "res://addons/yard/editor_only/state.cfg"

var _opened_registries: Dictionary[String, Registry] = { } # Dict[uid, Registry]
var _session_closed_uids: Array[String] = [] # Array[uid]
var _file_dialog: EditorFileDialog
var _file_dialog_option: MenuAction = MenuAction.NONE
var _current_registry_uid: String = ""
var _fuz := FuzzySearch.new()

@onready var file_menu_button: MenuButton = %FileMenuButton
@onready var registries_filter: LineEdit = %RegistriesFilter
@onready var registries_itemlist: RegistriesItemList = %RegistriesItemList
@onready var registry_view: RegistryView = %RegistryView
@onready var registry_context_menu: PopupMenu = %RegistryContextMenu
@onready var new_registry_dialog: NewRegistryDialog = %NewRegistryDialog


func _ready() -> void:
	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.file_selected.connect(_on_file_dialog_action)
	add_child(_file_dialog)

	registries_itemlist.registries_dropped.connect(_on_itemlist_registries_dropped)

	registries_filter.right_icon = get_theme_icon(&"Search", &"EditorIcons")

	_set_context_menu_accelerators()
	_populate_file_menu()
	file_menu_button.get_popup().id_pressed.connect(_on_file_menu_id_pressed)

	# Fuzzy Search settings
	_fuz.max_results = 20
	_fuz.max_misses = 2
	_fuz.allow_subsequences = true
	_fuz.start_offset = 0


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_pressed():
		registry_context_menu.activate_item_by_event(event)


## Open a registry from the filesystem and add it to the list of opened ones
func open_registry(registry: Registry) -> void:
	var filepath := registry.resource_path
	var uid := ResourceUID.path_to_uid(filepath)

	if uid not in _opened_registries:
		_opened_registries[uid] = registry
	_update_registries_itemlist()
	select_registry(uid)


## Close a registry, ask for save if not saved, and remove it from the list
func close_registry(uid: String) -> void:
	assert(_opened_registries.has(uid))
	_opened_registries.erase(uid)

	# TODO: save accept dialog if unsaved changes to resource
	if _opened_registries.is_empty():
		unselect_registry()
	elif _current_registry_uid == uid:
		select_registry(_opened_registries.keys()[0])

	_session_closed_uids.append(uid)
	_update_registries_itemlist()


func close_all() -> void:
	var safe_iter := _opened_registries.keys()
	safe_iter.reverse()
	for uid: String in safe_iter:
		close_registry(uid)


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
	#registry_view.show_placeholder()
	registry_view.current_registry = registry


func unselect_registry() -> void:
	_current_registry_uid = ""
	registries_itemlist.deselect_all()


func is_any_registry_selected() -> bool:
	#return registries_itemlist.is_anything_selected()
	return not _current_registry_uid.is_empty()


func popup_new_registry_dialog(current_directory: String) -> void:
	#new_registry_dialog.path_line_edit.text = current_directory.path_join("new_registry.reg")
	new_registry_dialog.popup()


## Returns the index in the ItemList of the specified registry (by uid)
## -1 if not found
func _get_registry_list_index(uid: String) -> int:
	for idx in registries_itemlist.item_count:
		if registries_itemlist.get_item_metadata(idx) == uid:
			return idx
	return -1


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


func _add_registry_to_itemlist(uid: String, display_name: String) -> int:
	var registry := _opened_registries[uid]
	var path := registry.resource_path
	var icon := AnyIcon.get_variant_icon(load(uid), &"ClassList")

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
	var parts_by_uid: Dictionary = { } # uid -> Array[String] (path components, without "res://")
	var groups: Dictionary = { } # basename -> Array[String] of uids
	var result: Dictionary = { } # uid -> display name

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
			var seen: Dictionary = { }
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


@warning_ignore_start("int_as_enum_without_cast")
@warning_ignore_start("int_as_enum_without_match")
func _populate_file_menu() -> void:
	# TODO: when Godot 4.6 is out, register editor shortcuts
	# and reuse already registered ones using `EditorSettings.get_shortcut()`
	# https://github.com/godotengine/godot/pull/102889
	var file_menu := file_menu_button.get_popup()
	file_menu.name = "FileMenu"
	file_menu.set_item_accelerator(file_menu.get_item_index(MenuAction.NEW), KEY_MASK_META | KEY_N)
	file_menu.set_item_accelerator(
		file_menu.get_item_index(MenuAction.REOPEN_CLOSED),
		KEY_MASK_SHIFT | KEY_MASK_META | KEY_T,
	)
	file_menu.set_item_accelerator(file_menu.get_item_index(MenuAction.CLOSE), KEY_MASK_META | KEY_W)

	# TODO: implement "previous" logic
	var recent := PopupMenu.new()
	recent.add_item("previously_used.reg")
	recent.add_item("placeholder.reg")
	file_menu.set_item_submenu_node(
		file_menu.get_item_index(MenuAction.OPEN_RECENT),
		recent,
	)


func _set_context_menu_accelerators() -> void:
	registry_context_menu.set_item_accelerator(registry_context_menu.get_item_index(MenuAction.CLOSE), KEY_MASK_META | KEY_W)
	registry_context_menu.set_item_accelerator(registry_context_menu.get_item_index(MenuAction.MOVE_UP), KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_UP)
	registry_context_menu.set_item_accelerator(registry_context_menu.get_item_index(MenuAction.MOVE_DOWN), KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_DOWN)


@warning_ignore_restore("int_as_enum_without_cast")
@warning_ignore_restore("int_as_enum_without_match")
func _toggle_selection_related_menu_items(enable: bool) -> void:
	var disabled := !enable
	var file_menu := file_menu_button.get_popup()
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.COPY_PATH), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.COPY_UID), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.SHOW_IN_FILESYSTEM), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.COPY_UID), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE_ALL), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE_OTHER_TABS), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(MenuAction.CLOSE_TABS_BELOW), disabled)


func _toggle_move_up_down_items() -> void:
	var idx := _get_registry_list_index(_current_registry_uid)
	var is_first := idx == 0
	var is_last := idx == registries_itemlist.item_count - 1
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(MenuAction.MOVE_UP),
		is_first,
	)
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(MenuAction.MOVE_DOWN),
		is_last,
	)


func _do_menu_action(action_id: int) -> void:
	# TODO: implement actions logic
	match action_id:
		MenuAction.NEW:
			popup_new_registry_dialog("res://")
		MenuAction.OPEN:
			_file_dialog_option = MenuAction.OPEN
			_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.add_filter("*.reg", "Registries")
			_file_dialog.title = tr("Open Registry")
			_file_dialog.popup_file_dialog()
		MenuAction.REOPEN_CLOSED:
			if _session_closed_uids.is_empty(): # check because of shortcut
				return
			for idx in range(_session_closed_uids.size() - 1, -1, -1):
				var uid := _session_closed_uids[idx]
				if ResourceUID.has_id(ResourceUID.text_to_id(uid)):
					_session_closed_uids.remove_at(idx)
					open_registry(load(uid))
					return
				_session_closed_uids.remove_at(idx)
			push_warning(tr("None of the closed resources exist anymore"))
		MenuAction.CLOSE:
			if is_any_registry_selected(): # check because of shortcut
				close_registry(_current_registry_uid)
		MenuAction.CLOSE_OTHER_TABS:
			_close_other_tabs(_current_registry_uid)
		MenuAction.CLOSE_TABS_BELOW:
			_close_tabs_below(_current_registry_uid)
		MenuAction.CLOSE_ALL:
			close_all()
		MenuAction.COPY_PATH:
			var path := ResourceUID.uid_to_path(_current_registry_uid)
			if path:
				DisplayServer.clipboard_set(path)
		MenuAction.COPY_UID:
			DisplayServer.clipboard_set(_current_registry_uid)
		MenuAction.SHOW_IN_FILESYSTEM:
			_show_in_filesystem(_current_registry_uid)
		MenuAction.MOVE_UP:
			_reorder_opened_registries_move(_current_registry_uid, -1)
			_update_registries_itemlist()
		MenuAction.MOVE_DOWN:
			_reorder_opened_registries_move(_current_registry_uid, +1)
			_update_registries_itemlist()
		MenuAction.SORT:
			_sort_opened_registries_by_filename()
			_update_registries_itemlist()


func _reorder_opened_registries_move(uid: String, delta: int) -> bool:
	# delta = -1 -> move one up,
	# delta = +1 -> move one down
	if not _opened_registries.has(uid):
		return false

	var keys: Array[String] = _opened_registries.keys()
	var i := keys.find(uid)
	if i == -1:
		return false

	var j := i + delta
	if j < 0 or j >= keys.size():
		return false # can't move

	var tmp := keys[i]
	keys[i] = keys[j]
	keys[j] = tmp

	var reordered: Dictionary[String, Registry] = { }
	for k in keys:
		reordered[k] = _opened_registries[k]
	_opened_registries = reordered
	return true


func _sort_opened_registries_by_filename() -> void:
	var keys: Array[String] = _opened_registries.keys()
	var sorted: Dictionary[String, Registry] = { }
	keys.sort_custom(
		func(a: String, b: String) -> bool:
			return _opened_registries[a].resource_path.get_file().to_lower() \
			< _opened_registries[b].resource_path.get_file().to_lower()
	)
	for uid in keys:
		sorted[uid] = _opened_registries[uid]
	_opened_registries = sorted


func _close_other_tabs(uid: String) -> void:
	var other_uids := _opened_registries.keys()
	other_uids.erase(uid)
	other_uids.reverse()
	for o_uid: String in other_uids:
		close_registry(o_uid)


func _close_tabs_below(uid: String) -> void:
	var idx := _get_registry_list_index(uid)
	var tabs_below_uids := []
	for i in registries_itemlist.item_count:
		if i <= idx:
			continue
		tabs_below_uids.append(registries_itemlist.get_item_metadata(i))

	tabs_below_uids.reverse()
	for below_uid: String in tabs_below_uids:
		close_registry(below_uid)


func _show_in_filesystem(uid: String) -> void:
	var path := ResourceUID.uid_to_path(uid)
	var fs := EditorInterface.get_file_system_dock()
	fs.navigate_to_path(path)


func _warn_unimplemented() -> void:
	push_warning("This feature is not implemented yet. Demand to see my manager !")


func _on_registries_filter_text_changed(_new_text: String) -> void:
	_update_registries_itemlist()


func _on_registries_list_item_selected(idx: int) -> void:
	var selection_uid: String = registries_itemlist.get_item_metadata(idx)
	select_registry(selection_uid)


func _on_registries_list_item_clicked(idx: int, _at: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return

	var clicked_registry_uid := str(registries_itemlist.get_item_metadata(idx))
	select_registry(clicked_registry_uid)

	var pos := DisplayServer.mouse_get_position()
	registry_context_menu.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))


func _on_file_menu_button_about_to_popup() -> void:
	_toggle_selection_related_menu_items(is_any_registry_selected())
	var file_menu := file_menu_button.get_popup()
	var no_closed_uids := _session_closed_uids.is_empty()
	file_menu.set_item_disabled(
		file_menu.get_item_index(MenuAction.REOPEN_CLOSED),
		no_closed_uids,
	)


func _on_registry_context_menu_about_to_popup() -> void:
	_toggle_move_up_down_items()


func _on_file_menu_id_pressed(id: int) -> void:
	_do_menu_action(id)


func _on_registry_context_menu_id_pressed(id: int) -> void:
	_do_menu_action(id)


func _on_itemlist_registries_dropped(registries: Array[Registry]) -> void:
	print(registries)
	for registry in registries:
		open_registry(registry)


func _on_file_dialog_action(path: String) -> void:
	match _file_dialog_option:
		MenuAction.NEW:
			_warn_unimplemented()
		MenuAction.OPEN:
			var res := load(path)
			if res is Registry:
				open_registry(res)
			elif res.get_script():
				push_error("Tried to open %s as a Registry" % res.get_script().get_global_name())
			else:
				push_error("Tried to open %s as a Registry" % res.get_class())


func _on_refresh_view_button_pressed() -> void:
	if registry_view.current_registry:
		registry_view.update_view()


func _on_report_issue_button_pressed() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PluginCFG)
	var repo: String = cfg.get_value("plugin", "repository", "")
	if repo:
		OS.shell_open(repo + "/issues/new")


func _on_make_floating_button_pressed() -> void:
	_warn_unimplemented()
