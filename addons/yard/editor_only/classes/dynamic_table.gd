# MIT License
# Copyright (c) 2025 Giuseppe Pica (jospic)
# https://github.com/jospic/dynamicdatatable

# BEHOLD THE 2000-LINES BEAST.
# Original was probably vibe-coded, but it does the job nonetheless

@tool
extends Control

# Signals
signal cell_selected(row: int, col: int)
signal multiple_rows_selected(selected_row_indices: Array)
signal cell_right_selected(row: int, col: int, mousepos: Vector2)
signal header_clicked(column: int)
signal column_resized(column: int, new_width: float)
signal progress_changed(row: int, col: int, new_value: float)
signal cell_edited(row: int, col: int, old_value: Variant, new_value: Variant)

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ClassUtils := Namespace.ClassUtils
const EditorThemeUtils := Namespace.EditorThemeUtils
const AnyIcon := Namespace.AnyIcon

const H_ALIGNMENT_MARGINS = {
	HORIZONTAL_ALIGNMENT_LEFT: 5,
	HORIZONTAL_ALIGNMENT_CENTER: 0,
	HORIZONTAL_ALIGNMENT_RIGHT: -5,
}
const CELL_INVALID := "<INVALID>"

# Theming properties
@export_group("Custom YARD Properties")
@export var base_height_from_line_edit: bool = false
@export_group("Default color")
@export var default_font_color: Color = Color(1.0, 1.0, 1.0)
@export_group("Header")
#@export var headers: Array[String] = []
@export var header_height: float = 35.0
@export var header_color: Color = Color(0.2, 0.2, 0.2)
@export var header_filter_active_font_color: Color = Color(1.0, 1.0, 0.0)
@export_group("Size and grid")
@export var default_minimum_column_width: float = 50.0
@export var row_height: float = 30.0
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
@export var progress_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_group("Invalid cell")
@export var invalid_cell_color: Color = Color("252b3aff")

# Fonts
var font := get_theme_default_font()
var mono_font: Font = EditorInterface.get_editor_theme().get_font("font", "CodeEdit")
var font_size := get_theme_default_font_size()

# Selection and focus variables (public)
var selected_rows: Array = [] # Indices of the selected rows
var focused_row: int = -1 # Currently focused row
var focused_col: int = -1 # Currently focused column

# Internal variables
var _columns: Array[ColumnConfig]
var _data: Array[Array] = []
var _full_data: Array = []
var _total_rows := 0
var _visible_rows_range := [0, 0]
var _h_scroll_position := 0
var _v_scroll_position := 0
var _resizing_column := -1
var _resizing_start_pos := 0
var _resizing_start_width := 0
var _mouse_over_divider := -1
var _divider_width := 5
var _icon_sort := " ▼ "
var _last_column_sorted := -1
var _ascending := true
var _dragging_progress := false
var _progress_drag_row := -1
var _progress_drag_col := -1

# Resource previews cache management
var _resource_thumb_cache: Dictionary = { } # key -> Texture2D (or null if failed)
var _resource_thumb_pending: Dictionary = { } # key -> bool

# Selection and focus variables
var _previous_sort_selected_rows: Array = [] # Array containing the selected rows before sorting
var _anchor_row: int = -1 # Anchor row for Shift-based selection

var _pan_delta_accumulation: Vector2 = Vector2.ZERO

# Editing variables
var _editing_cell := [-1, -1] # row, column
var _text_editor_line_edit: LineEdit
var _color_editor: Control
var _resource_editor: EditorResourcePicker
var _path_editor: EditorFileDialog
var _double_click_timer: Timer
var _click_count := 0
var _last_click_pos := Vector2.ZERO
var _double_click_threshold := 400 # milliseconds
var _click_position_threshold := 5 # pixels

# Filtering variables
var _filter_line_edit: LineEdit
var _filtering_column := -1

# Tooltip variable
var _tooltip_cell := [-1, -1] # [row, col]

# Node references
var _h_scroll: HScrollBar
var _v_scroll: VScrollBar


func _ready() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)
		EditorInterface.get_resource_previewer().preview_invalidated.connect(_on_resource_previewer_preview_invalidated)
		set_native_theming()

	self.focus_mode = Control.FOCUS_ALL # For input from keyboard

	_setup_editing_components()
	_setup_filtering_components()

	_h_scroll = HScrollBar.new()
	_h_scroll.name = "HScrollBar"
	_h_scroll.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_h_scroll.offset_top = -12
	_h_scroll.value_changed.connect(_on_h_scroll_changed)

	_v_scroll = VScrollBar.new()
	_v_scroll.name = "VScrollBar"
	_v_scroll.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
	_v_scroll.offset_top = header_height
	_v_scroll.offset_left = -12
	_v_scroll.value_changed.connect(_on_v_scroll_value_changed)

	add_child(_h_scroll)
	add_child(_v_scroll)

	_reset_column_widths()

	resized.connect(_on_resized)
	gui_input.connect(_on_gui_input) # Manage input from keyboard whwn has focus control

	self.anchor_left = 0.0
	self.anchor_top = 0.0
	self.anchor_right = 1.0
	self.anchor_bottom = 1.0

	queue_redraw()


func _draw() -> void:
	if not is_inside_tree() or _columns.is_empty():
		return

	var current_x_offset := -_h_scroll_position
	var current_y_offset := header_height
	var visible_drawing_width := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.0)
	var header_font_color := default_font_color

	draw_rect(Rect2(0, 0, size.x, header_height), header_color)

	var header_cell_x := current_x_offset
	for col_idx in _columns.size():
		var column: ColumnConfig = _columns[col_idx]
		if header_cell_x + column.current_width > 0 and header_cell_x < visible_drawing_width:
			draw_line(Vector2(header_cell_x, 0), Vector2(header_cell_x, header_height), grid_color)
			var rect_width: float = min(header_cell_x + column.current_width, visible_drawing_width)
			draw_line(Vector2(header_cell_x, header_height), Vector2(rect_width, header_height), grid_color)

			if col_idx < _columns.size():
				var header_text_content := column.header
				var x_margin_val: int = H_ALIGNMENT_MARGINS.get(column.h_alignment)
				if (col_idx == _filtering_column):
					header_font_color = header_filter_active_font_color
					header_text_content += " (" + str(_data.size()) + ")"
				#elif column.custom_font_color:
				#	header_font_color = column.custom_font_color
				else:
					header_font_color = default_font_color

				var text_size := font.get_string_size(header_text_content, column.h_alignment, column.current_width, font_size)
				var baseline_y := (header_height / 2.0) + (font.get_height(font_size) / 2.0) - font.get_descent(font_size)
				draw_string(
					font,
					Vector2(header_cell_x + x_margin_val, baseline_y),
					header_text_content,
					column.h_alignment,
					column.current_width - abs(x_margin_val),
					font_size,
					header_font_color,
				)
				if (col_idx == _last_column_sorted):
					var icon_h_align := HORIZONTAL_ALIGNMENT_LEFT
					if column.h_alignment in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER]:
						icon_h_align = HORIZONTAL_ALIGNMENT_RIGHT
					draw_string(font, Vector2(header_cell_x, header_height / 2.0 + text_size.y / 2.0 - (font_size / 2.0 - 1.0)), _icon_sort, icon_h_align, column.current_width, font_size / 1.3, header_font_color)

			var divider_x_pos := header_cell_x + column.current_width
			if (divider_x_pos < visible_drawing_width and col_idx <= _columns.size() - 1): # Do not draw for the last column
				draw_line(Vector2(divider_x_pos, 0), Vector2(divider_x_pos, header_height), grid_color, 2.0 if _mouse_over_divider == col_idx else 1.0)
		header_cell_x += column.current_width

	# Draw data rows
	for row in range(_visible_rows_range[0], _visible_rows_range[1]):
		if row >= _total_rows:
			continue # Safety break
		var row_y_pos: float = current_y_offset + (row - _visible_rows_range[0]) * row_height

		var current_bg_color := alternate_row_color if row % 2 == 1 else row_color
		draw_rect(Rect2(0, row_y_pos, visible_drawing_width, row_height), current_bg_color)

		if selected_rows.has(row):
			draw_rect(Rect2(0, row_y_pos, visible_drawing_width, row_height - 1), selected_row_back_color)

		draw_line(Vector2(0, row_y_pos + row_height), Vector2(visible_drawing_width, row_y_pos + row_height), grid_color)

		var cell_x_pos := current_x_offset # Relative to -_h_scroll_position
		for col_idx in _columns.size():
			var col := _columns[col_idx]
			if cell_x_pos < visible_drawing_width and cell_x_pos + col.current_width > 0:
				draw_line(Vector2(cell_x_pos, row_y_pos), Vector2(cell_x_pos, row_y_pos + row_height), grid_color)

				if row == focused_row and col_idx == focused_col:
					draw_rect(Rect2(cell_x_pos + 1, row_y_pos + 1, col.current_width - 3, row_height - 3), selected_cell_back_color, false, 2.0)
				#if not (_editing_cell[0] == row and _editing_cell[1] == col_idx):
				if col.is_progress_column():
					_draw_progress_bar(cell_x_pos, row_y_pos, col_idx, row)
				elif col.is_boolean_column():
					_draw_checkbox(cell_x_pos, row_y_pos, col_idx, row)
				elif col.is_color_column():
					_draw_color_cell(cell_x_pos, row_y_pos, col_idx, row)
				elif col.is_resource_column():
					_draw_resource_cell(cell_x_pos, row_y_pos, col_idx, row)
				elif col.is_enum_column():
					_draw_cell_enum(cell_x_pos, row_y_pos, col_idx, row)
				else:
					_draw_cell_text(cell_x_pos, row_y_pos, col_idx, row)
			cell_x_pos += col.current_width

		# Draw the final right vertical line of the table (right border of the last column)
		if cell_x_pos <= visible_drawing_width and cell_x_pos > -_h_scroll_position:
			draw_line(Vector2(cell_x_pos, row_y_pos), Vector2(cell_x_pos, row_y_pos + row_height), grid_color)

