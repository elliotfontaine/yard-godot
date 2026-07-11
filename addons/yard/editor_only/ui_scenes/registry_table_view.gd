@tool
extends PanelContainer

enum EditMenuAction {
	NONE = -1,
	DELETE_ENTRIES = 0,
	COPY_STRING_ID = 1,
	COPY_UID = 2,
	SHOW_IN_FILESYSTEM = 3,
	DUPLICATE_ENTRIES = 4,
	CUT_CELL_VALUE = 5,
	COPY_CELL_VALUE = 6,
	PASTE_TO_CELL = 7,
	SELECT_ALL = 9,
	INVERT_SELECTION = 10,
	UNSELECT = 11,
}
enum ColumnMenuAction {
	HIDDEN = 0,
	FROZEN = 1
}

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO
const ClassUtils := Namespace.ClassUtils
const EditorThemeUtils := Namespace.EditorThemeUtils
const DataTable := Namespace.DataTable
const YardLogger := Namespace.YardLogger
const RegistryCacheData := Namespace.YardEditorCache.RegistryCacheData

const ACCELERATORS_WIN: Dictionary = {
	EditMenuAction.DELETE_ENTRIES: KEY_MASK_CTRL | KEY_BACKSPACE,
	EditMenuAction.DUPLICATE_ENTRIES: KEY_MASK_CTRL | KEY_D,
	EditMenuAction.CUT_CELL_VALUE: KEY_MASK_CTRL | KEY_X,
	EditMenuAction.COPY_CELL_VALUE: KEY_MASK_CTRL | KEY_C,
	EditMenuAction.PASTE_TO_CELL: KEY_MASK_CTRL | KEY_V,
	EditMenuAction.SELECT_ALL: KEY_MASK_CTRL | KEY_A,
}

const ACCELERATORS_MAC: Dictionary = {
	EditMenuAction.DELETE_ENTRIES: KEY_MASK_META | KEY_BACKSPACE,
	EditMenuAction.DUPLICATE_ENTRIES: KEY_MASK_META | KEY_D,
	EditMenuAction.CUT_CELL_VALUE: KEY_MASK_META | KEY_X,
	EditMenuAction.COPY_CELL_VALUE: KEY_MASK_META | KEY_C,
	EditMenuAction.PASTE_TO_CELL: KEY_MASK_META | KEY_V,
	EditMenuAction.SELECT_ALL: KEY_MASK_META | KEY_A,
}

const INVALID_UID := "uid://<invalid>"
const UID_COLUMN_CONFIG := ["uid", "UID", TYPE_STRING]
const STRINGID_COLUMN_CONFIG := ["string_id", "String ID", TYPE_STRING]
const STRINGID_COLUMN: StringName = &"string_id"
const UID_COLUMN: StringName = &"uid"

var current_cache_data: RegistryCacheData
var properties_column_info: Array[Dictionary]
var clipboard: Variant

var current_registry: Registry:
	set(new):
		var is_another := new != current_registry
		current_registry = new
		current_cache_data = RegistryCacheData.load_or_default(new) if new else null
		if current_cache_data:
			_setup_add_entry()
		if is_another:
			data_table.clear_filter()
			data_table.sort_column = STRINGID_COLUMN
			data_table.sort_ascending = true
		update_view()

var toggle_button_forward := false:
	set(forward):
		var icon_name := &"Forward" if forward else &"Back"
		toggle_registry_panel_button.icon = get_theme_icon(icon_name, &"EditorIcons")

var _texture_rect_parent: Button
var _res_picker: EditorResourcePicker
var _uid_resource_to_inspect: String
var _subresource_to_inspect: Resource

@onready var data_table: DataTable = %DataTable
@onready var toggle_registry_panel_button: Button = %ToggleRegistryPanelButton
@onready var add_entry_container: HBoxContainer = %AddEntryContainer
@onready var resource_picker_container: PanelContainer = %ResourcePickerContainer
@onready var entry_name_line_edit: LineEdit = %EntryNameLineEdit
@onready var add_entry_button: Button = %AddEntryButton
@onready var edit_context_menu: PopupMenu = %EditContextMenu
@onready var delete_entries_confirmation_dialog := %DeleteEntriesConfirmationDialog
@onready var drag_and_drop_info_panel: PanelContainer = %DragAndDropInfoPanel
@onready var focus_panel: PanelContainer = %FocusPanel


