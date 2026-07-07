extends "res://addons/yard/editor_only/ui_scenes/components/cell_types/cell_type.gd"
## Enum columns (any type with PROPERTY_HINT_ENUM), edited via a PopupMenu.
## Draw color is a deterministic pseudo-random hash of the display string,
## ignoring the column's normal font-color resolution. The chosen value has to
## survive from the index_pressed callback to read_editor_value (the popup may
## already be hidden by then), so it's stashed as metadata on the editor Node
## itself rather than as instance state.

const SELECTED_VALUE_META := &"selected_value"


static func matches(column: ColumnConfig) -> bool:
	return column.is_enum_column()


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var value_str: String
	if not column.is_numeric_column():
		value_str = str(value)
	else:
		var int_value := value as int
		var map := column.enum_values_map
		value_str = "%s:%s" % [map[int_value], int_value] if map.has(int_value) else "?:%d" % int_value

	var color := Color(value_str.hash()) + Color(0.25, 0.25, 0.25, 1.0)
	draw_text(canvas, rect, value_str, resolve_font(column, style.font), style.font_size, HORIZONTAL_ALIGNMENT_CENTER, color)


static func has_editor() -> bool:
	return true


static func commits_on_click_away() -> bool:
	return false


## Replicates today's absence of a dedicated sort branch for enums: numeric-backed
## enums sort by the raw int value, others fall back to string comparison.
static func get_sort_key(value: Variant, column: ColumnConfig) -> Variant:
	if column.is_numeric_column():
		return float(value)
	return str(value)


static func create_editor(owner: Control, _rect: Rect2, value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var editor := PopupMenu.new()
	owner.add_child(editor)

	var is_numeric := column.is_numeric_column()

	@warning_ignore("incompatible_ternary")
	var value_iter: Variant = -1 if is_numeric else ""

	for choice: String in column.hint_string.split(",", false):
		var colon := choice.rfind(":")
		var text: String
		if colon != -1:
			text = choice.substr(0, colon)
			value_iter = choice.substr(colon + 1).to_int()
		else:
			text = choice
			value_iter = value_iter + 1 if is_numeric else text

		editor.add_radio_check_item(text)
		editor.set_item_metadata(editor.item_count - 1, value_iter)
		if value == value_iter:
			editor.toggle_item_checked(editor.item_count - 1)

	editor.index_pressed.connect(
		func(idx: int) -> void:
			editor.set_meta(SELECTED_VALUE_META, editor.get_item_metadata(idx))
			on_finished.call(true)
	)
	editor.popup_hide.connect(
		func() -> void:
			await editor.get_tree().create_timer(0.05).timeout
			on_finished.call(false)
	)

	editor.position = DisplayServer.mouse_get_position()
	editor.popup()
	return editor


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	if not editor.has_meta(SELECTED_VALUE_META):
		return null
	return editor.get_meta(SELECTED_VALUE_META)
