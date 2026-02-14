@tool
extends Panel

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO
const DynamicTable := Namespace.DynamicTable
const UID_COLUMN_CONFIG := ["uid", "UID", TYPE_STRING]
const STRINGID_COLUMN_CONFIG := ["string_id", "String ID", TYPE_STRING]
const NON_PROP_COLUMNS_COUNT := 2
const UID_COLUMN := 0
const STRINGID_COLUMN := 1
const DISABLED_BY_DEFAULT_PROPERTIES: Array[StringName] = [
	&"script",
	&"resource_local_to_scene",
	&"resource_path",
	&"resource_name",
]

var current_registry: Registry:
	set(value):
		current_registry = value
		update_view()

var disabled_property_columns: Array[StringName] = DISABLED_BY_DEFAULT_PROPERTIES.duplicate()
var properties_column_info: Array[Dictionary]
var entries_data: Array[Array] # inner arrays are rows, their content is columns

var current_selected_row := -1
var current_multiple_selected_rows := -1
var multiple_selected_rows: Array

@onready var dynamic_table: DynamicTable = %DynamicTable
@onready var popup := %PopupMenu
@onready var confirm_popup := %ConfirmationDialog


func _ready() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_inspector().property_edited.connect(
			_on_inspector_property_edited,
		)

	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END

	dynamic_table.cell_selected.connect(_on_cell_selected)
	dynamic_table.cell_right_selected.connect(_on_cell_right_selected)
	dynamic_table.cell_edited.connect(_on_cell_edited)
	dynamic_table.header_clicked.connect(_on_header_clicked)
	dynamic_table.column_resized.connect(_on_column_resized)
	dynamic_table.multiple_rows_selected.connect(_on_multiple_rows_selected)


func _process(_delta: float) -> void:
	if (Input.is_key_pressed(KEY_DELETE) and (current_selected_row >= 0 or current_multiple_selected_rows > 0)): # add support deleting items from keyboard
		_confirm_delete_rows()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		return false

	if not current_registry:
		return false

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO._is_resource_class_valid(current_registry, load(path)):
				return true

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO._is_resource_class_valid(current_registry, load(path)):
				RegistryIO._add_entry(current_registry, ResourceUID.path_to_uid(path))
	update_view()


func update_view() -> void:
	if not current_registry:
		dynamic_table.set_columns([])
		var empty_data: Array[Array] = [[]]
		dynamic_table.set_data(empty_data)
		return

	var resources: Dictionary[StringName, Resource] = current_registry.load_all_blocking()
	set_columns_data(resources.values())
	entries_data.clear()

	for uid in current_registry.get_all_uids():
		var entry_data := [uid, current_registry.get_string_id(uid)]
		entry_data.append_array(get_res_row_data(current_registry.load_entry(uid)))
		entries_data.append(entry_data)

	dynamic_table.set_columns(_build_columns())
	dynamic_table.set_data(entries_data)
	dynamic_table.ordering_data(1, true)


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
		if res == null:
			continue

		for prop: Dictionary in res.get_property_list():
			found_props[prop[&"name"]] = prop
			prop[&"owner_object"] = res

	for prop: Dictionary in found_props.values():
		if can_display_property(prop):
			properties_column_info.append(prop)


func get_res_row_data(res: Resource) -> Array[Variant]:
	if properties_column_info.is_empty():
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
	columns.append(DynamicTable.ColumnConfig.new.callv(UID_COLUMN_CONFIG))
	columns.append(DynamicTable.ColumnConfig.new.callv(STRINGID_COLUMN_CONFIG))

	for prop in properties_column_info:
		if not can_display_property(prop) or is_property_disabled(prop):
			continue

		var prop_name: String = prop[&"name"]
		var prop_header := prop_name.capitalize()
		var prop_type: Variant.Type = prop[&"type"]
		var hint: PropertyHint = prop[&"hint"]
		var column := DynamicTable.ColumnConfig.new(
			prop[&"name"],
			prop_header,
			prop_type,
		)

		if hint:
			column.property_hint = hint

		columns.append(column)

	return columns


func _edit_entry_property(entry: StringName, property: StringName, old_value: Variant, new_value: Variant) -> void:
	var res := load(entry)
	if property in res:
		res.set(property, new_value)
		print_rich(
			"[color=lightslategray]Set %s from %s to %s[/color]" % [
				property,
				old_value,
				new_value,
			],
		)
	else:
		print_rich(
			"[color=orangered]●[/color] [color=salmon][b]ERROR:[/b] ",
			"Property %s not in resource[/color]" % property,
		)


func _confirm_delete_rows() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if (current_multiple_selected_rows > 0):
		confirm_popup.dialog_text = dialogtext % ["these " + str(current_multiple_selected_rows) + " rows"]
	else:
		confirm_popup.dialog_text = dialogtext % "this row"
	confirm_popup.show()


func _on_cell_selected(row: int, column: int) -> void:
	#print("Cell selected on row ", row, ", column ", column, " Cell value: ", dynamic_table.get_cell_value(row, column), " Row value: ", dynamic_table.get_row_value(row))
	current_selected_row = row
	current_multiple_selected_rows = -1
	if row != -1 and column != -1:
		var uid: StringName = get_row_resource_uid(row)
		EditorInterface.edit_resource(load(uid))


func _on_cell_right_selected(row: int, column: int, mouse_pos: Vector2) -> void:
	#print("Cell right selected on row ", row, ", column ", column, " Mouse position x: ", mouse_pos.x, " y: ", mouse_pos.y)
	if (row >= 0): # ignore header cells
		current_selected_row = row
		popup.position = mouse_pos
		if (entries_data.size() == 0 or row == entries_data.size()):
			popup.set(&"item_1/disabled", true)
			current_multiple_selected_rows = -1
		else:
			popup.set(&"item_1/disabled", false)
		popup.show()


func _on_multiple_rows_selected(rows: Array) -> void:
	current_multiple_selected_rows = rows.size() # number of current multiple rows selected
	multiple_selected_rows = rows # current multiple rows selected array


func _on_cell_edited(row: int, column: int, old_value: Variant, new_value: Variant) -> void:
	#print("Cell edited on row ", row, ", column ", column, " Old value: ", old_value, " New value: ", new_value)
	if column not in [UID_COLUMN, STRINGID_COLUMN]:
		var entry := get_row_resource_uid(row)
		var col_config: DynamicTable.ColumnConfig = dynamic_table.get_column(column)
		var prop_name: StringName = col_config.identifier
		_edit_entry_property(entry, prop_name, old_value, new_value)


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
