# Originally based on dynamicdatatable by Giuseppe Pica (jospic), MIT licensed.
# https://github.com/jospic/dynamicdatatable
# Heavily modified / rewritten by Elliot Fontaine, 2026

# BEHOLD THE 2000-LINES BEAST.

@tool
extends Control

signal cell_selected(row_id: StringName, col: StringName)
signal multiple_rows_selected(row_ids: Array[StringName])
signal cell_right_selected(row_id: StringName, col: StringName, mouse_pos: Vector2)
signal header_clicked(column: StringName)
signal column_resized(column: StringName, new_width: float)
signal progress_changed(row_id: StringName, col: StringName, new_value: float)
signal cell_edited(row_id: StringName, col: StringName, old_value: Variant, new_value: Variant)

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ClassUtils := Namespace.ClassUtils
const EditorThemeUtils := Namespace.EditorThemeUtils
const AnyIcon := Namespace.AnyIcon
const YardLogger := Namespace.YardLogger

const H_ALIGNMENT_MARGINS = {
	HORIZONTAL_ALIGNMENT_LEFT: 5,
	HORIZONTAL_ALIGNMENT_CENTER: 0,
	HORIZONTAL_ALIGNMENT_RIGHT: -5,
}
const CELL_INVALID := "<CELL_INVALID>"
const INVALID_UID := "uid://<invalid>"

# Theming properties
@export_group("Custom YARD Properties")
@export var base_height_from_line_edit: bool = false
@export_group("Default color")
@export var default_font_color: Color = Color(1.0, 1.0, 1.0)
@export_group("Header")
@export var header_height: float = 35.0
@export var header_color: Color = Color(0.2, 0.2, 0.2)
@export var header_filter_active_font_color: Color = Color(1.0, 1.0, 0.0)
@export_group("Size and grid")
@export var default_minimum_column_width: float = 50.0
@export var row_height: float = 30.0
@export var n_frozen_columns: int = 0
@export var grid_color: Color = Color(0.8, 0.8, 0.8)
@export_group("Rows")
@export var selected_row_back_color: Color = Color(0.0, 0.0, 1.0, 0.5)
@export var selected_cell_back_color: Color = Color(0.0, 0.0, 1.0, 0.5)
@export var row_color: Color = Color(0.55, 0.55, 0.55, 1.0)
@export var alternate_row_color: Color = Color(0.45, 0.45, 0.45, 1.0)
@export_group("Checkbox")
@export var checkbox_checked_color: Color = Color(0.0, 0.8, 0.0)
@export var checkbox_unchecked_color: Color = Color(0.8, 0.0, 0.0)
@export var checkbox_border_color: Color = Color(0.8, 0.8, 0.8)
@export_group("Progress bar")
@export var progress_bar_start_color: Color = Color.RED
@export var progress_bar_middle_color: Color = Color.ORANGE
@export var progress_bar_end_color: Color = Color.FOREST_GREEN
@export var progress_background_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var progress_border_color: Color = Color(0.6, 0.6, 0.6, 1.0)
@export var progress_text_color_light: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var progress_text_color_dark: Color = Color.BLACK
@export_group("Invalid cell")
@export var invalid_cell_color: Color = Color("252b3aff")

# Fonts
var font := get_theme_default_font()
var mono_font: Font = EditorInterface.get_editor_theme().get_font("font", "CodeEdit")
var font_size := get_theme_default_font_size()

# Public state: selection, focus and sort (row/column keys)
var selected_rows: Array[StringName] = []
var focused_row: StringName = &""
var focused_col: StringName = &""
var sort_column: StringName = &""
var sort_ascending: bool = true

# Row model: key -> cells (the data), and the current display order
var _rows: Dictionary[StringName, Array] = { }
var _base_order: Array[StringName] = [] # insertion order, source for filter
var _order: Array[StringName] = [] # current visible filtered / sorted order
var _anchor_row: StringName = &"" # shift-select range anchor

# Column model: the ordered list is both the model and the display order
# (no column reordering feature exists). The map is a position cache.
var _columns: Array[ColumnConfig]
var _column_index_by_id: Dictionary[StringName, int] = { }

# Scrolling
var _h_scroll: HScrollBar
var _v_scroll: VScrollBar
var _h_scroll_position := 0
var _visible_rows_range: Array[int] = [0, 0]

# Column resizing (dragging a header divider)
var _resizing_column: StringName = &""
var _resizing_start_pos := 0
var _resizing_start_width := 0
var _mouse_over_divider := -1
var _divider_width := 5

# Sort icon (header rendering)
var _icon_sort := " ▼ "

# Column filter (double-click a header to search within that column)
var _filter_line_edit: LineEdit
var _filtered_column: StringName = &""

# Inline cell editing
var _edited_row: StringName = &""
var _edited_col: StringName = &""
var _text_editor_line_edit: LineEdit
var _color_editor: Control
var _resource_editor: EditorResourcePicker
var _path_editor: EditorFileDialog
var _enum_editor: PopupMenu
var _enum_editor_last_idx: int = -1

# Click detection (single vs. double click)
var _double_click_timer: Timer
var _click_count := 0
var _last_click_pos := Vector2.ZERO
var _double_click_threshold := 400 # milliseconds
var _click_position_threshold := 5 # pixels

# Progress bar dragging
var _dragging_progress := false
var _dragging_start_value: Variant
var _progress_drag_row: StringName = &""
var _progress_drag_col: StringName = &""

# Resource preview cache (thumbnails for resource / path columns)
var _resource_thumb_cache: Dictionary = { }
var _resource_thumb_pending: Dictionary = { }

# Tooltip tracking
var _tooltip_row: StringName = &""
var _tooltip_col: StringName = &""

# Trackpad / touch pan gesture
var _pan_delta_accumulation: Vector2 = Vector2.ZERO

# Rendering
var _pixelated_canvas_rid: RID


func _ready() -> void:
	if Engine.is_editor_hint() and not EditorInterface.get_edited_scene_root() == self:
		EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)
		EditorInterface.get_resource_previewer().preview_invalidated.connect(_on_resource_previewer_preview_invalidated)
		set_native_theming()

	self.focus_mode = Control.FOCUS_ALL

	_setup_editing_components()
	_setup_filtering_components()

	_pixelated_canvas_rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_pixelated_canvas_rid, get_canvas_item())
	RenderingServer.canvas_item_set_default_texture_filter(_pixelated_canvas_rid, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)

	_h_scroll = HScrollBar.new()
	_h_scroll.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_h_scroll.offset_top = -8 * get_theme_default_base_scale()
	_h_scroll.value_changed.connect(_on_h_scroll_changed)

	_v_scroll = VScrollBar.new()
	_v_scroll.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
	_v_scroll.offset_top = header_height
	_v_scroll.offset_left = -8 * get_theme_default_base_scale()
	_v_scroll.value_changed.connect(_on_v_scroll_value_changed)

	add_child(_h_scroll)
	add_child(_v_scroll)

	_reset_column_widths()

	resized.connect(_on_resized)

	self.anchor_left = 0.0
	self.anchor_top = 0.0
	self.anchor_right = 1.0
	self.anchor_bottom = 1.0

	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _pixelated_canvas_rid.is_valid():
		RenderingServer.free_rid(_pixelated_canvas_rid)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		_handle_pan_gesture(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventKey and event.is_pressed() and has_focus():
		_handle_key_input(event as InputEventKey)


func _draw() -> void:
	RenderingServer.canvas_item_clear(_pixelated_canvas_rid)
	if not is_inside_tree() or _columns.is_empty() or _order.is_empty():
		return

	var frozen_w := _get_frozen_width()
	var scroll_x := frozen_w - _h_scroll_position
	var vis_w := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.0)
	var y_offset := header_height
	RenderingServer.canvas_item_set_clip(_pixelated_canvas_rid, true)
	RenderingServer.canvas_item_set_custom_rect(_pixelated_canvas_rid, true, Rect2(frozen_w, 0.0, maxf(0.0, vis_w - frozen_w), size.y))

	draw_rect(Rect2(0, 0, size.x, header_height), header_color)

	# Pass 1: scrollable columns
	_draw_header_column_range(n_frozen_columns, _columns.size(), scroll_x, frozen_w, vis_w)

	for row_idx in range(_visible_rows_range[0], _visible_rows_range[1]):
		if row_idx >= _order.size():
			continue
		var row := _order[row_idx]
		var row_y := y_offset + (row_idx - _visible_rows_range[0]) * row_height
		var bg := alternate_row_color if row_idx % 2 == 1 else row_color
		draw_rect(Rect2(0, row_y, vis_w, row_height), bg)
		if selected_rows.has(row):
			draw_rect(Rect2(0, row_y, vis_w, row_height - 1), selected_row_back_color)
		draw_line(Vector2(0, row_y + row_height), Vector2(vis_w, row_y + row_height), grid_color)
		_draw_cells_column_range(row, row_y, n_frozen_columns, _columns.size(), scroll_x, frozen_w, vis_w)

	# Pass 2: frozen columns drawn on top
	if n_frozen_columns > 0:
		for row_idx in range(_visible_rows_range[0], _visible_rows_range[1]):
			if row_idx >= _order.size():
				continue
			var row := _order[row_idx]
			var row_y := y_offset + (row_idx - _visible_rows_range[0]) * row_height
			var bg := alternate_row_color if row_idx % 2 == 1 else row_color
			draw_rect(Rect2(0, row_y, frozen_w, row_height), bg)
			if selected_rows.has(row):
				draw_rect(Rect2(0, row_y, frozen_w, row_height - 1), selected_row_back_color)
			draw_line(Vector2(0, row_y + row_height), Vector2(frozen_w, row_y + row_height), grid_color)
			_draw_cells_column_range(row, row_y, 0, n_frozen_columns, 0.0, 0.0, frozen_w)

		draw_rect(Rect2(0, 0, frozen_w, header_height), header_color)
		_draw_header_column_range(0, n_frozen_columns, 0.0, 0.0, vis_w)

		var separator_bottom := header_height + mini(_order.size(), _visible_rows_range[1] - _visible_rows_range[0]) * row_height
		draw_line(Vector2(frozen_w, 0), Vector2(frozen_w, separator_bottom), grid_color.darkened(0.2), 2.0)

		if _v_scroll.visible:
			draw_rect(Rect2(vis_w, header_height, _v_scroll.size.x + 50, size.y), row_color)

