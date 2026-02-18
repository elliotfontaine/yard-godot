@tool
extends PanelContainer

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
		if current_registry:
			_setup_add_entry()
		add_entry_container.visible = new != null

		update_view()

var disabled_property_columns: Array[StringName] = DISABLED_BY_DEFAULT_PROPERTIES.duplicate()
var properties_column_info: Array[Dictionary]
var entries_data: Array[Array] # inner arrays are rows, their content is columns

var current_selected_cell := [-1, -1]
var current_selected_row := -1
var current_multiple_selected_rows := -1
var multiple_selected_rows: Array

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
@onready var popup := %PopupMenu
@onready var confirm_popup := %ConfirmationDialog


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
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END


func _process(_delta: float) -> void:
	if (Input.is_key_pressed(KEY_DELETE) and (current_selected_row >= 0 or current_multiple_selected_rows > 0)): # add support deleting items from keyboard
		_confirm_delete_rows()

	# Too many load() and inspect requests might be the source of the 'Abort trap: 6' crashes
	if _uid_resource_to_inspect and Engine.get_process_frames() % 30 == 0:
		EditorInterface.edit_resource(load(_uid_resource_to_inspect))
		_uid_resource_to_inspect = ""

	if _texture_rect_parent and _texture_rect_parent.custom_minimum_size != Vector2(1, 1):
		# It's set by C++ code to enlarge the resource preview in the inspector.
		# Since we want the bottom bar height to remain constant, we have to reset it.
		_texture_rect_parent.custom_minimum_size = Vector2(1, 1)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		return false

	if not current_registry:
		return false

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO._is_resource_class_valid(current_registry, load(path)):
				return true
		elif path.ends_with("/"): # is dir
			if RegistryIO.dir_has_matching_resource(current_registry, path, true):
				return true

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var n_added := 0

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO._is_resource_class_valid(current_registry, load(path)):
				var added := RegistryIO._add_entry(current_registry, ResourceUID.path_to_uid(path))
				n_added += int(added)
		elif path.ends_with("/"):
			var matching_resources := RegistryIO.dir_get_matching_resources(
				current_registry,
				path,
				true,
			)
			for res in matching_resources:
				var added := RegistryIO._add_entry(
					current_registry,
					ResourceUID.path_to_uid(res.resource_path),
				)
				n_added += int(added)

	print_rich("[color=%s]Added %s new Resources to the registry.[/color]" % [LOGGING_INFO_COLOR, n_added])
	update_view()


func update_view() -> void:
	if not current_registry:
		dynamic_table.set_columns([])
		var empty_data: Array[Array] = [[]]
		dynamic_table.set_data(empty_data)
		return
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


func can_display_property(property_info: Dictionary) -> bool:
	return (
		property_info[&"type"] not in [TYPE_CALLABLE, TYPE_SIGNAL]
		and property_info[&"usage"] & PROPERTY_USAGE_EDITOR != 0
	)


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
		if can_display_property(prop):
			properties_column_info.append(prop)


func get_res_row_data(res: Resource) -> Array[Variant]:
	if properties_column_info.is_empty() or not res:
		return []

	var row: Array[Variant] = []
	for prop: Dictionary in properties_column_info:
		if prop[&"name"] in res and not is_property_disabled(prop):
			row.append(res.get(prop[&"name"]))
	return row


func get_row_resource_uid(row: int) -> StringName:
	var uid: StringName = dynamic_table.get_cell_value(row, UID_COLUMN)
	return uid


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
		if not can_display_property(prop) or is_property_disabled(prop):
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


func _edit_entry_property(entry: StringName, property: StringName, old_value: Variant, new_value: Variant) -> void:
	var uid := current_registry.get_uid(entry)
	if not uid or not ResourceLoader.exists(uid):
		return
	var res := load(entry)
	if property in res:
		var prop_type := ClassUtils.get_property_declared_type(res, property)
		if (
			ClassUtils.is_type_builtin(typeof(new_value)) and type_string(typeof(new_value)) == prop_type
			or ClassUtils.is_class_of(new_value, prop_type)
		):
			res.set(property, new_value)
			print_rich(
				"[color=%s]Set %s from %s to %s[/color]" % [
					LOGGING_INFO_COLOR,
					property,
					old_value,
					new_value,
				],
			)
		else:
			print_rich(
				"[color=%s]● [b]ERROR:[/b] Invalid type. Couldn't set %s (%s) to %s (%s)[/color]" % [
					EditorThemeUtils.color_error.to_html(false),
					property,
					prop_type,
					new_value,
					ClassUtils.get_type_name(new_value),
				],
			)

	else:
		print_rich(
			"[color=%s]● [b]ERROR:[/b] Property %s not in resource[/color]" % [
				EditorThemeUtils.color_error.to_html(false),
				property,
			],
		)


