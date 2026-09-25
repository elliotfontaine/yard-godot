# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends PanelContainer

signal registry_changed

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
	OPEN_SUBRESOURCES = 12,
}
enum ColumnMenuAction {
	FROZEN = 1,
}

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const Compat := Namespace.Compat
const RegistryIO := Namespace.RegistryIO
const ClassUtils := Namespace.ClassUtils
const ShortcutUtils := Namespace.ShortcutUtils
const EditorThemeUtils := Namespace.EditorThemeUtils
const DataTable := Namespace.DataTable
const YardLogger := Namespace.YardLogger
const RegistryCacheData := Namespace.YardEditorCache.RegistryCacheData

const ACTION_SHORTCUTS: Dictionary[EditMenuAction, String] = {
	EditMenuAction.DELETE_ENTRIES: "delete_entries",
	EditMenuAction.DUPLICATE_ENTRIES: "duplicate_entries",
	EditMenuAction.CUT_CELL_VALUE: "cut_cell_clipboard",
	EditMenuAction.COPY_CELL_VALUE: "copy_cell_clipboard",
	EditMenuAction.PASTE_TO_CELL: "paste_cell_clipboard",
	EditMenuAction.SELECT_ALL: "select_all_entries",
}

const INVALID_UID := "uid://<invalid>"
const STRINGID_COLUMN: StringName = &"string_id"
const UID_COLUMN: StringName = &"uid"

var current_cache_data: RegistryCacheData
var clipboard: Variant
var properties_column_info: Array[Dictionary]:
	get:
		return _subresource_stack.back().columns_info if is_in_subresource_view() else _root_properties_column_info
var current_registry: Registry:
	set(new):
		var is_another := new != current_registry
		current_registry = new
		current_cache_data = RegistryCacheData.load_or_default(new) if new else null
		footer.set_current_registry(current_registry)
		if is_another:
			_subresource_stack.clear()
			data_table.clear_filter()
			data_table.sort_column = STRINGID_COLUMN
			data_table.sort_ascending = true
		update_view()

## Path of expanded subresource properties. Empty means we're viewing the root registry.
var _subresource_stack: Array[SubresourceFrame] = []
## Rows currently shown by the deepest subresource frame: row_id -> {resource, display_id}.
var _subresource_rows: Dictionary[StringName, Dictionary] = { }
var _root_properties_column_info: Array[Dictionary]
var _uid_resource_to_inspect: String
var _subresource_to_inspect: Resource

@onready var data_table: DataTable = %DataTable
@onready var edit_context_menu: PopupMenu = %EditContextMenu
@onready var delete_entries_confirmation_dialog := %DeleteEntriesConfirmationDialog
@onready var drag_and_drop_info_panel: PanelContainer = %DragAndDropInfoPanel
@onready var focus_panel: PanelContainer = %FocusPanel
@onready var footer: HBoxContainer = %Footer
@onready var subresource_bar: Container = %SubresourceBar
@onready var subresource_bar_breadcrumb: HBoxContainer = %SubresourceBarBreadcrumb


func _ready() -> void:
	if not Engine.is_editor_hint() or EditorInterface.get_edited_scene_root() == self:
		return

	EditorInterface.get_inspector().property_edited.connect(_on_inspector_property_edited)

	data_table.cell_selected.connect(_on_cell_selected)
	data_table.cell_right_selected.connect(_on_cell_right_selected)
	data_table.cell_edited.connect(_on_cell_edited)
	data_table.column_resized.connect(_on_column_resized)
	data_table.multiple_rows_selected.connect(_on_multiple_rows_selected)
	footer.add_entry_requested.connect(_on_footer_add_entry_requested)

	for action: EditMenuAction in ACTION_SHORTCUTS:
		if edit_context_menu.get_item_index(action) != -1:
			var action_string: String = ACTION_SHORTCUTS.get(action, "")
			var shortcut := ShortcutUtils.get_action_shortcut(action_string)
			if shortcut and shortcut.has_valid_event():
				edit_context_menu.set_item_shortcut(
					edit_context_menu.get_item_index(action),
					shortcut,
				)

	var lighter_base_color := EditorThemeUtils.get_base_color(0.6)
	drag_and_drop_info_panel.get_theme_stylebox(&"panel").bg_color = lighter_base_color
	drag_and_drop_info_panel.get_theme_stylebox(&"panel").bg_color.a = 0.8
	focus_panel.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"Focus", &"EditorStyles"))

	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END


