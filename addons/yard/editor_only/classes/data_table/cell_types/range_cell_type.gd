# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Range/progress-bar columns (numeric type + PROPERTY_HINT_RANGE). Has no editor
## of its own; ColumnConfig.get_editor_cell_type() falls back to NumericCellType's
## editor when a range cell is double-clicked. Drag-to-adjust is the main
## interaction.

static func matches(column: ColumnConfig) -> bool:
	return column.type in [TYPE_FLOAT, TYPE_INT] and column.property_hint == PROPERTY_HINT_RANGE


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var cell_value: float = value
	var range_cfg := _get_range_config(column)
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


static func handle_input(event: InputEvent, rect: Rect2, _value: Variant, column: ColumnConfig, _style: CellStyle) -> Dictionary:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return { &"commit": false } # claim the drag; value doesn't move until motion
		var released_value: Variant = _compute_drag_value(event.position, column, rect.position.x, rect.size.x)
		return { &"value": released_value, &"commit": true } if released_value != null else { &"commit": true }

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var new_value: Variant = _compute_drag_value(event.position, column, rect.position.x, rect.size.x)
		return { &"value": new_value, &"commit": false } if new_value != null else { }

	return { }


static func _compute_drag_value(mouse_pos: Vector2, column: ColumnConfig, cell_x: float, cell_width: float) -> Variant:
	var margin := 4.0
	var bar_x := cell_x + margin
	var bar_w := cell_width - margin * 2.0
	if bar_w <= 0:
		return null

	var range_cfg := _get_range_config(column)
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


static func _get_range_config(column: ColumnConfig) -> Dictionary:
	return column.get_cached(&"range_config", func() -> Dictionary: return _compute_range_config(column))


static func _compute_range_config(column: ColumnConfig) -> Dictionary[StringName, Variant]:
	var hint_elements := column.hint_string.split(",", false)
	var result: Dictionary[StringName, Variant] = {
		&"min": float(hint_elements[0]) if hint_elements.size() > 0 else 0.0,
		&"max": float(hint_elements[1]) if hint_elements.size() > 1 else 1.0,
		&"step": float(hint_elements[2]) if hint_elements.size() > 2 else (0.001 if column.type == TYPE_FLOAT else 1.0),
	}
	for hint_str in hint_elements.slice(3):
		match hint_str:
			"or_greater":
				result[&"or_greater"] = true
			"or_less":
				result[&"or_less"] = true
	return result
