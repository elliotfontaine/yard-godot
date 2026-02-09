@tool
extends Panel

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const DynamicTable := Namespace.DynamicTable
const UID_COLUMN_CONFIG := ["uid", "UID", TYPE_STRING]
const STRINGID_COLUMN_CONFIG := ["string_id", "String ID", TYPE_STRING]
const UID_COLUMN := 0
const STRINGID_COLUMN := 1
const PROPERTY_BLACKLIST := [
	&"script",
	&"resource_local_to_scene",
	&"resource_path",
	&"resource_name",
]

# Reference to dynamic table
@onready var dynamic_table: DynamicTable = %DynamicTable
# Popups
@onready var popup := %PopupMenu
@onready var confirm_popup := %ConfirmationDialog

var current_registry: Registry:
	set(value):
		current_registry = value
		update_view()

var properties_column_info: Array[Dictionary]
var entries_data: Array[Array] # inner arrays are rows, their content is columns

var current_selected_row := -1
var current_multiple_selected_rows := -1 # current multiple selected_rows
var multiple_selected_rows: Array # array of selected rows


func _ready() -> void:
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
	if not typeof(data) == TYPE_DICTIONARY and data.has("files"):
		return false
	
	if not current_registry:
		return false

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if current_registry._is_resource_class_valid(load(path)):
				return true

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	for path: String in data.files:
		if ResourceLoader.exists(path):
			if current_registry._is_resource_class_valid(load(path)):
				current_registry._add_entry(ResourceUID.path_to_uid(path))
	update_view()


func update_view() -> void:
	var resources: Dictionary[StringName, Resource] = current_registry.load_all()
	set_columns_data(resources.values())
	entries_data.clear()

	for uid in current_registry._uids_to_string_ids:
		var entry_data := [uid, current_registry.get_stringid(uid)]
		entry_data.append_array(get_res_row_data(current_registry.load_entry(uid)))
		entries_data.append(entry_data)

	dynamic_table.set_columns(_build_columns())
	dynamic_table.set_data(entries_data)
	dynamic_table.ordering_data(1, true)


func can_display_property(property_info: Dictionary) -> bool:
	return (
		property_info[&"type"] not in [TYPE_CALLABLE, TYPE_SIGNAL]
		and property_info[&"usage"] & PROPERTY_USAGE_EDITOR != 0
		and property_info[&"name"] not in PROPERTY_BLACKLIST
	)


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
			properties_column_info.append(
				{
					&"name": prop[&"name"],
					&"type": prop[&"type"],
					&"hint": prop[&"hint"],
					&"hint_string": prop[&"hint_string"].split(","),
				},
			)


func get_res_row_data(res: Resource) -> Array[Variant]:
	if properties_column_info.is_empty():
		return []

	var row: Array[Variant] = []
	for prop: Dictionary in properties_column_info:
		if prop[&"name"] in res:
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
		var prop_name: String = prop[&"name"]
		var prop_header := prop_name.capitalize()
		var prop_type: Variant.Type = prop[&"type"]
		var hint: PropertyHint = prop[&"hint"]
		var column := DynamicTable.ColumnConfig.new(
			prop[&"name"],
			prop_header,
			prop_type
		)

		if hint:
			column.property_hint = hint
		
		columns.append(column)
	return columns



func _confirm_delete_rows() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if (current_multiple_selected_rows > 0):
		confirm_popup.dialog_text = dialogtext % ["these " + str(current_multiple_selected_rows) + " rows"]
	else:
		confirm_popup.dialog_text = dialogtext % "this row"
	confirm_popup.show()


func _on_cell_selected(row: int, column: int) -> void:
	print("Cell selected on row ", row, ", column ", column, " Cell value: ", dynamic_table.get_cell_value(row, column), " Row value: ", dynamic_table.get_row_value(row))
	current_selected_row = row
	current_multiple_selected_rows = -1
	var uid: StringName = get_row_resource_uid(row)
	EditorInterface.edit_resource(load(uid))


func _on_cell_right_selected(row: int, column: int, mouse_pos: Vector2) -> void:
	print("Cell right selected on row ", row, ", column ", column, " Mouse position x: ", mouse_pos.x, " y: ", mouse_pos.y)
	if (row >= 0): # ignore header cells
		current_selected_row = row
		popup.position = mouse_pos
		if (entries_data.size() == 0 or row == entries_data.size()):
			popup.set("item_1/disabled", true)
			current_multiple_selected_rows = -1
		else:
			popup.set("item_1/disabled", false)
		popup.show()


func _on_multiple_rows_selected(rows: Array) -> void:
	current_multiple_selected_rows = rows.size() # number of current multiple rows selected
	multiple_selected_rows = rows # current multiple rows selected array


func _on_cell_edited(row: int, column: int, old_value: Variant, new_value: Variant) -> void:
	print("Cell edited on row ", row, ", column ", column, " Old value: ", old_value, " New value: ", new_value)


func _on_header_clicked(column: int) -> void:
	print("Header clicked on column ", column)


func _on_column_resized(column: int, new_width: float) -> void:
	print("Column ", column, " resized at width ", new_width)


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
