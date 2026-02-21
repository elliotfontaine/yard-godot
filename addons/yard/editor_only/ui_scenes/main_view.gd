@tool
extends Container

# To be used for PopupMenus items (context menu or the "File" MenuButton)
enum FileMenuAction {
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
const EditMenuAction := registry_view.EditMenuAction # Enum

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const PluginCFG := Namespace.PluginCFG
const RegistryIO := Namespace.RegistryIO
const RegistriesItemList := Namespace.RegistriesItemList
const RegistryView := Namespace.RegistryView
const NewRegistryDialog := Namespace.NewRegistryDialog
const AnyIcon := Namespace.AnyIcon
const FuzzySearch := Namespace.FuzzySearch
const FuzzySearchResult := Namespace.FuzzySearchResult

const ACCELERATORS: Dictionary = {
	FileMenuAction.NEW: KEY_MASK_META | KEY_N,
	FileMenuAction.REOPEN_CLOSED: KEY_MASK_SHIFT | KEY_MASK_META | KEY_T,
	FileMenuAction.CLOSE: KEY_MASK_META | KEY_W,
	FileMenuAction.MOVE_UP: KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_UP,
	FileMenuAction.MOVE_DOWN: KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_DOWN,
}

var _opened_registries: Dictionary[String, Registry] = { } # Dict[uid, Registry]
var _session_closed_uids: Array[String] = [] # Array[uid]
var _file_dialog: EditorFileDialog # TODO: refactor as Node in packed scene
var _file_dialog_option: FileMenuAction = FileMenuAction.NONE
var _current_registry_uid: String = ""
var _fuz := FuzzySearch.new()

@onready var file_menu_button: MenuButton = %FileMenuButton
@onready var edit_menu_button: MenuButton = %EditMenuButton
@onready var registry_buttons_v_separator: VSeparator = %RegistryButtonsVSeparator
@onready var columns_menu_button: MenuButton = %ColumnsMenuButton
@onready var registry_settings_button: Button = %RegistrySettingsButton
@onready var refresh_view_button: Button = %RefreshViewButton
@onready var registries_filter: LineEdit = %RegistriesFilter
@onready var registries_container: VBoxContainer = %RegistriesContainer
@onready var registries_itemlist: RegistriesItemList = %RegistriesItemList
@onready var registry_view: RegistryView = %RegistryView
@onready var registry_context_menu: PopupMenu = %RegistryContextMenu
@onready var new_registry_dialog: NewRegistryDialog = %NewRegistryDialog


func _ready() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(
		_on_filesystem_changed,
	)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.file_selected.connect(_on_file_dialog_action)
	add_child(_file_dialog)

	_toggle_visibility_topbar_buttons(false)
	_setup_accelerators()
	_populate_open_recent_submenu()

	file_menu_button.get_popup().id_pressed.connect(_on_file_menu_id_pressed)
	edit_menu_button.get_popup().id_pressed.connect(_on_edit_menu_id_pressed)
	columns_menu_button.get_popup().id_pressed.connect(_on_columns_menu_id_pressed)
	columns_menu_button.get_popup().hide_on_checkable_item_selection = false
	registries_itemlist.registries_dropped.connect(_on_itemlist_registries_dropped)

	registry_view.toggle_registry_panel_button.pressed.connect(_on_toggle_registries_pressed)

	# Fuzzy Search settings
	_fuz.max_results = 20
	_fuz.max_misses = 2
	_fuz.allow_subsequences = true
	_fuz.start_offset = 0

	var fixed_size := get_theme_constant("class_icon_size", "Editor")
	registries_itemlist.fixed_icon_size = Vector2i(fixed_size, fixed_size)


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
	_toggle_visibility_topbar_buttons(true)

	var registry: Registry = _opened_registries[uid]
	if EditorInterface.get_inspector().get_edited_object() != registry:
		EditorInterface.inspect_object(registry, "", true)

