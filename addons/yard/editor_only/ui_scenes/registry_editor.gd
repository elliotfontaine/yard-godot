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
	CLEAR_RECENT = 40,
}
const EditMenuAction := RegistryTableView.EditMenuAction # Enum

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const PluginCFG := Namespace.PluginCFG
const RegistryIO := Namespace.RegistryIO
const EditorStateData := Namespace.YardEditorCache.EditorStateData
const RegistryCacheData := Namespace.YardEditorCache.RegistryCacheData
const RegistriesItemList := Namespace.RegistriesItemList
const RegistryTableView := Namespace.RegistryTableView
const NewRegistryDialog := Namespace.NewRegistryDialog
const AnyIcon := Namespace.AnyIcon
const FuzzySearch := Namespace.FuzzySearch
const FuzzySearchResult := FuzzySearch.FuzzySearchResult
const DISABLED_BY_DEFAULT_COLUMNS: Array[StringName] = RegistryCacheData.DISABLED_BY_DEFAULT_COLUMNS

const ACCELERATORS_WIN: Dictionary = {
	FileMenuAction.NEW: KEY_MASK_CTRL | KEY_N,
	FileMenuAction.REOPEN_CLOSED: KEY_MASK_SHIFT | KEY_MASK_CTRL | KEY_T,
	FileMenuAction.CLOSE: KEY_MASK_CTRL | KEY_W,
	FileMenuAction.MOVE_UP: KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_UP,
	FileMenuAction.MOVE_DOWN: KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_DOWN,
}

const ACCELERATORS_MAC: Dictionary = {
	FileMenuAction.NEW: KEY_MASK_META | KEY_N,
	FileMenuAction.REOPEN_CLOSED: KEY_MASK_SHIFT | KEY_MASK_META | KEY_T,
	FileMenuAction.CLOSE: KEY_MASK_META | KEY_W,
	FileMenuAction.MOVE_UP: KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_UP,
	FileMenuAction.MOVE_DOWN: KEY_MASK_SHIFT | KEY_MASK_ALT | KEY_DOWN,
}

var _editor_state_data: EditorStateData
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
@onready var reindex_button: Button = %ReindexButton
@onready var rescan_button: Button = %RescanButton
@onready var registries_filter: LineEdit = %RegistriesFilter
@onready var registries_container: VBoxContainer = %RegistriesContainer
@onready var registries_itemlist: RegistriesItemList = %RegistriesItemList
@onready var registry_table_view: RegistryTableView = %RegistryTableView
@onready var registry_context_menu: PopupMenu = %RegistryContextMenu
@onready var new_registry_dialog: NewRegistryDialog = %NewRegistryDialog
@onready var read_me_window: AcceptDialog = $ReadMeWindow


func _ready() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.file_selected.connect(_on_file_dialog_action)
	add_child(_file_dialog)

	_toggle_visibility_topbar_buttons()
	_setup_accelerators()

	file_menu_button.get_popup().id_pressed.connect(_on_file_menu_id_pressed)
	edit_menu_button.get_popup().id_pressed.connect(_on_edit_menu_id_pressed)
	columns_menu_button.get_popup().id_pressed.connect(_on_columns_menu_id_pressed)
	columns_menu_button.get_popup().hide_on_checkable_item_selection = false
	registries_itemlist.registries_dropped.connect(_on_itemlist_registries_dropped)
	registry_table_view.toggle_registry_panel_button.pressed.connect(_on_toggle_registries_pressed)

	# Fuzzy Search settings
	_fuz.max_results = 20
	_fuz.max_misses = 2
	_fuz.allow_subsequences = true
	_fuz.start_offset = 0

	var fixed_size := get_theme_constant("class_icon_size", "Editor")
	registries_itemlist.fixed_icon_size = Vector2i(fixed_size, fixed_size)

	_editor_state_data = EditorStateData.load_or_default()
	if _editor_state_data.opened_registries.size() > 0:
		var first_uid: String = _editor_state_data.opened_registries.keys()[0]
		select_registry(first_uid)
	_update_registries_itemlist()


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_pressed():
		registry_context_menu.activate_item_by_event(event)