func _ready() -> void:
	if not Engine.is_editor_hint() or EditorInterface.get_edited_scene_root() == self:
		return

	EditorInterface.get_inspector().property_edited.connect(
		_on_inspector_property_edited,
	)

	data_table.cell_selected.connect(_on_cell_selected)
	data_table.cell_right_selected.connect(_on_cell_right_selected)
	data_table.cell_edited.connect(_on_cell_edited)
	data_table.column_resized.connect(_on_column_resized)
	data_table.multiple_rows_selected.connect(_on_multiple_rows_selected)
	entry_name_line_edit.text_submitted.connect(_on_new_entry_text_submitted)

	var accelerators := ACCELERATORS_MAC if OS.get_name() == "macOS" else ACCELERATORS_WIN
	for action: EditMenuAction in accelerators:
		if edit_context_menu.get_item_index(action) != -1:
			edit_context_menu.set_item_accelerator(edit_context_menu.get_item_index(action), accelerators.get(action))

	resource_picker_container.add_theme_stylebox_override(
		&"panel",
		get_theme_stylebox("normal", "LineEdit").duplicate(),
	)
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_bottom = 0
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_top = 0
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_left = 0
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_right = 0

	drag_and_drop_info_panel.get_theme_stylebox(&"panel").bg_color = EditorThemeUtils.get_base_color(0.6)
	drag_and_drop_info_panel.get_theme_stylebox(&"panel").bg_color.a = 0.8
	focus_panel.add_theme_stylebox_override(&"panel", get_theme_stylebox("Focus", "EditorStyles"))

	if ClassUtils.is_engine_version_equal_or_newer(4, 6):
		var files_shortcut: Shortcut = EditorInterface.get_editor_settings().get_shortcut("script_editor/toggle_files_panel")
		if files_shortcut:
			toggle_registry_panel_button.shortcut = files_shortcut

	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END


func _process(_delta: float) -> void:
	# Too many load() and inspect requests might be the source of the 'Abort trap: 6' crashes
	if (_uid_resource_to_inspect or _subresource_to_inspect) and Engine.get_process_frames() % 30 == 0:
		if _subresource_to_inspect:
			EditorInterface.edit_resource(_subresource_to_inspect)
			_subresource_to_inspect = null
		elif _uid_resource_to_inspect:
			EditorInterface.edit_resource(load(_uid_resource_to_inspect))
			_uid_resource_to_inspect = ""

	if _texture_rect_parent and _texture_rect_parent.custom_minimum_size != Vector2(1, 1):
		# It's set by C++ code to enlarge the resource preview in the inspector.
		# Since we want the bottom bar height to remain constant, we have to reset it.
		_texture_rect_parent.custom_minimum_size = Vector2(1, 1)

	if not get_viewport().gui_is_dragging():
		drag_and_drop_info_panel.visible = current_registry and current_registry.is_empty()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			_on_drag_begin()
		NOTIFICATION_DRAG_END:
			_on_drag_end()


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if data_table.has_focus() and edit_context_menu.activate_item_by_event(event):
		get_viewport().set_input_as_handled()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		return false

	if not current_registry:
		return false

	var settings := RegistryIO.get_registry_settings(current_registry)
	var all_class_restrictions := settings.get_all_class_restrictions()
	var scan_rulesets := settings.get_compiled_rulesets()

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO.does_resource_match_class_restrictions(load(path), all_class_restrictions):
				return true

		elif path.ends_with("/"): # is dir
			for scan_ruleset in scan_rulesets:
				if RegistryIO.dir_has_matching_resource(path, scan_ruleset, "", true):
					return true

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var n_added := 0

	var settings := RegistryIO.get_registry_settings(current_registry)
	var all_class_restrictions := settings.get_all_class_restrictions()
	var scan_rulesets := settings.get_compiled_rulesets()

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO.does_resource_match_class_restrictions(load(path), all_class_restrictions):
				var status := RegistryIO.add_entry(current_registry, ResourceUID.path_to_uid(path))
				n_added += int(status == OK)

		elif path.ends_with("/"):
			for scan_ruleset in scan_rulesets:
				var matching_resources := RegistryIO.dir_get_matching_resources(path, scan_ruleset, "", true)
				for res in matching_resources:
					var status := RegistryIO.add_entry(
						current_registry,
						ResourceUID.path_to_uid(res.resource_path),
					)
					n_added += int(status == OK)

	YardLogger.info("Added %s new Resources to the registry." % n_added)
	update_view()