	#print("registry selected:  ", registry.resource_path, " (", uid, ")")
	RegistryIO.sync_registry_entries_from_scan_dir(registry)
	registry_view.current_registry = registry


func unselect_registry() -> void:
	_current_registry_uid = ""
	registry_view.current_registry = null
	_toggle_visibility_topbar_buttons(false)
	registries_itemlist.deselect_all()


func is_any_registry_selected() -> bool:
	return not _current_registry_uid.is_empty()


func _setup_accelerators() -> void:
	# TODO: when Godot 4.6 is out, register editor shortcuts
	# and reuse already registered ones using `EditorSettings.get_shortcut()`
	# https://github.com/godotengine/godot/pull/102889
	var file_menu := file_menu_button.get_popup()
	for action: FileMenuAction in ACCELERATORS:
		if file_menu.get_item_index(action) != -1:
			file_menu.set_item_accelerator(file_menu.get_item_index(action), ACCELERATORS.get(action))
		if registry_context_menu.get_item_index(action) != -1:
			registry_context_menu.set_item_accelerator(registry_context_menu.get_item_index(action), ACCELERATORS.get(action))

	var edit_menu := edit_menu_button.get_popup()
	for action: EditMenuAction in registry_view.ACCELERATORS:
		if edit_menu.get_item_index(action) != -1:
			edit_menu.set_item_accelerator(edit_menu.get_item_index(action), registry_view.ACCELERATORS.get(action))


func _populate_open_recent_submenu() -> void:
	var file_menu := file_menu_button.get_popup()
	file_menu.name = "FileMenu"

	# TODO: implement "recent" logic
	var recent := PopupMenu.new()
	#recent.add_item("previously_used.tres")
	#recent.add_item("placeholder.tres")
	file_menu.set_item_submenu_node(
		file_menu.get_item_index(FileMenuAction.OPEN_RECENT),
		recent,
	)


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

	var resource_icon := AnyIcon.get_class_icon(&"Resource")
	var registry_icon := AnyIcon.get_class_icon(&"Registry")
	var custom_res_icon := AnyIcon.get_variant_icon(registry, &"FileList")
	var icon := custom_res_icon

	if icon in [resource_icon, registry_icon]:
		icon = AnyIcon.get_class_icon(registry._class_restriction, &"FileList")
	if icon == resource_icon:
		icon = registry_icon

	var display_text := display_name + " (%s)" % registry.size()
	var idx := registries_itemlist.add_item(display_text, icon, true)

	registries_itemlist.set_item_tooltip(idx, path)
	registries_itemlist.set_item_metadata(idx, uid)
	return idx


func _restore_selection(uid: String) -> void:
	for i in range(registries_itemlist.item_count):
		if str(registries_itemlist.get_item_metadata(i)) == uid:
			registries_itemlist.select(i)
			return


func _toggle_visibility_topbar_buttons(p_visible: bool) -> void:
	registry_buttons_v_separator.visible = p_visible
	registry_settings_button.visible = p_visible
	columns_menu_button.visible = p_visible
	refresh_view_button.visible = p_visible


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


func _toggle_file_menu_items() -> void:
	var file_menu := file_menu_button.get_popup()
	var disabled := !is_any_registry_selected()
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.COPY_PATH), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.COPY_UID), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.SHOW_IN_FILESYSTEM), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.COPY_UID), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.CLOSE), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.CLOSE_ALL), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.CLOSE_OTHER_TABS), disabled)
	file_menu.set_item_disabled(file_menu.get_item_index(FileMenuAction.CLOSE_TABS_BELOW), disabled)

	var no_closed_uids := _session_closed_uids.is_empty()
	file_menu.set_item_disabled(
		file_menu.get_item_index(FileMenuAction.REOPEN_CLOSED),
		no_closed_uids,
	)

	var idx := _get_registry_list_index(_current_registry_uid)
	var is_last := idx == registries_itemlist.item_count - 1
	var has_single_file := registries_itemlist.item_count == 1
	var has_no_file := registries_itemlist.item_count == 0
	file_menu.set_item_disabled(
		file_menu.get_item_index(FileMenuAction.CLOSE_TABS_BELOW),
		is_last,
	)
	file_menu.set_item_disabled(
		file_menu.get_item_index(FileMenuAction.CLOSE_OTHER_TABS),
		has_single_file or has_no_file,
	)
	file_menu.set_item_disabled(
		file_menu.get_item_index(FileMenuAction.CLOSE_ALL),
		has_no_file,
	)