#region PUBLIC METHODS

func set_native_theming(delay: int = 0) -> void:
	if delay != 0 and is_inside_tree():
		# Useful because the editor theme isn't instantly changed
		await get_tree().create_timer(delay).timeout

	var root := EditorInterface.get_base_control()
	header_color = root.get_theme_color(&"dark_color_2", &"Editor")
	row_color = root.get_theme_color(&"base_color", &"Editor")
	alternate_row_color = root.get_theme_color(&"dark_color_3", &"Editor")
	#selected_row_back_color = root.get_theme_color(&"box_selection_fill_color", &"Editor")
	selected_row_back_color = Color(1, 1, 1, 0.20)
	selected_cell_back_color = root.get_theme_color(&"accent_color", &"Editor")
	header_filter_active_font_color = root.get_theme_color(&"accent_color", &"Editor")
	grid_color = root.get_theme_color(&"disabled_border_color", &"Editor")
	invalid_cell_color = EditorThemeUtils.get_base_color(0.9)
	font = root.get_theme_font(&"main", &"EditorFonts")
	default_font_color = root.get_theme_color(&"font_color", &"Editor")
	font_size = root.get_theme_font_size(&"main_size", &"EditorFonts")
	row_height = font_size * 2
	header_height = font_size * 2

	queue_redraw()


func set_columns(columns: Array[ColumnConfig]) -> void:
	_columns = columns
	_reset_column_widths()
	queue_redraw()


func get_column(index: int) -> ColumnConfig:
	return _columns[index]