#region PUBLIC METHODS

func set_native_theming(delay: int = 0) -> void:
	if delay != 0 and is_inside_tree():
		await get_tree().create_timer(delay).timeout

	var root := EditorInterface.get_base_control()
	var editor_settings := EditorInterface.get_editor_settings()
	font = root.get_theme_font(&"main", &"EditorFonts")
	default_font_color = root.get_theme_color(&"font_color", &"Editor")
	font_size = root.get_theme_font_size(&"main_size", &"EditorFonts")
	row_color = root.get_theme_color(&"base_color", &"Editor")
	if ClassUtils.is_engine_version_equal_or_newer(4, 6) and editor_settings.get_setting("interface/theme/style") == "Modern":
		alternate_row_color = root.get_theme_color(&"dark_color_3", &"Editor")
		header_color = root.get_theme_color(&"dark_color_1", &"Editor")
	else:
		alternate_row_color = root.get_theme_color(&"dark_color_1", &"Editor")
		header_color = root.get_theme_color(&"dark_color_2", &"Editor")
	selected_row_back_color = Color(1, 1, 1, 0.20)
	selected_cell_back_color = root.get_theme_color(&"accent_color", &"Editor")
	header_filter_active_font_color = root.get_theme_color(&"accent_color", &"Editor")
	grid_color = root.get_theme_color(&"dark_color_1", &"Editor").darkened(0.4)
	invalid_cell_color = EditorThemeUtils.get_base_color(0.9)
	progress_background_color = root.get_theme_color(&"prop_category", &"Editor")
	progress_border_color = root.get_theme_color(&"extra_border_color_2", &"Editor")
	progress_text_color_light = default_font_color
	progress_text_color_dark = root.get_theme_color(&"dark_color_1", &"Editor")
	progress_bar_start_color = root.get_theme_color(&"axis_x_color", &"Editor")
	progress_bar_middle_color = root.get_theme_color(&"executing_line_color", &"CodeEdit")
	progress_bar_end_color = root.get_theme_color(&"success_color", &"Editor")

	row_height = font_size * 2
	header_height = font_size * 2

	queue_redraw()


func set_columns(columns: Array[ColumnConfig]) -> void:
	_columns = columns
	_column_index_by_id.clear()
	for i in _columns.size():
		_column_index_by_id[_columns[i].identifier] = i
	_reset_column_widths()
	queue_redraw()


func get_column(col: StringName) -> ColumnConfig:
	var idx: int = _column_index_by_id.get(col, -1)
	return _columns[idx] if idx >= 0 else null


## Returns all columns, in display order.
func get_all_columns() -> Array[ColumnConfig]:
	return _columns.duplicate()


func _column_index(col: StringName) -> int:
	return _column_index_by_id.get(col, -1)


## Replace all rows. Preserves focused_row and selected_rows for keys that still exist.
## Preserves the current sort: re-applies it after rebuilding _order.
func set_data(rows: Array, row_ids: Array[StringName]) -> void:
	_rows.clear()
	_base_order.clear()
	for i in row_ids.size():
		var row := row_ids[i]
		_rows[row] = rows[i].duplicate() if i < rows.size() else []
		_base_order.append(row)
	_order = _base_order.duplicate()

	_visible_rows_range = [0, min(_order.size(), floori(size.y / row_height) if row_height > 0 else 0)]

	# Pad short rows
	for row in _order:
		var row_data: Array = _rows[row]
		while row_data.size() < _columns.size():
			row_data.append(CELL_INVALID)

	# Preserve selection / focus for rows that still exist
	var kept_rows: Array[StringName] = []
	for row in selected_rows:
		if _rows.has(row):
			kept_rows.append(row)
	selected_rows = kept_rows

	if not _rows.has(focused_row):
		focused_row = &""
		focused_col = &""
	if not _rows.has(_anchor_row):
		_anchor_row = &""

	_resource_thumb_cache.clear()
	_resource_thumb_pending.clear()

	_update_scrollbars()
	queue_redraw()


## Update a single row in place without rebuilding the full dataset.
func update_row(row: StringName, cells: Array) -> void:
	if not _rows.has(row):
		return
	_rows[row] = cells.duplicate()
	while _rows[row].size() < _columns.size():
		_rows[row].append(CELL_INVALID)
	queue_redraw()


## Append a new row. No-op if the row already exists.
func add_row(row: StringName, cells: Array) -> void:
	if _rows.has(row):
		return
	_rows[row] = cells.duplicate()
	while _rows[row].size() < _columns.size():
		_rows[row].append(CELL_INVALID)
	_base_order.append(row)
	_order.append(row)
	_update_scrollbars()
	queue_redraw()


## Remove a row by key. Clears selection/focus if they pointed to it.
func remove_row(row: StringName) -> void:
	if not _rows.has(row):
		return
	_rows.erase(row)
	_base_order.erase(row)
	_order.erase(row)
	selected_rows.erase(row)
	if focused_row == row:
		focused_row = &""
		focused_col = &""
	if _anchor_row == row:
		_anchor_row = &""
	_update_scrollbars()
	queue_redraw()


func ordering_data(column: StringName, ascending: bool = true) -> void:
	var column_cfg := get_column(column)
	if not column_cfg:
		return
	_finish_editing(false)
	sort_column = column
	sort_ascending = ascending
	var column_idx := _column_index(column)
	_icon_sort = " ▼ " if ascending else " ▲ "

	_order.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var a_cells: Array = _rows.get(a, [])
			var b_cells: Array = _rows.get(b, [])
			var va: Variant = a_cells[column_idx] if column_idx < a_cells.size() else null
			var vb: Variant = b_cells[column_idx] if column_idx < b_cells.size() else null
			var ka: Variant = _key_for_sort(va, column_cfg)
			var kb: Variant = _key_for_sort(vb, column_cfg)
			if ka == null and kb == null:
				return false
			if ka == null:
				return ascending
			if kb == null:
				return not ascending
			if typeof(ka) == TYPE_ARRAY and typeof(kb) == TYPE_ARRAY:
				var n := mini(ka.size(), kb.size())
				for i in range(n):
					if ka[i] != kb[i]:
						return ka[i] < kb[i] if ascending else ka[i] > kb[i]
				return ka.size() < kb.size() if ascending else ka.size() > kb.size()
			if (typeof(ka) in [TYPE_INT, TYPE_FLOAT]) and (typeof(kb) in [TYPE_INT, TYPE_FLOAT]):
				return ka < kb if ascending else ka > kb
			return str(ka) < str(kb) if ascending else str(ka) > str(kb)
	)

	queue_redraw()


func update_cell(row: StringName, col: StringName, value: Variant) -> void:
	var col_idx := _column_index(col)
	if not _rows.has(row) or col_idx < 0:
		return
	while _rows[row].size() <= col_idx:
		_rows[row].append(CELL_INVALID)
	_rows[row][col_idx] = value
	queue_redraw()


func get_cell_value(row: StringName, col: StringName) -> Variant:
	var col_idx := _column_index(col)
	if not _rows.has(row) or col_idx < 0 or col_idx >= _rows[row].size():
		return null
	var raw: Variant = _rows[row][col_idx]
	if is_cell_invalid(row, col):
		return raw
	if get_column(col) and get_column(col).is_numeric_column() and not _is_numeric_value(raw):
		return 0
	return raw


func set_selected_cell(row: StringName, col: StringName) -> void:
	var idx := _order.find(row)
	if row != &"" and idx >= 0 and col != &"" and get_column(col):
		focused_row = row
		focused_col = col
		selected_rows.clear()
		selected_rows.append(row)
		_anchor_row = row
		_ensure_row_visible(row)
		_ensure_col_visible(col)
		queue_redraw()
	else:
		focused_row = &""
		focused_col = &""
		selected_rows.clear()
		_anchor_row = &""
		queue_redraw()
	cell_selected.emit(focused_row, focused_col)


func select_all_rows() -> void:
	if _order.is_empty():
		return
	selected_rows = _order.duplicate()
	if focused_row == &"":
		focused_row = _order[0]
		_anchor_row = _order[0]
		focused_col = _columns[0].identifier if not _columns.is_empty() else &""
	else:
		_anchor_row = focused_row
	_ensure_row_visible(focused_row)
	_ensure_col_visible(focused_col)