func _confirm_delete_rows() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if (current_multiple_selected_rows > 0):
		confirm_popup.dialog_text = dialogtext % ["these " + str(current_multiple_selected_rows) + " rows"]
	else:
		confirm_popup.dialog_text = dialogtext % "this row"
	confirm_popup.show()


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


func _on_cell_selected(row: int, column: int) -> void:
	# WARNING: uncommenting it increases the chance of a crash occuring by a lot. Inexplicable,
	# but supposedly related to switching selected cell with arrow keys. Only report: 'Abort trap: 6'
	#print("Cell selected on row ", row, ", column ", column, " Cell value: ", dynamic_table.get_cell_value(row, column)) #, " Row value: ", dynamic_table.get_row_value(row))
	current_selected_row = row
	current_selected_cell = [row, column]
	current_multiple_selected_rows = -1
	Engine.get_process_frames()
	if row != -1 and column != -1:
		var uid: StringName = get_row_resource_uid(row)
		if ResourceLoader.exists(uid):
			_uid_resource_to_inspect = uid


func _on_cell_right_selected(row: int, column: int, mouse_pos: Vector2) -> void:
	print("Cell right selected on row ", row, ", column ", column, " Mouse position x: ", mouse_pos.x, " y: ", mouse_pos.y)
	if (row >= 0): # ignore header cells
		current_selected_row = row
		current_selected_cell = [row, column]
		popup.position = mouse_pos
		if (entries_data.size() == 0 or row == entries_data.size()):
			popup.set(&"item_1/disabled", true)
			current_multiple_selected_rows = -1
		else:
			popup.set(&"item_1/disabled", false)
		popup.show()


func _on_multiple_rows_selected(rows: Array) -> void:
	print("Multiple row selected : ", rows)
	current_multiple_selected_rows = rows.size() # number of current multiple rows selected
	multiple_selected_rows = rows # current multiple rows selected array


func _on_cell_edited(row: int, column: int, old_value: Variant, new_value: Variant) -> void:
	#print("Cell edited on row ", row, ", column ", column, " Old value: ", old_value, " New value: ", new_value)
	if column not in [UID_COLUMN, STRINGID_COLUMN]:
		var entry := get_row_resource_uid(row)
		var col_config: DynamicTable.ColumnConfig = dynamic_table.get_column(column)
		var prop_name: StringName = col_config.identifier
		if ResourceLoader.exists(entry):
			_edit_entry_property(entry, prop_name, old_value, new_value)
	elif column == STRINGID_COLUMN:
		RegistryIO.rename_entry(current_registry, old_value, new_value)
	elif column == UID_COLUMN:
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


func _on_popup_menu_id_pressed(id: int) -> void:
	if (id == 0): # Insert data row
		dynamic_table.insert_row(current_selected_row, [0, "----", "--------", "--", "-----", "-----", "01/01/2000", 0, 0])
	else: # Delete data row
		_confirm_delete_rows()


func _on_confirmation_dialog_confirmed() -> void:
	if (current_multiple_selected_rows > 0): # multiple rows
		multiple_selected_rows.sort_custom(func(a: Array, b: Array) -> bool: return a > b)
		for rowidx in range(0, multiple_selected_rows.size()):
			dynamic_table.delete_row(multiple_selected_rows[rowidx])
		multiple_selected_rows.clear()
	else:
		dynamic_table.delete_row(current_selected_row) # single row
	dynamic_table.set_selected_cell(-1, -1) # cancel current selection


func _on_entry_name_line_edit_text_changed(_new_text: String) -> void:
	_toggle_add_entry_button()


func _on_res_picker_resource_changed(_new_resource: Resource) -> void:
	_toggle_add_entry_button()


func _on_add_entry_button_pressed() -> void:
	_toggle_add_entry_button()
	if add_entry_button.disabled:
		return

	var res: Resource = _res_picker.edited_resource
	var string_id: StringName = StringName(entry_name_line_edit.text)
	var path := res.resource_path
	var uid := ResourceUID.path_to_uid(path)

	var success := RegistryIO._add_entry(current_registry, uid, string_id)
	if success:
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