func set_data(new_data: Array) -> void:
	# Store a full copy of the data as the master list
	_full_data = new_data.duplicate(true)
	# The view (_data) contains references to rows in the master list
	_data = _full_data.duplicate(false)

	_total_rows = _data.size()
	_visible_rows_range = [0, min(_total_rows, floor(self.size.y / row_height) if row_height > 0 else 0)]

	selected_rows.clear()
	_resource_thumb_cache.clear()
	_resource_thumb_pending.clear()
	_anchor_row = -1
	focused_row = -1
	focused_col = -1

	var blank: Variant = CELL_INVALID # TODO: manage undefined cells differently
	for row_data_item: Array in _data:
		while row_data_item.size() < _columns.size():
			row_data_item.append(blank)

	for row in range(_total_rows):
		for col_idx in _columns.size():
			var column := _columns[col_idx]
			var data_s := Vector2.ZERO

			if column.is_progress_column():
				data_s = Vector2(default_minimum_column_width + 20, font_size)
			elif column.is_boolean_column():
				data_s = Vector2(row_height, row_height)
			elif column.is_color_column():
				data_s = Vector2(row_height, row_height)
			elif column.is_resource_column():
				data_s = Vector2(row_height * 2, row_height)
			elif column.is_enum_column():
				var hint_sizes_x: Array[float]
				for enum_value: String in column.hint_string.split(",", false):
					var text_s := font.get_string_size(enum_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(font_size * 2, 0)
					hint_sizes_x.append(text_s.x)
				var max_size_x: float = hint_sizes_x.max()
				if (column.current_width < max_size_x):
					column.minimum_width = max_size_x
			else:
				if row < _data.size() and col_idx < _data[row].size():
					var data_font := font
					if column.custom_font:
						data_font = column.custom_font
					elif column.is_path_column():
						data_font = mono_font
					data_s = data_font.get_string_size(str(_data[row][col_idx]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(font_size * 2, 0)

			if (column.current_width < data_s.x):
				column.minimum_width = data_s.x

	_update_scrollbars()
	queue_redraw()


func ordering_data(column_index: int, ascending: bool = true) -> int:
	_finish_editing(false)
	_last_column_sorted = column_index
	_store_selected_rows()
	var column := _columns[column_index]
	_icon_sort = " ▼ " if ascending else " ▲ "

	if column.is_progress_column():
		_data.sort_custom(
			func(a: Array, b: Array) -> bool:
				var a_val := _get_progress_value(a[column_index])
				var b_val := _get_progress_value(b[column_index])
				_restore_selected_rows()
				return a_val < b_val if ascending else a_val > b_val
		)
	elif column.is_boolean_column():
		_data.sort_custom(
			func(a: Array, b: Array) -> bool:
				var a_val := bool(a[column_index])
				var b_val := bool(b[column_index])
				_restore_selected_rows()
				return (a_val and not b_val) if ascending else (not a_val and b_val)
		)
	elif column.is_color_column():
		_data.sort_custom(
			func(a: Array, b: Array) -> bool:
				var ca := Color(a[column_index])
				var cb := Color(b[column_index])

				# HSV ordering: H, then S, then V, then A (tie-break)
				if ca.h != cb.h:
					_restore_selected_rows()
					return ca.h < cb.h if ascending else ca.h > cb.h
				if ca.s != cb.s:
					_restore_selected_rows()
					return ca.s < cb.s if ascending else ca.s > cb.s
				if ca.v != cb.v:
					_restore_selected_rows()
					return ca.v < cb.v if ascending else ca.v > cb.v

				_restore_selected_rows()
				return ca.a < cb.a if ascending else ca.a > cb.a
		)
	else:
		_data.sort_custom(
			func(a: Array, b: Array) -> bool:
				var a_val: Variant = a[column_index]
				var b_val: Variant = b[column_index]
				# Robust handling for mixed types or null values
				if typeof(a_val) != typeof(b_val):
					if a_val == null:
						return ascending # nulls first if ascending
					if b_val == null:
						return not ascending # nulls last if ascending
					# Compare as strings if types differ but are not null
					_restore_selected_rows()
					return str(a_val) < str(b_val) if ascending else str(a_val) > str(b_val)
				if a_val == null and b_val == null:
					return false # Both null, considered equal
				if a_val == null:
					return ascending
				if b_val == null:
					return not ascending
				if typeof(a_val) == TYPE_STRING_NAME:
					a_val = str(a_val)
					b_val = str(b_val)
				_restore_selected_rows()
				return a_val < b_val if ascending else a_val > b_val
		)
	queue_redraw()
	return -1 # The original function returned -1


func insert_row(index: int, row_data: Array) -> void:
	while row_data.size() < _columns.size(): # Ensure column consistency
		row_data.append(null) # or a default value
	_data.insert(index, row_data)
	_total_rows += 1
	_update_scrollbars()
	queue_redraw()


func delete_row(index: int) -> void:
	if (_total_rows >= 1 and index < _total_rows):
		_data.remove_at(index)
		_total_rows -= 1
		if (_total_rows == 0):
			selected_rows.clear()
		_update_scrollbars()
		queue_redraw()


func update_cell(row: int, col: int, value: Variant) -> void:
	if row >= 0 and row < _data.size() and col >= 0 and col < _columns.size():
		while _data[row].size() <= col:
			_data[row].append("")
		_data[row][col] = value
		queue_redraw()


func get_cell_value(row: int, col: int) -> Variant:
	if row >= 0 and row < _data.size() and col >= 0 and col < _data[row].size():
		return _data[row][col]
	return null


func get_row_value(row: int) -> Variant:
	if row >= 0 and row < _data.size():
		return _data[row]
	return null


func get_progress_value(row_idx: int, col: int) -> float:
	if row_idx >= 0 and row_idx < _data.size() and col >= 0 and col < _data[row_idx].size():
		if _columns[col].is_progress_column():
			return _get_progress_value(_data[row_idx][col]) # Use the internal function for the logic
	return 0.0


func set_selected_cell(row: int, col: int) -> void:
	if row >= 0 and row < _total_rows and col >= 0 and col < _columns.size():
		focused_row = row
		focused_col = col
		selected_rows.clear()
		selected_rows.append(row)
		_anchor_row = row
		_ensure_row_visible(row)
		_ensure_col_visible(col)
		queue_redraw()
	else: # Invalid selection, clear everything
		focused_row = -1
		focused_col = -1
		selected_rows.clear()
		_anchor_row = -1
		queue_redraw()
	cell_selected.emit(focused_row, focused_col)


func set_progress_value(row: int, col: int, value: float) -> void:
	if row >= 0 and row < _data.size() and col >= 0 and col < _columns.size():
		if _columns[col].is_progress_column():
			_data[row][col] = clamp(value, 0.0, 1.0)
			queue_redraw()


func set_progress_colors(bar_start_color: Color, bar_middle_color: Color, bar_end_color: Color, bg_color: Color, border_c: Color, text_c: Color) -> void:
	progress_bar_start_color = bar_start_color
	progress_bar_middle_color = bar_middle_color
	progress_bar_end_color = bar_end_color
	progress_background_color = bg_color
	progress_border_color = border_c
	progress_text_color = text_c
	queue_redraw()

#endregion

#region PRIVATE METHODS

func _setup_filtering_components() -> void:
	_filter_line_edit = LineEdit.new()
	_filter_line_edit.name = "FilterLineEdit"
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

	# TODO: Make Inner class instead of packed scene, for portability
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
	_path_editor.dir_selected.connect(_on_path_editor_path_selected)
	_path_editor.file_selected.connect(_on_path_editor_path_selected)
	add_child(_path_editor)

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
	if _total_rows == null or row_height == null:
		_total_rows = 0 if _total_rows == null else _total_rows
		row_height = 30.0 if row_height == null or row_height <= 0 else row_height

	var visible_width = size.x - (_v_scroll.size.x if _v_scroll.visible else 0)
	var visible_height = size.y - (_h_scroll.size.y if _h_scroll.visible else 0) - header_height

	var total_content_width := 0
	for column in _columns:
		if column.current_width != null:
			total_content_width += column.current_width

	_h_scroll.visible = total_content_width > visible_width
	if _h_scroll.visible:
		_h_scroll.max_value = total_content_width
		_h_scroll.page = visible_width
		#_h_scroll.step = default_minimum_column_width / 2.0 # Ensure float division
	else:
		_h_scroll.value = 0

	var total_content_height := float(_total_rows) * row_height
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


func _get_progress_value(value: Variant) -> float:
	if value == null:
		return 0.0
	var num_val := 0.0
	if _is_numeric_value(value):
		num_val = float(str(value))
	if num_val >= 0.0 and num_val <= 1.0:
		return num_val
	elif num_val >= 0.0 and num_val <= 100.0:
		return num_val / 100.0
	else:
		return clamp(num_val, 0.0, 1.0)


func _parse_date(date_str: String) -> Array:
	var parts := date_str.split("/")
	if parts.size() != 3:
		return [0, 0, 0]
	return [int(parts[2]), int(parts[1]), int(parts[0])] # Year, Month, Day


func _store_selected_rows() -> void:
	if (selected_rows.size() == 0):
		return
	_previous_sort_selected_rows.clear()
	for index in range(selected_rows.size()):
		_previous_sort_selected_rows.append(_data[selected_rows[index]])


func _restore_selected_rows() -> void:
	if (_previous_sort_selected_rows.size() == 0):
		return
	selected_rows.clear()
	for index in range(_previous_sort_selected_rows.size()):
		var idx := _data.find(_previous_sort_selected_rows[index])
		if (idx >= 0):
			selected_rows.append(idx)


func _start_cell_editing(row: int, col: int) -> void:
	var column := _columns[col]
	if str(get_cell_value(row, col)) == CELL_INVALID:
		return

	if column.is_color_column():
		_open_color_editor(row, col)
	elif column.is_resource_column():
		_open_resource_editor(row, col)
	elif column.is_path_column():
		_open_path_editor(row, col)
	elif column.is_numeric_column():
		_open_text_editor(row, col)
	elif column.is_string_column():
		_open_text_editor(row, col)
	else:
		push_warning("There is no editor for this type of cell.")
	# NB: boolean cells are toggled using single click


func _open_text_editor(row: int, col: int) -> void:
	var cell_rect := _get_cell_rect(row, col)
	if not cell_rect:
		return

	var cell_value: Variant = get_cell_value(row, col)
	_editing_cell = [row, col]
	_text_editor_line_edit.position = cell_rect.position
	_text_editor_line_edit.size = cell_rect.size
	_text_editor_line_edit.text = str(cell_value) if get_cell_value(row, col) != null else ""
	_text_editor_line_edit.show()
	_text_editor_line_edit.grab_focus()
	_text_editor_line_edit.select_all()


func _open_color_editor(row: int, col: int) -> void:
	var cell_rect := _get_cell_rect(row, col)
	if not cell_rect:
		return

	var cell_value: Color = get_cell_value(row, col)
	_editing_cell = [row, col]
	_color_editor.position = cell_rect.get_center()
	_color_editor.color = cell_value
	_color_editor.show()
	_color_editor.grab_focus()


func _open_resource_editor(row: int, col: int) -> void:
	_editing_cell = [row, col]
	var columnn := get_column(col)
	_resource_editor.edited_resource = null
	if ClassUtils.is_valid(columnn.hint_string):
		_resource_editor.base_type = columnn.hint_string
	else:
		_resource_editor.base_type = "Resource"
	var quick_load: Button = _resource_editor.get_child(1, true)
	if quick_load:
		quick_load.pressed.emit()


func _open_path_editor(row: int, col: int) -> void:
	_editing_cell = [row, col]
	var column := get_column(col)
	if column.property_hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_FILE_PATH]:
		_path_editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	if column.property_hint in [PROPERTY_HINT_DIR]:
		_path_editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_path_editor.popup_centered_ratio(0.55)


func _finish_editing(save_changes: bool = true) -> void:
	if _editing_cell[0] == -1 and _editing_cell[1] == -1:
		return

	if save_changes:
		var column := _columns[_editing_cell[1]]
		var old_value: Variant = get_cell_value.callv(_editing_cell)
		var new_value: Variant = _get_editor_value_for_column(column)
		if typeof(new_value) == column.type:
			if column.is_path_column() and column.property_hint == PROPERTY_HINT_FILE:
				new_value = ResourceUID.path_to_uid(new_value)
			update_cell(_editing_cell[0], _editing_cell[1], new_value)
			cell_edited.emit(_editing_cell[0], _editing_cell[1], old_value, new_value)

	_editing_cell = [-1, -1]
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

	var text := _text_editor_line_edit.text
	if column.is_string_column():
		return text
	elif column.is_integer_column() and text.is_valid_int():
		return int(text)
	elif column.is_float_column() and text.is_valid_float():
		return float(text)

	return null


func _get_cell_rect(row: int, col: int) -> Rect2:
	var column := _columns[col]
	if row < _visible_rows_range[0] or row >= _visible_rows_range[1] or col >= _columns.size():
		return Rect2()
	var x_offset := -_h_scroll_position
	var cell_x := x_offset
	for c in range(col):
		cell_x += _columns[c].current_width
	var visible_width = size.x - (_v_scroll.size.x if _v_scroll.visible else 0)
	if cell_x + column.current_width <= 0 or cell_x >= visible_width:
		return Rect2()
	var row_y_pos = header_height + (row - _visible_rows_range[0]) * row_height
	return Rect2(cell_x, row_y_pos, column.current_width, row_height)


func _draw_progress_bar(cell_x: float, row_y: float, col: int, row: int) -> void:
	var cell_value = 0.0
	if row < _data.size() and col < _data[row].size():
		cell_value = _get_progress_value(_data[row][col])

	var margin := 4.0
	var bar_x_pos := cell_x + margin
	var bar_y_pos := row_y + margin
	var bar_width := _columns[col].current_width - (margin * 2.0)
	var bar_h := row_height - (margin * 2.0)

	draw_rect(Rect2(bar_x_pos, bar_y_pos, bar_width, bar_h), progress_background_color)
	draw_rect(Rect2(bar_x_pos, bar_y_pos, bar_width, bar_h), progress_border_color, false, 1.0)

	var progress_w: float = bar_width * cell_value
	if progress_w > 0:
		draw_rect(Rect2(bar_x_pos, bar_y_pos, progress_w, bar_h), _get_interpolated_three_colors(progress_bar_start_color, progress_bar_middle_color, progress_bar_end_color, cell_value))

	var perc_text := str(int(round(cell_value * 100.0))) + "%"
	var text_size := font.get_string_size(perc_text, HORIZONTAL_ALIGNMENT_CENTER, bar_width, font_size)
	draw_string(font, Vector2(bar_x_pos + bar_width / 2.0 - text_size.x / 2.0, bar_y_pos + bar_h / 2.0 + text_size.y / 2.0 - 5.0), perc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, progress_text_color)


func _draw_checkbox(cell_x: float, row_y: float, col: int, row: int) -> void:
	if not row < _data.size() and col < _data[row].size():
		return

	var cell_value: Variant = _data[row][col]
	if cell_value is not bool:
		_draw_cell_text(cell_x, row_y, col, row)
		return
	var is_checked: bool = cell_value
	var icon_name := &"checked" if is_checked else &"unchecked"
	var icon: Texture2D = get_theme_icon(icon_name, &"CheckBox")
	if icon == null:
		return

	var margin := 2.0
	var tex_size := icon.get_size()
	var cell_inner_width: float = _columns[col].current_width - margin * 2
	var cell_inner_height: float = row_height - margin * 2
	var pos := Vector2(
		cell_x + margin + (cell_inner_width - tex_size.x) / 2.0,
		row_y + margin + (cell_inner_height - tex_size.y) / 2.0,
	)

	draw_texture(icon, pos)


func _draw_color_cell(cell_x: float, row_y: float, col: int, row: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not value is Color:
		_draw_cell_text(cell_x, row_y, col, row)
		return

	var color: Color = value
	var margin := 2.0
	var cell_inner_width: float = _columns[col].current_width - margin * 2
	var cell_inner_height: float = row_height - margin * 2
	if cell_inner_width <= 0.0 or cell_inner_height <= 0.0:
		return

	var rect := Rect2(
		Vector2(cell_x + margin, row_y + margin),
		Vector2(cell_inner_width, cell_inner_height),
	)
	var border_alpha := 0.65 if color.a < 0.25 else 0.35

	# Checkerboard background to visualize transparency
	if color.a < 1.0:
		var tile := 6.0
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.position.x + rect.size.x
		var y1 := rect.position.y + rect.size.y

		var y := y0
		var row_i := 0
		while y < y1:
			var x := x0
			var col_i := 0
			while x < x1:
				var w := min(tile, x1 - x)
				var h := min(tile, y1 - y)
				var is_dark := ((row_i + col_i) % 2) == 0
				var bg := Color(0, 0, 0, 0.10) if is_dark else Color(1, 1, 1, 0.10)
				draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bg, true)
				x += tile
				col_i += 1
			y += tile
			row_i += 1

	draw_rect(rect, color, true)
	draw_rect(rect, Color(1, 1, 1, border_alpha), false, 1.0)


func _draw_resource_cell(cell_x: float, row_y: float, col: int, row: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not value is Resource:
		_draw_cell_text(cell_x, row_y, col, row)
		return

	var res: Resource = value

	var key: String = res.resource_path
	if key.is_empty():
		key = "iid:%d" % res.get_instance_id()

	var margin := 2.0
	var cell_inner_width: float = _columns[col].current_width - margin * 2
	var cell_inner_height: float = row_height - margin * 2
	if cell_inner_width <= 0.0 or cell_inner_height <= 0.0:
		return

	var inner_pos := Vector2(cell_x + margin, row_y + margin)

	# Cached thumbnail? draw it
	if _resource_thumb_cache.has(key):
		var texture: Texture2D = _resource_thumb_cache[key]
		if texture == null:
			return

		var tex_size := texture.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return

		var tex_aspect := tex_size.x / tex_size.y
		var cell_aspect := cell_inner_width / cell_inner_height

		var drawn_rect := Rect2()
		if tex_aspect > cell_aspect:
			drawn_rect.size.x = cell_inner_width
			drawn_rect.size.y = cell_inner_width / tex_aspect
			drawn_rect.position.x = inner_pos.x
			drawn_rect.position.y = inner_pos.y + (cell_inner_height - drawn_rect.size.y) / 2.0
		else:
			drawn_rect.size.y = cell_inner_height
			drawn_rect.size.x = cell_inner_height * tex_aspect
			drawn_rect.position.y = inner_pos.y
			drawn_rect.position.x = inner_pos.x + (cell_inner_width - drawn_rect.size.x) / 2.0

		draw_texture_rect(texture, drawn_rect, false)
		return

	# Not cached yet and no pending request: request once
	if not _resource_thumb_pending.has(key):
		_resource_thumb_pending[key] = true

		var previewer := EditorInterface.get_resource_previewer()
		previewer.queue_edited_resource_preview(
			res,
			self,
			"_on_resource_cell_thumb_ready",
			{
				"key": key,
				"class": ClassUtils.get_type_name(res),
			},
		)

	# Placeholder
	draw_rect(Rect2(inner_pos, Vector2(cell_inner_width, cell_inner_height)), Color(1, 1, 1, 0.06), true)
	draw_rect(Rect2(inner_pos, Vector2(cell_inner_width, cell_inner_height)), Color(1, 1, 1, 0.18), false, 1.0)


func _draw_cell_text(cell_x: float, row_y: float, col: int, row: int) -> void:
	var cell_value := str(get_cell_value(row, col))
	if cell_value == CELL_INVALID:
		_draw_cell_invalid(cell_x, row_y, col, row)
		return

	var column := _columns[col]
	var text_font: Font = font
	var h_alignment := column.h_alignment
	if column.custom_font:
		text_font = column.custom_font
	elif get_column(col).is_path_column():
		text_font = mono_font

	if column.is_resource_column() and _data[row][col] == null:
		cell_value = "<empty>"
		h_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(h_alignment)
	var text_size := text_font.get_string_size(
		cell_value,
		h_alignment,
		_columns[col].current_width - abs(x_margin_val) * 2,
		font_size,
	)
	var baseline_y := row_y + (row_height / 2.0) + (font.get_height(font_size) / 2.0) - font.get_descent(font_size)
	var text_color := column.custom_font_color if column.custom_font_color else default_font_color
	# TODO: the following line is registry-specific. Refactor outside.
	# For example, give the ability to set colors for specific rows.
	text_color = get_theme_color("error_color", "Editor") if cell_value.begins_with("(!) ") else text_color
	draw_string(
		text_font,
		Vector2(cell_x + x_margin_val, baseline_y),
		cell_value,
		h_alignment,
		_columns[col].current_width - abs(x_margin_val),
		font_size,
		text_color,
	)


func _draw_cell_enum(cell_x: float, row_y: float, col: int, row: int) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	if not cell_value is int:
		_draw_cell_text(cell_x, row_y, col, row)
		return

	var value_str: String
	var key_found := -1
	var column := _columns[col]
	var hint_arr: Array = column.hint_string.split(",", false)
	for i in hint_arr.size():
		var colon_found: int = hint_arr[i].rfind(":")
		if colon_found == -1:
			key_found = cell_value
			break

		if hint_arr[i].substr(colon_found + 1).to_int() == cell_value:
			key_found = i
			break

	if key_found != -1 and key_found < hint_arr.size():
		value_str = hint_arr[key_found]

	else:
		value_str = "?:%s" % cell_value

	var text_font: Font = font #mono_font
	var h_alignment := HORIZONTAL_ALIGNMENT_CENTER #column.h_alignment
	var color := Color(value_str.hash()) + Color(0.25, 0.25, 0.25, 1.0)
	if column.custom_font:
		text_font = column.custom_font
	elif get_column(col).is_path_column():
		text_font = mono_font

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(h_alignment)
	var text_size := text_font.get_string_size(
		value_str,
		h_alignment,
		_columns[col].current_width - abs(x_margin_val) * 2,
		font_size,
	)
	var baseline_y := row_y + (row_height / 2.0) + (font.get_height(font_size) / 2.0) - font.get_descent(font_size)
	draw_string(
		text_font,
		Vector2(cell_x + x_margin_val, baseline_y),
		value_str,
		h_alignment,
		_columns[col].current_width - abs(x_margin_val),
		font_size,
		color,
	)


func _draw_cell_invalid(cell_x: float, row_y: float, col: int, row: int) -> void:
	var color: Color = invalid_cell_color
	var margin := 0.0 # 0 for continuous rect between invalid cells
	var cell_inner_width: float = _columns[col].current_width - margin * 2
	var cell_inner_height: float = row_height - margin * 2
	if cell_inner_width <= 0.0 or cell_inner_height <= 0.0:
		return

	var rect := Rect2(
		Vector2(cell_x, row_y + margin),
		Vector2(cell_inner_width, cell_inner_height),
	)

	draw_rect(rect, color, true)
	#draw_rect(rect, Color(1, 1, 1, border_alpha), false, 1.0, true)


func _get_interpolated_three_colors(start_c: Color, mid_c: Color, end_c: Color, t_val: float) -> Color:
	var clamped_t = clampf(t_val, 0.0, 1.0)
	if clamped_t <= 0.5:
		return start_c.lerp(mid_c, clamped_t * 2.0)
	else:
		return mid_c.lerp(end_c, (clamped_t - 0.5) * 2.0)


func _start_filtering(col: int, header_rect: Rect2) -> void:
	if _filtering_column == col and _filter_line_edit.visible:
		return # Already in filter mode on this column

	_filtering_column = col
	_filter_line_edit.position = header_rect.position + Vector2(1, 1)
	_filter_line_edit.size = header_rect.size - Vector2(2, 2)
	_filter_line_edit.text = ""
	_filter_line_edit.visible = true
	_filter_line_edit.grab_focus()


func _apply_filter(search_key: String) -> void:
	if not _filter_line_edit.visible:
		return

	_filter_line_edit.visible = false
	if _filtering_column == -1:
		return

	if search_key.is_empty():
		# If the key is empty, restore all data (remove the filter)
		_data = _full_data.duplicate(false)
		_filtering_column = -1
	else:
		var filtered_data: Array[Array] = []
		var key_lower = search_key.to_lower()
		for row_data in _full_data:
			if _filtering_column < row_data.size() and row_data[_filtering_column] != null:
				var cell_value = str(row_data[_filtering_column]).to_lower()
				if cell_value.contains(key_lower):
					filtered_data.append(row_data) # Adds the reference
		_data = filtered_data

	# Reset the view
	_total_rows = _data.size()
	_v_scroll_position = 0
	_v_scroll.value = 0
	selected_rows.clear()
	_previous_sort_selected_rows.clear()
	focused_row = -1
	_last_column_sorted = -1 # Reset visual sorting

	_update_scrollbars()
	queue_redraw()


func _check_mouse_over_divider(mouse_pos: Vector2) -> void:
	_mouse_over_divider = -1
	mouse_default_cursor_shape = CURSOR_ARROW

	if mouse_pos.y < header_height:
		var current_x := -_h_scroll_position

		for col_idx in range(_columns.size() - 1): # Not for the last column
			var column := _columns[col_idx]
			current_x += column.current_width
			var divider_rect := Rect2(
				current_x - _divider_width / 2,
				0,
				_divider_width,
				header_height,
			)

			if divider_rect.has_point(mouse_pos):
				_mouse_over_divider = col_idx
				mouse_default_cursor_shape = CURSOR_HSIZE

	queue_redraw() # Refresh to show the highlighted divider


func _update_tooltip(mouse_pos: Vector2) -> void:
	var current_cell := [-1, -1]
	var new_tooltip := ""

	if mouse_pos.y < header_height:
		var current_x = -_h_scroll_position
		for col_idx in _columns.size():
			var column := _columns[col_idx]
			if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
				new_tooltip = column.header
				current_cell = [-2, col_idx]
				break
			current_x += column.current_width
	else:
		var row_idx = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]
		if row_idx >= 0 and row_idx < _total_rows:
			var current_x := -_h_scroll_position
			for col_idx in _columns.size():
				var column := _columns[col_idx]
				if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
					if not column.is_progress_column() and not column.is_boolean_column():
						var cell_text := str(get_cell_value(row_idx, col_idx))
						new_tooltip = cell_text
					current_cell = [row_idx, col_idx]
					break
				current_x += column.current_width

	if current_cell != _tooltip_cell:
		_tooltip_cell = current_cell
		self.tooltip_text = new_tooltip


func _is_clicking_progress_bar(mouse_pos: Vector2) -> bool:
	if mouse_pos.y < header_height:
		return false

	var row := -1
	if row_height > 0:
		row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]

	if row < 0 or row >= _total_rows:
		return false

	var current_x := -_h_scroll_position # Renamed from `x_offset`
	var clicked_col_idx := -1

	for col_idx in _columns.size():
		var column := _columns[col_idx]
		if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
			clicked_col_idx = col_idx
			break
		current_x += column.current_width

	# TODO: WHAT THE HELL IS THAT SIDE EFFECT ?! Method is a predicate goddamnit. REFACTOR ASAP
	var column := _columns[clicked_col_idx]
	if column.is_progress_column():
		# Set focused_row and focused_col when clicking on a progress bar
		# This ensures the row becomes "active"
		if focused_row != row or focused_col != clicked_col_idx:
			focused_row = row
			focused_col = clicked_col_idx
			# If not already selected, select it as a single row
			if not selected_rows.has(row):
				selected_rows.clear()
				selected_rows.append(row)
				_anchor_row = row
			cell_selected.emit(focused_row, focused_col) # Emit signal
			queue_redraw()
		_progress_drag_row = row
		_progress_drag_col = clicked_col_idx
		return true

	return false


func _ensure_row_visible(row_idx: int) -> void:
	if _total_rows == 0 or row_height == 0 or not _v_scroll.visible:
		return

	var visible_area_height: float = size.y - header_height - (_h_scroll.size.y if _h_scroll.visible else 0.0)
	var num_visible_rows_in_page := floori(visible_area_height / row_height)

	# _visible_rows_range[0] is the first visible row (0-based index)
	# _visible_rows_range[1] is the index of the first row that is NOT visible at the bottom
	# Therefore, visible rows go from _visible_rows_range[0] to _visible_rows_range[1] - 1
	var first_fully_visible_row: int = _visible_rows_range[0]

	if row_idx < first_fully_visible_row:
		# The row is above the current viewport
		_v_scroll.value = row_idx * row_height
	elif row_idx >= first_fully_visible_row + num_visible_rows_in_page:
		# The row is below the current viewport
		# Scroll so that row_idx becomes the last (or nearly last) visible row
		_v_scroll.value = (row_idx - num_visible_rows_in_page + 1) * row_height

	_v_scroll.value = clamp(_v_scroll.value, 0, _v_scroll.max_value)
	# _on_v_scroll_value_changed will be called, updating _visible_rows_range
	# and triggering queue_redraw()


func _ensure_col_visible(col_idx: int) -> void:
	if _columns.is_empty() or col_idx not in range(_columns.size()) or not _h_scroll.visible:
		return

	#print(Engine.get_process_frames())
	#return
	var column_start: float
	var column_end: float
	var visible_area_x := Vector2(
		_h_scroll.value,
		size.x + _h_scroll.value - _v_scroll.size.x,
	)

	var col_width: float
	var iter_x_pos := 0.0
	for i in _columns.size():
		var column := _columns[i]
		if i == col_idx:
			col_width = column.current_width
			column_start = iter_x_pos
			column_end = iter_x_pos + col_width
			break
		iter_x_pos += column.current_width

	if column_start < visible_area_x[0]:
		_h_scroll.value = column_start
	elif column_end > visible_area_x[1]:
		if col_width > (visible_area_x[1] - visible_area_x[0]):
			_h_scroll.value = column_start
		else:
			_h_scroll.value = column_end - (visible_area_x[1] - visible_area_x[0])


func _handle_key_input(event: InputEventKey) -> void:
	if _text_editor_line_edit.visible: # Let the LineEdit handle input during editing
		if event.keycode == KEY_ESCAPE: # Except ESC to cancel
			_finish_editing(false)
			get_viewport().set_input_as_handled()
		return

	var keycode := event.keycode
	var is_shift := event.is_shift_pressed()
	var is_ctrl := event.is_ctrl_pressed()
	var is_meta := event.is_meta_pressed() # Cmd on Mac
	var is_ctrl_cmd := is_ctrl or is_meta # For actions like Ctrl+A / Cmd+A

	var current_focused_r := focused_row
	var current_focused_c := focused_col

	var new_focused_r := current_focused_r
	var new_focused_c := current_focused_c

	var key_operation_performed := false # Flag to track whether a key operation modified the state
	var event_consumed := true # Assume the event will be consumed unless stated otherwise
	var emit_multiple_selection_signal := false

	if is_ctrl_cmd and keycode == KEY_A:
		if _total_rows > 0:
			selected_rows.clear()
			for i in range(_total_rows):
				selected_rows.append(i)
			emit_multiple_selection_signal = true

			# Set or keep focus and anchor
			if current_focused_r == -1: # If there is no focus, go to the first row
				focused_row = 0
				focused_col = 0 if _columns.size() > 0 else -1
				_anchor_row = 0
			else: # Otherwise, keep the current focus as anchor
				_anchor_row = focused_row

			_ensure_row_visible(focused_row)
			_ensure_col_visible(focused_col)
		key_operation_performed = true

	elif keycode == KEY_HOME:
		if _total_rows > 0:
			new_focused_r = 0
			new_focused_c = 0 if _columns.size() > 0 else -1
			key_operation_performed = true
		else:
			event_consumed = false # No rows, no action

	elif keycode == KEY_END:
		if _total_rows > 0:
			new_focused_r = _total_rows - 1
			new_focused_c = (_columns.size() - 1) if _columns.size() > 0 else -1
			key_operation_performed = true
		else:
			event_consumed = false # No rows, no action

	# Other navigation keys (generally require an initial focus)
	elif current_focused_r != -1 and current_focused_c != -1:
		match keycode:
			KEY_UP:
				new_focused_r = max(0, current_focused_r - 1)
				key_operation_performed = true
			KEY_DOWN:
				new_focused_r = min(_total_rows - 1, current_focused_r + 1)
				key_operation_performed = true
			KEY_LEFT:
				new_focused_c = max(0, current_focused_c - 1)
				key_operation_performed = true
			KEY_RIGHT:
				new_focused_c = min(_columns.size() - 1, current_focused_c + 1)
				key_operation_performed = true
			KEY_PAGEUP:
				var page_row_count = floor((size.y - header_height) / row_height) if row_height > 0 else 10
				page_row_count = max(1, page_row_count) # Ensure scrolling of at least 1 row
				new_focused_r = max(0, current_focused_r - page_row_count)
				key_operation_performed = true
			KEY_PAGEDOWN:
				var page_row_count = floor((size.y - header_height) / row_height) if row_height > 0 else 10
				page_row_count = max(1, page_row_count)
				new_focused_r = min(_total_rows - 1, current_focused_r + page_row_count)
				key_operation_performed = true
			KEY_SPACE:
				if is_ctrl_cmd:
					if selected_rows.has(current_focused_r):
						selected_rows.erase(current_focused_r)
					else:
						if not selected_rows.has(current_focused_r):
							selected_rows.append(current_focused_r)
					_anchor_row = current_focused_r
					key_operation_performed = true
				else:
					event_consumed = false
			KEY_ESCAPE:
				if selected_rows.size() > 0 or focused_row != -1: # Act only if there is a selection or focus
					selected_rows.clear()
					_previous_sort_selected_rows.clear()
					_anchor_row = -1
					focused_row = -1
					focused_col = -1
					key_operation_performed = true
					set_selected_cell(-1, -1)
				else:
					event_consumed = false # No selection/focus to cancel

	else: # No initial focus for most navigation keys, or unhandled key above
		event_consumed = false

	# If the focus changed or a key operation modified the selection state
	if key_operation_performed and (new_focused_r != current_focused_r or new_focused_c != current_focused_c or keycode in [KEY_HOME, KEY_END, KEY_SPACE, KEY_A]):
		var old_focused_r := focused_row # Save previous focus for anchor

		focused_row = new_focused_r
		focused_col = new_focused_c

		# Selection update logic
		if not (is_ctrl_cmd and keycode == KEY_A): # Ctrl+A handles its own selection
			#var emit_multiple_selection_signal = false
			if is_shift:
				# Set anchor if not defined, using previous focus or 0 as fallback
				if _anchor_row == -1:
					_anchor_row = old_focused_r if old_focused_r != -1 else 0

				if focused_row != -1: # Only if the new focused row is valid
					selected_rows.clear()
					var start_r: int = min(_anchor_row, focused_row)
					var end_r: int = max(_anchor_row, focused_row)
					for i in range(start_r, end_r + 1):
						if i >= 0 and i < _total_rows: # Check index validity
							if not selected_rows.has(i):
								selected_rows.append(i)
								emit_multiple_selection_signal = true
				# If focused_row is -1 (e.g. empty table), selected_rows stays empty or cleared
				#if emit_multiple_selection_signal:
				# The selected_rows array already contains the correct indices
				#multiple_rows_selected.emit(selected_rows)

			elif is_ctrl_cmd and not (keycode == KEY_SPACE):
				# Ctrl + Arrows/Pg/Home/End: move focus only, do not change selection.
				# The anchor does not change to allow future Shift selections.
				pass
			elif not (keycode == KEY_SPACE and is_ctrl_cmd):
				# No modifier (or Ctrl not for pure navigation): select only the focused row
				if focused_row != -1: # Only if the new focused row is valid
					selected_rows.clear()
					selected_rows.append(focused_row)
					_anchor_row = focused_row
					#emit_multiple_selection_signal = true
				else: # The new focused row is not valid (e.g. empty table)
					selected_rows.clear()
					_anchor_row = -1

		if focused_row != -1:
			_ensure_row_visible(focused_row)
			_ensure_col_visible(focused_col)

		if current_focused_r != focused_row or current_focused_c != focused_col or (keycode == KEY_SPACE and is_ctrl_cmd):
			# Emit the signal only if the focus actually changed or if Ctrl+Space modified the selection
			cell_selected.emit(focused_row, focused_col)
			pass

		if emit_multiple_selection_signal:
			# The selected_rows array already contains the correct indices
			multiple_rows_selected.emit(selected_rows)

	if key_operation_performed:
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event_consumed: # Consume the event if it was partially handled (e.g. key recognized but no action)
		get_viewport().set_input_as_handled()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if _v_scroll.visible:
		if not sign(event.delta.y) == sign(_pan_delta_accumulation.y):
			_pan_delta_accumulation.y = 0
		_pan_delta_accumulation.y += event.delta.y
		if abs(_pan_delta_accumulation.y) >= 1:
			_v_scroll.value += sign(_pan_delta_accumulation.y) * _v_scroll.step
			_pan_delta_accumulation.y -= 1 * sign(_pan_delta_accumulation.y)
	if _h_scroll.visible and abs(event.delta.x) > 0.05:
		if not sign(event.delta.x) == sign(_pan_delta_accumulation.x):
			_pan_delta_accumulation.x = 0
		_pan_delta_accumulation.x += event.delta.x
		if abs(_pan_delta_accumulation.x) >= 1:
			_h_scroll.value += sign(_pan_delta_accumulation.x) * _v_scroll.step
			_pan_delta_accumulation.x -= 1 * sign(_pan_delta_accumulation.x)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var m_pos = event.position

	if (
		_dragging_progress
		and _progress_drag_row >= 0
		and _progress_drag_col >= 0
	):
		_handle_progress_drag(m_pos)

	elif (
		_resizing_column >= 0
		and _resizing_column < _columns.size() - 1
	):
		var delta_x: float = m_pos.x - _resizing_start_pos
		var new_width: float = max(
			_resizing_start_width + delta_x,
			_columns[_resizing_column].minimum_width,
		)

		_columns[_resizing_column].current_width = new_width
		_update_scrollbars()
		column_resized.emit(_resizing_column, new_width)
		queue_redraw()

	else:
		_check_mouse_over_divider(m_pos)
		_update_tooltip(m_pos)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var m_pos := event.position

			# Double-click handling
			if (
				_click_count == 1
				and _double_click_timer.time_left > 0
				and _last_click_pos.distance_to(m_pos) < _click_position_threshold
			):
				_click_count = 0
				_double_click_timer.stop()

				if m_pos.y < header_height:
					_handle_header_double_click(m_pos) # <-- NEW CALL
				else:
					_handle_double_click(m_pos)
			else:
				# Single-click handling
				_click_count = 1
				_last_click_pos = m_pos
				_double_click_timer.start()

				if m_pos.y < header_height:
					# If the filter LineEdit is visible, do not process single header clicks
					if not _filter_line_edit.visible:
						_handle_header_click(m_pos)
				else:
					_handle_checkbox_click(m_pos)
					_handle_cell_click(m_pos, event)

					if _is_clicking_progress_bar(m_pos):
						_dragging_progress = true

				if _mouse_over_divider >= 0:
					_resizing_column = _mouse_over_divider
					_resizing_start_pos = m_pos.x
					_resizing_start_width = _columns[_resizing_column].current_width

		else:
			# Mouse button released
			_resizing_column = -1
			_dragging_progress = false
			_progress_drag_row = -1
			_progress_drag_col = -1

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click(event.position) # Use event.position

	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if _v_scroll.visible:
			_v_scroll.value = max(
				0,
				_v_scroll.value - _v_scroll.step * 1,
			)

	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _v_scroll.visible:
			_v_scroll.value = min(
				_v_scroll.max_value,
				_v_scroll.value + _v_scroll.step * 1,
			)


func _handle_progress_drag(mouse_pos: Vector2) -> void:
	if (
		_progress_drag_row < 0
		or _progress_drag_col < 0
		or _progress_drag_col >= _columns.size()
	):
		return

	var current_x := -_h_scroll_position
	for col_loop in range(_progress_drag_col):
		current_x += _columns[col_loop].current_width

	var margin := 4.0
	var bar_x_pos := current_x + margin
	var bar_width = _columns[_progress_drag_col].current_width - (margin * 2.0)

	if bar_width <= 0:
		return # Avoid division by zero

	var relative_x := mouse_pos.x - bar_x_pos
	var new_progress = clamp(relative_x / bar_width, 0.0, 1.0)

	if (
		_progress_drag_row < _data.size()
		and _progress_drag_col < _data[_progress_drag_row].size()
	):
		_data[_progress_drag_row][_progress_drag_col] = new_progress
		progress_changed.emit(_progress_drag_row, _progress_drag_col, new_progress)
		queue_redraw()


func _handle_checkbox_click(mouse_pos: Vector2) -> bool:
	if mouse_pos.y < header_height:
		return false

	var row := -1
	if row_height > 0:
		row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]

	if row < 0 or row >= _total_rows:
		return false

	var current_x := -_h_scroll_position
	var clicked_col_idx := -1

	for col_idx in _columns.size():
		var column := _columns[col_idx]
		if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
			clicked_col_idx = col_idx
			break
		current_x += column.current_width

	# TODO: WHAT THE HELL IS THAT SIDE EFFECT ?! Method is a predicate goddamnit. REFACTOR ASAP
	# TODO: same code as progress above, refactor for that too
	var column := _columns[clicked_col_idx]
	if column.is_boolean_column():
		# When clicking a checkbox, the row becomes the current single selection (if not already)
		if focused_row != row or focused_col != clicked_col_idx:
			focused_row = row
			focused_col = clicked_col_idx

			# If it is not the only selected row
			if not selected_rows.has(row) or selected_rows.size() > 1:
				selected_rows.clear()
				selected_rows.append(row)
				_anchor_row = row

			cell_selected.emit(focused_row, focused_col) # Emit focus signal
			# Do not call queue_redraw() here; it will be done after update_cell

		var old_val: Variant = get_cell_value(row, clicked_col_idx)
		var new_val := not bool(old_val)

		update_cell(row, clicked_col_idx, new_val) # update_cell calls queue_redraw()
		cell_edited.emit(row, clicked_col_idx, old_val, new_val)
		return true

	return false