func _process(_delta: float) -> void:
	# Too many load() and inspect requests might be the source of the 'Abort trap: 6' crashes
	if (
		(_uid_resource_to_inspect or _subresource_to_inspect)
		and Engine.get_process_frames() % 30 == 0
	):
		if _subresource_to_inspect:
			EditorInterface.edit_resource(_subresource_to_inspect)
			_subresource_to_inspect = null
		elif _uid_resource_to_inspect:
			EditorInterface.edit_resource(load(_uid_resource_to_inspect))
			_uid_resource_to_inspect = ""

	if not get_viewport().gui_is_dragging() and drag_and_drop_info_panel:
		drag_and_drop_info_panel.visible = (
			current_registry and current_registry.is_empty() and not is_in_subresource_view()
		)


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

	if not current_registry or is_in_subresource_view():
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
	if is_in_subresource_view():
		return

	var n_added := 0

	var settings := RegistryIO.get_registry_settings(current_registry)
	var all_class_restrictions := settings.get_all_class_restrictions()
	var scan_rulesets := settings.get_compiled_rulesets()

	for path: String in data.files:
		if ResourceLoader.exists(path):
			if RegistryIO.does_resource_match_class_restrictions(load(path), all_class_restrictions):
				var status := RegistryIO.add_entry(current_registry, Compat.path_to_uid(path))
				n_added += int(status == OK)

		elif path.ends_with("/"):
			for scan_ruleset in scan_rulesets:
				var matching_resources := RegistryIO.dir_get_matching_resources(
					path,
					scan_ruleset,
					"",
					true,
				)
				for res in matching_resources:
					var status := RegistryIO.add_entry(
						current_registry,
						Compat.path_to_uid(res.resource_path),
					)
					n_added += int(status == OK)

	YardLogger.info("Added %s new Resources to the registry." % n_added)
	update_view()
	registry_changed.emit()


func update_view() -> void:
	if not current_registry:
		footer.toggle_add_entry_fields(false)
		subresource_bar.visible = false
		data_table.set_columns([])
		data_table.set_data([], [])
		return

	if is_in_subresource_view():
		_update_subresource_view()
	else:
		_update_root_view()


func is_in_subresource_view() -> bool:
	return not _subresource_stack.is_empty()


func do_edit_menu_action(action_id: int) -> void:
	if not current_registry:
		return
	var focused_row := data_table.focused_row
	var focused_col := data_table.focused_col
	match action_id:
		EditMenuAction.DELETE_ENTRIES:
			_ask_confirm_delete_entries()
		EditMenuAction.COPY_STRING_ID:
			DisplayServer.clipboard_set(
				str(data_table.get_cell_value(focused_row, STRINGID_COLUMN))
			)
		EditMenuAction.COPY_UID:
			DisplayServer.clipboard_set(current_registry.get_uid(focused_row))
		EditMenuAction.SHOW_IN_FILESYSTEM:
			var uid := current_registry.get_uid(focused_row)
			var path := Compat.uid_to_path(uid)
			EditorInterface.get_file_system_dock().navigate_to_path(path)
		EditMenuAction.DUPLICATE_ENTRIES:
			_duplicate_selected_entries()
		EditMenuAction.OPEN_SUBRESOURCES:
			_enter_subresource_view(focused_col)
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


func is_column_disabled(column_id: StringName) -> bool:
	return resolve_column_storage_key(column_id) in current_cache_data.disabled_columns


func set_columns_data(resources: Array[Resource]) -> void:
	_root_properties_column_info = _compute_columns_info(resources)