func is_cell_invalid(row: StringName, col: StringName) -> bool:
	var col_idx := _column_index(col)
	if not _rows.has(row) or col_idx < 0 or col_idx >= _rows[row].size():
		return false
	var raw: Variant = _rows[row][col_idx]
	return raw is String and raw == CELL_INVALID


## Returns the rows currently visible (after sort/filter), in display order.
## /!\ These are not the rows in view (when there is overflow + HScrollbar)
func get_displayed_rows() -> Array[StringName]:
	return _order.duplicate()


## Call after changing n_frozen_columns or other layout properties.
func refresh_layout() -> void:
	_update_scrollbars()
	queue_redraw()

#endregion

#region PRIVATE METHODS

func _setup_filtering_components() -> void:
	_filter_line_edit = LineEdit.new()
	_filter_line_edit.visible = false
	_filter_line_edit.text_submitted.connect(_apply_filter)
	_filter_line_edit.focus_exited.connect(_on_filter_focus_exited)
	add_child(_filter_line_edit)


func _setup_editing_components() -> void:
	_text_editor_line_edit = LineEdit.new()
	_text_editor_line_edit.text_submitted.connect(_on_text_editor_text_submitted)
	_text_editor_line_edit.focus_exited.connect(_on_text_editor_focus_exited)
	_text_editor_line_edit.hide()
	add_child(_text_editor_line_edit)

	if base_height_from_line_edit:
		header_height = _text_editor_line_edit.size.y
		row_height = _text_editor_line_edit.size.y

	# TODO: Make inner class instead of packed scene, for portability
	_color_editor = preload("uid://cuhed17jgms48").instantiate()
	_color_editor.color_selected.connect(_on_color_editor_color_selected)
	_color_editor.canceled.connect(_on_color_editor_canceled)
	_color_editor.hide()
	add_child(_color_editor)

	_resource_editor = EditorResourcePicker.new()
	_resource_editor.resource_changed.connect(_on_resource_editor_resource_changed)
	_resource_editor.hide()
	add_child(_resource_editor)

	_path_editor = EditorFileDialog.new()
	_path_editor.disable_overwrite_warning = true
	_path_editor.dir_selected.connect(_on_path_editor_path_selected)
	_path_editor.file_selected.connect(_on_path_editor_path_selected)
	add_child(_path_editor)

	_enum_editor = PopupMenu.new()
	_enum_editor.index_pressed.connect(_on_enum_editor_index_pressed)
	_enum_editor.popup_hide.connect(_on_enum_editor_popup_hide)
	add_child(_enum_editor)

	_double_click_timer = Timer.new()
	_double_click_timer.wait_time = _double_click_threshold / 1000.0
	_double_click_timer.one_shot = true
	_double_click_timer.timeout.connect(_on_double_click_timeout)
	add_child(_double_click_timer)


func _reset_column_widths() -> void:
	for column in _columns:
		column.minimum_width = default_minimum_column_width
		var header_size := font.get_string_size(column.header, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(font_size * 2, 0)
		column.current_width = header_size.x


func _update_scrollbars() -> void:
	if not is_inside_tree():
		return
	if row_height <= 0:
		row_height = 30.0

	var visible_width := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.)
	var visible_height := size.y - (_h_scroll.size.y if _h_scroll.visible else 0.) - header_height

	var frozen_w := _get_frozen_width()
	var visible_scrollable_w := visible_width - frozen_w
	var total_scrollable_w := 0.0
	for i in range(n_frozen_columns, _columns.size()):
		total_scrollable_w += _columns[i].current_width

	_h_scroll.visible = total_scrollable_w > visible_scrollable_w
	_h_scroll.offset_left = frozen_w
	if _h_scroll.visible:
		_h_scroll.max_value = total_scrollable_w
		_h_scroll.page = visible_scrollable_w
	else:
		_h_scroll.value = 0

	var total_content_height := float(_order.size()) * row_height
	_v_scroll.visible = total_content_height > visible_height
	if _v_scroll.visible:
		_v_scroll.max_value = total_content_height + row_height / 2
		_v_scroll.page = visible_height
		_v_scroll.step = row_height
	else:
		_v_scroll.value = 0

	_on_v_scroll_value_changed(_v_scroll.value)


func _is_numeric_value(value: Variant) -> bool:
	if value == null:
		return false
	var str_val := str(value)
	return str_val.is_valid_float() or str_val.is_valid_int()


func _start_cell_editing(row: StringName, col: StringName) -> void:
	var column := get_column(col)
	if is_cell_invalid(row, col):
		return

	if column.is_color_column():
		_open_color_editor(row, col)
	elif column.is_resource_column():
		_open_resource_editor(row, col)
	elif column.is_path_column():
		_open_path_editor(row, col)
	elif column.is_enum_column():
		_open_enum_editor(row, col)
	elif column.is_numeric_column() or column.is_string_column():
		_open_text_editor(row, col)
	else:
		YardLogger.warn("There is no editor for this type of cell.")


func _open_text_editor(row: StringName, col: StringName) -> void:
	var cell_rect := _get_cell_rect(row, col)
	if not cell_rect:
		return

	var cell_value: Variant = get_cell_value(row, col)
	_edited_row = row
	_edited_col = col
	_text_editor_line_edit.position = cell_rect.position
	_text_editor_line_edit.size = cell_rect.size
	_text_editor_line_edit.text = str(cell_value) if cell_value != null else ""
	_text_editor_line_edit.alignment = get_column(col).h_alignment
	_text_editor_line_edit.show()
	_text_editor_line_edit.grab_focus()
	_text_editor_line_edit.select_all()


func _open_color_editor(row: StringName, col: StringName) -> void:
	var cell_rect := _get_cell_rect(row, col)
	if not cell_rect:
		return

	var cell_value: Color = get_cell_value(row, col)
	_edited_row = row
	_edited_col = col
	_color_editor.position = cell_rect.get_center() + global_position
	_color_editor.color = cell_value
	_color_editor.show()
	_color_editor.grab_focus()


func _open_resource_editor(row: StringName, col: StringName) -> void:
	_edited_row = row
	_edited_col = col
	var column := get_column(col)
	_resource_editor.edited_resource = null
	_resource_editor.base_type = "Resource"
	if not column.hint_string.is_empty():
		var valid_types := Array(column.hint_string.split(",", false)).filter(ClassUtils.is_valid)
		if not valid_types.is_empty():
			_resource_editor.base_type = ",".join(valid_types)

	for child in _resource_editor.get_children(true):
		if child is Button and child.tooltip_text == "Quick Load":
			child.pressed.emit()
			break


func _open_path_editor(row: StringName, col: StringName) -> void:
	_edited_row = row
	_edited_col = col
	var cell_value: String = get_cell_value(row, col)
	var column := get_column(col)
	if column.property_hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_FILE_PATH]:
		_path_editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	if column.property_hint in [PROPERTY_HINT_DIR]:
		_path_editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR

	if FileAccess.file_exists(cell_value):
		var current_path := ResourceUID.ensure_path(cell_value)
		_path_editor.current_dir = current_path.get_base_dir()
		_path_editor.current_path = current_path

	_path_editor.popup_centered_ratio(0.55)


func _open_enum_editor(row: StringName, col: StringName) -> void:
	_edited_row = row
	_edited_col = col
	var current_value: Variant = get_cell_value(row, col)
	var column := get_column(col)
	var is_numeric := column.is_numeric_column()

	@warning_ignore("incompatible_ternary")
	var value_iter: Variant = -1 if is_numeric else ""

	_enum_editor.clear()
	for choice: String in column.hint_string.split(",", false):
		var colon := choice.rfind(":")
		var text: String
		if colon != -1:
			text = choice.substr(0, colon)
			value_iter = choice.substr(colon + 1).to_int()
		else:
			text = choice
			value_iter = value_iter + 1 if is_numeric else text

		_enum_editor.add_radio_check_item(text)
		_enum_editor.set_item_metadata(_enum_editor.item_count - 1, value_iter)
		if current_value == value_iter:
			_enum_editor.toggle_item_checked(_enum_editor.item_count - 1)

	_enum_editor.position = DisplayServer.mouse_get_position()
	_enum_editor.popup()


func _finish_editing(save_changes: bool = true) -> void:
	if _edited_row == &"" and _edited_col == &"":
		return

	if save_changes:
		var column := get_column(_edited_col)
		var old_value: Variant = get_cell_value(_edited_row, _edited_col)
		var new_value: Variant = _get_editor_value_for_column(column)
		if typeof(new_value) == column.type:
			if column.is_path_column() and column.property_hint == PROPERTY_HINT_FILE:
				new_value = ResourceUID.path_to_uid(new_value)
			update_cell(_edited_row, _edited_col, new_value)
			cell_edited.emit(_edited_row, _edited_col, old_value, new_value)

	_edited_row = &""
	_edited_col = &""
	_text_editor_line_edit.hide()
	_color_editor.hide()
	queue_redraw()


