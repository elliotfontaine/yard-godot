extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Boolean columns: a checkbox icon, toggled by a direct click or Enter, with
## no separate cell editor.

static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_BOOL


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	if value is not bool:
		draw_text(canvas, rect, str(value) if value != null else "", resolve_font(column, style.font), style.font_size, column.h_alignment, resolve_text_color(column, style))
		return

	var icon: Texture2D = style.checkbox_checked_icon if (value as bool) else style.checkbox_unchecked_icon
	if icon == null:
		return

	var inner := rect.grow(-2.0)
	var pos := inner.position + (inner.size - icon.get_size()) / 2.0
	canvas.draw_texture(icon, pos)


static func suppresses_tooltip() -> bool:
	return true


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return 1 if bool(value) else 0


static func handle_click(mouse_pos: Vector2, rect: Rect2, value: Variant, _column: ColumnConfig, style: CellStyle) -> Dictionary:
	var icon := style.checkbox_checked_icon
	if icon == null:
		return { }
	var icon_rect := Rect2(rect.get_center() - icon.get_size() / 2.0, icon.get_size())
	if not icon_rect.has_point(mouse_pos):
		return { }
	return { &"action": &"toggle", &"value": not bool(value) }


static func handle_enter(value: Variant, _column: ColumnConfig) -> Dictionary:
	return { &"action": &"toggle", &"value": not bool(value) }
