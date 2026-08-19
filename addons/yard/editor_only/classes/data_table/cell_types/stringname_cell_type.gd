# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/text_cell_type.gd"
## As for the String cell type, drawing and value parsing (raw text, as-is) come from
## CellType / TextCellType respectively. Additionnaly, it shows the ampersand (&) before the value.

const AMPERSAND_CHAR := "&"


static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_STRING_NAME


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var text := value as String
	var font := resolve_font(column, style.font)
	var ampersand_width := font.get_string_size(AMPERSAND_CHAR, HORIZONTAL_ALIGNMENT_LEFT, -1, style.font_size).x
	var ampersand_color: Color = canvas.get_theme_color(&"readonly_color", &"EditorProperty")
	var x_margin: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var text_rect := rect.grow_side(SIDE_LEFT, -(ampersand_width + x_margin / 2.0))
	draw_text(canvas, rect, AMPERSAND_CHAR, font, style.font_size, column.h_alignment, ampersand_color)
	draw_text(canvas, text_rect, text, font, style.font_size, column.h_alignment, resolve_text_color(column, style))