func get_resource_row_data(
	res: Resource,
	columns_info: Array[Dictionary],
) -> Dictionary[StringName, Variant]:
	if columns_info.is_empty() or not res:
		return { }

	var displayed_props: Dictionary[StringName, bool] = { }
	for prop: Dictionary in res.get_property_list():
		if _can_display_property(prop):
			displayed_props[prop[&"name"]] = true

	var row: Dictionary[StringName, Variant] = { }
	for prop: Dictionary in columns_info:
		var prop_name: StringName = prop[&"name"]
		if is_column_disabled(prop_name) or ClassUtils.is_class_property(prop):
			continue
		if displayed_props.has(prop_name):
			row.set(prop_name, res.get(prop_name))
	return row


func toggle_edit_menu_items(edit_menu: PopupMenu) -> void:
	var row := data_table.focused_row
	var col := data_table.focused_col
	var has_selected_cell := row != &"" and col != &""
	var has_selected_row := row != &""
	var in_subresource := is_in_subresource_view()
	var cant_be_cut := col in [UID_COLUMN, STRINGID_COLUMN]
	var is_cell_invalid: bool = not data_table.is_cell_valid(row, col)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES),
		!has_selected_row or in_subresource,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.DUPLICATE_ENTRIES),
		!has_selected_row or in_subresource,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.COPY_STRING_ID),
		!has_selected_row,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.COPY_UID),
		!has_selected_row or in_subresource,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.SHOW_IN_FILESYSTEM),
		!has_selected_row or in_subresource,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.CUT_CELL_VALUE),
		!has_selected_cell or cant_be_cut or is_cell_invalid,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.COPY_CELL_VALUE),
		!has_selected_cell or is_cell_invalid,
	)
	edit_menu.set_item_disabled(
		edit_menu.get_item_index(EditMenuAction.PASTE_TO_CELL),
		!has_selected_cell or is_cell_invalid,
	)

	for select_action: int in [
		EditMenuAction.SELECT_ALL,
		EditMenuAction.INVERT_SELECTION,
		EditMenuAction.UNSELECT,
	]:
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
		edit_menu.set_item_text(
			edit_menu.get_item_index(EditMenuAction.DELETE_ENTRIES),
			tr("Delete Entry"),
		)
		edit_menu.set_item_text(
			edit_menu.get_item_index(EditMenuAction.DUPLICATE_ENTRIES),
			tr("Duplicate Entry"),
		)


func _compute_columns_info(resources: Array[Resource]) -> Array[Dictionary]:
	var found_props := _collect_props(resources)
	var grouped := _group_props_by_class(found_props)

	var ordered_groups: Array[String] = ClassUtils.sort_by_inheritance(grouped.keys())
	if not current_cache_data.parent_props_first:
		ordered_groups.reverse()

	var result: Array[Dictionary] = []
	for class_str: String in ordered_groups:
		for prop_name: StringName in grouped[class_str]:
			var prop := found_props[prop_name]
			if _can_display_property(prop) or ClassUtils.is_class_property(prop):
				result.append(prop)
	return result


func _build_columns(
	columns_info: Array[Dictionary],
	include_uid: bool,
) -> Array[DataTable.ColumnConfig]:
	var columns: Array[DataTable.ColumnConfig] = []

	if not is_column_disabled(STRINGID_COLUMN):
		var string_id_column: DataTable.ColumnConfig = DataTable.ColumnConfig.new(
			STRINGID_COLUMN,
			"String ID",
			TYPE_STRING,
		)
		string_id_column.custom_font_color = get_theme_color(&"accent_color", &"Editor")
		string_id_column.h_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		string_id_column.frozen = is_column_frozen(STRINGID_COLUMN)
		columns.append(string_id_column)

	if include_uid and not is_column_disabled(UID_COLUMN):
		var uid_column: DataTable.ColumnConfig = DataTable.ColumnConfig.new(
			UID_COLUMN,
			"UID",
			TYPE_STRING,
		)
		uid_column.custom_font_color = get_theme_color(&"disabled_font_color", &"Editor")
		uid_column.property_hint = PROPERTY_HINT_FILE
		uid_column.frozen = is_column_frozen(UID_COLUMN)
		columns.append(uid_column)

	for prop in columns_info:
		var prop_name: String = prop[&"name"]
		if not _can_display_property(prop) or is_column_disabled(prop_name):
			continue

		var prop_header := prop_name.capitalize()
		var prop_type: Variant.Type = prop[&"type"]
		var hint: PropertyHint = prop[&"hint"]
		var hint_string: String = prop[&"hint_string"]
		var class_string: String = prop[&"class_name"]
		var column := DataTable.ColumnConfig.new(prop_name, prop_header, prop_type)
		column.frozen = is_column_frozen(column.identifier)

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
				var prop_name: StringName = prop[&"name"]
				if (
					found_props.has(prop_name)
					and (
						_can_display_property(found_props[prop_name])
						or not _can_display_property(prop)
					)
				):
					continue
				found_props[prop_name] = prop
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


