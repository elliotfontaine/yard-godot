# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/popup_menu_cell_type.gd"
## Enum columns (any type with PROPERTY_HINT_ENUM / PROPERTY_HINT_ENUM_SUGGESTION), edited via a PopupMenu.
## Draw color is a deterministic pseudo-random hash of the display string,
## ignoring the column's normal font-color resolution.


static func matches(column: ColumnConfig) -> bool:
	return column.property_hint == PROPERTY_HINT_ENUM or _is_suggestion(column)


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
		var choices := _get_choices(column)
		value_str = "%s:%s" % [choices[int_value], int_value] if choices.has(int_value) else "?:%d" % int_value

	draw_text(
		canvas,
		rect,
		value_str,
		resolve_font(column, style.font),
		style.font_size,
		HORIZONTAL_ALIGNMENT_CENTER,
		resolve_text_color(column, style, _hashed_color(value_str)),
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
	var choices := _get_choices(column)
	var suggestion := _is_suggestion(column)
	return popup_single_choice(owner, rect, value, column, on_finished, choices, suggestion)


## Ordered value -> label pairs, cached on the column. Only numeric enums have values of their
## own ("A,B:4" -> {0:"A", 4:"B"}). String ones store the label itself.
static func _get_choices(column: ColumnConfig) -> Dictionary:
	return column.get_cached(&"enum_choices", _parse_choices.bind(column)) as Dictionary


static func _parse_choices(column: ColumnConfig) -> Dictionary:
	if _is_numeric(column):
		return parse_enum_hint_string(column.hint_string)
	var choices := { }
	for label: String in column.hint_string.split(",", false):
		choices[label] = label
	return choices


static func _is_numeric(column: ColumnConfig) -> bool:
	return column.type in [TYPE_INT, TYPE_FLOAT]


static func _is_suggestion(column: ColumnConfig) -> bool:
	return (
		column.property_hint == PROPERTY_HINT_ENUM_SUGGESTION
		and column.type in [TYPE_STRING, TYPE_STRING_NAME]
	)
