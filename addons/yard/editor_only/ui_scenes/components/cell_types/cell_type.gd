extends RefCounted
## Base class for column-type-specific cell behavior in DynamicTable: drawing,
## the cell editor, and type-specific input (drag, direct click, Enter key).
##
## Every method is static and no subclass is ever instantiated. They're
## referenced as plain GDScript scripts (like ClassUtils, YardLogger, etc.
## elsewhere in this addon) and called directly on the script reference.
## ColumnConfig.get_cell_type() / get_editor_cell_type() resolve which script
## applies to a given column; DynamicTable never names a concrete subclass.

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ColumnConfig := Namespace.ColumnConfig
const CellStyle := Namespace.CellStyle

const H_ALIGNMENT_MARGINS = {
	HORIZONTAL_ALIGNMENT_LEFT: 5,
	HORIZONTAL_ALIGNMENT_CENTER: 0,
	HORIZONTAL_ALIGNMENT_RIGHT: -5,
}


static func matches(_column: ColumnConfig) -> bool:
	return true


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var text := str(value) if value != null else ""
	draw_text(canvas, rect, text, resolve_font(column, style.font), style.font_size, column.h_alignment, resolve_text_color(column, style))


static func draw_text(canvas: CanvasItem, rect: Rect2, text: String, font: Font, font_size: int, h_align: HorizontalAlignment, color: Color) -> void:
	var x_margin: int = H_ALIGNMENT_MARGINS.get(h_align)
	var baseline_y := get_text_baseline_y(font, font_size, rect.position.y, rect.size.y)
	var display_text := get_display_text(text, font, font_size, rect.size.x - absf(x_margin))
	canvas.draw_string(
		font,
		Vector2(rect.position.x + x_margin, baseline_y),
		display_text,
		h_align,
		maxf(0.001, rect.size.x - absf(x_margin)),
		font_size,
		color,
	)


static func get_text_baseline_y(font: Font, font_size: int, cell_y: float, cell_height: float) -> float:
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	return cell_y + (cell_height + ascent - descent) / 2.0


static func get_display_text(text: String, font: Font, font_size: int, max_width: float) -> String:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if text_size.x <= max_width:
		return text

	var ellipsis := "..."
	var ellipsis_width := font.get_string_size(ellipsis, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_text_width := max_width - ellipsis_width
	if max_text_width <= 0:
		return ellipsis

	var truncated_text := ""
	for i in range(text.length()):
		var test_text := text.substr(0, i + 1)
		var test_width := font.get_string_size(test_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if test_width > max_text_width:
			break
		truncated_text = test_text
	return truncated_text + ellipsis


static func resolve_font(column: ColumnConfig, fallback_font: Font) -> Font:
	return column.custom_font if column.custom_font else fallback_font


static func resolve_text_color(column: ColumnConfig, style: CellStyle, override: Color = Color.TRANSPARENT) -> Color:
	if override != Color.TRANSPARENT:
		return override
	if column.custom_font_color:
		return column.custom_font_color
	return style.default_font_color


static func fit_texture_rect(texture: Texture2D, container: Rect2, anchor_to_left := false) -> Rect2:
	var tex_size := texture.get_size()
	var tex_aspect := tex_size.x / tex_size.y
	var cell_aspect := container.size.x / container.size.y
	var thumb_size: Vector2
	if tex_aspect > cell_aspect:
		thumb_size = Vector2(container.size.x, container.size.x / tex_aspect)
	else:
		thumb_size = Vector2(container.size.y * tex_aspect, container.size.y)
	var offset_x := 0.0 if anchor_to_left else (container.size.x - thumb_size.x) / 2.0
	var offset_y := (container.size.y - thumb_size.y) / 2.0
	return Rect2(container.position + Vector2(offset_x, offset_y), thumb_size)


static func draw_filtered_texture_rect(canvas: CanvasItem, pixelated_canvas_rid: RID, texture: Texture2D, rect: Rect2, frozen_width: float) -> void:
	var ratio := rect.size / texture.get_size()
	if minf(ratio.x, ratio.y) > 1.5 * EditorInterface.get_editor_scale() and rect.end.x > frozen_width:
		if texture is AtlasTexture:
			RenderingServer.canvas_item_add_texture_rect_region(pixelated_canvas_rid, rect, texture.get_rid(), texture.region)
		else:
			RenderingServer.canvas_item_add_texture_rect(pixelated_canvas_rid, rect, texture.get_rid())
	else:
		canvas.draw_texture_rect(texture, rect, false)


# Editing: stateless factory. create_editor builds a fresh Node each time,
# already parented under `owner` and ready to use. DynamicTable keeps the
# returned Node (the only cell-editing instance that can exist at once) and
# queue_free()s it when done; read_editor_value reads the committed value back
# off that same Node.
static func has_editor() -> bool:
	return false


static func create_editor(_owner: Control, _rect: Rect2, _value: Variant, _column: ColumnConfig, _on_finished: Callable) -> Node:
	return null


static func read_editor_value(_editor: Node, _column: ColumnConfig) -> Variant:
	return null


static func commits_on_click_away() -> bool:
	return true


static func suppresses_tooltip() -> bool:
	return false


## `value` is guaranteed non-null by the caller (DynamicTable.ordering_data).
static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return str(value)


# Direct input (click, Enter key). Empty Dictionary means "not handled, do the
# default thing" (normal cell selection, or opening the editor on Enter).
static func handle_click(_mouse_pos: Vector2, _rect: Rect2, _value: Variant, _column: ColumnConfig, _style: CellStyle) -> Dictionary:
	return { }


static func handle_enter(_value: Variant, _column: ColumnConfig) -> Dictionary:
	return { }