func _enter_subresource_view(property: StringName) -> void:
	if property == &"":
		return
	var frame := SubresourceFrame.new()
	frame.property = property
	_subresource_stack.append(frame)
	_reset_table_navigation()
	update_view()


func _reset_table_navigation() -> void:
	data_table.clear_filter()
	data_table.set_selected_cell(&"", &"")
	data_table.sort_column = STRINGID_COLUMN
	data_table.sort_ascending = true


func _update_root_view() -> void:
	subresource_bar.visible = false
	footer.toggle_add_entry_fields(true)

	var saved_sort_col := data_table.sort_column
	var saved_sort_asc := data_table.sort_ascending
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() else null
	var table_had_focus := (
		focus_owner and (data_table == focus_owner or data_table.is_ancestor_of(focus_owner))
	)

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
			entry_data.merge(
				get_resource_row_data(
					current_registry.load_entry(uid),
					_root_properties_column_info,
				)
			)
		else:
			entry_data.set(UID_COLUMN, INVALID_UID)
			entry_data.merge(get_resource_row_data(null, _root_properties_column_info))
		rows.append(entry_data)
		row_ids.append(string_id)

	data_table.set_columns(_build_columns(_root_properties_column_info, true))

	for column: DataTable.ColumnConfig in data_table.get_all_columns():
		match column.identifier:
			UID_COLUMN:
				column.current_width = current_cache_data.uid_column_width
			STRINGID_COLUMN:
				column.current_width = current_cache_data.string_id_column_width
			_:
				var width_key := _cache_key(column.identifier)
				if current_cache_data.property_columns_widths.has(width_key):
					column.current_width = current_cache_data.property_columns_widths[width_key]

	# set_data preserves focused_row and selected_rows for keys that still exist
	data_table.set_data(rows, row_ids)

	if saved_sort_col != &"":
		data_table.ordering_data(saved_sort_col, saved_sort_asc)

	if table_had_focus:
		data_table.grab_focus()


func _update_subresource_view() -> void:
	subresource_bar.visible = true
	footer.toggle_add_entry_fields(false)

	var saved_sort_col := data_table.sort_column
	var saved_sort_asc := data_table.sort_ascending
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() else null
	var table_had_focus := (
		focus_owner and (data_table == focus_owner or data_table.is_ancestor_of(focus_owner))
	)

	_subresource_rows = _resolve_subresource_leaves()
	_update_subresource_breadcrumb()

	var frame: SubresourceFrame = _subresource_stack.back()
	var leaf_resources: Array[Resource] = []
	for row_id: StringName in _subresource_rows:
		leaf_resources.append(_subresource_rows[row_id][&"resource"])
	frame.columns_info = _compute_columns_info(leaf_resources)

	var rows: Array[Dictionary] = []
	var row_ids: Array[StringName] = []
	for row_id: StringName in _subresource_rows:
		var row_data: Dictionary = _subresource_rows[row_id]
		var entry_data: Dictionary[StringName, Variant] = { }
		entry_data.set(STRINGID_COLUMN, row_data[&"display_id"])
		entry_data.merge(get_resource_row_data(row_data[&"resource"], frame.columns_info))
		rows.append(entry_data)
		row_ids.append(row_id)

	data_table.set_columns(_build_columns(frame.columns_info, false))

	for column: DataTable.ColumnConfig in data_table.get_all_columns():
		if column.identifier == STRINGID_COLUMN:
			column.current_width = current_cache_data.string_id_column_width
		else:
			var width_key := _cache_key(column.identifier)
			if current_cache_data.property_columns_widths.has(width_key):
				column.current_width = current_cache_data.property_columns_widths[width_key]

	data_table.set_data(rows, row_ids)

	if saved_sort_col != &"":
		data_table.ordering_data(saved_sort_col, saved_sort_asc)

	if table_had_focus:
		data_table.grab_focus()