func update_view() -> void:
	if not current_registry:
		add_entry_container.visible = false
		data_table.set_columns([])
		data_table.set_data([], [])
		return

	var saved_sort_col := data_table.sort_column
	var saved_sort_asc := data_table.sort_ascending
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() else null
	var table_had_focus := focus_owner and (data_table == focus_owner or data_table.is_ancestor_of(focus_owner))

	add_entry_container.visible = true

	var resources: Dictionary[StringName, Resource] = current_registry.load_all_blocking()
	set_columns_data(resources.values())

	var rows: Array[Dictionary] = []
	var row_ids: Array[StringName] = []
	for uid in current_registry.get_all_uids():
		var string_id: StringName = current_registry.get_string_id(uid)
		var entry_data: Dictionary[StringName, Variant] = { }
		entry_data.set(STRINGID_COLUMN, string_id)
		if RegistryIO.is_uid_valid(uid):
			entry_data.set(UID_COLUMN, uid)
			entry_data.merge(get_resource_row_data(current_registry.load_entry(uid)))
		else:
			entry_data.set(UID_COLUMN, INVALID_UID)
			entry_data.merge(get_resource_row_data(null))
		rows.append(entry_data)
		row_ids.append(string_id)

	data_table.set_columns(_build_columns())

	for column: DataTable.ColumnConfig in data_table.get_all_columns():
		match column.identifier:
			UID_COLUMN:
				column.current_width = current_cache_data.uid_column_width
			STRINGID_COLUMN:
				column.current_width = current_cache_data.string_id_column_width
			_:
				var prop_name := column.identifier
				if current_cache_data.property_columns_widths.has(prop_name):
					column.current_width = current_cache_data.property_columns_widths[prop_name]

	# set_data preserves focused_row and selected_rows for keys that still exist
	data_table.set_data(rows, row_ids)

	if saved_sort_col != &"":
		data_table.ordering_data(saved_sort_col, saved_sort_asc)

	if table_had_focus:
		data_table.grab_focus()


func do_edit_menu_action(action_id: int) -> void:
	if not current_registry:
		return
	var focused_row := data_table.focused_row
	var focused_col := data_table.focused_col
	match action_id:
		EditMenuAction.DELETE_ENTRIES:
			_ask_confirm_delete_entries()
		EditMenuAction.COPY_STRING_ID:
			DisplayServer.clipboard_set(focused_row)
		EditMenuAction.COPY_UID:
			DisplayServer.clipboard_set(current_registry.get_uid(focused_row))
		EditMenuAction.SHOW_IN_FILESYSTEM:
			var uid := current_registry.get_uid(focused_row)
			var path := ResourceUID.uid_to_path(uid)
			EditorInterface.get_file_system_dock().navigate_to_path(path)
		EditMenuAction.DUPLICATE_ENTRIES:
			_duplicate_selected_entries()
		EditMenuAction.CUT_CELL_VALUE:
			var value: Variant = data_table.get_cell_value(focused_row, focused_col)
			if data_table.is_cell_valid(focused_row, focused_col):
				clipboard = value
				_on_cell_edited(focused_row, focused_col, value, null)
		EditMenuAction.COPY_CELL_VALUE:
			var value: Variant = data_table.get_cell_value(focused_row, focused_col)
			if data_table.is_cell_valid(focused_row, focused_col):
				clipboard = value
		EditMenuAction.PASTE_TO_CELL:
			var value: Variant = data_table.get_cell_value(focused_row, focused_col)
			if data_table.is_cell_valid(focused_row, focused_col):
				_on_cell_edited(focused_row, focused_col, value, clipboard)
		EditMenuAction.SELECT_ALL:
			_select_all()
		EditMenuAction.INVERT_SELECTION:
			_invert_selection()
		EditMenuAction.UNSELECT:
			_unselect()


