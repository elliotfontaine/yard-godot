@tool
extends PanelContainer

enum EditMenuAction {
	NONE = -1,
	DELETE_ENTRIES = 0,
	COPY_STRING_ID = 1,
	COPY_UID = 2,
	SHOW_IN_FILESYSTEM = 3,
	INSPECT_RESOURCE = 4,
	CUT_CELL_VALUE = 5,
	COPY_CELL_VALUE = 6,
	PASTE_TO_CELL = 7,
	SELECT_ALL = 9,
	INVERT_SELECTION = 10,
	UNSELECT = 11,
}

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO
const ClassUtils := Namespace.ClassUtils
const EditorThemeUtils := Namespace.EditorThemeUtils
const DynamicTable := Namespace.DynamicTable

const LOGGING_INFO_COLOR := "lightslategray"
const UID_COLUMN_CONFIG := ["uid", "UID", TYPE_STRING]
const STRINGID_COLUMN_CONFIG := ["string_id", "String ID", TYPE_STRING]
const NON_PROP_COLUMNS_COUNT := 2
const STRINGID_COLUMN := 0
const UID_COLUMN := 1
const DISABLED_BY_DEFAULT_PROPERTIES: Array[StringName] = [
	&"script",
	&"resource_local_to_scene",
	&"resource_path",
	&"resource_name",
]

var current_registry: Registry:
	set(new):
		current_registry = new
		update_view()

var disabled_property_columns: Array[StringName] = DISABLED_BY_DEFAULT_PROPERTIES.duplicate()
var properties_column_info: Array[Dictionary]
var entries_data: Array[Array] # inner arrays are rows, their content is columns
var clipboard: Variant

var toggle_button_forward := false:
	set(value):
		if value:
			toggle_registry_panel_button.icon = get_theme_icon("Forward", "EditorIcons")
		else:
			toggle_registry_panel_button.icon = get_theme_icon("Back", "EditorIcons")

var _texture_rect_parent: Button
var _res_picker: EditorResourcePicker
var _uid_resource_to_inspect: String

@onready var dynamic_table: DynamicTable = %DynamicTable
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
	if Engine.is_editor_hint():
		EditorInterface.get_inspector().property_edited.connect(
			_on_inspector_property_edited,
		)

	dynamic_table.cell_selected.connect(_on_cell_selected)
	dynamic_table.cell_right_selected.connect(_on_cell_right_selected)
	dynamic_table.cell_edited.connect(_on_cell_edited)
	dynamic_table.header_clicked.connect(_on_header_clicked)
	dynamic_table.column_resized.connect(_on_column_resized)
	dynamic_table.multiple_rows_selected.connect(_on_multiple_rows_selected)

	# Resource Picker Theming
	resource_picker_container.add_theme_stylebox_override(
		&"panel",
		get_theme_stylebox("normal", "LineEdit").duplicate(),
	)
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_bottom = 0
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_top = 0
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_left = 0
	resource_picker_container.get_theme_stylebox(&"panel").content_margin_right = 0

	drag_and_drop_info_panel.get_theme_stylebox(&"panel").bg_color = EditorThemeUtils.get_base_color(
		0.6,
	)
	drag_and_drop_info_panel.get_theme_stylebox(&"panel").bg_color.a = 0.8
	focus_panel.add_theme_stylebox_override(&"panel", get_theme_stylebox("Focus", "EditorStyles"))

	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END


