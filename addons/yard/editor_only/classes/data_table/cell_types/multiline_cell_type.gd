# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"

static func has_editor() -> bool:
	return true


static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_STRING and column.property_hint == PROPERTY_HINT_MULTILINE_TEXT


static func create_editor(owner: Control, rect: Rect2, value: Variant, _column: ColumnConfig, on_finished: Callable) -> Node:
	var editor := TextEdit.new()
	owner.add_child(editor)
	editor.position = rect.position
	editor.size = Vector2(rect.size.x, 4.5 * rect.size.y)
	editor.text = str(value) if value != null else ""
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text_set.connect(on_finished.bind(true))
	editor.focus_exited.connect(func() -> void: on_finished.call(true))
	editor.grab_focus()
	editor.select_all()
	return editor


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var text_edit: TextEdit = editor
	return text_edit.text
