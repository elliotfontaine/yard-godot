# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/popup_menu_cell_type.gd"
## Enum columns (any type with PROPERTY_HINT_ENUM), edited via a PopupMenu.
## Draw color is a deterministic pseudo-random hash of the display string,
## ignoring the column's normal font-color resolution.


static func matches(column: ColumnConfig) -> bool:
	return column.property_hint == PROPERTY_HINT_ENUM


static func draw_cell(
	canvas: CanvasItem,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	style: CellStyle,
) -> void:
	var value_str: String
	if not _is_numeric(column):
		value_str = str(value)
	else:
		var int_value := value as int
		var map: Dictionary = column.get_cached(
			&"enum_values_map",
			parse_enum_hint_string.bind(column.hint_string),
		)
		value_str = "%s:%s" % [map[int_value], int_value] if map.has(int_value) else "?:%d" % int_value

	draw_text(
		canvas,
		rect,
		value_str,
		resolve_font(column, style.font),
		style.font_size,
		HORIZONTAL_ALIGNMENT_CENTER,
		_hashed_color(value_str),
	)


static func get_sort_key(value: Variant, column: ColumnConfig) -> Variant:
	if _is_numeric(column):
		return float(value)
	return str(value)


static func create_editor(
	owner: Control,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
) -> Node:
	var popup_menu := PopupMenu.new()
	var is_numeric := _is_numeric(column)

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

		popup_menu.add_radio_check_item(text)
		popup_menu.set_item_metadata(popup_menu.item_count - 1, value_iter)
		if value == value_iter:
			popup_menu.set_item_checked(popup_menu.item_count - 1, true)

	return popup_single_choice(popup_menu, owner, rect, on_finished)


static func _is_numeric(column: ColumnConfig) -> bool:
	return column.type in [TYPE_INT, TYPE_FLOAT]