## Open a registry from the filesystem and add it to the list of opened ones
func open_registry(registry: Registry) -> void:
	var filepath := registry.resource_path
	var uid := ResourceUID.path_to_uid(filepath)

	if uid not in _editor_state_data.opened_registries:
		_editor_state_data.opened_registries[uid] = registry
		_editor_state_data = _editor_state_data.save_and_reload()
	_update_registries_itemlist()
	_editor_state_data.add_recent(registry)

	if RegistryIO.get_registry_settings(registry).auto_rescan:
		RegistryIO.sync_registry_entries_from_scan_dir(registry)

	select_registry(uid)


## Close a registry, which removes it from the registry list and from memory
func close_registry(uid: String) -> void:
	assert(_editor_state_data.opened_registries.has(uid))
	_editor_state_data.opened_registries.erase(uid)
	_editor_state_data = _editor_state_data.save_and_reload()

	# TODO: save accept dialog if unsaved changes to resource
	if _editor_state_data.opened_registries.is_empty():
		unselect_registry()
	elif _current_registry_uid == uid:
		select_registry(_editor_state_data.opened_registries.keys()[0])

	_session_closed_uids.append(uid)
	_update_registries_itemlist()


func close_all() -> void:
	var safe_iter: Array[String] = _editor_state_data.opened_registries.keys()
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

	var registry: Registry = _editor_state_data.opened_registries[uid]
	if EditorInterface.get_inspector().get_edited_object() != registry:
		EditorInterface.inspect_object(registry, "", true)

	registry_table_view.current_registry = registry
	_toggle_visibility_topbar_buttons()
	_toggle_file_menu_items()
	_toggle_registry_context_menu_items()


func unselect_registry() -> void:
	_current_registry_uid = ""
	registry_table_view.current_registry = null
	_toggle_visibility_topbar_buttons()
	registries_itemlist.deselect_all()


func is_any_registry_selected() -> bool:
	return not _current_registry_uid.is_empty()


func _setup_accelerators() -> void:
	# TODO: when Godot 4.6 is out, register editor shortcuts
	# and reuse already registered ones using `EditorSettings.get_shortcut()`
	# https://github.com/godotengine/godot/pull/102889
	var file_menu := file_menu_button.get_popup()
	var is_mac := OS.get_name() == "macOS"
	var accelerators := ACCELERATORS_MAC if is_mac else ACCELERATORS_WIN
	var edit_accelerators := RegistryTableView.ACCELERATORS_MAC if is_mac else RegistryTableView.ACCELERATORS_WIN
	for action: FileMenuAction in accelerators:
		if file_menu.get_item_index(action) != -1:
			file_menu.set_item_accelerator(file_menu.get_item_index(action), accelerators.get(action))
		if registry_context_menu.get_item_index(action) != -1:
			registry_context_menu.set_item_accelerator(registry_context_menu.get_item_index(action), accelerators.get(action))

	var edit_menu := edit_menu_button.get_popup()
	for action: EditMenuAction in edit_accelerators:
		if edit_menu.get_item_index(action) != -1:
			edit_menu.set_item_accelerator(edit_menu.get_item_index(action), edit_accelerators.get(action))


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

	if _editor_state_data.opened_registries.is_empty():
		registries_itemlist.set_block_signals(false)
		return

	_editor_state_data = _editor_state_data.save_and_reload()
	var all_uids: Array[String] = _editor_state_data.opened_registries.keys()

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
			# `targets.append(_editor_state_data.opened_registries[uid].resource_path)`
			targets.append(display_name_by_uid[uid])
		var fuzzy_results: Array[FuzzySearchResult] = []
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
	var registry: Registry = _editor_state_data.opened_registries[uid]
	var idx := registries_itemlist.add_item(
		"%s (%s)" % [display_name, registry.size()],
		_resolve_registry_itemlist_icon(registry),
		true,
	)
	registries_itemlist.set_item_tooltip(idx, registry.resource_path)
	registries_itemlist.set_item_metadata(idx, uid)
	return idx