func _handle_cell_click(mouse_pos: Vector2, event: InputEventMouseButton) -> void:
	# TODO: clean / refactor method
	if _editing_cell[1] >= 0:
		var column := get_column(_editing_cell[1])
		if column.is_resource_column() or column.is_path_column():
			# When focus is lost (after an editor window was closed) do NOT save changes
			_finish_editing(false)
		else:
			_finish_editing(true)

	var clicked_row := -1
	if row_height > 0: # Avoid division by zero
		clicked_row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]

	if clicked_row < 0 or clicked_row >= _total_rows: # Click outside valid row area
		# Optional: clear selection when clicking outside
		# selected_rows.clear()
		# _anchor_row = -1
		# focused_row = -1
		# focused_col = -1
		# queue_redraw()
		return

	var current_x_pos := -_h_scroll_position
	var clicked_col := -1
	for col_idx in _columns.size():
		var column := _columns[col_idx]
		if mouse_pos.x >= current_x_pos && mouse_pos.x < current_x_pos + column.current_width:
			clicked_col = col_idx
			break
		current_x_pos += column.current_width

	if clicked_col == -1:
		return # Click outside column area

	focused_row = clicked_row
	focused_col = clicked_col

	var is_shift := event.is_shift_pressed()
	var is_ctrl_cmd := event.is_ctrl_pressed() or event.is_meta_pressed() # Ctrl or Cmd

	var selection_was_multiple := selected_rows.size() > 1 # State before the change
	var emit_multiple_selection_signal := false

	if is_shift and _anchor_row != -1:
		selected_rows.clear()
		var start_range: int = min(_anchor_row, focused_row)
		var end_range: int = max(_anchor_row, focused_row)
		for i in range(start_range, end_range + 1):
			selected_rows.append(i)
		# After a Shift selection, if more than one row is selected, prepare to emit.
		if selected_rows.size() > 1:
			emit_multiple_selection_signal = true
	elif is_ctrl_cmd:
		if selected_rows.has(focused_row):
			selected_rows.erase(focused_row)
		else:
			selected_rows.append(focused_row)
		_anchor_row = focused_row # Update the anchor for future Shift selections
		# After a Ctrl/Cmd selection, if more than one row is selected, prepare to emit.
		if selected_rows.size() > 1:
			emit_multiple_selection_signal = true
		# If the selection was multiple and now is no longer multiple (because Ctrl-click deselects),
		# you might still want to emit to indicate a change from a multiple-selection state.
		# However, the requirement is "when a multiple selection EXISTS".
		# So if selected_rows.size() <= 1, we do not set emit_multiple_selection_signal = true.
	else: # Single click without modifiers
		selected_rows.clear()
		selected_rows.append(focused_row)
		_anchor_row = focused_row
		# In this case, selected_rows.size() will be 1.
		# If the previous selection was multiple and now is single,
		# we do not emit multiple_rows_selected because a multiple selection no longer exists.

	cell_selected.emit(focused_row, focused_col) # Always emit for a valid cell click
	_ensure_col_visible(focused_col)

	# Emit the new signal if a multiple selection was identified
	if emit_multiple_selection_signal:
		# selected_rows already contains the correct indices
		multiple_rows_selected.emit(selected_rows)
	# Also consider the case where the selection transitions from multiple to single/none
	# due to a Ctrl operation. If you want a signal for that "change" as well,
	# the logic here should be slightly different. But sticking to "when it exists",
	# the current approach is correct.

	queue_redraw()