func _process(_delta: float) -> void:
	# Too many load() and inspect requests might be the source of the 'Abort trap: 6' crashes
	if _uid_resource_to_inspect and Engine.get_process_frames() % 30 == 0:
		EditorInterface.edit_resource(load(_uid_resource_to_inspect))
		_uid_resource_to_inspect = ""

	if _texture_rect_parent and _texture_rect_parent.custom_minimum_size != Vector2(1, 1):
		# It's set by C++ code to enlarge the resource preview in the inspector.
		# Since we want the bottom bar height to remain constant, we have to reset it.
		_texture_rect_parent.custom_minimum_size = Vector2(1, 1)

	if not get_viewport().gui_is_dragging():
		drag_and_drop_info_panel.visible = (
			current_registry and current_registry.is_empty()
		)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			_on_drag_begin()
		NOTIFICATION_DRAG_END:
			_on_drag_end()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		return false

	if not current_registry:
		return false

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO.is_resource_matching_restriction(current_registry, load(path)):
				return true
		elif path.ends_with("/"): # is dir
			if RegistryIO.dir_has_matching_resource(current_registry, path, true):
				return true

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var n_added := 0

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO.is_resource_matching_restriction(current_registry, load(path)):
				var status := RegistryIO.add_entry(current_registry, ResourceUID.path_to_uid(path))
				n_added += int(status == OK)
		elif path.ends_with("/"):
			var matching_resources := RegistryIO.dir_get_matching_resources(
				current_registry,
				path,
				true,
			)
			for res in matching_resources:
				var status := RegistryIO.add_entry(
					current_registry,
					ResourceUID.path_to_uid(res.resource_path),
				)
				n_added += int(status == OK)

	print_rich("[color=%s]Added %s new Resources to the registry.[/color]" % [LOGGING_INFO_COLOR, n_added])
	update_view()


func update_view() -> void:
	if not current_registry:
		add_entry_container.visible = false
		dynamic_table.set_columns([])
		var empty_data: Array[Array] = [[]]
		dynamic_table.set_data(empty_data)
		return

	add_entry_container.visible = true
	_setup_add_entry()

	var resources: Dictionary[StringName, Resource] = current_registry.load_all_blocking() # WARNING: Blocking!
	set_columns_data(resources.values())
	entries_data.clear()
	for uid in current_registry.get_all_uids():
		var entry_data := [current_registry.get_string_id(uid), uid]
		if not ResourceLoader.exists(uid): # WARN: Will throw error in console... Which is dumb.
			entry_data[UID_COLUMN] = "(!) " + uid
		entry_data.append_array(get_res_row_data(current_registry.load_entry(uid)))
		entries_data.append(entry_data)

	dynamic_table.set_columns(_build_columns())
	dynamic_table.set_data(entries_data)
	dynamic_table.ordering_data(STRINGID_COLUMN, true)


func is_property_disabled(property_info: Dictionary) -> bool:
	return property_info[&"name"] in disabled_property_columns


func set_columns_data(resources: Array[Resource]) -> void:
	properties_column_info.clear()
	var found_props := { }
	for res: Resource in resources:
		if not res:
			continue

		for prop: Dictionary in res.get_property_list():
			found_props[prop[&"name"]] = prop
			prop[&"owner_object"] = res

	for prop: Dictionary in found_props.values():
		if _can_display_property(prop):
			properties_column_info.append(prop)


func get_res_row_data(res: Resource) -> Array[Variant]:
	if properties_column_info.is_empty() or not res:
		return []

	var row: Array[Variant] = []
	for prop: Dictionary in properties_column_info:
		if is_property_disabled(prop):
			continue
		if prop[&"name"] in res:
			row.append(res.get(prop[&"name"]))
		else:
			row.append(DynamicTable.CELL_INVALID)
	return row


func get_row_resource_uid(row: int) -> StringName:
	var uid: StringName = dynamic_table.get_cell_value(row, UID_COLUMN)
	return uid


func get_row_resource_string_id(row: int) -> StringName:
	var string_id: StringName = dynamic_table.get_cell_value(row, STRINGID_COLUMN)
	return string_id


func _on_drag_begin() -> void:
	if not current_registry:
		drag_and_drop_info_panel.visible = false
		return
	var drag_data: Variant = get_viewport().gui_get_drag_data()
	var can_drop := drag_data != null and _can_drop_data(Vector2.ZERO, drag_data)
	drag_and_drop_info_panel.visible = can_drop
	focus_panel.visible = can_drop


func _on_drag_end() -> void:
	drag_and_drop_info_panel.hide()
	focus_panel.hide()