func is_property_disabled(property_info: Dictionary) -> bool:
	return property_info[&"name"] in current_cache_data.disabled_columns


func set_columns_data(resources: Array[Resource]) -> void:
	properties_column_info.clear()
	var found_props := _collect_props(resources)
	var grouped := _group_props_by_class(found_props)

	var ordered_groups: Array[String] = ClassUtils.sort_by_inheritance(grouped.keys())
	if not current_cache_data.parent_props_first:
		ordered_groups.reverse()

	for class_str: String in ordered_groups:
		for prop_name: StringName in grouped[class_str]:
			var prop := found_props[prop_name]
			if _can_display_property(prop) or ClassUtils.is_class_property(prop):
				properties_column_info.append(prop)


func get_resource_row_data(res: Resource) -> Dictionary[StringName, Variant]:
	if properties_column_info.is_empty() or not res:
		return { }

	var row: Dictionary[StringName, Variant] = { }
	for prop: Dictionary in properties_column_info:
		if is_property_disabled(prop) or ClassUtils.is_class_property(prop):
			continue
		var prop_name: StringName = prop[&"name"]
		if prop_name in res:
			row.set(prop_name, res.get(prop_name))
	return row


func toggle_edit_menu_items(edit_menu: PopupMenu) -> void:
	var row := data_table.focused_row
	var col := data_table.focused_col
	var has_selected_cell := row != &"" and col != &""
	var has_selected_row := row != &""
	var cant_be_cut := col in [UID_COLUMN, STRINGID_COLUMN]
	var is_cell_invalid: bool = not data_table.is_cell_valid(row, col)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.DUPLICATE_ENTRIES), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.COPY_STRING_ID), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.COPY_UID), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.SHOW_IN_FILESYSTEM), !has_selected_row)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.CUT_CELL_VALUE), !has_selected_cell or cant_be_cut or is_cell_invalid)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.COPY_CELL_VALUE), !has_selected_cell or is_cell_invalid)
	edit_menu.set_item_disabled(edit_menu.get_item_index(EditMenuAction.PASTE_TO_CELL), !has_selected_cell or is_cell_invalid)

	for select_action: int in [EditMenuAction.SELECT_ALL, EditMenuAction.INVERT_SELECTION, EditMenuAction.UNSELECT]:
		edit_menu.set_item_disabled(edit_menu.get_item_index(select_action), false)

	if data_table.selected_rows.size() > 1:
		edit_menu.set_item_text(
			edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES),
			tr("Delete Entries (%s)") % data_table.selected_rows.size(),
		)
		edit_menu.set_item_text(
			edit_menu.get_item_index(EditMenuAction.DUPLICATE_ENTRIES),
			tr("Duplicate Entries (%s)") % data_table.selected_rows.size(),
		)
	else:
		edit_menu.set_item_text(edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES), tr("Delete Entry"))
		edit_menu.set_item_text(edit_menu.get_item_index(EditMenuAction.DUPLICATE_ENTRIES), tr("Duplicate Entry"))


func _build_columns() -> Array[DataTable.ColumnConfig]:
	var columns: Array[DataTable.ColumnConfig] = []

	var string_id_column: DataTable.ColumnConfig = DataTable.ColumnConfig.new.callv(STRINGID_COLUMN_CONFIG)
	string_id_column.custom_font_color = get_theme_color(&"accent_color", &"Editor")
	string_id_column.h_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	string_id_column.frozen = STRINGID_COLUMN in current_cache_data.frozen_columns
	columns.append(string_id_column)

	var uid_column: DataTable.ColumnConfig = DataTable.ColumnConfig.new.callv(UID_COLUMN_CONFIG)
	uid_column.custom_font_color = get_theme_color(&"disabled_font_color", &"Editor")
	uid_column.property_hint = PROPERTY_HINT_FILE
	uid_column.frozen = UID_COLUMN in current_cache_data.frozen_columns
	columns.append(uid_column)

	for prop in properties_column_info:
		if not _can_display_property(prop) or is_property_disabled(prop):
			continue

		var prop_name: String = prop[&"name"]
		var prop_header := prop_name.capitalize()
		var prop_type: Variant.Type = prop[&"type"]
		var hint: PropertyHint = prop[&"hint"]
		var hint_string: String = prop[&"hint_string"]
		var class_string: String = prop[&"class_name"]
		var column := DataTable.ColumnConfig.new(
			prop[&"name"],
			prop_header,
			prop_type,
		)
		column.frozen = column.identifier in current_cache_data.frozen_columns

		if hint:
			column.property_hint = hint
		if hint_string:
			column.hint_string = hint_string
		if class_string:
			column.class_string = class_string

		columns.append(column)

	return columns


