# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Vector2/3/4 and Vector2i/3i/4i columns. Components are drawn and edited side
## by side, one LineEdit each.

const COMPONENT_COUNTS: Dictionary[Variant.Type, int] = {
	TYPE_VECTOR2: 2,
	TYPE_VECTOR2I: 2,
	TYPE_VECTOR3: 3,
	TYPE_VECTOR3I: 3,
	TYPE_VECTOR4: 4,
	TYPE_VECTOR4I: 4,
}
const INT_TYPES: Array[Variant.Type] = [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]
const AXES: Array[String] = ["x", "y", "z", "w"]


static func matches(column: ColumnConfig) -> bool:
	return COMPONENT_COUNTS.has(column.type)


static func draw_cell(
	canvas: CanvasItem,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	style: CellStyle,
) -> void:
	if value == null:
		return
	var count := _get_count(column)
	var font := resolve_font(column, style.font)
	for i: int in count:
		var slot := _get_slot_rect(rect, i, count)
		var axis: String = AXES[i]
		draw_text(
			canvas,
			slot,
			axis,
			font,
			style.font_size,
			HORIZONTAL_ALIGNMENT_LEFT,
			resolve_text_color(column, style, _get_axis_color(canvas, axis)),
		)
		draw_text(
			canvas,
			slot.grow_side(SIDE_LEFT, -_get_axis_label_width(axis, font, style.font_size)),
			str(value[i]),
			font,
			style.font_size,
			HORIZONTAL_ALIGNMENT_LEFT,
			resolve_text_color(column, style),
		)


static func get_sort_key(value: Variant, column: ColumnConfig) -> Variant:
	var components: Array = []
	for i: int in _get_count(column):
		components.append(value[i])
	return components


static func has_editor() -> bool:
	return true


static func create_editor(
	owner: Control,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
) -> Node:
	var vector: Variant = type_convert(value, column.type)
	var editor := HBoxContainer.new()
	editor.set_meta(&"vector", vector)
	editor.add_theme_constant_override(&"separation", 0)
	owner.add_child(editor)
	editor.position = rect.position
	editor.size = rect.size

	# Moving between the component fields keeps the editor open. Leaving all of them commits.
	# Runs deferred, possibly after the editor is freed, so it looks the editor up by ID:
	# a lambda capturing the freed node itself would log an error.
	var editor_id := editor.get_instance_id()
	var finish_if_focus_left := func() -> void:
		var live_editor := instance_from_id(editor_id) as Control
		if not live_editor or not live_editor.is_inside_tree():
			return
		var focus_owner := live_editor.get_viewport().gui_get_focus_owner()
		if not focus_owner or not live_editor.is_ancestor_of(focus_owner):
			on_finished.call(true)

	var count := _get_count(column)
	for i: int in count:
		var line_edit := LineEdit.new()
		editor.add_child(line_edit) # In the tree first, so the theme lookups below see the editor theme.
		_add_axis_label(line_edit, AXES[i])
		line_edit.text = str(vector[i])
		line_edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.add_theme_constant_override(&"minimum_character_width", 2)
		line_edit.text_submitted.connect(
			func(_text: String) -> void:
				on_finished.call(true),
		)
		line_edit.gui_input.connect(
			func(event: InputEvent) -> void:
				if event.is_action_pressed(&"ui_cancel"):
					on_finished.call(true),
		)
		line_edit.select_all_on_focus = true
		line_edit.focus_exited.connect(finish_if_focus_left, CONNECT_DEFERRED)

	var focused_field: LineEdit = editor.get_child(_get_clicked_index(owner, rect, count))
	focused_field.grab_focus()
	focused_field.select_all()
	return editor


## Components whose text doesn't parse keep their previous value.
static func read_editor_value(editor: Node, column: ColumnConfig) -> Variant:
	var vector: Variant = editor.get_meta(&"vector")
	var is_int := column.type in INT_TYPES
	for i: int in editor.get_child_count():
		var text := (editor.get_child(i) as LineEdit).text.strip_edges()
		if is_int and text.is_valid_int():
			vector[i] = text.to_int()
		elif not is_int and text.is_valid_float():
			vector[i] = text.to_float()
	return vector


static func _get_count(column: ColumnConfig) -> int:
	return COMPONENT_COUNTS[column.type]


## The inspector's vector editors draw their axis labels in this color, at half opacity.
static func _get_axis_color(canvas: CanvasItem, axis: String) -> Color:
	var axis_color: Color = canvas.get_theme_color(StringName("property_color_" + axis), &"Editor")
	return axis_color * Color(1, 1, 1, 0.5)


## Horizontal space the axis label takes at the start of its slot, left margin included.
static func _get_axis_label_width(axis: String, font: Font, font_size: int) -> float:
	var x_margin: int = H_ALIGNMENT_MARGINS[HORIZONTAL_ALIGNMENT_LEFT]
	return x_margin + font.get_string_size(axis, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Draws the axis label inside the field, where draw_cell puts it, and starts the
## text right after it, so editing doesn't move the label or the value.
static func _add_axis_label(line_edit: LineEdit, axis: String) -> void:
	var font := line_edit.get_theme_font(&"font")
	var font_size := line_edit.get_theme_font_size(&"font_size")
	var axis_color := _get_axis_color(line_edit, axis)
	var x_margin: int = H_ALIGNMENT_MARGINS[HORIZONTAL_ALIGNMENT_LEFT]
	var style := line_edit.get_theme_stylebox(&"normal").duplicate() as StyleBox
	style.content_margin_left = _get_axis_label_width(axis, font, font_size) + x_margin
	line_edit.add_theme_stylebox_override(&"normal", style)
	line_edit.draw.connect(
		func() -> void:
			draw_text(
				line_edit,
				Rect2(Vector2.ZERO, line_edit.size),
				axis,
				font,
				font_size,
				HORIZONTAL_ALIGNMENT_LEFT,
				axis_color,
			),
	)


## The component under the mouse when a double-click started the edit (DataTable
## starts it on the press), else the first one, as when Enter started it.
static func _get_clicked_index(owner: Control, rect: Rect2, count: int) -> int:
	var mouse := owner.get_local_mouse_position()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not rect.has_point(mouse):
		return 0
	return clampi(floori((mouse.x - rect.position.x) / (rect.size.x / count)), 0, count - 1)


static func _get_slot_rect(rect: Rect2, index: int, count: int) -> Rect2:
	var slot_width := rect.size.x / count
	return Rect2(rect.position.x + slot_width * index, rect.position.y, slot_width, rect.size.y)