func _toggle_registry_context_menu_items() -> void:
	var idx := _get_registry_list_index(_current_registry_uid)
	var is_first := idx == 0
	var is_last := idx == registries_itemlist.item_count - 1
	var has_single_file := registries_itemlist.item_count == 1
	var has_no_file := registries_itemlist.item_count == 0
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(FileMenuAction.MOVE_UP),
		is_first,
	)
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(FileMenuAction.MOVE_DOWN),
		is_last,
	)
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(FileMenuAction.CLOSE_TABS_BELOW),
		is_last,
	)
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(FileMenuAction.CLOSE_TABS_BELOW),
		is_last,
	)
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(FileMenuAction.CLOSE_OTHER_TABS),
		has_single_file or has_no_file,
	)
	registry_context_menu.set_item_disabled(
		registry_context_menu.get_item_index(FileMenuAction.CLOSE_ALL),
		has_no_file,
	)


func _toggle_edit_menu_items() -> void:
	var edit_menu := edit_menu_button.get_popup()
	if not registry_view.current_registry:
		for idx in edit_menu.item_count:
			edit_menu.set_item_disabled(idx, true)
		return

	var dynamic_table := registry_view.dynamic_table
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES), dynamic_table.focused_row == -1)

	if dynamic_table.selected_rows.size() > 1:
		edit_menu.set_item_text(
			edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES),
			"Delete Entries (%s)" % dynamic_table.selected_rows.size(),
		)
	else:
		edit_menu.set_item_text(edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES), "Delete Entry")

	var has_selected_cell := -1 not in [dynamic_table.focused_row, dynamic_table.focused_col]
	var cant_be_cut := dynamic_table.focused_col in [registry_view.UID_COLUMN, registry_view.STRINGID_COLUMN]
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.CUT_CELL_VALUE), !has_selected_cell or cant_be_cut)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.COPY_CELL_VALUE), !has_selected_cell)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.PASTE_TO_CELL), !has_selected_cell)

	var is_resource_cell := has_selected_cell and dynamic_table.get_column(dynamic_table.focused_col).is_resource_column()
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.INSPECT_RESOURCE), !is_resource_cell)

	var has_selected_row: = dynamic_table.focused_row != -1
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.COPY_STRING_ID), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.COPY_UID), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.SHOW_IN_FILESYSTEM), !has_selected_row)


func _do_file_menu_action(action_id: int) -> void:
	match action_id:
		FileMenuAction.NEW:
			new_registry_dialog.popup_with_state(
				new_registry_dialog.RegistryDialogState.NEW_REGISTRY,
			)
		FileMenuAction.OPEN:
			_file_dialog_option = FileMenuAction.OPEN
			_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.title = tr("Open Registry")
			var filter := ""
			for ext: String in RegistryIO.REGISTRY_FILE_EXTENSIONS:
				filter += "%s*.%s" % ["" if filter == "" else ", ", ext]
			_file_dialog.add_filter(filter, "Registries")
			_file_dialog.popup_file_dialog()
		FileMenuAction.REOPEN_CLOSED:
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
		FileMenuAction.CLOSE:
			if is_any_registry_selected(): # check because of shortcut
				close_registry(_current_registry_uid)
		FileMenuAction.CLOSE_OTHER_TABS:
			_close_other_tabs(_current_registry_uid)
		FileMenuAction.CLOSE_TABS_BELOW:
			_close_tabs_below(_current_registry_uid)
		FileMenuAction.CLOSE_ALL:
			close_all()
		FileMenuAction.COPY_PATH:
			var path := ResourceUID.uid_to_path(_current_registry_uid)
			if path:
				DisplayServer.clipboard_set(path)
		FileMenuAction.COPY_UID:
			DisplayServer.clipboard_set(_current_registry_uid)
		FileMenuAction.SHOW_IN_FILESYSTEM:
			_show_in_filesystem(_current_registry_uid)
		FileMenuAction.MOVE_UP:
			_reorder_opened_registries_move(_current_registry_uid, -1)
			_update_registries_itemlist()
		FileMenuAction.MOVE_DOWN:
			_reorder_opened_registries_move(_current_registry_uid, +1)
			_update_registries_itemlist()
		FileMenuAction.SORT:
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
	_toggle_file_menu_items()