func _resolve_registry_itemlist_icon(registry: Registry) -> Texture2D:
	var restriction := RegistryIO.get_registry_settings(registry).class_restriction
	if restriction != "":
		if RegistryIO.is_quoted_string(restriction):
			var path := restriction.substr(1, restriction.length() - 2)
			return AnyIcon.get_script_icon(ResourceLoader.load(path))
		else:
			var icon := AnyIcon.get_class_icon(restriction, &"Resource")
			if icon:
				return icon

	var custom_icon := AnyIcon.get_variant_icon(registry, &"Resource")
	var registry_icon := AnyIcon.get_class_icon(&"Registry")
	if custom_icon and custom_icon != registry_icon:
		return custom_icon

	return registry_icon


func _restore_selection(uid: String) -> void:
	for i in range(registries_itemlist.item_count):
		if str(registries_itemlist.get_item_metadata(i)) == uid:
			registries_itemlist.select(i)
			return


func _toggle_visibility_topbar_buttons() -> void:
	var has_registry := registry_table_view.current_registry != null
	registry_buttons_v_separator.visible = has_registry
	registry_settings_button.visible = has_registry
	columns_menu_button.visible = has_registry
	refresh_view_button.visible = false #has_registry # TODO: add project setting for showing it based on user preference
	reindex_button.visible = has_registry
	reindex_button.disabled = not has_registry or registry_table_view.current_registry.get_indexed_properties().is_empty()
	var show_rescan := has_registry and not RegistryIO.get_registry_settings(registry_table_view.current_registry).auto_rescan
	rescan_button.visible = show_rescan
	rescan_button.disabled = not show_rescan


## Returns: uid -> display name in list.
## Show basename; if duplicates, prepend parent folders until unique within that duplicate set.
func _build_registry_display_names(uids: Array[String]) -> Dictionary:
	var parts_by_uid: Dictionary = { } # uid -> Array[String] (path components, without "res://")
	var groups: Dictionary = { } # basename -> Array[String] of uids
	var result: Dictionary = { } # uid -> display name

	# 1) Collect path parts and group by basename
	for uid in uids:
		var path := _editor_state_data.opened_registries[uid].resource_path
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
	_toggle_generic_file_menu_items(file_menu)

	file_menu.set_item_disabled(
		file_menu.get_item_index(FileMenuAction.REOPEN_CLOSED),
		_session_closed_uids.is_empty(),
	)
	_populate_open_recent_submenu()


func _toggle_registry_context_menu_items() -> void:
	_toggle_generic_file_menu_items(registry_context_menu)


func _toggle_generic_file_menu_items(menu: PopupMenu) -> void:
	var no_registry := !is_any_registry_selected()
	for action: FileMenuAction in [
		FileMenuAction.COPY_PATH,
		FileMenuAction.COPY_UID,
		FileMenuAction.SHOW_IN_FILESYSTEM,
		FileMenuAction.CLOSE,
	]:
		menu.set_item_disabled(menu.get_item_index(action), no_registry)

	var idx := _get_registry_list_index(_current_registry_uid)
	var count := registries_itemlist.item_count
	menu.set_item_disabled(menu.get_item_index(FileMenuAction.MOVE_UP), idx == 0)
	menu.set_item_disabled(menu.get_item_index(FileMenuAction.MOVE_DOWN), idx == count - 1)
	menu.set_item_disabled(menu.get_item_index(FileMenuAction.CLOSE_TABS_BELOW), idx == count - 1)
	menu.set_item_disabled(menu.get_item_index(FileMenuAction.CLOSE_OTHER_TABS), count <= 1)
	menu.set_item_disabled(menu.get_item_index(FileMenuAction.CLOSE_ALL), count == 0)