func _handle_right_click(mouse_pos: Vector2) -> void:
	var clicked_row := -1
	var clicked_col := -1

	if mouse_pos.y >= header_height and row_height > 0:
		var local_row: int = floori((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]

		if local_row >= 0 and local_row < _total_rows:
			clicked_row = local_row

	var current_x := -_h_scroll_position
	for col_idx in range(_columns.size()):
		var column := _columns[col_idx]

		if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
			clicked_col = col_idx
			break

		current_x += column.current_width

	if selected_rows.size() <= 1:
		set_selected_cell(clicked_row, clicked_col)

	cell_right_selected.emit(clicked_row, clicked_col, get_global_mouse_position())


func _handle_double_click(mouse_pos: Vector2) -> void:
	if mouse_pos.y < header_height: # Clicked on header
		return

	var row = -1
	if row_height > 0:
		row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]

	if row >= 0 and row < _total_rows:
		var current_x = -_h_scroll_position
		var col = -1

		for col_idx in _columns.size():
			var column := _columns[col_idx]
			if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
				col = col_idx
				break
			current_x += column.current_width

		if col != -1:
			# If the clicked cell is not the currently focused/selected one,
			# update the selection as a single click before starting editing.
			if not (selected_rows.size() == 1 and selected_rows[0] == row and focused_row == row and focused_col == col):
				set_selected_cell(row, col)

			_start_cell_editing(row, col)