func _build_columns() -> Array[DynamicTable.ColumnConfig]:
	var columns: Array[DynamicTable.ColumnConfig] = []

	var string_id_column: DynamicTable.ColumnConfig = DynamicTable.ColumnConfig.new.callv(STRINGID_COLUMN_CONFIG)
	string_id_column.custom_font_color = get_theme_color("font_hover_pressed_color", "Editor")
	string_id_column.h_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	columns.append(string_id_column) #0

	var uid_column: DynamicTable.ColumnConfig = DynamicTable.ColumnConfig.new.callv(UID_COLUMN_CONFIG)
	uid_column.custom_font_color = get_theme_color("disabled_font_color", "Editor")
	uid_column.property_hint = PROPERTY_HINT_FILE
	columns.append(uid_column) #1

	for prop in properties_column_info:
		if not _can_display_property(prop) or is_property_disabled(prop):
			continue

		var prop_name: String = prop[&"name"]
		var prop_header := prop_name.capitalize()
		var prop_type: Variant.Type = prop[&"type"]
		var hint: PropertyHint = prop[&"hint"]
		var hint_string: String = prop[&"hint_string"]
		var class_string: String = prop[&"class_name"]
		var column := DynamicTable.ColumnConfig.new(
			prop[&"name"],
			prop_header,
			prop_type,
		)

		if hint:
			column.property_hint = hint
		if hint_string:
			column.hint_string = hint_string
		if class_string:
			column.class_string = class_string

		columns.append(column)

	return columns


func _can_display_property(property_info: Dictionary) -> bool:
	return (
		property_info[&"type"] not in [TYPE_CALLABLE, TYPE_SIGNAL]
		and property_info[&"usage"] & PROPERTY_USAGE_EDITOR != 0
	)


func _edit_entry_property(entry: StringName, property: StringName, old_value: Variant, new_value: Variant) -> void:
	var uid := current_registry.get_uid(entry)
	if not uid or not ResourceLoader.exists(uid):
		return

	var res := load(entry)
	if not property in res:
		print_rich(
			"[color=%s]● [b]ERROR:[/b] Property %s not in resource[/color]" % [
				EditorThemeUtils.color_error.to_html(false),
				property,
			],
		)
		return

	var prop_types := ClassUtils.get_property_declared_types(res, property)
	if new_value == null:
		if res.get_script():
			new_value = res.get_script().get_property_default_value(property)
		else:
			new_value = ClassDB.class_get_property_default_value(ClassUtils.get_type_name(res), property)

	var valid := false
	for prop_type: String in prop_types:
		if (ClassUtils.is_type_builtin(typeof(new_value)) and type_string(typeof(new_value)) == prop_type) \
		or ClassUtils.is_class_of(new_value, prop_type) \
		or (new_value == null and typeof(old_value) == TYPE_OBJECT):
			valid = true
			break

	if not valid:
		print_rich(
			"[color=%s]● [b]ERROR:[/b] Invalid type. Couldn't set %s (%s) to %s (%s)[/color]" % [
				EditorThemeUtils.color_error.to_html(false),
				property,
				", ".join(prop_types),
				new_value,
				ClassUtils.get_type_name(new_value),
			],
		)
		return

	res.set(property, new_value)
	print_rich(
		"[color=%s]Set %s from %s to %s[/color]" % [
			LOGGING_INFO_COLOR,
			property,
			old_value,
			new_value,
		],
	)


func _ask_confirm_delete_entries() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if not dynamic_table.selected_rows.is_empty():
		delete_entries_confirmation_dialog.dialog_text = dialogtext % ["these " + str(dynamic_table.selected_rows.size()) + " entries"]
	else:
		delete_entries_confirmation_dialog.dialog_text = dialogtext % "this entry"
	delete_entries_confirmation_dialog.show()


func _setup_add_entry() -> void:
	if _res_picker:
		_res_picker.queue_free()
	_res_picker = EditorResourcePicker.new()
	_res_picker.custom_minimum_size = Vector2(240, 0)
	if current_registry._class_restriction:
		_res_picker.base_type = current_registry._class_restriction
	else:
		_res_picker.base_type = "Resource"
	resource_picker_container.add_child(_res_picker)
	_texture_rect_parent = _res_picker.get_child(0)
	_res_picker.resource_changed.connect(_on_res_picker_resource_changed)
	_toggle_add_entry_button()
	entry_name_line_edit.text = ""


