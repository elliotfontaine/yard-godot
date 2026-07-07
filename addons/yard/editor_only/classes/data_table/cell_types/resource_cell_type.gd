extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Resource columns: a thumbnail + filename, edited via Godot's own
## EditorResourcePicker. Clicking away does not commit; the picker manages
## its own commit/cancel through its popup.

const ClassUtils := preload("res://addons/yard/editor_only/classes/class_utils.gd")


static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_OBJECT and column.property_hint == PROPERTY_HINT_RESOURCE_TYPE


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	if value is not Resource:
		draw_text(canvas, rect, "<empty>", resolve_font(column, style.font), style.font_size, column.h_alignment, resolve_text_color(column, style))
		return

	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var res: Resource = value
	var label := "<" + res.resource_path.get_file() + ">"
	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var thumb_width := 0.0
	var texture: Texture2D = res if res is Texture2D else style.get_thumbnail.call(res.resource_path, ClassUtils.get_type_name(res))
	if texture != null:
		var thumb_rect := fit_texture_rect(texture, inner, true)
		thumb_rect.position.x += x_margin_val
		thumb_width = thumb_rect.size.x
		draw_filtered_texture_rect(canvas, style.pixelated_canvas_rid, texture, thumb_rect, style.frozen_width)

	var text_rect := inner.grow_individual(-thumb_width - x_margin_val, 0, 0, 0)
	draw_text(canvas, text_rect, label, resolve_font(column, style.font), style.font_size, column.h_alignment, resolve_text_color(column, style))


static func has_editor() -> bool:
	return true


static func commits_on_click_away() -> bool:
	return false


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	if value is Resource:
		var r: Resource = value
		if r.resource_path != "":
			return r.resource_path.get_file()
		return str(r.get_class()) + ":" + str(r.get_instance_id())
	return str(value)


static func create_editor(owner: Control, _rect: Rect2, _value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var editor := EditorResourcePicker.new()
	owner.add_child(editor)
	editor.edited_resource = null
	editor.base_type = "Resource"
	if not column.hint_string.is_empty():
		var valid_types := Array(column.hint_string.split(",", false)).filter(ClassUtils.is_valid)
		if not valid_types.is_empty():
			editor.base_type = ",".join(valid_types)
	editor.resource_changed.connect(func(_res: Resource) -> void: on_finished.call(true))

	for child in editor.get_children(true):
		if child is Button and child.tooltip_text == "Quick Load":
			child.pressed.emit()
			break

	return editor


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var resource_picker: EditorResourcePicker = editor
	return resource_picker.edited_resource
