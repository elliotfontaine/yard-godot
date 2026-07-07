extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Path/file columns, edited via Godot's own EditorFileDialog. Only the FILE
## hint gets thumbnail + invalid-UID rendering; FILE_PATH/DIR fall back to
## plain (mono-font) text.

const INVALID_UID := "uid://<invalid>"


static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_STRING and column.property_hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_FILE_PATH, PROPERTY_HINT_DIR]


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	if column.property_hint != PROPERTY_HINT_FILE:
		draw_text(canvas, rect, str(value) if value != null else "", resolve_font(column, style.mono_font), style.font_size, column.h_alignment, resolve_text_color(column, style))
		return

	var is_invalid_uid: bool = value == INVALID_UID
	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var thumb_width := 0.0
	var texture: Texture2D
	if is_invalid_uid:
		texture = style.file_dead_icon
	elif ResourceLoader.exists(value):
		texture = style.get_thumbnail.call(value)

	if texture != null:
		var thumb_rect := fit_texture_rect(texture, inner, true)
		thumb_rect.position.x += x_margin_val
		thumb_width = thumb_rect.size.x
		draw_filtered_texture_rect(canvas, style.pixelated_canvas_rid, texture, thumb_rect, style.frozen_width)

	var text_rect := inner.grow_individual(-thumb_width - x_margin_val, 0, 0, 0)
	if is_invalid_uid:
		draw_text(canvas, text_rect, str(value), resolve_font(column, style.mono_font), style.font_size, column.h_alignment, style.error_color)
	else:
		draw_text(canvas, text_rect, str(value) if value != null else "", resolve_font(column, style.mono_font), style.font_size, column.h_alignment, resolve_text_color(column, style))


static func has_editor() -> bool:
	return true


static func commits_on_click_away() -> bool:
	return false


static func create_editor(owner: Control, _rect: Rect2, value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var editor := EditorFileDialog.new()
	owner.add_child(editor)
	editor.disable_overwrite_warning = true

	if column.property_hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_FILE_PATH]:
		editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	if column.property_hint in [PROPERTY_HINT_DIR]:
		editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR

	var cell_value := str(value) if value != null else ""
	if FileAccess.file_exists(cell_value):
		var current_path := ResourceUID.ensure_path(cell_value)
		editor.current_dir = current_path.get_base_dir()
		editor.current_path = current_path

	var on_path_selected := func(path: String) -> void:
		if column.property_hint == PROPERTY_HINT_DIR:
			editor.current_path = path.path_join("")
		on_finished.call(true)
	editor.dir_selected.connect(on_path_selected)
	editor.file_selected.connect(on_path_selected)

	editor.popup_centered_ratio(0.55)
	return editor


static func read_editor_value(editor: Node, column: ColumnConfig) -> Variant:
	var raw: String = (editor as EditorFileDialog).current_path
	if column.property_hint == PROPERTY_HINT_FILE:
		return ResourceUID.path_to_uid(raw)
	return raw
