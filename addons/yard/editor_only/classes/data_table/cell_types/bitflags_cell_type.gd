# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/popup_menu_cell_type.gd"


static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_INT and column.property_hint == PROPERTY_HINT_FLAGS


static func draw_cell(
	canvas: CanvasItem,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	style: CellStyle,
) -> void:
	var font := resolve_font(column, style.font)
	var x_margin: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var remaining_rect := rect
	for key in _get_selected_labels(value, column):
		if not remaining_rect.has_area():
			break
		var key_width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, style.font_size).x
		draw_text(
			canvas,
			remaining_rect,
			key,
			font,
			style.font_size,
			HORIZONTAL_ALIGNMENT_LEFT,
			resolve_text_color(column, style, _hashed_color(key)),
		)
		remaining_rect = remaining_rect.grow_side(SIDE_LEFT, -(key_width + x_margin * 2))


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return str(value) # Sort on bitflags integer value.


static func get_filter_key(value: Variant, column: ColumnConfig) -> Variant:
	return " ".join(_get_selected_labels(value, column))


static func create_editor(
	owner: Control,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
) -> Node:
	return popup_multiple_choice(owner, rect, value, on_finished, _get_flags(column))


## Ordered bit value -> label pairs, cached on the column. As in Godot's inspector, implicit
## values follow the item's position ("A,B,C:8" -> {1:"A", 2:"B", 8:"C"}).
static func _get_flags(column: ColumnConfig) -> Dictionary:
	return column.get_cached(&"flags", _parse_flags.bind(column.hint_string)) as Dictionary


static func _parse_flags(hint_string: String) -> Dictionary:
	var flags := { }
	var idx := 0
	for entry: String in hint_string.split(",", false):
		var colon := entry.rfind(":")
		if colon == -1:
			flags[1 << idx] = entry
		else:
			flags[entry.substr(colon + 1).to_int()] = entry.substr(0, colon)
		idx += 1
	return flags


static func _get_selected_labels(value: Variant, column: ColumnConfig) -> PackedStringArray:
	var flags := _get_flags(column)
	var labels := PackedStringArray()
	for bit: int in flags:
		if value & bit:
			labels.append(flags[bit])
	return labels