func _toggle_add_entry_button() -> void:
	add_entry_button.disabled = !(
		_res_picker and _res_picker.edited_resource and entry_name_line_edit.text
	)


func _toggle_edit_context_menu_items() -> void:
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.DELETE_ENTRIES), dynamic_table.focused_row == -1)

	if dynamic_table.selected_rows.size() > 1:
		edit_context_menu.set_item_text(
			edit_context_menu.get_item_index(EditMenuAction.DELETE_ENTRIES),
			"Delete Entries (%s)" % dynamic_table.selected_rows.size(),
		)
	else:
		edit_context_menu.set_item_text(edit_context_menu.get_item_index(EditMenuAction.DELETE_ENTRIES), "Delete Entry")

	var has_selected_cell := -1 not in [dynamic_table.focused_row, dynamic_table.focused_col]
	var cant_be_cut := dynamic_table.focused_col in [UID_COLUMN, STRINGID_COLUMN]
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.CUT_CELL_VALUE), !has_selected_cell or cant_be_cut)
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.COPY_CELL_VALUE), !has_selected_cell)
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.PASTE_TO_CELL), !has_selected_cell)

	var is_resource_cell := has_selected_cell and dynamic_table.get_column(dynamic_table.focused_col).is_resource_column()
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.INSPECT_RESOURCE), !is_resource_cell)

	var has_selected_row: = dynamic_table.focused_row != -1
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.COPY_STRING_ID), !has_selected_row)
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.COPY_UID), !has_selected_row)
	edit_context_menu.set_item_disabled(edit_context_menu.get_item_index(EditMenuAction.SHOW_IN_FILESYSTEM), !has_selected_row)


func do_edit_menu_action(action_id: int) -> void:
	if not current_registry:
		return
	match action_id:
		EditMenuAction.DELETE_ENTRIES:
			_ask_confirm_delete_entries()
		EditMenuAction.COPY_STRING_ID:
			DisplayServer.clipboard_set(get_row_resource_string_id(dynamic_table.focused_row))
		EditMenuAction.COPY_UID:
			DisplayServer.clipboard_set(get_row_resource_uid(dynamic_table.focused_row))
		EditMenuAction.SHOW_IN_FILESYSTEM:
			var uid := get_row_resource_uid(dynamic_table.focused_row)
			var path := ResourceUID.uid_to_path(uid)
			EditorInterface.get_file_system_dock().navigate_to_path(path)
		EditMenuAction.INSPECT_RESOURCE:
			var row := dynamic_table.focused_row
			var col := dynamic_table.focused_col
			if -1 not in [row, col]:
				var value: Variant = dynamic_table.get_cell_value(row, col)
				if value is Resource:
					EditorInterface.edit_resource(value)
		EditMenuAction.CUT_CELL_VALUE:
			var row := dynamic_table.focused_row
			var col := dynamic_table.focused_col
			var value: Variant = dynamic_table.get_cell_value(row, col)
			clipboard = value
			_on_cell_edited(row, col, value, null)
		EditMenuAction.COPY_CELL_VALUE:
			var row := dynamic_table.focused_row
			var col := dynamic_table.focused_col
			var value: Variant = dynamic_table.get_cell_value(row, col)
			clipboard = value
		EditMenuAction.PASTE_TO_CELL:
			var row := dynamic_table.focused_row
			var col := dynamic_table.focused_col
			var value: Variant = dynamic_table.get_cell_value(row, col)
			_on_cell_edited(row, col, value, clipboard)
		EditMenuAction.SELECT_ALL:
			_select_all()
		EditMenuAction.INVERT_SELECTION:
			_invert_selection()
		EditMenuAction.UNSELECT:
			_unselect()


