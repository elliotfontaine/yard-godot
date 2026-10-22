# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Resource columns: a thumbnail + label (see get_label()), edited via Godot's
## own EditorResourcePicker. Clicking away does not commit; the picker manages
## its own commit/cancel through its popup.

const ClassUtils := Namespace.ClassUtils
const YardSettings := Namespace.YardSettings


static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_OBJECT and column.property_hint == PROPERTY_HINT_RESOURCE_TYPE


static func draw_cell(
	canvas: CanvasItem,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	style: CellStyle,
) -> void:
	if value is not Resource:
		draw_text(
			canvas,
			rect,
			"<empty>",
			resolve_font(column, style.font),
			style.font_size,
			column.h_alignment,
			resolve_text_color(column, style),
		)
		return

	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var res: Resource = value
	var label := get_label(res)
	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var thumb_width := 0.0
	var texture: Texture2D = (
		res
		if res is Texture2D
		else style.get_thumbnail.call(res.resource_path, ClassUtils.get_type_name(res))
	)
	if texture != null:
		var thumb_rect := fit_texture_rect(texture, inner, true)
		thumb_rect.position.x += x_margin_val
		thumb_width = thumb_rect.size.x
		draw_filtered_texture_rect(
			canvas,
			style.pixelated_canvas_rid,
			texture,
			thumb_rect,
			style.frozen_width,
			resolve_texture_modulate(column, style),
		)

	var text_rect := inner.grow_individual(-thumb_width - x_margin_val, 0, 0, 0)
	draw_text(
		canvas,
		text_rect,
		label,
		resolve_font(column, style.font),
		style.font_size,
		column.h_alignment,
		resolve_text_color(column, style),
	)


static func has_editor() -> bool:
	return true


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	if value is Resource:
		return get_label(value)
	return str(value)


static func get_filter_key(value: Variant, _column: ColumnConfig) -> Variant:
	if value is Resource:
		return get_label(value)
	return "<empty>"


## The name shown for a resource in table cells, shared with collection cells.
## First non-empty of: resource_name, _to_string() (order swappable through the
## RESOURCE_LABEL_PRIORITY project setting), file name, then class name.
static func get_label(res: Resource) -> String:
	var to_string_label := _get_to_string_label(res)
	var priority: int = YardSettings.get_setting(YardSettings.RESOURCE_LABEL_PRIORITY)
	if priority == YardSettings.ResourceLabelPriority.TO_STRING_FIRST and to_string_label:
		return to_string_label
	if res.resource_name:
		return res.resource_name
	if to_string_label:
		return to_string_label
	if not res.is_built_in():
		return res.resource_path.get_file()
	return ClassUtils.get_type_name(res)


static func get_inline_summary(res: Resource) -> String:
	return "<%s> (%s)" % [get_label(res), ", ".join(get_summary_lines(res))]


static func get_summary_lines(res: Resource) -> Array[String]:
	var lines: Array[String]
	if not res.is_built_in():
		lines.append("%s" % res.resource_path)
	lines.append("Type: %s" % ClassUtils.get_type_name(res))
	if res is Texture2D:
		lines.append("Dimensions: %s × %s" % [res.get_width(), res.get_height()])
	return lines


## Empty unless the script overrides _to_string() and is a @tool: in the editor,
## other scripts only get a placeholder instance, which never runs it. Newlines
## are flattened since cells draw a single line.
static func _get_to_string_label(res: Resource) -> String:
	var script: Script = res.get_script()
	if not script or not script.is_tool() or not res.has_method(&"_to_string"):
		return ""
	return res.to_string().replace("\n", " ").strip_edges()


static func create_editor(
	owner: Control,
	_rect: Rect2,
	_value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
) -> Node:
	var editor := EditorResourcePicker.new()
	owner.add_child(editor)
	editor.edited_resource = null
	editor.base_type = "Resource"
	if not column.hint_string.is_empty():
		var valid_types := Array(column.hint_string.split(",", false)).filter(ClassUtils.is_valid)
		if not valid_types.is_empty():
			editor.base_type = ",".join(valid_types)
	editor.resource_changed.connect(
		func(_res: Resource) -> void:
			on_finished.call(true),
	)

	for child in editor.get_children(true):
		if child is Button and child.tooltip_text == "Quick Load":
			child.pressed.emit()
			break

	return editor


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var resource_picker: EditorResourcePicker = editor
	return resource_picker.edited_resource


static func get_tooltip(value: Variant, column: ColumnConfig) -> String:
	if not value:
		return super(value, column)

	var res := value as Resource
	var lines := get_summary_lines(res)
	lines.append("Properties:")
	for prop: Dictionary in res.get_property_list():
		if _can_display_property(prop):
			lines.append('    "%s": %s' % [prop.name, var_to_str(res.get(prop.name))])
	return "\n".join(lines)


static func _can_display_property(property_info: Dictionary) -> bool:
	return (
		property_info[&"type"] not in [TYPE_CALLABLE, TYPE_SIGNAL]
		and property_info[&"usage"] & PROPERTY_USAGE_EDITOR != 0
	)
