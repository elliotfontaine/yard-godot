extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Enum columns (any type with PROPERTY_HINT_ENUM), edited via a PopupMenu.
## Draw color is a deterministic pseudo-random hash of the display string,
## ignoring the column's normal font-color resolution.

static func matches(column: ColumnConfig) -> bool:
	return column.property_hint == PROPERTY_HINT_ENUM


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var value_str: String
	if not _is_numeric(column):
		value_str = str(value)
	else:
		var int_value := value as int
		var map: Dictionary = column.get_cached(&"enum_values_map", parse_enum_hint_string.bind(column.hint_string))
		value_str = "%s:%s" % [map[int_value], int_value] if map.has(int_value) else "?:%d" % int_value

	var color := Color(value_str.hash()) + Color(0.25, 0.25, 0.25, 1.0)
	draw_text(canvas, rect, value_str, resolve_font(column, style.font), style.font_size, HORIZONTAL_ALIGNMENT_CENTER, color)


static func has_editor() -> bool:
	return true


static func commits_on_click_away() -> bool:
	return false


static func get_sort_key(value: Variant, column: ColumnConfig) -> Variant:
	if _is_numeric(column):
		return float(value)
	return str(value)


static func create_editor(owner: Control, _rect: Rect2, value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var popup_menu := PopupMenu.new()
	owner.add_child(popup_menu)

	var is_numeric := _is_numeric(column)

	@warning_ignore("incompatible_ternary")
	var value_iter: Variant = -1 if is_numeric else ""
	var checked_idx := -1

	for choice: String in column.hint_string.split(",", false):
		var colon := choice.rfind(":")
		var text: String
		if colon != -1:
			text = choice.substr(0, colon)
			value_iter = choice.substr(colon + 1).to_int()
		else:
			text = choice
			value_iter = value_iter + 1 if is_numeric else text

		popup_menu.add_radio_check_item(text)
		popup_menu.set_item_metadata(popup_menu.item_count - 1, value_iter)
		if value == value_iter:
			checked_idx = popup_menu.item_count - 1
			popup_menu.set_item_checked(checked_idx, true)

	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
			if checked_idx != -1:
				popup_menu.set_item_checked(checked_idx, false)
			popup_menu.set_item_checked(idx, true)
			on_finished.call(true) # Not good. Why does it know callback signature?!
	)
	popup_menu.popup_hide.connect(
		func() -> void:
			await popup_menu.get_tree().create_timer(0.05).timeout
			on_finished.call(false) # Same issue
	)

	popup_menu.position = DisplayServer.mouse_get_position()
	popup_menu.popup()
	return popup_menu


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var popup_menu: PopupMenu = editor
	for idx in popup_menu.item_count:
		if popup_menu.is_item_checked(idx):
			return popup_menu.get_item_metadata(idx)
	return null


static func _is_numeric(column: ColumnConfig) -> bool:
	return column.type in [TYPE_INT, TYPE_FLOAT]