## Walks the whole subresource stack from the root registry entries down to the deepest
## level, expanding Array[Resource] properties into one row per element along the way.
## Returns row_id -> {resource, display_id}. A Resource property keeps its parent's row_id;
## an Array element appends ":n" to it. row_id must be used as an opaque key, never
## parsed back — the resource reference and display string are resolved once, here.
func _resolve_subresource_leaves() -> Dictionary[StringName, Dictionary]:
	var current: Array[Dictionary] = []
	for uid in current_registry.get_all_uids():
		if not RegistryIO.is_uid_valid(uid):
			continue
		var string_id := current_registry.get_string_id(uid)
		current.append(
			{
				&"row_id": string_id,
				&"resource": current_registry.load_entry(uid),
				&"display_id": String(string_id),
			}
		)

	for frame: SubresourceFrame in _subresource_stack:
		var next: Array[Dictionary] = []
		for item: Dictionary in current:
			var parent_res: Resource = item[&"resource"]
			if not parent_res or frame.property not in parent_res:
				continue
			var value: Variant = parent_res.get(frame.property)
			if value is Array:
				var arr: Array = value
				for i in arr.size():
					if arr[i] is not Resource:
						continue
					next.append(
						{
							&"row_id": StringName("%s:%d" % [item[&"row_id"], i]),
							&"resource": arr[i],
							&"display_id": "%s[%d]" % [item[&"display_id"], i],
						}
					)
			elif value is Resource:
				next.append(
					{
						&"row_id": item[&"row_id"],
						&"resource": value,
						&"display_id": item[&"display_id"],
					}
				)
		current = next

	var result: Dictionary[StringName, Dictionary] = { }
	for item: Dictionary in current:
		result[item[&"row_id"]] = item
	return result


## True if this column's property is a Resource, or an Array[Resource]-like typed array,
## and so can be expanded into a subresource table.
static func _column_holds_subresources(column: DataTable.ColumnConfig) -> bool:
	if column.type == TYPE_OBJECT and column.property_hint == PROPERTY_HINT_RESOURCE_TYPE:
		return not column.hint_string.is_empty()
	if column.type == TYPE_ARRAY and column.property_hint == PROPERTY_HINT_TYPE_STRING:
		var element_class := column.hint_string.get_slice(":", 1) if ":" in column.hint_string else ""
		return not element_class.is_empty() and ClassUtils.is_class_of(element_class, "Resource")
	return false


## Cache keys for property columns are namespaced by the current subresource path
## ("weapon:attachments:damage") so a subresource property never collides with a root
## property of the same name. UID and String ID stay unprefixed and shared across views.
func _cache_key(column_id: StringName) -> StringName:
	var parts: PackedStringArray = []
	for frame: SubresourceFrame in _subresource_stack:
		parts.append(frame.property)
	var path := ":".join(parts)
	return StringName("%s:%s" % [path, column_id]) if path else column_id


## Storage key used in disabled_columns/frozen_columns. UID and String ID stay shared
## and unprefixed across views; other columns are namespaced via _cache_key().
func resolve_column_storage_key(column_id: StringName) -> StringName:
	if column_id in [UID_COLUMN, STRINGID_COLUMN]:
		return column_id
	return _cache_key(column_id)


func is_column_frozen(column_id: StringName) -> bool:
	return resolve_column_storage_key(column_id) in current_cache_data.frozen_columns