func _on_edit_menu_button_about_to_popup() -> void:
	_toggle_edit_menu_items()


func _on_registry_context_menu_about_to_popup() -> void:
	_toggle_registry_context_menu_items()


func _on_file_menu_id_pressed(id: int) -> void:
	_do_file_menu_action(id)


func _on_edit_menu_id_pressed(id: int) -> void:
	registry_view.do_edit_menu_action(id)


func _on_registry_context_menu_id_pressed(id: int) -> void:
	_do_file_menu_action(id)


func _on_columns_menu_id_pressed(id: int) -> void:
	var popup := columns_menu_button.get_popup()
	var prop_name: StringName = popup.get_item_tooltip(id)
	popup.toggle_item_checked(id)

	if popup.is_item_checked(id):
		registry_view.disabled_property_columns.erase(prop_name)
	else:
		if not prop_name in registry_view.disabled_property_columns:
			registry_view.disabled_property_columns.append(prop_name)

	registry_view.update_view()


func _on_itemlist_registries_dropped(registries: Array[Registry]) -> void:
	for registry in registries:
		open_registry(registry)


func _on_file_dialog_action(path: String) -> void:
	match _file_dialog_option:
		FileMenuAction.NEW:
			_warn_unimplemented()
		FileMenuAction.OPEN:
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


func _on_columns_menu_button_about_to_popup() -> void:
	var popup := columns_menu_button.get_popup()
	var registry := registry_view.current_registry
	popup.clear()

	if not registry:
		popup.add_separator("Select a registry first")
		return

	for prop: Dictionary in registry_view.properties_column_info:
		var prop_name: String = prop[&"name"]
		if prop_name not in registry_view.DISABLED_BY_DEFAULT_PROPERTIES:
			popup.add_check_item(prop_name.capitalize())
			popup.set_item_tooltip(popup.item_count - 1, prop_name)
			popup.set_item_icon(popup.item_count - 1, AnyIcon.get_property_icon_from_dict(prop))
			popup.set_item_checked(popup.item_count - 1, prop_name not in registry_view.disabled_property_columns)

	popup.add_separator()

	for prop: Dictionary in registry_view.properties_column_info:
		var prop_name: String = prop[&"name"]
		if prop_name in registry_view.DISABLED_BY_DEFAULT_PROPERTIES:
			popup.add_check_item(prop_name.capitalize())
			popup.set_item_tooltip(popup.item_count - 1, prop_name)
			popup.set_item_icon(popup.item_count - 1, AnyIcon.get_property_icon_from_dict(prop))
			popup.set_item_checked(popup.item_count - 1, prop_name not in registry_view.disabled_property_columns)


func _on_registry_settings_button_pressed() -> void:
	new_registry_dialog.edited_registry = registry_view.current_registry
	new_registry_dialog.popup_with_state(
		new_registry_dialog.RegistryDialogState.REGISTRY_SETTINGS,
	)


func _on_toggle_registries_pressed() -> void:
	registries_container.visible = !registries_container.visible
	registry_view.toggle_button_forward = !registries_container.visible


func _on_new_registry_dialog_confirmed() -> void:
	_update_registries_itemlist()
	if (
		new_registry_dialog._state == new_registry_dialog.RegistryDialogState.REGISTRY_SETTINGS
		and new_registry_dialog.edited_registry == registry_view.current_registry
	):
		registry_view.update_view()


func _on_filesystem_changed() -> void:
	for registry: Registry in _opened_registries.values():
		RegistryIO.sync_registry_entries_from_scan_dir(registry)
	_update_registries_itemlist()
	registry_view.update_view()


func _on_open_documentation_button_pressed() -> void:
	EditorInterface.get_script_editor().goto_help("class:Registry")