func _handle_header_click(mouse_pos: Vector2) -> void:
	var current_x := -_h_scroll_position

	for col_idx in _columns.size():
		var column := _columns[col_idx]
		if (
			mouse_pos.x >= current_x + _divider_width / 2
			and mouse_pos.x < current_x + column.current_width - _divider_width / 2
		):
			# Finish editing if active
			_finish_editing(false)

			if _last_column_sorted == col_idx:
				_ascending = not _ascending
			else:
				_ascending = true

			ordering_data(col_idx, _ascending)
			header_clicked.emit(col_idx)
			break

		current_x += column.current_width


func _handle_header_double_click(mouse_pos: Vector2) -> void:
	_finish_editing(false) # Finish cell editing, if active
	var current_x := -_h_scroll_position

	for col_idx in _columns.size():
		var column := _columns[col_idx]
		if mouse_pos.x >= current_x and mouse_pos.x < current_x + column.current_width:
			var header_rect := Rect2(current_x, 0, column.current_width, header_height)
			_start_filtering(col_idx, header_rect)
			break

		current_x += column.current_width

#endregion

#region SIGNAL CALLBACKS

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		_handle_pan_gesture(event)

	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

	elif event is InputEventMouseButton:
		_handle_mouse_button(event)

	elif (
		event is InputEventKey
		and event.is_pressed()
		and has_focus()
	):
		_handle_key_input(event as InputEventKey)


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