func _toggle_edit_menu_items() -> void:
	var edit_menu := edit_menu_button.get_popup()
	if not registry_table_view.current_registry:
		for idx in edit_menu.item_count:
			edit_menu.set_item_disabled(idx, true)
		return

	registry_table_view.toggle_edit_menu_items(edit_menu)


func _populate_open_recent_submenu() -> void:
	var file_menu := file_menu_button.get_popup()

	var recent := PopupMenu.new()
	for entry in _editor_state_data.recent_registry_uids:
		if ResourceUID.has_id(ResourceUID.text_to_id(entry)):
			recent.add_item(ResourceUID.uid_to_path(entry))
	recent.add_separator()
	recent.add_item(tr("Clear Recent Registries"), FileMenuAction.CLEAR_RECENT)
	recent.set_item_disabled(recent.get_item_index(FileMenuAction.CLEAR_RECENT), recent.get_item_count() == 2) # only the "Clear" item
	recent.id_pressed.connect(
		func(id: int) -> void:
			if id == FileMenuAction.CLEAR_RECENT:
				_editor_state_data.clear_recent()
				return
			var uid := _editor_state_data.recent_registry_uids[id]
			if RegistryIO.is_uid_valid(uid):
				@warning_ignore("standalone_ternary")
				select_registry(uid) if _editor_state_data.opened_registries.has(uid) else open_registry(load(uid))
	)

	file_menu.set_item_submenu_node(
		file_menu.get_item_index(FileMenuAction.OPEN_RECENT),
		recent,
	)


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
				if RegistryIO.is_uid_valid(uid):
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
	_toggle_file_menu_items()
	_toggle_registry_context_menu_items()


func _reorder_opened_registries_move(uid: String, delta: int) -> bool:
	# delta = -1 -> move one up,
	# delta = +1 -> move one down
	if not _editor_state_data.opened_registries.has(uid):
		return false

	var keys: Array[String] = _editor_state_data.opened_registries.keys()
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
		reordered[k] = _editor_state_data.opened_registries[k]
	_editor_state_data.opened_registries = reordered
	_editor_state_data = _editor_state_data.save_and_reload()
	return true


func _sort_opened_registries_by_filename() -> void:
	var keys: Array[String] = _editor_state_data.opened_registries.keys()
	var sorted: Dictionary[String, Registry] = { }
	keys.sort_custom(
		func(a: String, b: String) -> bool:
			return _editor_state_data.opened_registries[a].resource_path.get_file().to_lower() \
			< _editor_state_data.opened_registries[b].resource_path.get_file().to_lower()
	)
	for uid in keys:
		sorted[uid] = _editor_state_data.opened_registries[uid]
	_editor_state_data.opened_registries = sorted
	_editor_state_data = _editor_state_data.save_and_reload()


func _close_other_tabs(uid: String) -> void:
	var other_uids := _editor_state_data.opened_registries.keys()
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
	registry_table_view.do_edit_menu_action(id)


func _on_registry_context_menu_id_pressed(id: int) -> void:
	_do_file_menu_action(id)


func _on_columns_menu_id_pressed(id: int) -> void:
	var popup := columns_menu_button.get_popup()

	if id == 0: # Freeze ID Columns
		popup.toggle_item_checked(0)
		registry_table_view.id_columns_frozen = popup.is_item_checked(0)
		return

	var prop_name: StringName = popup.get_item_tooltip(id)
	popup.toggle_item_checked(id)

	if popup.is_item_checked(id):
		registry_table_view.current_cache_data.disabled_columns.erase(prop_name)
		registry_table_view.current_cache_data.save()
	else:
		if not prop_name in registry_table_view.current_cache_data.disabled_columns:
			registry_table_view.current_cache_data.disabled_columns.append(prop_name)
			registry_table_view.current_cache_data.save()

	registry_table_view.update_view()


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
	if registry_table_view.current_registry:
		registry_table_view.update_view()