func _get_editor_value_for_column(column: ColumnConfig) -> Variant:
	if column.is_color_column():
		return _color_editor.color
	elif column.is_resource_column():
		return _resource_editor.edited_resource
	elif column.is_path_column():
		return _path_editor.current_path
	elif column.is_enum_column():
		if _enum_editor_last_idx != -1:
			var new: Variant = _enum_editor.get_item_metadata(_enum_editor_last_idx)
			_enum_editor_last_idx = -1
			return new
		else:
			return null

	var text := _text_editor_line_edit.text
	if column.is_string_column():
		return text
	elif column.is_integer_column() and text.is_valid_int():
		return int(text)
	elif column.is_float_column() and text.is_valid_float():
		return float(text)

	return null


func _get_cell_rect(row: StringName, col: StringName) -> Rect2:
	var row_idx := _order.find(row)
	var col_idx := _column_index(col)
	if row_idx < _visible_rows_range[0] or row_idx >= _visible_rows_range[1] or col_idx < 0:
		return Rect2()
	var cell_x := _get_col_x_pos(col_idx)
	var vis_w := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.)
	var col_cfg := get_column(col)
	if cell_x + col_cfg.current_width <= 0 or cell_x >= vis_w:
		return Rect2()
	var row_y := header_height + (row_idx - _visible_rows_range[0]) * row_height
	return Rect2(cell_x, row_y, col_cfg.current_width, row_height)


func _dispatch_cell_draw(cell_rect: Rect2, row: StringName, col: StringName) -> void:
	var column := get_column(col)
	if is_cell_invalid(row, col):
		_draw_cell_invalid(cell_rect, row, col)
	elif column.is_range_column():
		_draw_cell_progress(cell_rect, row, col)
	elif column.is_boolean_column():
		_draw_cell_bool(cell_rect, row, col)
	elif column.is_color_column():
		_draw_cell_color(cell_rect, row, col)
	elif column.is_resource_column():
		_draw_cell_resource(cell_rect, row, col)
	elif column.is_path_column():
		_draw_cell_path(cell_rect, row, col)
	elif column.is_enum_column():
		_draw_cell_enum(cell_rect, row, col)
	elif column.is_collection_column():
		_draw_cell_collection(cell_rect, row, col)
	else:
		_draw_cell_text(cell_rect, row, col)


func _draw_header_cell(col_idx: int, cell_x: float, vis_w: float) -> void:
	var column := _columns[col_idx]
	draw_line(Vector2(cell_x, 0), Vector2(cell_x, header_height), grid_color)
	draw_line(
		Vector2(cell_x, header_height),
		Vector2(minf(cell_x + column.current_width, vis_w), header_height),
		grid_color,
	)

	var header_text := column.header
	var font_color := default_font_color
	if column.identifier == _filtered_column:
		font_color = header_filter_active_font_color
		header_text += " (" + str(_order.size()) + ")"

	var header_alignment := HORIZONTAL_ALIGNMENT_LEFT
	var x_margin: int = H_ALIGNMENT_MARGINS.get(header_alignment)
	var baseline_y := _get_text_baseline_y(0.0, header_height)
	draw_string(
		font,
		Vector2(cell_x + x_margin, baseline_y),
		header_text,
		header_alignment,
		column.current_width - abs(x_margin),
		font_size,
		font_color,
	)

	if column.identifier == sort_column:
		var text_size := font.get_string_size(header_text, header_alignment, column.current_width, font_size)
		var icon_align := (
			HORIZONTAL_ALIGNMENT_RIGHT
			if header_alignment in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER]
			else HORIZONTAL_ALIGNMENT_LEFT
		)
		draw_string(
			font,
			Vector2(cell_x, header_height / 2.0 + text_size.y / 2.0 - (font_size / 2.0 - 1.0)),
			_icon_sort,
			icon_align,
			column.current_width,
			int(font_size / 1.3),
			font_color,
		)

	var divider_x := cell_x + column.current_width
	if col_idx < _columns.size() - 1 and divider_x < vis_w:
		draw_line(
			Vector2(divider_x, 0),
			Vector2(divider_x, header_height),
			grid_color,
			2.0 if _mouse_over_divider == col_idx else 1.0,
		)


func _draw_header_column_range(col_from: int, col_to: int, start_x: float, clip_left: float, vis_w: float) -> void:
	var hx := start_x
	for col_idx in range(col_from, col_to):
		var col := _columns[col_idx]
		if hx + col.current_width > clip_left and hx < vis_w:
			_draw_header_cell(col_idx, hx, vis_w)
		hx += col.current_width


func _draw_cells_column_range(row: StringName, row_y: float, col_from: int, col_to: int, start_x: float, clip_left: float, vis_w: float) -> void:
	var col_x := start_x
	for col_idx in range(col_from, col_to):
		var col := _columns[col_idx]
		if col_x + col.current_width > clip_left and col_x < vis_w:
			var cell_rect := Rect2(col_x, row_y, col.current_width, row_height)
			draw_line(Vector2(col_x, row_y), Vector2(col_x, row_y + row_height), grid_color)
			_dispatch_cell_draw(cell_rect, row, col.identifier)
			if row == focused_row and col.identifier == focused_col:
				draw_rect(cell_rect.grow_individual(-1, -1, -2, -2), selected_cell_back_color, false, 2.0)
		col_x += col.current_width
	if col_to == _columns.size() and col_x <= vis_w and col_x > clip_left:
		draw_line(Vector2(col_x, row_y), Vector2(col_x, row_y + row_height), grid_color)


func _draw_cell_progress(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: float = get_cell_value(row, col)
	var range_cfg := get_column(col).range_config
	var progress: float = inverse_lerp(range_cfg.get(&"min"), range_cfg.get(&"max"), cell_value)
	var progress_color := _get_interpolated_three_colors(progress_bar_start_color, progress_bar_middle_color, progress_bar_end_color, progress)

	var bar := rect.grow(-2.0 * EditorThemeUtils.scale)
	var fill := Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y))

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_CENTER)
	var numeric_text := str(snappedf(cell_value, 0.001))
	var display_text := _get_display_text(numeric_text, font, rect.size.x - absf(x_margin_val))
	var text_width := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_pos := Vector2(rect.position.x + (rect.size.x - text_width) / 2.0, _get_text_baseline_y(rect.position.y))
	var fill_width: float = maxf(0.001, fill.position.x + fill.size.x - text_pos.x - abs(x_margin_val) + 5 * EditorThemeUtils.scale)

	draw_rect(bar, progress_background_color)
	draw_string(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - abs(x_margin_val), font_size, progress_text_color_light)
	draw_rect(fill, progress_color)
	@warning_ignore("integer_division")
	draw_string_outline(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, fill_width, font_size, font_size / 3, progress_color)
	draw_string(font, text_pos, display_text, HORIZONTAL_ALIGNMENT_LEFT, fill_width, font_size, Color.BLACK)
	draw_rect(bar, progress_border_color, false, 1.0 * EditorThemeUtils.scale)