## Rebuilds the breadcrumb as one clickable crumb per level (root registry included),
## the current (deepest) level shown as plain text with its row count.
func _update_subresource_breadcrumb() -> void:
	for child: Node in subresource_bar_breadcrumb.get_children():
		child.queue_free()

	var root_label := current_registry.resource_path.get_file() if current_registry else ""
	_add_breadcrumb_crumb(root_label, 0, _subresource_stack.is_empty())

	for i in _subresource_stack.size():
		var frame: SubresourceFrame = _subresource_stack[i]
		var is_current := i == _subresource_stack.size() - 1
		var label := String(frame.property).capitalize()
		if is_current:
			label += " (%d)" % _subresource_rows.size()
		_add_breadcrumb_crumb(label, i + 1, is_current)


func _add_breadcrumb_crumb(label: String, depth: int, is_current: bool) -> void:
	if depth > 0:
		var separator := Label.new()
		separator.text = "›"
		separator.modulate.a = 0.5
		subresource_bar_breadcrumb.add_child(separator)

	if is_current:
		var current_label := Label.new()
		var accent_color := get_theme_color(&"accent_color", &"Editor")
		current_label.text = label
		current_label.add_theme_color_override(&"font_color", accent_color)
		subresource_bar_breadcrumb.add_child(current_label)
	else:
		var crumb := Button.new()
		crumb.text = label
		crumb.theme_type_variation = &"FlatButton"
		crumb.pressed.connect(_on_breadcrumb_crumb_pressed.bind(depth))
		subresource_bar_breadcrumb.add_child(crumb)


func _edit_entry_property(
	uid: StringName,
	property: StringName,
	old_value: Variant,
	new_value: Variant,
) -> void:
	if not RegistryIO.is_uid_valid(uid):
		return

	var res := load(uid)
	var string_id := current_registry.get_string_id(uid)
	_apply_property_edit(res, property, old_value, new_value, "%s—>%s" % [string_id, property])


func _edit_subresource_property(
	row_id: StringName,
	column: StringName,
	old_value: Variant,
	new_value: Variant,
) -> void:
	var row_data: Dictionary = _subresource_rows.get(row_id, { })
	if row_data.is_empty():
		return
	var res: Resource = row_data.get(&"resource")
	if not res:
		return
	var display_id: String = row_data.get(&"display_id", "")
	_apply_property_edit(res, column, old_value, new_value, "%s—>%s" % [display_id, column])


func _apply_property_edit(
	res: Resource,
	property: StringName,
	old_value: Variant,
	new_value: Variant,
	label: String,
) -> void:
	if not property in res:
		YardLogger.error("Property %s not in resource" % property)
		return

	var prop_types := ClassUtils.get_property_declared_types(res, property)
	if new_value == null:
		if res.get_script():
			new_value = res.get_script().get_property_default_value(property)
		else:
			new_value = ClassDB.class_get_property_default_value(
				ClassUtils.get_type_name(res),
				property,
			)

	var valid := false
	for prop_type: String in prop_types:
		if (
			(
				ClassUtils.is_type_builtin(typeof(new_value))
				and type_string(typeof(new_value)) == prop_type
			)
			or (
				typeof(new_value) in [TYPE_INT, TYPE_FLOAT]
				and prop_type in [type_string(TYPE_INT), type_string(TYPE_FLOAT)]
			)
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
			"Invalid type. Couldn't set %s (%s) to %s (%s)"
			% [property, ", ".join(prop_types), new_value, ClassUtils.get_type_name(new_value)],
		)
		return

	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Set %s" % label)
	undo_redo.add_do_property(res, property, new_value)
	undo_redo.add_undo_property(res, property, old_value)
	undo_redo.add_undo_method(self, &"update_view")
	undo_redo.commit_action()


func _ask_confirm_delete_entries() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if data_table.selected_rows.size() > 1:
		delete_entries_confirmation_dialog.dialog_text = dialogtext % [
			"these " + str(data_table.selected_rows.size()) + " entries"
		]
	else:
		delete_entries_confirmation_dialog.dialog_text = dialogtext % "this entry"
	delete_entries_confirmation_dialog.show()