func _on_resource_editor_resource_changed(res: Resource) -> void:
	_finish_editing(true)


func _on_path_editor_path_selected(path: String) -> void:
	_finish_editing(true)


func _on_double_click_timeout() -> void:
	_click_count = 0


func _on_h_scroll_changed(value) -> void:
	_h_scroll_position = value
	if _text_editor_line_edit.visible:
		_finish_editing(false)
	queue_redraw()


func _on_v_scroll_value_changed(value) -> void:
	_v_scroll_position = value
	if row_height > 0: # Avoid division by zero
		_visible_rows_range[0] = floor(value / row_height)
		_visible_rows_range[1] = _visible_rows_range[0] + floor((size.y - header_height) / row_height) + 1
		_visible_rows_range[1] = min(_visible_rows_range[1], _total_rows)
	else: # Fallback if row_height is not valid
		_visible_rows_range = [0, _total_rows]

	if _text_editor_line_edit.visible:
		_finish_editing(false)
	queue_redraw()


func _on_filter_focus_exited() -> void:
	# Apply the filter also when the text field loses focus
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
	#if (
	#EditorInterface.get_editor_settings().check_changed_settings_in_group("interface/theme")
	#or EditorInterface.get_editor_settings().get_changed_settings()interface / editor / main_font_size
	#):
	#set_native_theming(3)