func _collect_props(resources: Array[Resource]) -> Dictionary[StringName, Dictionary]:
	var found_props: Dictionary[StringName, Dictionary] = { }
	for res: Resource in resources:
		if res:
			for prop: Dictionary in res.get_property_list():
				prop[&"owner_object"] = res
				found_props[prop[&"name"]] = prop
	return found_props


func _group_props_by_class(found_props: Dictionary) -> Dictionary[String, Array]:
	var grouped: Dictionary[String, Array] = { }
	var current_group: Array[String] = []
	var current_class: String

	for prop: Dictionary in found_props.values():
		if ClassUtils.is_class_property(prop):
			if current_group.size() > 0:
				grouped[current_class] = current_group
			current_group = [prop[&"name"]]
			current_class = ClassUtils.get_class_name_or_path_from_prop(prop)
		else:
			current_group.append(prop[&"name"])

	if current_group.size() > 0:
		grouped[current_class] = current_group

	return grouped


func _can_display_property(property_info: Dictionary) -> bool:
	return (
		property_info[&"type"] not in [TYPE_CALLABLE, TYPE_SIGNAL]
		and property_info[&"usage"] & PROPERTY_USAGE_EDITOR != 0
	)


func _edit_entry_property(uid: StringName, property: StringName, old_value: Variant, new_value: Variant) -> void:
	if not RegistryIO.is_uid_valid(uid):
		return

	var res := load(uid)
	if not property in res:
		YardLogger.error("Property %s not in resource" % property)
		return

	var prop_types := ClassUtils.get_property_declared_types(res, property)
	if new_value == null:
		if res.get_script():
			new_value = res.get_script().get_property_default_value(property)
		else:
			new_value = ClassDB.class_get_property_default_value(ClassUtils.get_type_name(res), property)

	var valid := false
	for prop_type: String in prop_types:
		if (
			(ClassUtils.is_type_builtin(typeof(new_value)) and type_string(typeof(new_value)) == prop_type)
			or (typeof(new_value) in [TYPE_INT, TYPE_FLOAT] and prop_type in [type_string(TYPE_INT), type_string(TYPE_FLOAT)])
			or ClassUtils.is_class_of(new_value, prop_type)
			or (new_value == null and typeof(old_value) == TYPE_OBJECT)
		):
			valid = true
			break
		elif typeof(new_value) in [TYPE_INT, TYPE_FLOAT] and prop_type == type_string(TYPE_STRING):
			valid = true
			new_value = str(new_value)
			break

	if not valid:
		YardLogger.error(
			"Invalid type. Couldn't set %s (%s) to %s (%s)" % [
				property,
				", ".join(prop_types),
				new_value,
				ClassUtils.get_type_name(new_value),
			],
		)
		return

	var string_id := current_registry.get_string_id(uid)
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Set %s—>%s" % [string_id, property])
	undo_redo.add_do_property(res, property, new_value)
	undo_redo.add_undo_property(res, property, old_value)
	undo_redo.add_undo_method(self, &"update_view")
	undo_redo.commit_action()


func _ask_confirm_delete_entries() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if data_table.selected_rows.size() > 1:
		delete_entries_confirmation_dialog.dialog_text = dialogtext % ["these " + str(data_table.selected_rows.size()) + " entries"]
	else:
		delete_entries_confirmation_dialog.dialog_text = dialogtext % "this entry"
	delete_entries_confirmation_dialog.show()