func _add_entry_from_picker(res: Resource, string_id: String, target_dir: String) -> void:
	var res_is_file := res.resource_path and ResourceLoader.exists(res.resource_path)
	string_id = string_id.strip_edges()
	if not res_is_file:
		var chosen_dir := (
			target_dir
			if target_dir
			else current_registry.resource_path.get_base_dir()
		)
		var save_path := chosen_dir.path_join(string_id + ".tres")
		if ResourceLoader.exists(save_path):
			YardLogger.error(
				"A file already exists at '%s'. Choose a different String ID or save the resource manually first."
				% save_path
			)
			return
		var save_status := ResourceSaver.save(res, save_path, ResourceSaver.FLAG_CHANGE_PATH)
		if save_status != OK:
			YardLogger.error("Failed to save resource to '%s'." % save_path)
			return
		EditorInterface.get_editor_toaster().push_toast("Resource saved to %s" % save_path)
		res = load(save_path) # Required because of race condition shinenigans I guess

	var uid := Compat.path_to_uid(res.resource_path)

	var adding_status := RegistryIO.add_entry(current_registry, uid, string_id)
	match adding_status:
		OK:
			if res_is_file:
				footer.clear_resource_picker()
			footer.clear_string_id_line_edit()
			update_view()
			registry_changed.emit()
		ERR_ALREADY_EXISTS:
			YardLogger.error("An entry with the same UID already exists in the registry.")
		ERR_CANT_ACQUIRE_RESOURCE:
			YardLogger.error(
				"This resource is not saved as a file. Click [b]v[/b] then [b]Save[/b] on the resource picker to save it first."
			)
		ERR_INVALID_PARAMETER:
			YardLogger.error("The String ID is invalid. It must not start with 'uid://'.")
		ERR_DATABASE_CANT_WRITE:
			YardLogger.error("This resource doesn't match the registry class restriction.")
		_:
			YardLogger.error("Failed to add entry to the registry.")


func _toggle_edit_context_menu_items() -> void:
	toggle_edit_menu_items(edit_context_menu)
	_update_subresource_menu_item()


func _update_subresource_menu_item() -> void:
	var col := data_table.focused_col
	var focused_column := data_table.get_column(col) if col != &"" else null
	var can_open := focused_column != null and _column_holds_subresources(focused_column)
	var item_idx := edit_context_menu.get_item_index(EditMenuAction.OPEN_SUBRESOURCES)
	var already_present := item_idx != -1

	if can_open == already_present:
		return

	if can_open:
		edit_context_menu.add_separator()
		edit_context_menu.add_item(tr("Open Sub-resources"), EditMenuAction.OPEN_SUBRESOURCES)
		edit_context_menu.set_item_icon(
			edit_context_menu.item_count - 1,
			get_theme_icon(&"Object", &"EditorIcons"),
		)
	else:
		edit_context_menu.remove_item(item_idx)
		edit_context_menu.remove_item(item_idx - 1) # the separator added alongside it


func _delete_selected_entries() -> void:
	for string_id: StringName in data_table.selected_rows:
		var uid := current_registry.get_uid(string_id)
		if RegistryIO.erase_entry(current_registry, uid) != OK:
			YardLogger.error(
				"Failed to remove %s from %s." % [uid, current_registry.resource_path.get_file()],
			)

	data_table.set_selected_cell(&"", &"")
	update_view()
	registry_changed.emit()


func _duplicate_selected_entries() -> void:
	for string_id: StringName in data_table.selected_rows:
		var uid := current_registry.get_uid(string_id)
		if RegistryIO.duplicate_entry(current_registry, uid) != OK:
			YardLogger.error(
				"Failed to duplicate %s in %s." % [uid, current_registry.resource_path.get_file()],
			)
	update_view()
	registry_changed.emit()


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
	if not current_registry or is_in_subresource_view():
		drag_and_drop_info_panel.visible = false
		return
	var drag_data: Variant = get_viewport().gui_get_drag_data()
	var can_drop := drag_data != null and _can_drop_data(Vector2.ZERO, drag_data)
	drag_and_drop_info_panel.visible = can_drop or current_registry.is_empty()
	focus_panel.visible = can_drop


