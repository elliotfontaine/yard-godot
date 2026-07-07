extends "res://addons/yard/editor_only/ui_scenes/components/cell_types/cell_type.gd"
## Range/progress-bar columns (numeric type + PROPERTY_HINT_RANGE). Has no editor
## of its own; ColumnConfig.get_editor_cell_type() falls back to NumericCellType's
## editor when a range cell is double-clicked. Drag-to-adjust is the main
## interaction: DynamicTable tracks which cell is being dragged (same as it
## already tracks the edited cell) and calls compute_drag_value each frame.

static func matches(column: ColumnConfig) -> bool:
	return column.is_range_column()


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var cell_value: float = value
	var range_cfg := column.range_config
	var progress: float = inverse_lerp(range_cfg.get(&"min"), range_cfg.get(&"max"), cell_value)
	var progress_color := _get_interpolated_three_colors(style.progress_bar_start_color, style.progress_bar_middle_color, style.progress_bar_end_color, progress)

	var scale := EditorInterface.get_editor_scale()
	var bar := rect.grow(-2.0 * scale)
	var fill := Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y))

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_CENTER)
	var numeric_text := str(snappedf(cell_value, 0.001))
	var display_text := get_display_text(numeric_text, style.font, style.font_size, rect.size.x - absf(x_margin_val))
	var text_width := style.font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.font_size).x
	var text_pos := Vector2(rect.position.x + (rect.size.x - text_width) / 2.0, get_text_baseline_y(style.font, style.font_size, rect.position.y, rect.size.y))
	var fill_width: float = maxf(0.001, fill.position.x + fill.size.x - text_pos.x - absf(x_margin_val) + 5 * scale)

	canvas.draw_rect(bar, style.progress_background_color)
	canvas.draw_string(style.font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - absf(x_margin_val), style.font_size, style.progress_text_color_light)
	canvas.draw_rect(fill, progress_color)
	@warning_ignore("integer_division")
	canvas.draw_string_outline(style.font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, fill_width, style.font_size, style.font_size / 3, progress_color)
	canvas.draw_string(style.font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, fill_width, style.font_size, Color.BLACK)
	canvas.draw_rect(bar, style.progress_border_color, false, 1.0 * scale)


static func _get_interpolated_three_colors(start_color: Color, mid_color: Color, end_color: Color, progress: float) -> Color:
	var clamped_t := clampf(progress, 0.0, 1.0)
	if clamped_t <= 0.5:
		return start_color.lerp(mid_color, clamped_t * 2.0)
	else:
		return mid_color.lerp(end_color, (clamped_t - 0.5) * 2.0)


static func suppresses_tooltip() -> bool:
	return true


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return float(value)


static func handle_click(_mouse_pos: Vector2, _rect: Rect2, _value: Variant, _column: ColumnConfig, _style: CellStyle) -> Dictionary:
	return { &"action": &"drag" }


static func compute_drag_value(mouse_pos: Vector2, column: ColumnConfig, cell_x: float, cell_width: float) -> Variant:
	var margin := 4.0
	var bar_x := cell_x + margin
	var bar_w := cell_width - margin * 2.0
	if bar_w <= 0:
		return null

	var range_cfg := column.range_config
	var weight := (mouse_pos.x - bar_x) / bar_w
	var new_value: float = snappedf(
		lerpf(range_cfg.get(&"min"), range_cfg.get(&"max"), weight),
		range_cfg.get(&"step"),
	)
	if not range_cfg.has(&"or_greater"):
		new_value = min(new_value, range_cfg.get(&"max"))
	if not range_cfg.has(&"or_less"):
		new_value = max(new_value, range_cfg.get(&"min"))
	return new_value