func _delete_selected_entries() -> void:
	for row_idx: int in dynamic_table.selected_rows:
		var uid := get_row_resource_uid(row_idx)
		RegistryIO.erase_entry(current_registry, uid)

	dynamic_table.set_selected_cell(-1, -1) # cancel current selection
	update_view()


func _select_all() -> void:
	dynamic_table.selected_rows = range(dynamic_table._total_rows)
	dynamic_table.queue_redraw()


func _invert_selection() -> void:
	var selection := dynamic_table.selected_rows
	var inverted := []
	for row in dynamic_table._total_rows:
		if row not in selection:
			inverted.append(row)
	dynamic_table.selected_rows = inverted
	dynamic_table.queue_redraw()


func _unselect() -> void:
	dynamic_table.selected_rows = []
	dynamic_table.queue_redraw()


func _warn_unimplemented() -> void:
	push_warning("This feature is not implemented yet. Demand to see my manager !")


func _on_cell_selected(row: int, column: int) -> void:
	# WARNING: uncommenting it increases the chance of a crash occuring by a lot. Inexplicable,
	# but supposedly related to switching selected cell with arrow keys. Only report: 'Abort trap: 6'
	#print("Cell selected on row ", row, ", column ", column, " Cell value: ", dynamic_table.get_cell_value(row, column)) #, " Row value: ", dynamic_table.get_row_value(row))
	if row != -1 and column != -1:
		var uid: StringName = get_row_resource_uid(row)
		if ResourceLoader.exists(uid):
			_uid_resource_to_inspect = uid


func _on_cell_right_selected(row: int, column: int, mouse_pos: Vector2) -> void:
	#print("Cell right selected on row ", row, ", column ", column, " Mouse position x: ", mouse_pos.x, " y: ", mouse_pos.y)
	if (row >= 0): # ignore header cells
		edit_context_menu.popup(Rect2(DisplayServer.mouse_get_position(), Vector2.ZERO))


func _on_multiple_rows_selected(rows: Array) -> void:
	#print("Multiple row selected : ", rows)
	pass


func _on_cell_edited(row: int, column: int, old_value: Variant, new_value: Variant) -> void:
	#print("Cell edited on row ", row, ", column ", column, " Old value: ", old_value, " New value: ", new_value)
	if column not in [UID_COLUMN, STRINGID_COLUMN]:
		var entry := get_row_resource_uid(row)
		var col_config: DynamicTable.ColumnConfig = dynamic_table.get_column(column)
		var prop_name: StringName = col_config.identifier
		if ResourceLoader.exists(entry):
			_edit_entry_property(entry, prop_name, old_value, new_value)
	elif column == STRINGID_COLUMN and new_value:
		RegistryIO.rename_entry(current_registry, old_value, new_value)
	elif column == UID_COLUMN and new_value:
		RegistryIO.change_entry_uid(current_registry, old_value, new_value)
	update_view()


func _on_header_clicked(column: int) -> void:
	pass
	#print("Header clicked on column ", column)


func _on_column_resized(column: int, new_width: float) -> void:
	pass
	#print("Column ", column, " resized at width ", new_width)


func _on_inspector_property_edited(property: StringName) -> void:
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


func _on_delete_entries_confirmation_dialog_confirmed() -> void:
	_delete_selected_entries()


func _on_edit_context_menu_about_to_popup() -> void:
	_toggle_edit_context_menu_items()


func _on_add_entry_button_pressed() -> void:
	_toggle_add_entry_button()
	if add_entry_button.disabled:
		return

	var res: Resource = _res_picker.edited_resource
	var string_id: StringName = StringName(entry_name_line_edit.text)
	var path := res.resource_path
	var uid := ResourceUID.path_to_uid(path)

	var status := RegistryIO.add_entry(current_registry, uid, string_id)
	if status == OK:
		_res_picker.edited_resource = null
		entry_name_line_edit.text = ""
		_toggle_add_entry_button()
		update_view()
	else:
		print_rich(
			"[color=%s]● [b]ERROR:[/b] Invalid Resource Error: are you sure it is saved as a file ?[/color]" % [
				EditorThemeUtils.color_error.to_html(false),
			],
		)