func _on_drag_end() -> void:
	drag_and_drop_info_panel.hide()
	focus_panel.hide()


func _on_cell_selected(row_id: StringName, col: StringName) -> void:
	if row_id == &"" or col == &"":
		return

	var cell_value: Variant = data_table.get_cell_value(row_id, col)
	if cell_value is Resource:
		_subresource_to_inspect = cell_value
		_uid_resource_to_inspect = ""
		return

	_subresource_to_inspect = null
	if is_in_subresource_view():
		var row_data: Dictionary = _subresource_rows.get(row_id, { })
		var res: Resource = row_data.get(&"resource")
		if res and not res.resource_path.is_empty():
			_uid_resource_to_inspect = Compat.path_to_uid(res.resource_path)
		elif res:
			_subresource_to_inspect = res
	else:
		var uid: StringName = current_registry.get_uid(row_id)
		if RegistryIO.is_uid_valid(uid):
			_uid_resource_to_inspect = uid


func _on_cell_right_selected(string_id: StringName, _col: StringName, _mouse_pos: Vector2) -> void:
	if string_id != &"":
		edit_context_menu.popup(Rect2(DisplayServer.mouse_get_position(), Vector2.ZERO))


func _on_multiple_rows_selected(_ids: Array[StringName]) -> void:
	pass


func _on_cell_edited(
	row_id: StringName,
	column: StringName,
	old_value: Variant,
	new_value: Variant,
) -> void:
	if is_in_subresource_view():
		if column == STRINGID_COLUMN:
			YardLogger.warn(
				"String ID is read-only in sub-resource view. Go back to the main view to rename entries."
			)
		else:
			_edit_subresource_property(row_id, column, old_value, new_value)
		update_view()
		return

	if column not in [UID_COLUMN, STRINGID_COLUMN]:
		var uid := current_registry.get_uid(row_id)
		var property := column
		if RegistryIO.is_uid_valid(uid):
			_edit_entry_property(uid, property, old_value, new_value)
	elif column == STRINGID_COLUMN and new_value:
		RegistryIO.rename_entry(current_registry, row_id, new_value)
	elif column == UID_COLUMN and new_value:
		var uid := current_registry.get_uid(row_id)
		RegistryIO.change_entry_uid(current_registry, uid, new_value)
	update_view()


func _on_column_resized(column: StringName, new_width: float) -> void:
	match column:
		UID_COLUMN:
			current_cache_data.uid_column_width = new_width
		STRINGID_COLUMN:
			current_cache_data.string_id_column_width = new_width
		_:
			current_cache_data.property_columns_widths[_cache_key(column)] = new_width

	current_cache_data.save()


func _on_inspector_property_edited(_property: StringName) -> void:
	var object := EditorInterface.get_inspector().get_edited_object()
	if object is not Resource or not current_registry:
		return

	var res: Resource = object
	if is_in_subresource_view():
		for row_data: Dictionary in _subresource_rows.values():
			if row_data.get(&"resource").resource_path == res.resource_path:
				update_view()
				return
		return
	else:
		var uid := Compat.path_to_uid(res.resource_path)
		if uid.begins_with("uid://") and current_registry.has_uid(uid):
			update_view()


func _on_edit_context_menu_id_pressed(id: int) -> void:
	do_edit_menu_action(id)


func _on_delete_entries_confirmation_dialog_confirmed() -> void:
	_delete_selected_entries()


func _on_edit_context_menu_about_to_popup() -> void:
	_toggle_edit_context_menu_items()


func _on_breadcrumb_crumb_pressed(depth: int) -> void:
	_subresource_stack.resize(depth)
	_reset_table_navigation()
	update_view()


func _on_footer_add_entry_requested(res: Resource, string_id: String, target_dir: String) -> void:
	_add_entry_from_picker(res, string_id, target_dir)


## One level of subresource table navigation: the property that was expanded,
## and the column set resolved for the resources currently shown at that level.
class SubresourceFrame:
	var property: StringName
	var columns_info: Array[Dictionary] = []