func _setup_add_entry() -> void:
	if _res_picker:
		_res_picker.queue_free()
	_res_picker = EditorResourcePicker.new()
	_res_picker.custom_minimum_size = Vector2(240, 0)
	_res_picker.base_type = "Resource"

	var settings := RegistryIO.get_registry_settings(current_registry)
	if settings.has_any_class_restrictions():
		var all_class_restrictions_usable_strings: PackedStringArray
		for restriction in settings.get_all_class_restrictions():
			if not RegistryIO.is_quoted_string(restriction):
				all_class_restrictions_usable_strings.append(restriction)
			else:
				var script: Script = load(RegistryIO.unquote(restriction))
				all_class_restrictions_usable_strings.append(ClassUtils.get_type_name(script))
		if not all_class_restrictions_usable_strings.is_empty():
			_res_picker.base_type = ",".join(all_class_restrictions_usable_strings)

	resource_picker_container.add_child(_res_picker)
	_texture_rect_parent = _res_picker.get_child(0)
	_res_picker.resource_changed.connect(_on_res_picker_resource_changed)
	_res_picker.resource_selected.connect(_on_res_picker_resource_selected)
	_toggle_add_entry_button()
	entry_name_line_edit.text = ""


func _add_entry_from_picker(res: Resource, string_id: StringName) -> void:
	var res_is_file := res.resource_path and ResourceLoader.exists(res.resource_path)
	if not res_is_file:
		var current_dir := EditorInterface.get_current_path().get_base_dir()
		var save_path := current_dir.path_join(str(string_id) + ".tres")
		if ResourceLoader.exists(save_path):
			YardLogger.error("A file already exists at '%s'. Choose a different String ID or save the resource manually first." % save_path)
			return
		var save_status := ResourceSaver.save(res, save_path, ResourceSaver.FLAG_CHANGE_PATH)
		if save_status != OK:
			YardLogger.error("Failed to save resource to '%s'." % save_path)
			return
		EditorInterface.get_editor_toaster().push_toast("Resource saved to %s" % save_path)
		res = load(save_path) # Required because of race condition shinenigans I guess

	var uid := ResourceUID.path_to_uid(res.resource_path)

	var adding_status := RegistryIO.add_entry(current_registry, uid, string_id)
	match adding_status:
		OK:
			if res_is_file:
				_res_picker.edited_resource = null
			entry_name_line_edit.text = ""
			_toggle_add_entry_button()
			update_view()
		ERR_ALREADY_EXISTS:
			YardLogger.error("An entry with the same UID already exists in the registry.")
		ERR_CANT_ACQUIRE_RESOURCE:
			YardLogger.error("This resource is not saved as a file. Click [b]v[/b] then [b]Save[/b] on the resource picker to save it first.")
		ERR_INVALID_PARAMETER:
			YardLogger.error("The String ID is invalid. It must not start with 'uid://'.")
		ERR_DATABASE_CANT_WRITE:
			YardLogger.error("This resource doesn't match the registry class restriction.")
		_:
			YardLogger.error("Failed to add entry to the registry.")


func _toggle_add_entry_button() -> void:
	add_entry_button.disabled = !(
		_res_picker and _res_picker.edited_resource and entry_name_line_edit.text
	)


func _toggle_edit_context_menu_items() -> void:
	toggle_edit_menu_items(edit_context_menu)


func _delete_selected_entries() -> void:
	for string_id: StringName in data_table.selected_rows:
		var uid := current_registry.get_uid(string_id)
		if RegistryIO.erase_entry(current_registry, uid) != OK:
			YardLogger.error(
				"Failed to remove %s from %s." % [uid, current_registry.resource_path.get_file()],
			)

	data_table.set_selected_cell(&"", &"")
	update_view()


func _duplicate_selected_entries() -> void:
	for string_id: StringName in data_table.selected_rows:
		var uid := current_registry.get_uid(string_id)
		if RegistryIO.duplicate_entry(current_registry, uid) != OK:
			YardLogger.error(
				"Failed to duplicate %s in %s." % [uid, current_registry.resource_path.get_file()],
			)
	update_view()


func _select_all() -> void:
	data_table.select_all_rows()
	data_table.queue_redraw()


