# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"

const RIGHTWARDS_ARROW := "↪"


static func matches(column: ColumnConfig) -> bool:
	return (
		column.type in [TYPE_STRING, TYPE_STRING_NAME]
		and column.property_hint == Registry.PROPERTY_HINT_CUSTOM
	)


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var text := value as String
	if not text:
		return
	var font := resolve_font(column, style.font)
	var ampersand_width := font.get_string_size(RIGHTWARDS_ARROW, HORIZONTAL_ALIGNMENT_LEFT, -1, style.font_size).x
	var ampersand_color: Color = canvas.get_theme_color(&"readonly_color", &"EditorProperty")
	var x_margin: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var text_rect := rect.grow_side(SIDE_LEFT, -(ampersand_width + x_margin))
	draw_text(canvas, rect, RIGHTWARDS_ARROW, font, style.font_size, column.h_alignment, ampersand_color)
	draw_text(canvas, text_rect, text, font, style.font_size, column.h_alignment, _hashed_color(text))


static func has_editor() -> bool:
	return true


static func create_editor(owner: Control, _rect: Rect2, value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var popup_menu := PopupMenu.new()
	var checked_idx := -1
	owner.add_child(popup_menu)

	for entry: StringName in _get_registry_entries(column.hint_string):
		var str_entry := str(entry)
		popup_menu.add_radio_check_item(str_entry)
		popup_menu.set_item_metadata(popup_menu.item_count - 1, str_entry)
		if value == entry:
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


static func get_tooltip(value: Variant, column: ColumnConfig) -> String:
	var registry := _get_registry(column.hint_string)
	if not registry:
		return super(value, column)

	var lines: Array[String]
	var path := registry.resource_path
	if path.is_absolute_path():
		lines.append("Registry: %s" % path.get_file())
	lines.append(super(value, column))
	return "\n".join(lines)


static func _get_registry(hint_string: String) -> Registry:
	var parts: PackedStringArray = hint_string.split(",")
	var registry_path: String = parts[0]

	if not (registry_path.begins_with("res://") or registry_path.begins_with("uid://")):
		return null

	var registry: Registry = load(registry_path)
	if not registry is Registry:
		return null

	return registry


static func _get_registry_entries(hint_string: String) -> Array[StringName]:
	var registry := _get_registry(hint_string)
	return registry.get_all_string_ids() if registry else []


# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: Copyright 2022 Gennady Krupenyov (Don Tnowe) <https://github.com/don-tnowe/godot-resources-as-sheets-plugin>
#
# SPDX-License-Identifier: MIT
static func _hashed_color(text: String) -> Color:
	return Color(text.hash()) + Color(0.25, 0.25, 0.25, 1.0)
# SPDX-SnippetEnd