func _draw_cell_bool(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	if cell_value is not bool:
		_draw_cell_text(rect, row, col)
		return

	var icon_name := &"checked" if (cell_value as bool) else &"unchecked"
	var icon: Texture2D = get_theme_icon(icon_name, &"CheckBox")
	if icon == null:
		return

	var inner := rect.grow(-2.0)
	var tex_size := icon.get_size()
	var pos := inner.position + (inner.size - tex_size) / 2.0
	draw_texture(icon, pos)


func _draw_cell_color(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	if cell_value is not Color:
		_draw_cell_text(rect, row, col)
		return

	var color: Color = cell_value
	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var border_alpha := 0.65 if color.a < 0.25 else 0.35

	if color.a < 1.0:
		var tile := 6.0
		var x0 := inner.position.x
		var y0 := inner.position.y
		var x1 := inner.end.x
		var y1 := inner.end.y
		var y := y0
		var row_i := 0
		while y < y1:
			var x := x0
			var col_i := 0
			while x < x1:
				var bg := Color(0, 0, 0, 0.10) if ((row_i + col_i) % 2) == 0 else Color(1, 1, 1, 0.10)
				draw_rect(Rect2(Vector2(x, y), Vector2(min(tile, x1 - x), min(tile, y1 - y))), bg, true)
				x += tile
				col_i += 1
			y += tile
			row_i += 1

	draw_rect(inner, color, true)
	draw_rect(inner, Color(1, 1, 1, border_alpha), false, 1.0)


func _draw_cell_resource(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	if cell_value is not Resource:
		_draw_cell_text(rect, row, col, tr("<empty>"))
		return

	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var res: Resource = cell_value
	var label := "<" + res.resource_path.get_file() + ">"
	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var thumb_width := 0.0
	var texture: Texture2D = res if res is Texture2D else _get_or_queue_thumbnail(
		res.resource_path,
		ClassUtils.get_type_name(res),
	)
	if texture != null:
		var thumb_rect := _fit_texture_rect(texture, inner, true)
		thumb_rect.position.x += x_margin_val
		thumb_width = thumb_rect.size.x
		_draw_filtered_texture_rect(texture, thumb_rect)

	var text_rect := inner.grow_individual(-thumb_width - x_margin_val, 0, 0, 0)
	_draw_cell_text(text_rect, row, col, label)


func _draw_cell_path(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	var is_invalid_uid: bool = cell_value == INVALID_UID
	if not get_column(col).property_hint == PROPERTY_HINT_FILE:
		_draw_cell_text(rect, row, col)
		return

	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var thumb_width := 0.0
	var texture: Texture2D
	if is_invalid_uid:
		texture = get_theme_icon(&"FileDead", &"EditorIcons")
	elif ResourceLoader.exists(cell_value):
		texture = _get_or_queue_thumbnail(cell_value)

	if texture != null:
		var thumb_rect := _fit_texture_rect(texture, inner, true)
		thumb_rect.position.x += x_margin_val
		thumb_width = thumb_rect.size.x
		_draw_filtered_texture_rect(texture, thumb_rect)

	var text_rect := inner.grow_individual(-thumb_width - x_margin_val, 0, 0, 0)
	if is_invalid_uid:
		_draw_cell_text(text_rect, row, col, "", get_theme_color(&"error_color", &"Editor"))
	else:
		_draw_cell_text(text_rect, row, col)


func _draw_filtered_texture_rect(texture: Texture2D, rect: Rect2) -> void:
	var ratio := rect.size / texture.get_size()
	if minf(ratio.x, ratio.y) > 1.5 * EditorInterface.get_editor_scale() and rect.end.x > _get_frozen_width():
		if texture is AtlasTexture:
			RenderingServer.canvas_item_add_texture_rect_region(_pixelated_canvas_rid, rect, texture.get_rid(), texture.region)
		else:
			RenderingServer.canvas_item_add_texture_rect(_pixelated_canvas_rid, rect, texture.get_rid())
	else:
		draw_texture_rect(texture, rect, false)


func _draw_cell_text(rect: Rect2, row: StringName, col: StringName, text_override: String = "", color_override: Color = Color.TRANSPARENT) -> void:
	var cell_value := str(get_cell_value(row, col))

	var column := get_column(col)
	var text_font: Font = font
	var h_alignment := column.h_alignment
	if column.custom_font:
		text_font = column.custom_font
	elif column.is_path_column():
		text_font = mono_font

	var full_text := text_override if text_override else cell_value
	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(h_alignment)
	var baseline_y := _get_text_baseline_y(rect.position.y)
	var display_text := _get_display_text(full_text, text_font, rect.size.x - absf(x_margin_val))
	var text_color := default_font_color
	if color_override != Color.TRANSPARENT:
		text_color = color_override
	elif column.custom_font_color:
		text_color = column.custom_font_color

	draw_string(
		text_font,
		Vector2(rect.position.x + x_margin_val, baseline_y),
		display_text,
		h_alignment,
		max(0.001, rect.size.x - abs(x_margin_val)),
		font_size,
		text_color,
	)


func _draw_cell_enum(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	var column := get_column(col)
	var value_str := ""

	if not column.is_numeric_column():
		value_str = str(cell_value)
	else:
		var int_value := cell_value as int
		var map := column.enum_values_map
		value_str = "%s:%s" % [map[int_value], int_value] if map.has(int_value) else "?:%d" % int_value

	var text_font: Font = column.custom_font if column.custom_font else font
	var h_alignment := HORIZONTAL_ALIGNMENT_CENTER
	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(h_alignment)
	var display_text := _get_display_text(value_str, text_font, rect.size.x - absf(x_margin_val))
	var color := Color(value_str.hash()) + Color(0.25, 0.25, 0.25, 1.0)
	var baseline_y := _get_text_baseline_y(rect.position.y)
	draw_string(
		text_font,
		Vector2(rect.position.x + x_margin_val, baseline_y),
		display_text,
		h_alignment,
		rect.size.x - abs(x_margin_val),
		font_size,
		color,
	)


func _draw_cell_invalid(rect: Rect2, _row: StringName, _col: StringName) -> void:
	draw_rect(rect, invalid_cell_color, true)


func _draw_cell_collection(rect: Rect2, row: StringName, col: StringName) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	if cell_value is not Array and cell_value is not Dictionary:
		_draw_cell_text(rect, row, col)
	else:
		var column := get_column(col)
		_draw_cell_text(rect, row, col, _format_collection_text(cell_value, column))


func _format_collection_text(collection: Variant, column: ColumnConfig) -> String:
	var is_dict := collection is Dictionary
	var items: Array = (collection as Dictionary).keys() if is_dict else (collection as Array)
	var keys_map: Dictionary = column.enum_keys_map if column.is_enum_key_dictionary_column() else { }
	var values_map: Dictionary = column.enum_values_map if column.is_enum_value_dictionary_column() or column.is_enum_array_column() else { }
	var parts: Array[String] = []
	for i in mini(items.size(), 3):
		if is_dict:
			var key: Variant = items[i]
			var val: Variant = (collection as Dictionary)[key]
			parts.append(
				"%s: %s" % [
					_format_collection_elem(key, keys_map),
					_format_collection_elem(val, values_map),
				],
			)
		else:
			parts.append(_format_collection_elem(items[i], values_map))

	var result := ", ".join(parts)
	var remaining := items.size() - 3
	if remaining > 0:
		result += tr(" and {remaining} more").format({ &"remaining": remaining })
	return "{ %s }" % result if is_dict else "[%s]" % result


static func _format_collection_elem(elem: Variant, enum_map: Dictionary = { }) -> String:
	if elem is Resource:
		return "<%s>" % (elem as Resource).resource_path.get_file()
	if elem is Array:
		return "Array(%d)" % (elem as Array).size()
	if elem is Dictionary:
		return "Dict(%d)" % (elem as Dictionary).size()
	if elem is int and not enum_map.is_empty():
		var int_elem := elem as int
		return enum_map[int_elem] if enum_map.has(int_elem) else "?:%d" % int_elem
	return str(elem)


func _get_display_text(cell_value: String, text_font: Font, max_width: float) -> String:
	var text_size := text_font.get_string_size(cell_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if text_size.x <= max_width:
		return cell_value

	var ellipsis := "..."
	var ellipsis_width := text_font.get_string_size(ellipsis, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_text_width := max_width - ellipsis_width

	if max_text_width <= 0:
		return ellipsis

	var truncated_text := ""
	for i in range(cell_value.length()):
		var test_text := cell_value.substr(0, i + 1)
		var test_width := text_font.get_string_size(test_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if test_width > max_text_width:
			break
		truncated_text = test_text
	return truncated_text + ellipsis


func _get_interpolated_three_colors(start_color: Color, mid_color: Color, end_color: Color, progress: float) -> Color:
	var clamped_t := clampf(progress, 0.0, 1.0)
	if clamped_t <= 0.5:
		return start_color.lerp(mid_color, clamped_t * 2.0)
	else:
		return mid_color.lerp(end_color, (clamped_t - 0.5) * 2.0)


func _get_or_queue_thumbnail(resource_path: String, type_name: String = "Resource") -> Texture2D:
	if _resource_thumb_cache.has(resource_path):
		return _resource_thumb_cache[resource_path]
	if not _resource_thumb_pending.has(resource_path):
		_resource_thumb_pending[resource_path] = true
		EditorInterface.get_resource_previewer().queue_resource_preview(
			resource_path,
			self,
			&"_on_resource_cell_thumb_ready",
			{ &"resource_path": resource_path, &"class": type_name },
		)
	return null


func _fit_texture_rect(texture: Texture2D, container: Rect2, anchor_to_left := false) -> Rect2:
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


func _start_filtering(col: StringName) -> void:
	if _filtered_column == col and _filter_line_edit.visible:
		return

	var col_idx := _column_index(col)
	var col_x := _get_col_x_pos(col_idx)
	var header_rect := Rect2(col_x, 0, get_column(col).current_width, header_height)
	_filtered_column = col
	_filter_line_edit.position = header_rect.position + Vector2(1, 1)
	_filter_line_edit.size = header_rect.size - Vector2(2, 2)
	_filter_line_edit.text = ""
	_filter_line_edit.visible = true
	_filter_line_edit.grab_focus()


func _apply_filter(search_key: String) -> void:
	if not _filter_line_edit.visible:
		return

	_filter_line_edit.visible = false
	if _filtered_column == &"":
		return

	if search_key.is_empty():
		_order = _base_order.duplicate()
		_filtered_column = &""
	else:
		_order.clear()
		var filtered_col_idx := _column_index(_filtered_column)
		var key_lower := search_key.to_lower()
		for row in _base_order:
			var row_data: Array = _rows.get(row, [])
			if filtered_col_idx < row_data.size() and row_data[filtered_col_idx] != null:
				var cell_value := str(row_data[filtered_col_idx]).to_lower()
				if cell_value.contains(key_lower):
					_order.append(row)

	_v_scroll.value = 0

	# Keep selection only for rows still visible after filter
	var kept: Array[StringName] = []
	for row in selected_rows:
		if _order.has(row):
			kept.append(row)
	selected_rows = kept
	if not _order.has(focused_row):
		focused_row = &""

	sort_column = &""

	_update_scrollbars()
	queue_redraw()


func _key_for_sort(value: Variant, column: ColumnConfig) -> Variant:
	if value == null:
		return null
	if column.is_range_column() or column.is_numeric_column():
		return float(value)
	if column.is_boolean_column():
		return (1 if bool(value) else 0)
	if column.is_color_column():
		var c := Color(value)
		return [c.h, c.s, c.v, c.a]
	if column.is_resource_column():
		if value is Resource:
			var r: Resource = value
			if r.resource_path != "":
				return r.resource_path.get_file()
			return str(r.get_class()) + ":" + str(r.get_instance_id())
		return str(value)
	return str(value)


func _get_col_at_x(x: float) -> int:
	var frozen_w := _get_frozen_width()
	var col_x := 0.0

	if x < frozen_w:
		for col_idx in n_frozen_columns:
			if x < col_x + _columns[col_idx].current_width:
				return col_idx
			col_x += _columns[col_idx].current_width
		return -1

	col_x = frozen_w - _h_scroll_position
	for col_idx in range(n_frozen_columns, _columns.size()):
		var col_end := col_x + _columns[col_idx].current_width
		if x >= maxf(col_x, frozen_w) and x < col_end:
			return col_idx
		col_x = col_end
	return -1


func _get_row_at_y(y: float) -> int:
	if y < header_height or row_height <= 0:
		return -1
	var row: int = floori((y - header_height) / row_height) + _visible_rows_range[0]
	return row if row < _order.size() else -1


func _get_text_baseline_y(cell_y: float, cell_height: float = -1.0) -> float:
	var h := cell_height if cell_height >= 0.0 else row_height
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	return cell_y + (h + ascent - descent) / 2.0


func _get_frozen_width() -> float:
	var w := 0.0
	for i in mini(n_frozen_columns, _columns.size()):
		w += _columns[i].current_width
	return w


func _get_col_x_pos(col_idx: int) -> float:
	if col_idx < n_frozen_columns:
		var x := 0.0
		for i in col_idx:
			x += _columns[i].current_width
		return x
	else:
		var x := _get_frozen_width() - _h_scroll_position
		for i in range(n_frozen_columns, col_idx):
			x += _columns[i].current_width
		return x


func _check_mouse_over_divider(mouse_pos: Vector2) -> void:
	_mouse_over_divider = -1
	mouse_default_cursor_shape = CURSOR_ARROW

	if mouse_pos.y < header_height:
		for col_idx in _columns.size():
			var divider_x := _get_col_x_pos(col_idx) + _columns[col_idx].current_width
			if col_idx >= n_frozen_columns and divider_x <= _get_frozen_width():
				continue
			var divider_rect := Rect2(divider_x - _divider_width / 2.0, 0, _divider_width, header_height)
			if divider_rect.has_point(mouse_pos):
				_mouse_over_divider = col_idx
				mouse_default_cursor_shape = CURSOR_HSIZE
				break

	queue_redraw()


func _update_tooltip(mouse_pos: Vector2) -> void:
	var new_row: StringName = &""
	var new_col: StringName = &""
	var new_tooltip := ""

	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx == -1:
		if new_row != _tooltip_row or new_col != _tooltip_col:
			_tooltip_row = new_row
			_tooltip_col = new_col
			self.tooltip_text = new_tooltip
		return

	var col := _columns[col_idx].identifier
	if mouse_pos.y < header_height:
		new_tooltip = get_column(col).header
		new_row = &"<header>"
		new_col = col
	else:
		var row_idx := _get_row_at_y(mouse_pos.y)
		if row_idx >= 0:
			new_row = _order[row_idx]
			new_col = col
			var column := get_column(col)
			if not column.is_range_column() and not column.is_boolean_column():
				new_tooltip = str(get_cell_value(new_row, col))

	if new_row != _tooltip_row or new_col != _tooltip_col:
		_tooltip_row = new_row
		_tooltip_col = new_col
		self.tooltip_text = new_tooltip


func _is_clicking_progress_bar(mouse_pos: Vector2) -> bool:
	var row_idx := _get_row_at_y(mouse_pos.y)
	var col_idx := _get_col_at_x(mouse_pos.x)
	if row_idx < 0 or col_idx < 0:
		return false
	return _columns[col_idx].is_range_column()


func _toggle_checkbox(row: StringName, col: StringName) -> void:
	var old_val := bool(get_cell_value(row, col))
	var new_val := !old_val
	update_cell(row, col, new_val)
	cell_edited.emit(row, col, old_val, new_val)


func _ensure_row_visible(row: StringName) -> void:
	var row_idx := _order.find(row)
	if row_idx < 0 or _order.is_empty() or row_height == 0 or not _v_scroll.visible:
		return

	var visible_area_height: float = size.y - header_height - (_h_scroll.size.y if _h_scroll.visible else 0.0)
	var num_visible_rows := floori(visible_area_height / row_height)
	var first_fully_visible: int = _visible_rows_range[0]

	if row_idx < first_fully_visible:
		_v_scroll.value = row_idx * row_height
	elif row_idx >= first_fully_visible + num_visible_rows:
		_v_scroll.value = (row_idx - num_visible_rows + 1) * row_height

	_v_scroll.value = clamp(_v_scroll.value, 0, _v_scroll.max_value)


func _ensure_col_visible(col: StringName) -> void:
	var col_idx := _column_index(col)
	if _columns.is_empty() or col_idx < 0 or not _h_scroll.visible:
		return
	if col_idx < n_frozen_columns:
		return

	var col_scroll_pos := 0.0
	for i in range(n_frozen_columns, col_idx):
		col_scroll_pos += _columns[i].current_width
	var col_scroll_end := col_scroll_pos + _columns[col_idx].current_width
	var visible_scrollable_w := _h_scroll.page

	if col_scroll_pos < _h_scroll.value:
		_h_scroll.value = col_scroll_pos
	elif col_scroll_end > _h_scroll.value + visible_scrollable_w:
		_h_scroll.value = (
			col_scroll_end - visible_scrollable_w
			if _columns[col_idx].current_width <= visible_scrollable_w
			else col_scroll_pos
		)
	_h_scroll.value = clamp(_h_scroll.value, 0.0, _h_scroll.max_value)


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	_apply_pan_axis(event.delta.y, _v_scroll, Vector2.AXIS_Y)
	if abs(event.delta.x) > 0.05:
		_apply_pan_axis(event.delta.x, _h_scroll, Vector2.AXIS_X)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var m_pos := event.position

	if _dragging_progress and _progress_drag_row != &"" and _progress_drag_col != &"":
		_handle_progress_drag(m_pos)
	elif _resizing_column != &"":
		var delta_x: float = m_pos.x - _resizing_start_pos
		var new_width: float = max(
			_resizing_start_width + delta_x,
			get_column(_resizing_column).minimum_width,
		)
		get_column(_resizing_column).current_width = new_width
		_update_scrollbars()
		column_resized.emit(_resizing_column, new_width)
		queue_redraw()
	else:
		_check_mouse_over_divider(m_pos)
		_update_tooltip(m_pos)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_left_press(event)
			MOUSE_BUTTON_RIGHT:
				_handle_right_click(event.position)
			MOUSE_BUTTON_WHEEL_UP:
				_v_scroll.value = maxf(0.0, _v_scroll.value - _v_scroll.step)
			MOUSE_BUTTON_WHEEL_DOWN:
				_v_scroll.value = minf(_v_scroll.max_value, _v_scroll.value + _v_scroll.step)
			MOUSE_BUTTON_WHEEL_LEFT:
				_h_scroll.value = maxf(0.0, _h_scroll.value - _v_scroll.step)
			MOUSE_BUTTON_WHEEL_RIGHT:
				_h_scroll.value = minf(_h_scroll.max_value, _h_scroll.value + _v_scroll.step)
	else:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_left_release()


func _handle_left_press(event: InputEventMouseButton) -> void:
	var m_pos := event.position
	var is_double_click := (
		_click_count == 1
		and _double_click_timer.time_left > 0
		and _last_click_pos.distance_to(m_pos) < _click_position_threshold
	)

	if is_double_click:
		_click_count = 0
		_double_click_timer.stop()
		if m_pos.y < header_height:
			_handle_header_double_click(m_pos)
		else:
			_handle_double_click(m_pos)
		return

	_click_count = 1
	_last_click_pos = m_pos
	_double_click_timer.start()

	if m_pos.y < header_height:
		if not _filter_line_edit.visible:
			_handle_header_click(m_pos)
	else:
		_handle_checkbox_click(m_pos)
		_handle_cell_click(m_pos, event)
		if _is_clicking_progress_bar(m_pos):
			var row_idx := _get_row_at_y(m_pos.y)
			var col_idx := _get_col_at_x(m_pos.x)
			_progress_drag_row = _order[row_idx]
			_progress_drag_col = _columns[col_idx].identifier
			_dragging_start_value = get_cell_value(_progress_drag_row, _progress_drag_col)
			_dragging_progress = true

	if _mouse_over_divider >= 0:
		_resizing_column = _columns[_mouse_over_divider].identifier
		_resizing_start_pos = int(m_pos.x)
		_resizing_start_width = int(get_column(_resizing_column).current_width)


func _handle_left_release() -> void:
	if _dragging_progress:
		var new_val: Variant = get_cell_value(_progress_drag_row, _progress_drag_col)
		update_cell(_progress_drag_row, _progress_drag_col, new_val)
		cell_edited.emit(_progress_drag_row, _progress_drag_col, _dragging_start_value, new_val)
	_resizing_column = &""
	_dragging_progress = false
	_progress_drag_row = &""
	_progress_drag_col = &""


func _handle_progress_drag(mouse_pos: Vector2) -> void:
	if _progress_drag_row == &"" or _progress_drag_col == &"":
		return

	var margin := 4.0
	var bar_x := _get_col_x_pos(_column_index(_progress_drag_col)) + margin
	var bar_w := get_column(_progress_drag_col).current_width - margin * 2.0
	if bar_w <= 0:
		return

	var range_cfg := get_column(_progress_drag_col).range_config
	var weight := (mouse_pos.x - bar_x) / bar_w
	var new_progress: float = snappedf(
		lerpf(range_cfg.get(&"min"), range_cfg.get(&"max"), weight),
		range_cfg.get(&"step"),
	)
	if not range_cfg.has(&"or_greater"):
		new_progress = min(new_progress, range_cfg.get(&"max"))
	if not range_cfg.has(&"or_less"):
		new_progress = max(new_progress, range_cfg.get(&"min"))

	var col_idx := _column_index(_progress_drag_col)
	if _rows.has(_progress_drag_row) and col_idx < _rows[_progress_drag_row].size():
		_rows[_progress_drag_row][col_idx] = new_progress
		progress_changed.emit(_progress_drag_row, _progress_drag_col, new_progress)
		queue_redraw()


func _handle_checkbox_click(mouse_pos: Vector2) -> bool:
	var row_idx := _get_row_at_y(mouse_pos.y)
	var col_idx := _get_col_at_x(mouse_pos.x)
	if row_idx < 0 or col_idx == -1:
		return false
	if not _columns[col_idx].is_boolean_column():
		return false

	var row := _order[row_idx]
	var col := _columns[col_idx].identifier
	var rect := _get_cell_rect(row, col)
	var icon: Texture2D = get_theme_icon(&"checked", &"CheckBox")
	var icon_rect := Rect2(rect.get_center() - icon.get_size() / 2, icon.get_size())
	if icon_rect.has_point(mouse_pos):
		_toggle_checkbox(row, col)
		return true
	return false


func _handle_cell_click(mouse_pos: Vector2, event: InputEventMouseButton) -> void:
	if _edited_col != &"":
		var column := get_column(_edited_col)
		var save := not (column.is_resource_column() or column.is_path_column() or column.is_enum_column())
		_finish_editing(save)

	var clicked_idx := _get_row_at_y(mouse_pos.y)
	var clicked_col_idx := _get_col_at_x(mouse_pos.x)
	if clicked_idx < 0 or clicked_col_idx == -1:
		return

	var clicked_row := _order[clicked_idx]
	var clicked_col := _columns[clicked_col_idx].identifier
	focused_row = clicked_row
	focused_col = clicked_col

	if event.is_shift_pressed() and _anchor_row != &"":
		var anchor_idx := _order.find(_anchor_row)
		selected_rows.clear()
		for i in range(mini(anchor_idx, clicked_idx), maxi(anchor_idx, clicked_idx) + 1):
			selected_rows.append(_order[i])
	elif event.is_ctrl_pressed() or event.is_meta_pressed():
		if selected_rows.has(clicked_row):
			selected_rows.erase(clicked_row)
		else:
			selected_rows.append(clicked_row)
		_anchor_row = clicked_row
	else:
		selected_rows.clear()
		selected_rows.append(clicked_row)
		_anchor_row = clicked_row

	cell_selected.emit(focused_row, focused_col)
	_ensure_col_visible(focused_col)

	if selected_rows.size() > 1:
		multiple_rows_selected.emit(selected_rows)

	queue_redraw()


func _handle_right_click(mouse_pos: Vector2) -> void:
	var clicked_idx := _get_row_at_y(mouse_pos.y)
	var clicked_col_idx := _get_col_at_x(mouse_pos.x)
	var clicked_row := _order[clicked_idx] if clicked_idx >= 0 else &""
	var clicked_col := _columns[clicked_col_idx].identifier if clicked_col_idx >= 0 else &""

	if selected_rows.size() <= 1:
		set_selected_cell(clicked_row, clicked_col)

	cell_right_selected.emit(clicked_row, clicked_col, get_global_mouse_position())


func _handle_double_click(mouse_pos: Vector2) -> void:
	if mouse_pos.y < header_height:
		return

	var row_idx := _get_row_at_y(mouse_pos.y)
	if row_idx >= 0:
		var row := _order[row_idx]
		var col_idx := _get_col_at_x(mouse_pos.x)
		if col_idx != -1:
			var col := _columns[col_idx].identifier
			if not (selected_rows.size() == 1 and selected_rows[0] == row and focused_row == row and focused_col == col):
				set_selected_cell(row, col)
			_start_cell_editing(row, col)


func _handle_header_click(mouse_pos: Vector2) -> void:
	for col_idx in _columns.size():
		var col_x := _get_col_x_pos(col_idx)
		if (
			mouse_pos.x >= col_x + _divider_width / 2.0
			and mouse_pos.x < col_x + _columns[col_idx].current_width - _divider_width / 2.0
		):
			var col := _columns[col_idx].identifier
			_finish_editing(false)
			sort_ascending = not sort_ascending if sort_column == col else true
			ordering_data(col, sort_ascending)
			header_clicked.emit(col)
			break


func _handle_header_double_click(mouse_pos: Vector2) -> void:
	_finish_editing(false)
	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx != -1:
		var col := _columns[col_idx].identifier
		_ensure_col_visible(col)
		_start_filtering(col)


func _handle_key_input(event: InputEventKey) -> void:
	if _text_editor_line_edit.visible:
		if event.keycode == KEY_ESCAPE:
			_finish_editing(false)
			get_viewport().set_input_as_handled()
		return

	var keycode := event.keycode
	var is_shift := event.is_shift_pressed()
	var is_ctrl_cmd := event.is_ctrl_pressed() or event.is_meta_pressed()
	var is_cell_focused := focused_row != &"" and focused_col != &""

	var focused_idx := _order.find(focused_row) if focused_row != &"" else -1
	var focused_col_idx := _column_index(focused_col) if focused_col != &"" else -1
	var new_idx := focused_idx
	var new_col_idx := focused_col_idx

	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if not is_cell_focused:
				return
			if get_column(focused_col).is_boolean_column():
				_toggle_checkbox(focused_row, focused_col)
			else:
				_start_cell_editing(focused_row, focused_col)
			_finalize_key_operation()
			return
		KEY_A:
			if is_ctrl_cmd and not _order.is_empty():
				select_all_rows()
				multiple_rows_selected.emit(selected_rows)
				_finalize_key_operation()
			return
		KEY_ESCAPE:
			if selected_rows.is_empty() and focused_row == &"":
				return
			set_selected_cell(&"", &"")
			_finalize_key_operation()
			return
		KEY_HOME:
			if _order.is_empty():
				return
			new_idx = 0
			new_col_idx = 0 if not _columns.is_empty() else -1
		KEY_END:
			if _order.is_empty():
				return
			new_idx = _order.size() - 1
			new_col_idx = _columns.size() - 1 if not _columns.is_empty() else -1
		KEY_UP:
			if not is_cell_focused:
				return
			new_idx = maxi(0, focused_idx - 1)
		KEY_DOWN:
			if not is_cell_focused:
				return
			new_idx = mini(_order.size() - 1, focused_idx + 1)
		KEY_LEFT:
			if not is_cell_focused:
				return
			new_col_idx = maxi(0, focused_col_idx - 1)
		KEY_RIGHT:
			if not is_cell_focused:
				return
			new_col_idx = mini(_columns.size() - 1, focused_col_idx + 1)
		KEY_PAGEUP:
			if not is_cell_focused:
				return
			new_idx = maxi(0, focused_idx - _page_row_count())
		KEY_PAGEDOWN:
			if not is_cell_focused:
				return
			new_idx = mini(_order.size() - 1, focused_idx + _page_row_count())
		KEY_SPACE:
			if not is_cell_focused or not is_ctrl_cmd:
				return
			if selected_rows.has(focused_row):
				selected_rows.erase(focused_row)
			else:
				selected_rows.append(focused_row)
			_anchor_row = focused_row
			cell_selected.emit(focused_row, focused_col)
			_finalize_key_operation()
			return
		_:
			return

	var new_row := _order[new_idx] if new_idx >= 0 and new_idx < _order.size() else &""
	var new_col := _columns[new_col_idx].identifier if new_col_idx >= 0 and new_col_idx < _columns.size() else &""
	var old_row := focused_row
	var old_col := focused_col
	focused_row = new_row
	focused_col = new_col

	_update_selection_after_navigation(old_row, focused_idx, is_shift, is_ctrl_cmd)

	if focused_row != &"":
		_ensure_row_visible(focused_row)
		_ensure_col_visible(focused_col)

	if old_row != focused_row or old_col != focused_col:
		cell_selected.emit(focused_row, focused_col)

	_finalize_key_operation()


func _page_row_count() -> int:
	return maxi(1, floori((size.y - header_height) / row_height) if row_height > 0 else 10)


func _update_selection_after_navigation(old_row: StringName, _old_idx: int, is_shift: bool, is_ctrl_cmd: bool) -> void:
	if is_shift:
		if _anchor_row == &"":
			_anchor_row = old_row if old_row != &"" else (_order[0] if not _order.is_empty() else &"")
		if focused_row == &"":
			return
		var anchor_idx := _order.find(_anchor_row)
		var focus_idx := _order.find(focused_row)
		selected_rows.clear()
		for i in range(mini(anchor_idx, focus_idx), maxi(anchor_idx, focus_idx) + 1):
			if i >= 0 and i < _order.size():
				selected_rows.append(_order[i])
		if selected_rows.size() > 1:
			multiple_rows_selected.emit(selected_rows)
	elif is_ctrl_cmd:
		pass
	else:
		if focused_row != &"":
			selected_rows.clear()
			selected_rows.append(focused_row)
			_anchor_row = focused_row
		else:
			selected_rows.clear()
			_anchor_row = &""


func _finalize_key_operation() -> void:
	queue_redraw()
	get_viewport().set_input_as_handled()


func _apply_pan_axis(delta: float, scroll: ScrollBar, axis: int) -> void:
	if not scroll.visible:
		return
	if sign(delta) != sign(_pan_delta_accumulation[axis]):
		_pan_delta_accumulation[axis] = 0.0
	_pan_delta_accumulation[axis] += delta
	if abs(_pan_delta_accumulation[axis]) >= 1.0:
		scroll.value += sign(_pan_delta_accumulation[axis]) * _v_scroll.step
		_pan_delta_accumulation[axis] -= sign(_pan_delta_accumulation[axis])

#endregion

#region SIGNAL CALLBACKS

func _on_resized() -> void:
	_update_scrollbars()
	queue_redraw()


func _on_text_editor_text_submitted(_text: String) -> void:
	_finish_editing(true)


func _on_text_editor_focus_exited() -> void:
	_finish_editing(true)


func _on_color_editor_color_selected(_color: Color) -> void:
	_finish_editing(true)


func _on_color_editor_canceled() -> void:
	_finish_editing(false)


func _on_resource_editor_resource_changed(_res: Resource) -> void:
	_finish_editing(true)


func _on_path_editor_path_selected(path: String) -> void:
	var column := get_column(focused_col)
	if column and column.property_hint in [PROPERTY_HINT_DIR]:
		_path_editor.current_path = path.path_join("")
	_finish_editing(true)


func _on_enum_editor_index_pressed(idx: int) -> void:
	_enum_editor_last_idx = idx
	_finish_editing(true)


func _on_enum_editor_popup_hide() -> void:
	await get_tree().create_timer(0.05).timeout
	_finish_editing(false)


func _on_double_click_timeout() -> void:
	_click_count = 0


func _on_h_scroll_changed(value: float) -> void:
	_h_scroll_position = int(value)
	if _text_editor_line_edit.visible:
		_finish_editing(false)
	queue_redraw()


func _on_v_scroll_value_changed(value: float) -> void:
	if row_height > 0:
		_visible_rows_range[0] = floori(value / row_height)
		_visible_rows_range[1] = _visible_rows_range[0] + floori((size.y - header_height) / row_height) + 1
		_visible_rows_range[1] = min(_visible_rows_range[1], _order.size())
	else:
		_visible_rows_range = [0, _order.size()]

	if _text_editor_line_edit.visible:
		_finish_editing(false)
	queue_redraw()


func _on_filter_focus_exited() -> void:
	if _filter_line_edit.visible:
		_apply_filter(_filter_line_edit.text)


func _on_editor_settings_changed() -> void:
	var changed_settings := EditorInterface.get_editor_settings().get_changed_settings()
	for setting in changed_settings:
		if (
			setting in ["interface/editor/main_font_size", "interface/editor/display_scale"]
			or setting.begins_with("interface/theme")
		):
			set_native_theming(3)


func _on_resource_previewer_preview_invalidated(path: String) -> void:
	if _resource_thumb_cache.has(path):
		_resource_thumb_cache.erase(path)


func _on_resource_cell_thumb_ready(resource_path: String, preview: Texture2D, thumbnail_preview: Texture2D, userdata: Variant) -> void:
	if typeof(userdata) != TYPE_DICTIONARY:
		return

	var tex: Texture2D = thumbnail_preview if thumbnail_preview else preview

	if not tex:
		tex = AnyIcon.get_class_icon(userdata.get(&"class", &"Resource"))

	_resource_thumb_cache[resource_path] = tex
	_resource_thumb_pending.erase(resource_path)

	await get_tree().create_timer(0.01).timeout
	queue_redraw()

#endregion

class ColumnConfig:
	var identifier: StringName
	var header: String
	var type: Variant.Type
	var property_hint: PropertyHint
	var hint_string: String
	var class_string: String
	var h_alignment: HorizontalAlignment
	var custom_font_color: Color
	var custom_font: Font
	var minimum_width: float:
		set(value):
			minimum_width = value
			current_width = current_width
	var current_width: float:
		set(value):
			current_width = max(value, minimum_width)
	var enum_values_map: Dictionary[int, String]:
		get:
			if not _enum_values_map_ready:
				enum_values_map = _parse_enum_hint_string(_get_enum_value_hint_string())
				_enum_values_map_ready = true
			return enum_values_map
	var enum_keys_map: Dictionary[int, String]:
		get:
			if not _enum_keys_map_ready:
				enum_keys_map = _parse_enum_hint_string(_get_enum_key_hint_string())
				_enum_keys_map_ready = true
			return enum_keys_map
	var range_config: Dictionary[StringName, Variant]:
		get:
			if not _range_config_ready:
				range_config = _compute_range_config()
				_range_config_ready = true
			return range_config

	var _range_config_ready := false
	var _enum_values_map_ready := false
	var _enum_keys_map_ready := false


	func _init(p_identifier: StringName, p_header: String, p_type: Variant.Type, p_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		identifier = p_identifier
		header = p_header
		type = p_type
		h_alignment = p_alignment
		if self.is_numeric_column():
			h_alignment = HORIZONTAL_ALIGNMENT_RIGHT


	func is_path_column() -> bool:
		var is_filesystem_hint := property_hint in [
			PROPERTY_HINT_FILE,
			PROPERTY_HINT_FILE_PATH,
			PROPERTY_HINT_DIR,
		]
		return type == TYPE_STRING and is_filesystem_hint


	func is_range_column() -> bool:
		return type in [TYPE_FLOAT, TYPE_INT] and property_hint == PROPERTY_HINT_RANGE


	func is_boolean_column() -> bool:
		return type == TYPE_BOOL


	func is_string_column() -> bool:
		return type == TYPE_STRING


	func is_numeric_column() -> bool:
		return type in [TYPE_INT, TYPE_FLOAT]


	func is_integer_column() -> bool:
		return type == TYPE_INT


	func is_float_column() -> bool:
		return type == TYPE_FLOAT


	func is_color_column() -> bool:
		return type == TYPE_COLOR


	func is_enum_column() -> bool:
		return property_hint == PROPERTY_HINT_ENUM


	func is_resource_column() -> bool:
		return type == TYPE_OBJECT and property_hint == PROPERTY_HINT_RESOURCE_TYPE


	func is_array_column() -> bool:
		return type == TYPE_ARRAY


	func is_dictionary_column() -> bool:
		return type == TYPE_DICTIONARY


	func is_collection_column() -> bool:
		return is_array_column() or is_dictionary_column()


	func is_enum_array_column() -> bool:
		return is_array_column() and hint_string and _is_enum_collection_hint(hint_string)


	func is_enum_key_dictionary_column() -> bool:
		return is_dictionary_column() and hint_string and _is_enum_collection_hint(_dict_key_hint_part())


	func is_enum_value_dictionary_column() -> bool:
		return is_dictionary_column() and hint_string and _is_enum_collection_hint(_dict_value_hint_part())


	func _get_enum_value_hint_string() -> String:
		if is_array_column():
			return hint_string.split(":", true, 1)[1]
		if is_dictionary_column():
			return _dict_value_hint_part().split(":", true, 1)[1]
		return hint_string


	func _get_enum_key_hint_string() -> String:
		return _dict_key_hint_part().split(":", true, 1)[1]


	func _dict_key_hint_part() -> String:
		return hint_string.split(";", true, 1)[0]


	func _dict_value_hint_part() -> String:
		return hint_string.split(";", true, 1)[1]


	func _is_enum_collection_hint(hint: String) -> bool:
		return hint.length() > 3 and hint[1] == "/" and int(hint[2]) == PROPERTY_HINT_ENUM


	static func _parse_enum_hint_string(enum_hint_string: String) -> Dictionary[int, String]:
		var map: Dictionary[int, String] = { }
		var next_implicit := 0
		for entry: String in enum_hint_string.split(",", false):
			var colon := entry.rfind(":")
			if colon == -1:
				map[next_implicit] = entry
				next_implicit += 1
			else:
				var explicit_val := entry.substr(colon + 1).to_int()
				map[explicit_val] = entry.substr(0, colon)
				next_implicit = explicit_val + 1
		return map


	func _compute_range_config() -> Dictionary[StringName, Variant]:
		if not is_range_column():
			return { }
		var hint_elements := hint_string.split(",", false)
		var result: Dictionary[StringName, Variant] = {
			&"min": float(hint_elements[0]) if hint_elements.size() > 0 else 0.0,
			&"max": float(hint_elements[1]) if hint_elements.size() > 1 else 1.0,
			&"step": float(hint_elements[2]) if hint_elements.size() > 2 else (0.001 if is_float_column() else 1.0),
		}
		for hint_str in hint_elements.slice(3):
			match hint_str:
				"or_greater":
					result[&"or_greater"] = true
				"or_less":
					result[&"or_less"] = true
		return result