func _invert_selection() -> void:
	var selection := data_table.selected_rows
	var inverted: Array[StringName] = []
	for row: StringName in data_table.get_displayed_rows():
		if row not in selection:
			inverted.append(row)
	data_table.selected_rows = inverted
	data_table.queue_redraw()


func _unselect() -> void:
	data_table.selected_rows = []
	data_table.queue_redraw()


func _on_drag_begin() -> void:
	if not current_registry:
		drag_and_drop_info_panel.visible = false
		return
	var drag_data: Variant = get_viewport().gui_get_drag_data()
	var can_drop := drag_data != null and _can_drop_data(Vector2.ZERO, drag_data)
	drag_and_drop_info_panel.visible = can_drop or current_registry.is_empty()
	focus_panel.visible = can_drop


func _on_drag_end() -> void:
	drag_and_drop_info_panel.hide()
	focus_panel.hide()


func _on_cell_selected(string_id: StringName, col: StringName) -> void:
	if string_id != &"" and col != &"":
		var cell_value: Variant = data_table.get_cell_value(string_id, col)
		if cell_value is Resource:
			_subresource_to_inspect = cell_value
			_uid_resource_to_inspect = ""
		else:
			_subresource_to_inspect = null
			var uid: StringName = current_registry.get_uid(string_id)
			if RegistryIO.is_uid_valid(uid):
				_uid_resource_to_inspect = uid


func _on_cell_right_selected(string_id: StringName, _col: StringName, _mouse_pos: Vector2) -> void:
	if string_id != &"":
		edit_context_menu.popup(Rect2(DisplayServer.mouse_get_position(), Vector2.ZERO))


func _on_multiple_rows_selected(_ids: Array[StringName]) -> void:
	pass


func _on_cell_edited(string_id: StringName, column: StringName, old_value: Variant, new_value: Variant) -> void:
	if column not in [UID_COLUMN, STRINGID_COLUMN]:
		var uid := current_registry.get_uid(string_id)
		var property := column
		if RegistryIO.is_uid_valid(uid):
			_edit_entry_property(uid, property, old_value, new_value)
	elif column == STRINGID_COLUMN and new_value:
		RegistryIO.rename_entry(current_registry, string_id, new_value)
	elif column == UID_COLUMN and new_value:
		var uid := current_registry.get_uid(string_id)
		RegistryIO.change_entry_uid(current_registry, uid, new_value)
	update_view()


func _on_column_resized(column: StringName, new_width: float) -> void:
	match column:
		UID_COLUMN:
			current_cache_data.uid_column_width = new_width
		STRINGID_COLUMN:
			current_cache_data.string_id_column_width = new_width
		_:
			current_cache_data.property_columns_widths[column] = new_width

	current_cache_data.save()


func _on_inspector_property_edited(_property: StringName) -> void:
	var object := EditorInterface.get_inspector().get_edited_object()
	if object is not Resource or not current_registry:
		return

	var res: Resource = object
	var uid := ResourceUID.path_to_uid(res.resource_path)
	if uid.begins_with("uid://") and current_registry.has_uid(uid):
		update_view()


func _on_edit_context_menu_id_pressed(id: int) -> void:
	do_edit_menu_action(id)


func _on_entry_name_line_edit_text_changed(_new_text: String) -> void:
	_toggle_add_entry_button()


func _on_res_picker_resource_changed(_new_resource: Resource) -> void:
	_toggle_add_entry_button()


func _on_res_picker_resource_selected(resource: Resource, inspect: bool) -> void:
	if inspect:
		EditorInterface.edit_resource(resource)


func _on_delete_entries_confirmation_dialog_confirmed() -> void:
	_delete_selected_entries()


func _on_edit_context_menu_about_to_popup() -> void:
	_toggle_edit_context_menu_items()


func _on_new_entry_text_submitted(_new_text: String) -> void:
	_on_add_entry_button_pressed()


func _on_add_entry_button_pressed() -> void:
	_toggle_add_entry_button()
	if add_entry_button.disabled:
		return

	_add_entry_from_picker(_res_picker.edited_resource, StringName(entry_name_line_edit.text))
