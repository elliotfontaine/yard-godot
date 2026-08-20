# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"

static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_INT and column.property_hint == PROPERTY_HINT_FLAGS


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var indices := _unpack_indices(value)
	var keys := column.hint_string.split(",", false)
	var selected_keys: Array[String] = []
	for idx in indices:
		selected_keys.append(keys[idx])

	var font := resolve_font(column, style.font)
	var x_margin: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var remaining_rect := rect
	for key in selected_keys:
		if not remaining_rect.has_area():
			break
		var key_width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, style.font_size).x
		draw_text(canvas, remaining_rect, key, font, style.font_size, HORIZONTAL_ALIGNMENT_LEFT, _hashed_color(key))
		remaining_rect = remaining_rect.grow_side(SIDE_LEFT, -(key_width + x_margin * 2))
	#var int_value := value as int
	#var map: Dictionary = column.get_cached(&"enum_values_map", parse_enum_hint_string.bind(column.hint_string))
	#value_str = "%s:%s" % [map[int_value], int_value] if map.has(int_value) else "?:%d" % int_value


static func has_editor() -> bool:
	return true


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return str(value) # Sort on bitflags integer value.


static func get_filter_key(value: Variant, column: ColumnConfig) -> Variant:
	var indices := _unpack_indices(value)
	var keys := column.hint_string.split(",", false)
	var selected_keys: Array[String] = []
	for idx in indices:
		selected_keys.append(keys[idx])
	return " ".join(selected_keys)


static func create_editor(owner: Control, _rect: Rect2, value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var popup_menu := PopupMenu.new()
	popup_menu.hide_on_checkable_item_selection = false
	owner.add_child(popup_menu)

	var iter := 0
	var bit_value: Variant = 0

	for choice: String in column.hint_string.split(",", false):
		var colon := choice.rfind(":")
		var text: String
		if colon != -1:
			text = choice.substr(0, colon)
			bit_value = choice.substr(colon + 1).to_int()
		else:
			text = choice
			bit_value = 1 << iter

		popup_menu.add_check_item(text)
		popup_menu.set_item_metadata(iter, bit_value)
		if value & bit_value:
			popup_menu.set_item_checked(iter, true)
		iter += 1

	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
			popup_menu.toggle_item_checked(idx)
	)
	popup_menu.popup_hide.connect(
		func() -> void:
			await popup_menu.get_tree().create_timer(0.05).timeout
			on_finished.call(true)
	)

	popup_menu.position = DisplayServer.mouse_get_position()
	popup_menu.popup()
	return popup_menu


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var popup_menu: PopupMenu = editor
	var bitflags := 0
	for idx in popup_menu.item_count:
		if popup_menu.is_item_checked(idx):
			bitflags += popup_menu.get_item_metadata(idx)
	return bitflags


static func _unpack_flags(bitflags: int) -> Array[int]:
	var result: Array[int] = []
	var bit := 1
	while bit <= bitflags:
		if bitflags & bit:
			result.append(bit)
		bit <<= 1
	return result


static func _unpack_indices(bitflags: int) -> Array[int]:
	var result: Array[int] = []
	var idx := 0
	while (1 << idx) <= bitflags:
		if bitflags & (1 << idx):
			result.append(idx)
		idx += 1
	return result


# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: Copyright 2022 Gennady Krupenyov (Don Tnowe) <https://github.com/don-tnowe/godot-resources-as-sheets-plugin>
#
# SPDX-License-Identifier: MIT
static func _hashed_color(text: String) -> Color:
	return Color(text.hash()) + Color(0.25, 0.25, 0.25, 1.0)
# SPDX-SnippetEnd