func _on_reindex_button_pressed() -> void:
	var registry := registry_table_view.current_registry
	if registry:
		RegistryIO.rebuild_property_index(registry)
		print("Registry reindexed for %s." % ", ".join(registry.get_indexed_properties()))


func _on_rescan_button_pressed() -> void:
	var registry := registry_table_view.current_registry
	if registry:
		RegistryIO.sync_registry_entries_from_scan_dir(registry)
	registry_table_view.update_view()


func _on_report_issue_button_pressed() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PluginCFG)
	var repo: String = cfg.get_value("plugin", "repository", "")
	if repo:
		OS.shell_open(repo + "/issues/new?template=bug_report.yml")


func _on_make_floating_button_pressed() -> void:
	print_rich("Coming soon! Thanks, KoBeWi ! <3")
	print_rich(
		"[color=SKY_BLUE][url]",
		"https://github.com/godotengine/godot/pull/113051",
		"[/url][/color]",
	)
	#_warn_unimplemented()


func _on_columns_menu_button_about_to_popup() -> void:
	var popup := columns_menu_button.get_popup()
	var registry := registry_table_view.current_registry
	popup.clear()

	if not registry:
		popup.add_separator("Select a registry first")
		return

	popup.add_check_item("Freeze ID Columns")
	popup.set_item_checked(0, registry_table_view.id_columns_frozen)

	popup.add_separator()

	for prop: Dictionary in registry_table_view.properties_column_info:
		var prop_name: String = prop[&"name"]
		if prop_name not in DISABLED_BY_DEFAULT_COLUMNS:
			popup.add_check_item(prop_name.capitalize())
			popup.set_item_tooltip(popup.item_count - 1, prop_name)
			popup.set_item_icon(popup.item_count - 1, AnyIcon.get_property_icon_from_dict(prop))
			popup.set_item_checked(popup.item_count - 1, prop_name not in registry_table_view.current_cache_data.disabled_columns)

	popup.add_separator()

	for prop: Dictionary in registry_table_view.properties_column_info:
		var prop_name: String = prop[&"name"]
		if prop_name in DISABLED_BY_DEFAULT_COLUMNS:
			popup.add_check_item(prop_name.capitalize())
			popup.set_item_tooltip(popup.item_count - 1, prop_name)
			popup.set_item_icon(popup.item_count - 1, AnyIcon.get_property_icon_from_dict(prop))
			popup.set_item_checked(popup.item_count - 1, prop_name not in registry_table_view.current_cache_data.disabled_columns)


func _on_registry_settings_button_pressed() -> void:
	new_registry_dialog.edited_registry = registry_table_view.current_registry
	new_registry_dialog.popup_with_state(
		new_registry_dialog.RegistryDialogState.REGISTRY_SETTINGS,
	)


func _on_toggle_registries_pressed() -> void:
	registries_container.visible = !registries_container.visible
	registry_table_view.toggle_button_forward = !registries_container.visible


func _on_new_registry_dialog_confirmed() -> void:
	_update_registries_itemlist()
	if (
		new_registry_dialog._state == new_registry_dialog.RegistryDialogState.REGISTRY_SETTINGS
		and new_registry_dialog.edited_registry == registry_table_view.current_registry
	):
		select_registry(_current_registry_uid)


func _on_filesystem_changed() -> void:
	for registry: Registry in _editor_state_data.opened_registries.values():
		if RegistryIO.get_registry_settings(registry).auto_rescan:
			RegistryIO.sync_registry_entries_from_scan_dir(registry)
	_update_registries_itemlist()
	registry_table_view.update_view()


func _on_open_documentation_button_pressed() -> void:
	EditorInterface.get_script_editor().goto_help("class:Registry")


func _on_read_me_button_pressed() -> void:
	read_me_window.popup_centered_ratio(0.8)
