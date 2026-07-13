# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/text_cell_type.gd"
## Plain string columns. Drawing and value parsing (raw text, as-is) come from
## CellType / TextCellType respectively; this class only adds classification.

static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_STRING