func _on_resource_previewer_preview_invalidated(path: String) -> void:
	#push_warning("RESOURCE PREVIEW INVALIDATED: %s" % path)
	if _resource_thumb_cache.has(path):
		_resource_thumb_cache.erase(path)


func _on_resource_cell_thumb_ready(path: String, preview: Texture2D, thumbnail_preview: Texture2D, userdata: Variant) -> void:
	if typeof(userdata) != TYPE_DICTIONARY:
		return

	var key: String = userdata.get("key", "")
	if key.is_empty():
		return

	# Prefer thumbnail; fallback to preview if thumbnail missing
	var tex: Texture2D = thumbnail_preview if thumbnail_preview != null else preview

	# Fallback to resource class icon
	if not tex:
		tex = AnyIcon.get_class_icon(userdata.get("class", "Resource"))

	_resource_thumb_cache[key] = tex # can be null if both are null
	_resource_thumb_pending.erase(key)

	await get_tree().create_timer(0.01).timeout
	queue_redraw()

#endregion

class ColumnConfig:
	var identifier: String
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


	func _init(p_identifier: String, p_header: String, p_type: Variant.Type, p_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		identifier = p_identifier
		header = p_header
		type = p_type


	func is_path_column() -> bool:
		var is_filesystem_hint := property_hint in [
			PROPERTY_HINT_FILE,
			PROPERTY_HINT_FILE_PATH,
			PROPERTY_HINT_DIR,
		]
		return type == TYPE_STRING and is_filesystem_hint


	func is_progress_column() -> bool:
		#return type in [TYPE_FLOAT, TYPE_INT] and property_hint == PROPERTY_HINT_RANGE
		return false


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
		return type == TYPE_INT and property_hint == PROPERTY_HINT_ENUM


	func is_resource_column() -> bool:
		return type == TYPE_OBJECT and property_hint == PROPERTY_HINT_RESOURCE_TYPE
