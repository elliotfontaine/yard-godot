# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/popup_menu_cell_type.gd"

const RegistryIO := Namespace.RegistryIO

const RIGHTWARDS_ARROW := "↪"


static func matches(column: ColumnConfig) -> bool:
	return (
		column.type in [TYPE_STRING, TYPE_STRING_NAME]
		and column.property_hint == Registry.PROPERTY_HINT_CUSTOM
	)


static func draw_cell(
	canvas: CanvasItem,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	style: CellStyle,
) -> void:
	var text := value as String
	if not text:
		return
	var font := resolve_font(column, style.font)
	var ampersand_width := font \
			.get_string_size(RIGHTWARDS_ARROW, HORIZONTAL_ALIGNMENT_LEFT, -1, style.font_size) \
			.x
	var ampersand_color: Color = canvas.get_theme_color(&"readonly_color", &"EditorProperty")
	var x_margin: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var text_rect := rect.grow_side(SIDE_LEFT, -(ampersand_width + x_margin))
	draw_text(
		canvas,
		rect,
		RIGHTWARDS_ARROW,
		font,
		style.font_size,
		column.h_alignment,
		ampersand_color,
	)
	draw_text(
		canvas,
		text_rect,
		text,
		font,
		style.font_size,
		column.h_alignment,
		resolve_text_color(column, style, _hashed_color(text)),
	)


static func create_editor(
	owner: Control,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
) -> Node:
	var custom_hint := RegistryIO.CustomHint.parse(column.hint_string)
	var choices := _get_choices(custom_hint)
	var allow_custom := custom_hint.suggestion
	return popup_single_choice(owner, rect, value, column, on_finished, choices, allow_custom)


static func get_tooltip(value: Variant, column: ColumnConfig) -> String:
	var registry := RegistryIO.CustomHint.parse(column.hint_string).load_registry()
	if not registry:
		return super(value, column)

	var lines: Array[String]
	var path := registry.resource_path
	if path.is_absolute_path():
		lines.append("Registry: %s" % path.get_file())
	lines.append(super(value, column))
	return "\n".join(lines)


## The registry's string IDs in dropdown order, each one its own label.
static func _get_choices(custom_hint: RegistryIO.CustomHint) -> Dictionary:
	var registry := custom_hint.load_registry()
	if not registry:
		return { }

	var choices := { }
	for string_id: StringName in RegistryIO.get_string_ids_sorted_by(registry, custom_hint.sort):
		choices[str(string_id)] = str(string_id)
	return choices
