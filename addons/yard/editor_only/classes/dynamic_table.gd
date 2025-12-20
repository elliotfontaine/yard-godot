# MIT License
# Copyright (c) 2025 Giuseppe Pica (jospic)
# https://github.com/jospic/dynamicdatatable

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

# Theming properties
@export_group("Default color")
@export var default_font_color: Color = Color(1.0, 1.0, 1.0)
@export_group("Header")
@export var headers: Array[String] = []
@export var header_height: float = 35.0
@export var header_color: Color = Color(0.2, 0.2, 0.2)
@export var header_filter_active_font_color: Color = Color(1.0, 1.0, 0.0)
@export_group("Size and grid")
@export var default_minimum_column_width: float = 50.0
@export var row_height: float = 30.0
@export var grid_color: Color = Color(0.8, 0.8, 0.8)
@export_group("Rows")
@export var selected_back_color: Color = Color(0.0, 0.0, 1.0, 0.5)
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

# Fonts
var font := get_theme_default_font()
var font_size := get_theme_default_font_size()

# Internal variables
var _data: Array = []
var _full_data: Array = []
var _column_widths: Array = []
var _min_column_widths: Array = []
var _total_rows := 0
var _total_columns := 0
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

# Selection and focus variables
var _selected_rows: Array = [] # Indices of the selected rows
var _previous_sort_selected_rows: Array = [] # Array containing the selected rows before sorting
var _anchor_row: int = -1 # Anchor row for Shift-based selection
var _focused_row: int = -1 # Currently focused row
var _focused_col: int = -1 # Currently focused column

# Editing variables
var _editing_cell := [-1, -1]
var _edit_line_edit: LineEdit
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
	_v_scroll.offset_left = -12
	_v_scroll.value_changed.connect(_on_v_scroll_changed)
	
	add_child(_h_scroll)
	add_child(_v_scroll)
	
	_update_column_widths()
	
	resized.connect(_on_resized)
	gui_input.connect(_on_gui_input) # Manage input from keyboard whwn has focus control
	
	self.anchor_left = 0.0
	self.anchor_top = 0.0
	self.anchor_right = 1.0
	self.anchor_bottom = 1.0
		
	queue_redraw()


func _draw() -> void:
	if not is_inside_tree(): return
	
	var current_x_offset := -_h_scroll_position
	var current_y_offset := header_height
	var visible_drawing_width = size.x - (_v_scroll.size.x if _v_scroll.visible else 0)
	var header_font_color := default_font_color
	
	draw_rect(Rect2(0, 0, size.x, header_height), header_color)
	
	var header_cell_x := current_x_offset
	for col in range(_total_columns):
		if col >= _column_widths.size(): continue # Safety check
		var col_width = _column_widths[col]
		if header_cell_x + col_width > 0 and header_cell_x < visible_drawing_width:
			draw_line(Vector2(header_cell_x, 0), Vector2(header_cell_x, header_height), grid_color)
			var rect_width = min(header_cell_x + col_width, visible_drawing_width)
			draw_line(Vector2(header_cell_x, header_height), Vector2(rect_width, header_height), grid_color)
			
			if col < headers.size():
				var align_info = _align_text_in_cell(col) # Array [text, h_align, x_margin]
				var header_text_content = align_info[0]
				var h_align_val = align_info[1]
				var x_margin_val = align_info[2]
				if (col == _filtering_column):
					header_font_color = header_filter_active_font_color
					header_text_content += " (" + str(_data.size()) + ")"
				else:
					header_font_color = default_font_color
				var text_size = font.get_string_size(header_text_content, h_align_val, col_width, font_size)
				draw_string(font, Vector2(header_cell_x + x_margin_val, header_height / 2.0 + text_size.y / 2.0 - (font_size / 2.0 - 2.0)), header_text_content, h_align_val, col_width - abs(x_margin_val), font_size, header_font_color)
				if (col == _last_column_sorted):
					var icon_h_align = HORIZONTAL_ALIGNMENT_LEFT
					if (h_align_val == HORIZONTAL_ALIGNMENT_LEFT or h_align_val == HORIZONTAL_ALIGNMENT_CENTER):
						icon_h_align = HORIZONTAL_ALIGNMENT_RIGHT
					draw_string(font, Vector2(header_cell_x, header_height / 2.0 + text_size.y / 2.0 - (font_size / 2.0 - 1.0)), _icon_sort, icon_h_align, col_width, font_size / 1.3, header_font_color)
	
			var divider_x_pos = header_cell_x + col_width
			if (divider_x_pos < visible_drawing_width and col <= _total_columns - 1): # Do not draw for the last column
				draw_line(Vector2(divider_x_pos, 0), Vector2(divider_x_pos, header_height), grid_color, 2.0 if _mouse_over_divider == col else 1.0)
		header_cell_x += col_width
				
	# Draw data rows
	for row in range(_visible_rows_range[0], _visible_rows_range[1]):
		if row >= _total_rows: continue # Safety break
		var row_y_pos = current_y_offset + (row - _visible_rows_range[0]) * row_height
		
		var current_bg_color = alternate_row_color if row % 2 == 1 else row_color
		draw_rect(Rect2(0, row_y_pos, visible_drawing_width, row_height), current_bg_color)
		
		if _selected_rows.has(row):
			draw_rect(Rect2(0, row_y_pos, visible_drawing_width, row_height - 1), selected_back_color)

		draw_line(Vector2(0, row_y_pos + row_height), Vector2(visible_drawing_width, row_y_pos + row_height), grid_color)
		
		var cell_x_pos = current_x_offset # Relative to -_h_scroll_position
		for col in range(_total_columns):
			if col >= _column_widths.size(): continue
			var current_col_width = _column_widths[col]
			
			if cell_x_pos < visible_drawing_width and cell_x_pos + current_col_width > 0:
				draw_line(Vector2(cell_x_pos, row_y_pos), Vector2(cell_x_pos, row_y_pos + row_height), grid_color)
						
				if not (_editing_cell[0] == row and _editing_cell[1] == col):
					if _is_progress_column(col):
						_draw_progress_bar(cell_x_pos, row_y_pos, col, row)
					elif _is_checkbox_column(col):
						_draw_checkbox(cell_x_pos, row_y_pos, col, row)
					elif _is_image_column(col):
						_draw_image_cell(cell_x_pos, row_y_pos, col, row)
					else:
						_draw_cell_text(cell_x_pos, row_y_pos, col, row)
			cell_x_pos += current_col_width
		
		# Draw the final right vertical line of the table (right border of the last column)
		if cell_x_pos <= visible_drawing_width and cell_x_pos > -_h_scroll_position:
			draw_line(Vector2(cell_x_pos, row_y_pos), Vector2(cell_x_pos, row_y_pos + row_height), grid_color)


#region PUBLIC METHODS

func set_headers(new_headers: Array) -> void:
	var typed_headers: Array[String] = []
	for header in new_headers: typed_headers.append(String(header))
	headers = typed_headers
	_update_column_widths()
	_update_scrollbars()
	queue_redraw()


func set_data(new_data: Array) -> void:
	# Store a full copy of the data as the master list
	_full_data = new_data.duplicate(true)
	# The view (_data) contains references to rows in the master list
	_data = _full_data.duplicate(false)
	
	_total_rows = _data.size()
	_visible_rows_range = [0, min(_total_rows, floor(self.size.y / row_height) if row_height > 0 else 0)]
	
	_selected_rows.clear()
	_anchor_row = -1
	_focused_row = -1
	_focused_col = -1
	
	var blank := false
	for row_data_item in _data:
		while row_data_item.size() < _total_columns:
			row_data_item.append(blank)
	
	for r in range(_total_rows):
		for col in range(_total_columns):
			var header_size := font.get_string_size(str(_get_header_text(col)), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var data_s := Vector2.ZERO
			
			if _is_progress_column(col):
				data_s = Vector2(default_minimum_column_width + 20, font_size)
			elif _is_checkbox_column(col):
				data_s = Vector2(default_minimum_column_width - 50, font_size)
			elif _is_image_column(col):
				data_s = Vector2(row_height, row_height)
			else:
				if r < _data.size() and col < _data[r].size():
					data_s = font.get_string_size(str(_data[r][col]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			
			if (_column_widths[col] < max(header_size.x, data_s.x)):
				_column_widths[col] = max(header_size.x, data_s.x) + font_size * 4
				_min_column_widths[col] = _column_widths[col]
			
	_update_scrollbars()
	queue_redraw()


func ordering_data(column_index: int, ascending: bool = true) -> int:
	_finish_editing(false)
	_last_column_sorted = column_index
	_store_selected_rows()
	if _is_date_column(column_index):
		_data.sort_custom(func(a: Array, b: Array) -> bool:
			var a_val := _parse_date(str(a[column_index]))
			var b_val := _parse_date(str(b[column_index]))
			_set_icon_down() if ascending else _set_icon_up()
			_restore_selected_rows()
			return a_val < b_val if ascending else a_val > b_val)
	elif _is_progress_column(column_index):
		_data.sort_custom(func(a: Array, b: Array) -> bool:
			var a_val := _get_progress_value(a[column_index])
			var b_val := _get_progress_value(b[column_index])
			_set_icon_down() if ascending else _set_icon_up()
			_restore_selected_rows()
			return a_val < b_val if ascending else a_val > b_val)
	elif _is_checkbox_column(column_index):
		_data.sort_custom(func(a: Array, b: Array) -> bool:
			var a_val := bool(a[column_index])
			var b_val := bool(b[column_index])
			_set_icon_down() if ascending else _set_icon_up()
			_restore_selected_rows()
			return (a_val and not b_val) if ascending else (not a_val and b_val))
	else:
		_data.sort_custom(func(a: Array, b: Array) -> bool:
			var a_val: Variant = a[column_index]
			var b_val: Variant = b[column_index]
			_set_icon_down() if ascending else _set_icon_up()
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
			_restore_selected_rows()
			return a_val < b_val if ascending else a_val > b_val)
	queue_redraw()
	return -1 # The original function returned -1


func insert_row(index: int, row_data: Array) -> void:
	while row_data.size() < _total_columns: # Ensure column consistency
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
			_selected_rows.clear()
		_update_scrollbars()
		queue_redraw()


func update_cell(row: int, col: int, value: Variant) -> void:
	if row >= 0 and row < _data.size() and col >= 0 and col < _total_columns:
		while _data[row].size() <= col: _data[row].append("")
		_data[row][col] = value
		queue_redraw()


func get_cell_value(row: int, col: int) -> Variant:
	if row >= 0 and row < _data.size() and col >= 0 and col < _data[row].size():
		return _data[row][col]
	return null


func get_row_value(row: int) -> Variant:
	if row >= 0 and row < _data.size(): return _data[row]
	return null


func get_progress_value(row_idx: int, col: int) -> float:
	if row_idx >= 0 and row_idx < _data.size() and col >= 0 and col < _data[row_idx].size():
		if _is_progress_column(col):
			return _get_progress_value(_data[row_idx][col]) # Use the internal function for the logic
	return 0.0


func set_selected_cell(row: int, col: int) -> void:
	if row >= 0 and row < _total_rows and col >= 0 and col < _total_columns:
		_focused_row = row
		_focused_col = col
		_selected_rows.clear()
		_selected_rows.append(row)
		_anchor_row = row
		_ensure_row_visible(row)
		queue_redraw()
	else: # Invalid selection, clear everything
		_focused_row = -1
		_focused_col = -1
		_selected_rows.clear()
		_anchor_row = -1
		queue_redraw()
	cell_selected.emit(_focused_row, _focused_col)


func set_progress_value(row: int, col: int, value: float) -> void:
	if row >= 0 and row < _data.size() and col >= 0 and col < _total_columns:
		if _is_progress_column(col):
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
	_edit_line_edit = LineEdit.new()
	_edit_line_edit.visible = false
	_edit_line_edit.text_submitted.connect(_on_edit_text_submitted)
	_edit_line_edit.focus_exited.connect(_on_edit_focus_exited)
	add_child(_edit_line_edit)
	
	_double_click_timer = Timer.new()
	_double_click_timer.wait_time = _double_click_threshold / 1000.0
	_double_click_timer.one_shot = true
	_double_click_timer.timeout.connect(_on_double_click_timeout)
	add_child(_double_click_timer)


func _update_column_widths() -> void:
	_column_widths.resize(headers.size())
	_min_column_widths.resize(headers.size())
	for i in range(headers.size()):
		if i >= _column_widths.size() or _column_widths[i] == 0 or _column_widths[i] == null:
			_column_widths[i] = default_minimum_column_width
			_min_column_widths[i] = default_minimum_column_width
	_total_columns = headers.size()


func _update_scrollbars() -> void:
	if not is_inside_tree(): return
	if _total_rows == null or row_height == null:
		_total_rows = 0 if _total_rows == null else _total_rows
		row_height = 30.0 if row_height == null or row_height <= 0 else row_height

	var visible_width = size.x - (_v_scroll.size.x if _v_scroll.visible else 0)
	var visible_height = size.y - (_h_scroll.size.y if _h_scroll.visible else 0) - header_height

	var total_content_width := 0
	for width in _column_widths:
		if width != null: total_content_width += width

	_h_scroll.visible = total_content_width > visible_width
	if _h_scroll.visible:
		_h_scroll.max_value = total_content_width
		_h_scroll.page = visible_width
		_h_scroll.step = default_minimum_column_width / 2.0 # Ensure float division

	var total_content_height := float(_total_rows) * row_height
	_v_scroll.visible = total_content_height > visible_height
	if _v_scroll.visible:
		_v_scroll.max_value = total_content_height
		_v_scroll.page = visible_height
		_v_scroll.step = row_height


func _is_date_string(value: String) -> bool:
	var date_regex := RegEx.new()
	date_regex.compile("^\\d{2}/\\d{2}/\\d{4}$")
	return date_regex.search(value) != null


func _is_date_column(column_index: int) -> bool:
	var match_count := 0
	var total := 0
	for row_data_item in _data:
		if column_index >= row_data_item.size():
			continue
		var value := str(row_data_item[column_index])
		total += 1
		if _is_date_string(value):
			match_count += 1
	return (total > 0 and match_count > total / 2)


func _is_progress_column(column_index: int) -> bool:
	if column_index >= headers.size():
		return false
	var header_parts := headers[column_index].split("|")
	return header_parts.size() > 1 and (header_parts[1].to_lower().contains("p") or header_parts[1].to_lower().contains("progress"))


func _is_checkbox_column(column_index: int) -> bool:
	if column_index >= headers.size():
		return false
	var header_parts := headers[column_index].split("|")
	return header_parts.size() > 1 and (header_parts[1].to_lower().contains("check") or header_parts[1].to_lower().contains("checkbox"))


func _is_image_column(column_index: int) -> bool:
	if column_index >= headers.size():
		return false
	var header_parts := headers[column_index].split("|")
	return header_parts.size() > 1 and header_parts[1].to_lower().contains("image")


func _is_numeric_value(value: Variant) -> bool:
	if value == null:
		return false
	var str_val := str(value)
	return str_val.is_valid_float() or str_val.is_valid_int()


func _get_progress_value(value: Variant) -> float:
	if value == null: return 0.0
	var num_val := 0.0
	if _is_numeric_value(value): num_val = float(str(value))
	if num_val >= 0.0 and num_val <= 1.0: return num_val
	elif num_val >= 0.0 and num_val <= 100.0: return num_val / 100.0
	else: return clamp(num_val, 0.0, 1.0)


func _parse_date(date_str: String) -> Array:
	var parts := date_str.split("/")
	if parts.size() != 3: return [0, 0, 0]
	return [int(parts[2]), int(parts[1]), int(parts[0])] # Year, Month, Day


func _store_selected_rows() -> void:
	if (_selected_rows.size() == 0):
		return
	_previous_sort_selected_rows.clear()
	for index in range(_selected_rows.size()):
		_previous_sort_selected_rows.append(_data[_selected_rows[index]])


func _restore_selected_rows() -> void:
	if (_previous_sort_selected_rows.size() == 0):
		return
	_selected_rows.clear()
	for index in range(_previous_sort_selected_rows.size()):
		var idx := _data.find(_previous_sort_selected_rows[index])
		if (idx >= 0):
			_selected_rows.append(idx)


func _start_cell_editing(row: int, col: int) -> void:
	if _is_checkbox_column(col): return # or _is_progress_column(col)  enable also for progress bar column
	_editing_cell = [row, col]
	var cell_rect := _get_cell_rect(row, col)
	if cell_rect == Rect2(): return
	_edit_line_edit.position = cell_rect.position
	_edit_line_edit.size = cell_rect.size
	var cell_value := get_cell_value(row, col)
	if cell_value is float:
		cell_value = snapped(cell_value, 0.01)
	_edit_line_edit.text = str(cell_value) if get_cell_value(row, col) != null else ""
	_edit_line_edit.visible = true
	_edit_line_edit.grab_focus()
	_edit_line_edit.select_all()


func _finish_editing(save_changes: bool = true) -> void:
	if _editing_cell[0] >= 0 and _editing_cell[1] >= 0:
		if save_changes and _edit_line_edit.visible:
			var old_value: Variant = get_cell_value(_editing_cell[0], _editing_cell[1])
			var new_value_text := _edit_line_edit.text
			var new_value: Variant = new_value_text # # Default to string
			if new_value_text.is_valid_int(): new_value = int(new_value_text)
			elif new_value_text.is_valid_float(): new_value = float(new_value_text)
			update_cell(_editing_cell[0], _editing_cell[1], new_value)
			cell_edited.emit(_editing_cell[0], _editing_cell[1], old_value, new_value)
		_editing_cell = [-1, -1]
		_edit_line_edit.visible = false
		queue_redraw()


func _get_cell_rect(row: int, col: int) -> Rect2:
	if row < _visible_rows_range[0] or row >= _visible_rows_range[1]: return Rect2()
	var x_offset := -_h_scroll_position
	var cell_x := x_offset
	for c in range(col): cell_x += _column_widths[c]
	var visible_w = size.x - (_v_scroll.size.x if _v_scroll.visible else 0)
	if col >= _column_widths.size() or cell_x + _column_widths[col] <= 0 or cell_x >= visible_w: return Rect2()
	var row_y_pos = header_height + (row - _visible_rows_range[0]) * row_height
	return Rect2(cell_x, row_y_pos, _column_widths[col], row_height)


func _get_header_text(col: int) -> String:
	if col >= headers.size(): return ""
	return headers[col].split("|")[0]
func _draw_progress_bar(cell_x: float, row_y: float, col: int, row: int) -> void:
	var cell_value = 0.0
	if row < _data.size() and col < _data[row].size():
		cell_value = _get_progress_value(_data[row][col])
	
	var margin := 4.0
	var bar_x_pos := cell_x + margin
	var bar_y_pos := row_y + margin
	var bar_width = _column_widths[col] - (margin * 2.0)
	var bar_h := row_height - (margin * 2.0)
	
	draw_rect(Rect2(bar_x_pos, bar_y_pos, bar_width, bar_h), progress_background_color)
	draw_rect(Rect2(bar_x_pos, bar_y_pos, bar_width, bar_h), progress_border_color, false, 1.0)
	
	var progress_w = bar_width * cell_value
	if progress_w > 0:
		draw_rect(Rect2(bar_x_pos, bar_y_pos, progress_w, bar_h), _get_interpolated_three_colors(progress_bar_start_color, progress_bar_middle_color, progress_bar_end_color, cell_value))
		
	var perc_text := str(int(round(cell_value * 100.0))) + "%"
	var text_size := font.get_string_size(perc_text, HORIZONTAL_ALIGNMENT_CENTER, bar_width, font_size)
	draw_string(font, Vector2(bar_x_pos + bar_width / 2.0 - text_size.x / 2.0, bar_y_pos + bar_h / 2.0 + text_size.y / 2.0 - 5.0), perc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, progress_text_color)


func _draw_checkbox(cell_x: float, row_y: float, col: int, row: int) -> void:
	var cell_value := false
	if row < _data.size() and col < _data[row].size():
		cell_value = bool(_data[row][col])
	
	var checkbox_size = min(row_height, _column_widths[col]) * 0.6
	var x_offset_centered = cell_x + (_column_widths[col] - checkbox_size) / 2.0
	var y_offset_centered = row_y + (row_height - checkbox_size) / 2.0
	
	var checkbox_rect := Rect2(x_offset_centered, y_offset_centered, checkbox_size, checkbox_size)
	
	draw_rect(checkbox_rect, checkbox_border_color, false, 1.0) # Border
	
	var fill_rect := checkbox_rect.grow(-checkbox_size * 0.15)
	if cell_value:
		draw_rect(fill_rect, checkbox_checked_color)
	else:
		draw_rect(fill_rect, checkbox_unchecked_color)


func _draw_image_cell(cell_x: float, row_y: float, col: int, row: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not value is Texture2D:
		return # Draw only if the value is a texture

	var texture: Texture2D = value
	var margin := 2.0
	var cell_inner_width: float = _column_widths[col] - margin * 2
	var cell_inner_height: float = row_height - margin * 2
	
	if cell_inner_width <= 0 or cell_inner_height <= 0:
		return

	var tex_size := texture.get_size()
	var tex_aspect := tex_size.x / tex_size.y
	var cell_aspect := cell_inner_width / cell_inner_height

	var drawn_rect := Rect2()
	if tex_aspect > cell_aspect:
		# The texture is wider than the cell, fit to width
		drawn_rect.size.x = cell_inner_width
		drawn_rect.size.y = cell_inner_width / tex_aspect
		drawn_rect.position.x = cell_x + margin
		drawn_rect.position.y = row_y + margin + (cell_inner_height - drawn_rect.size.y) / 2
	else:
		# The texture is taller or equal, fit to height
		drawn_rect.size.y = cell_inner_height
		drawn_rect.size.x = cell_inner_height * tex_aspect
		drawn_rect.position.y = row_y + margin
		drawn_rect.position.x = cell_x + margin + (cell_inner_width - drawn_rect.size.x) / 2
		
	draw_texture_rect(texture, drawn_rect, false)


func _get_interpolated_three_colors(start_c: Color, mid_c: Color, end_c: Color, t_val: float) -> Color:
	var clamped_t = clampf(t_val, 0.0, 1.0)
	if clamped_t <= 0.5:
		return start_c.lerp(mid_c, clamped_t * 2.0)
	else:
		return mid_c.lerp(end_c, (clamped_t - 0.5) * 2.0)


func _draw_cell_text(cell_x: float, row_y: float, col: int, row: int) -> void:
	var cell_value = ""
	if row >= 0 and row < _data.size() and col >= 0 and col < _data[row].size(): # bounds check
		cell_value = str(_data[row][col])
	
	var align_info = _align_text_in_cell(col)
	var h_align_val = align_info[1]
	var x_margin_val = align_info[2]
	
	var text_size = font.get_string_size(
		cell_value,
		h_align_val,
		_column_widths[col] - abs(x_margin_val) * 2,
		font_size
	)
	var text_y_pos = row_y + row_height / 2.0 + text_size.y / 2.0 - (font_size / 2.0 - 2.0) # Y calculation to better center text
	draw_string(
		font,
		Vector2(cell_x + x_margin_val, text_y_pos),
		cell_value,
		h_align_val,
		_column_widths[col] - abs(x_margin_val),
		font_size,
		default_font_color
	)


func _align_text_in_cell(col: int) -> Array:
	var header_parts = headers[col].split("|")
	var h_alignment_character = ""
	if header_parts.size() > 1:
		for char_code in header_parts[1].to_lower():
			if char_code in ["l", "c", "r"]:
				h_alignment_character = char_code
				break
	
	var header_text_content = header_parts[0]
	var h_align_enum = HORIZONTAL_ALIGNMENT_LEFT
	var x_margin = 5
	if (h_alignment_character == "c"):
		h_align_enum = HORIZONTAL_ALIGNMENT_CENTER
		x_margin = 0
	elif (h_alignment_character == "r"):
		h_align_enum = HORIZONTAL_ALIGNMENT_RIGHT
		x_margin = -5 # Negative for right margin
	return [header_text_content, h_align_enum, x_margin]


func _handle_cell_click(mouse_pos: Vector2, event: InputEventMouseButton) -> void:
	_finish_editing(true)

	var clicked_row = -1
	if row_height > 0: # Avoid division by zero
		clicked_row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]
	
	if clicked_row < 0 or clicked_row >= _total_rows: # Click outside valid row area
		# Optional: clear selection when clicking outside
		# _selected_rows.clear()
		# _anchor_row = -1
		# _focused_row = -1
		# _focused_col = -1
		# queue_redraw()
		return

	var current_x_pos = - _h_scroll_position
	var clicked_col = -1
	for c in range(_total_columns):
		if c >= _column_widths.size(): continue
		if mouse_pos.x >= current_x_pos && mouse_pos.x < current_x_pos + _column_widths[c]:
			clicked_col = c
			break
		current_x_pos += _column_widths[c]

	if clicked_col == -1: return # Click outside column area

	_focused_row = clicked_row
	_focused_col = clicked_col

	var is_shift = event.is_shift_pressed()
	var is_ctrl_cmd = event.is_ctrl_pressed() or event.is_meta_pressed() # Ctrl or Cmd

	var selection_was_multiple = _selected_rows.size() > 1 # State before the change
	var emit_multiple_selection_signal = false

	if is_shift and _anchor_row != -1:
		_selected_rows.clear()
		var start_range = min(_anchor_row, _focused_row)
		var end_range = max(_anchor_row, _focused_row)
		for i in range(start_range, end_range + 1):
			_selected_rows.append(i)
		# After a Shift selection, if more than one row is selected, prepare to emit.
		if _selected_rows.size() > 1:
			emit_multiple_selection_signal = true
	elif is_ctrl_cmd:
		if _selected_rows.has(_focused_row):
			_selected_rows.erase(_focused_row)
		else:
			_selected_rows.append(_focused_row)
		_anchor_row = _focused_row # Update the anchor for future Shift selections
		# After a Ctrl/Cmd selection, if more than one row is selected, prepare to emit.
		if _selected_rows.size() > 1:
			emit_multiple_selection_signal = true
		# If the selection was multiple and now is no longer multiple (because Ctrl-click deselects),
		# you might still want to emit to indicate a change from a multiple-selection state.
		# However, the requirement is "when a multiple selection EXISTS".
		# So if _selected_rows.size() <= 1, we do not set emit_multiple_selection_signal = true.
	else: # Single click without modifiers
		_selected_rows.clear()
		_selected_rows.append(_focused_row)
		_anchor_row = _focused_row
		# In this case, _selected_rows.size() will be 1.
		# If the previous selection was multiple and now is single,
		# we do not emit multiple_rows_selected because a multiple selection no longer exists.

	cell_selected.emit(_focused_row, _focused_col) # Always emit for a valid cell click

	# Emit the new signal if a multiple selection was identified
	if emit_multiple_selection_signal:
		# _selected_rows already contains the correct indices
		multiple_rows_selected.emit(_selected_rows)
	# Also consider the case where the selection transitions from multiple to single/none
	# due to a Ctrl operation. If you want a signal for that "change" as well,
	# the logic here should be slightly different. But sticking to "when it exists",
	# the current approach is correct.

	queue_redraw()


func _handle_right_click(mouse_pos: Vector2) -> void:
	var row = -1
	var col = -1
	if mouse_pos.y >= header_height: # Non su header
		if row_height > 0: row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]
		if row >= 0 and row < _total_rows:
			var current_x = - _h_scroll_position
			for i in range(_total_columns):
				if i >= _column_widths.size(): continue
				if mouse_pos.x >= current_x and mouse_pos.x < current_x + _column_widths[i]:
					col = i; break
				current_x += _column_widths[i]
	if (_selected_rows.size() <= 1):
		set_selected_cell(row, col)
		cell_right_selected.emit(row, col, get_global_mouse_position())
	if (_total_rows > 0 and row <= _total_rows):
		cell_right_selected.emit(row, col, get_global_mouse_position())
	elif (row > _total_rows):
		cell_right_selected.emit(_total_rows, col, get_global_mouse_position())


func _handle_double_click(mouse_pos: Vector2) -> void:
	if mouse_pos.y >= header_height: # Not on the header
		var row = -1
		if row_height > 0:
			row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]
		
		if row >= 0 and row < _total_rows:
			var current_x = - _h_scroll_position
			var col = -1
			for i in range(_total_columns):
				if i >= _column_widths.size(): continue
				if mouse_pos.x >= current_x and mouse_pos.x < current_x + _column_widths[i]:
					col = i
					break
				current_x += _column_widths[i]
			
			if col != -1:
				# If the clicked cell is not the currently focused/selected one,
				# update the selection as a single click before starting editing.
				if not (_selected_rows.size() == 1 and _selected_rows[0] == row and _focused_row == row and _focused_col == col):
					_focused_row = row
					_focused_col = col
					_selected_rows.clear()
					_selected_rows.append(row)
					_anchor_row = row
					cell_selected.emit(row, col) # Emit selection signal
					queue_redraw() # Update the selection view
					
				_start_cell_editing(row, col)


func _handle_header_click(mouse_pos: Vector2) -> void:
	var current_x = - _h_scroll_position
	for col in range(_total_columns):
		if col >= _column_widths.size():
			continue

		if (
			mouse_pos.x >= current_x + _divider_width / 2
			and mouse_pos.x < current_x + _column_widths[col] - _divider_width / 2
		):
			# Finish editing if active
			_finish_editing(false)

			if _last_column_sorted == col:
				_ascending = not _ascending
			else:
				_ascending = true

			ordering_data(col, _ascending)
			header_clicked.emit(col)
			break

		current_x += _column_widths[col]


func _handle_header_double_click(mouse_pos: Vector2) -> void:
	_finish_editing(false) # Finish cell editing, if active
	var current_x = - _h_scroll_position
	for col in range(_total_columns):
		if col >= _column_widths.size():
			continue

		var col_width = _column_widths[col]
		if mouse_pos.x >= current_x and mouse_pos.x < current_x + col_width:
			var header_rect = Rect2(current_x, 0, col_width, header_height)
			_start_filtering(col, header_rect)
			break

		current_x += col_width


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
		var filtered_data = []
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
	_selected_rows.clear()
	_previous_sort_selected_rows.clear()
	_focused_row = -1
	_last_column_sorted = -1 # Reset visual sorting
	
	_update_scrollbars()
	queue_redraw()


func _check_mouse_over_divider(mouse_pos: Vector2) -> void:
	_mouse_over_divider = -1
	mouse_default_cursor_shape = CURSOR_ARROW

	if mouse_pos.y < header_height:
		var current_x = - _h_scroll_position
		for col in range(_total_columns - 1): # Not for the last column
			if col >= _column_widths.size():
				continue

			current_x += _column_widths[col]
			var divider_rect = Rect2(
				current_x - _divider_width / 2,
				0,
				_divider_width,
				header_height
			)

			if divider_rect.has_point(mouse_pos):
				_mouse_over_divider = col
				mouse_default_cursor_shape = CURSOR_HSIZE

	queue_redraw() # Refresh to show the highlighted divider


func _update_tooltip(mouse_pos: Vector2) -> void:
	var current_cell = [-1, -1]
	var new_tooltip = ""

	if mouse_pos.y < header_height:
		var current_x = - _h_scroll_position
		for col in range(_total_columns):
			if col >= _column_widths.size(): continue
			var col_width = _column_widths[col]
			if mouse_pos.x >= current_x and mouse_pos.x < current_x + col_width:
				var header_text = _get_header_text(col)
				var text_width = font.get_string_size(header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				new_tooltip = header_text
				current_cell = [-2, col]
				break
			current_x += col_width
	else:
		var row = floor((mouse_pos.y - header_height) / row_height) + _visible_rows_range[0]
		if row >= 0 and row < _total_rows:
			var current_x = - _h_scroll_position
			for col in range(_total_columns):
				if col >= _column_widths.size(): continue
				var col_width = _column_widths[col]
				if mouse_pos.x >= current_x and mouse_pos.x < current_x + col_width:
					if not _is_image_column(col) and not _is_progress_column(col) and not _is_checkbox_column(col):
						var cell_text = str(get_cell_value(row, col))
						var text_width = font.get_string_size(cell_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
						new_tooltip = cell_text
					current_cell = [row, col]
					break
				current_x += col_width

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
	var col := -1

	for i in range(_total_columns):
		if i >= _column_widths.size():
			continue
		if mouse_pos.x >= current_x and mouse_pos.x < current_x + _column_widths[i]:
			col = i
			break
		current_x += _column_widths[i]
	
	if col >= 0 and _is_progress_column(col):
		# Set _focused_row and _focused_col when clicking on a progress bar
		# This ensures the row becomes "active"
		if _focused_row != row or _focused_col != col:
			_focused_row = row
			_focused_col = col
			# If not already selected, select it as a single row
			if not _selected_rows.has(row):
				_selected_rows.clear()
				_selected_rows.append(row)
				_anchor_row = row
			cell_selected.emit(_focused_row, _focused_col) # Emit signal
			queue_redraw()
		_progress_drag_row = row
		_progress_drag_col = col
		return true

	return false


func _handle_progress_drag(mouse_pos: Vector2) -> void:
	if (
		_progress_drag_row < 0
		or _progress_drag_col < 0
		or _progress_drag_col >= _column_widths.size()
	):
		return
	
	var current_x := -_h_scroll_position
	for col_loop in range(_progress_drag_col):
		current_x += _column_widths[col_loop]
	
	var margin := 4.0
	var bar_x_pos := current_x + margin
	var bar_width = _column_widths[_progress_drag_col] - (margin * 2.0)

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
	var col := -1

	for i in range(_total_columns):
		if i >= _column_widths.size():
			continue

		if mouse_pos.x >= current_x and mouse_pos.x < current_x + _column_widths[i]:
			col = i
			break

		current_x += _column_widths[i]
	
	if col >= 0 and _is_checkbox_column(col):
		# When clicking a checkbox, the row becomes the current single selection (if not already)
		if _focused_row != row or _focused_col != col:
			_focused_row = row
			_focused_col = col

			# If it is not the only selected row
			if not _selected_rows.has(row) or _selected_rows.size() > 1:
				_selected_rows.clear()
				_selected_rows.append(row)
				_anchor_row = row

			cell_selected.emit(_focused_row, _focused_col) # Emit focus signal
			# Do not call queue_redraw() here; it will be done after update_cell

		var old_val: Variant = get_cell_value(row, col)
		var new_val := not bool(old_val)

		update_cell(row, col, new_val) # update_cell calls queue_redraw()
		cell_edited.emit(row, col, old_val, new_val)
		return true

	return false


func _ensure_row_visible(row_idx: int) -> void:
	if _total_rows == 0 or row_height == 0 or not _v_scroll.visible:
		return

	var visible_area_height = size.y - header_height - (_h_scroll.size.y if _h_scroll.visible else 0)
	var num_visible_rows_in_page = floor(visible_area_height / row_height)
	
	# _visible_rows_range[0] is the first visible row (0-based index)
	# _visible_rows_range[1] is the index of the first row that is NOT visible at the bottom
	# Therefore, visible rows go from _visible_rows_range[0] to _visible_rows_range[1] - 1
	
	var first_fully_visible_row = _visible_rows_range[0]
	# The last fully visible row is approximately:
	# first_fully_visible_row + num_visible_rows_in_page - 1
	# However, _visible_rows_range[1] gives a more accurate upper bound
	# including partially visible rows.
	
	if row_idx < first_fully_visible_row:
		# The row is above the current viewport
		_v_scroll.value = row_idx * row_height
	elif row_idx >= first_fully_visible_row + num_visible_rows_in_page:
		# The row is below the current viewport
		# Scroll so that row_idx becomes the last (or nearly last) visible row
		_v_scroll.value = (row_idx - num_visible_rows_in_page + 1) * row_height
	
	_v_scroll.value = clamp(_v_scroll.value, 0, _v_scroll.max_value)
	# _on_v_scroll_changed will be called, updating _visible_rows_range
	# and triggering queue_redraw()


func _handle_key_input(event: InputEventKey) -> void:
	if _edit_line_edit.visible: # Let the LineEdit handle input during editing
		if event.keycode == KEY_ESCAPE: # Except ESC to cancel
			_finish_editing(false)
			get_viewport().set_input_as_handled()
		return

	var keycode := event.keycode
	var is_shift := event.is_shift_pressed()
	var is_ctrl := event.is_ctrl_pressed()
	var is_meta := event.is_meta_pressed() # Cmd on Mac
	var is_ctrl_cmd := is_ctrl or is_meta # For actions like Ctrl+A / Cmd+A

	var current_focused_r := _focused_row
	var current_focused_c := _focused_col

	var new_focused_r := current_focused_r
	var new_focused_c := current_focused_c
	
	var key_operation_performed := false # Flag to track whether a key operation modified the state
	var event_consumed := true # Assume the event will be consumed unless stated otherwise
	var emit_multiple_selection_signal := false
	
	if is_ctrl_cmd and keycode == KEY_A:
		if _total_rows > 0:
			_selected_rows.clear()
			for i in range(_total_rows):
				_selected_rows.append(i)
			emit_multiple_selection_signal = true
			
			# Set or keep focus and anchor
			if current_focused_r == -1: # If there is no focus, go to the first row
				_focused_row = 0
				_focused_col = 0 if _total_columns > 0 else -1
				_anchor_row = 0
			else: # Otherwise, keep the current focus as anchor
				_anchor_row = _focused_row
			
			_ensure_row_visible(_focused_row)
			# Consider _ensure_col_visible(_focused_col) if implemented
		key_operation_performed = true

	elif keycode == KEY_HOME:
		if _total_rows > 0:
			new_focused_r = 0
			new_focused_c = 0 if _total_columns > 0 else -1
			key_operation_performed = true
		else:
			event_consumed = false # No rows, no action

	elif keycode == KEY_END:
		if _total_rows > 0:
			new_focused_r = _total_rows - 1
			new_focused_c = (_total_columns - 1) if _total_columns > 0 else -1
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
				new_focused_c = min(_total_columns - 1, current_focused_c + 1)
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
					if _selected_rows.has(current_focused_r):
						_selected_rows.erase(current_focused_r)
					else:
						if not _selected_rows.has(current_focused_r): _selected_rows.append(current_focused_r)
					_anchor_row = current_focused_r
					key_operation_performed = true
				else: event_consumed = false
			KEY_ESCAPE:
				if _selected_rows.size() > 0 or _focused_row != -1: # Act only if there is a selection or focus
					_selected_rows.clear()
					_previous_sort_selected_rows.clear()
					_anchor_row = -1
					_focused_row = -1
					_focused_col = -1
					key_operation_performed = true
					set_selected_cell(-1, -1)
				else:
					event_consumed = false # No selection/focus to cancel
		
	else: # No initial focus for most navigation keys, or unhandled key above
		event_consumed = false

	# If the focus changed or a key operation modified the selection state
	if key_operation_performed and (new_focused_r != current_focused_r or new_focused_c != current_focused_c or keycode in [KEY_HOME, KEY_END, KEY_SPACE, KEY_A]):
		var old_focused_r := _focused_row # Save previous focus for anchor
		
		_focused_row = new_focused_r
		_focused_col = new_focused_c

		# Selection update logic
		if not (is_ctrl_cmd and keycode == KEY_A): # Ctrl+A handles its own selection
			#var emit_multiple_selection_signal = false
			if is_shift:
				# Set anchor if not defined, using previous focus or 0 as fallback
				if _anchor_row == -1:
					_anchor_row = old_focused_r if old_focused_r != -1 else 0
				
				if _focused_row != -1: # Only if the new focused row is valid
					_selected_rows.clear()
					var start_r: int = min(_anchor_row, _focused_row)
					var end_r: int = max(_anchor_row, _focused_row)
					for i in range(start_r, end_r + 1):
						if i >= 0 and i < _total_rows: # Check index validity
							if not _selected_rows.has(i):
								_selected_rows.append(i)
								emit_multiple_selection_signal = true
				# If _focused_row is -1 (e.g. empty table), _selected_rows stays empty or cleared
				#if emit_multiple_selection_signal:
					# The _selected_rows array already contains the correct indices
					#multiple_rows_selected.emit(_selected_rows)
			
			elif is_ctrl_cmd and not (keycode == KEY_SPACE):
				# Ctrl + Arrows/Pg/Home/End: move focus only, do not change selection.
				# The anchor does not change to allow future Shift selections.
				pass
			elif not (keycode == KEY_SPACE and is_ctrl_cmd):
				# No modifier (or Ctrl not for pure navigation): select only the focused row
				if _focused_row != -1: # Only if the new focused row is valid
					_selected_rows.clear()
					_selected_rows.append(_focused_row)
					_anchor_row = _focused_row
					#emit_multiple_selection_signal = true
				else: # The new focused row is not valid (e.g. empty table)
					_selected_rows.clear()
					_anchor_row = -1
				
					
		if _focused_row != -1:
			_ensure_row_visible(_focused_row)
			# You could add here: _ensure_col_visible(_focused_col) if you want automatic horizontal scrolling
		
		if current_focused_r != _focused_row or current_focused_c != _focused_col or (keycode == KEY_SPACE and is_ctrl_cmd):
			# Emit the signal only if the focus actually changed or if Ctrl+Space modified the selection
			#cell_selected.emit(_focused_row, _focused_col)
			pass
		
		if emit_multiple_selection_signal:
			# The _selected_rows array already contains the correct indices
			multiple_rows_selected.emit(_selected_rows)
		
	if key_operation_performed:
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event_consumed: # Consume the event if it was partially handled (e.g. key recognized but no action)
		get_viewport().set_input_as_handled()


func _set_icon_down() -> void:
	_icon_sort = " ▼ "


func _set_icon_up() -> void:
	_icon_sort = " ▲ "

#endregion


#region SIGNAL CALLBACKS

func _on_resized() -> void:
	_update_scrollbars()
	queue_redraw()


func _on_edit_text_submitted(text: String) -> void:
	_finish_editing(true)


func _on_edit_focus_exited() -> void:
	_finish_editing(true)


func _on_double_click_timeout() -> void:
	_click_count = 0


func _on_h_scroll_changed(value) -> void:
	_h_scroll_position = value
	if _edit_line_edit.visible: _finish_editing(false)
	queue_redraw()


func _on_v_scroll_changed(value) -> void:
	_v_scroll_position = value
	if row_height > 0: # Avoid division by zero
		_visible_rows_range[0] = floor(value / row_height)
		_visible_rows_range[1] = _visible_rows_range[0] + floor((size.y - header_height) / row_height) + 1
		_visible_rows_range[1] = min(_visible_rows_range[1], _total_rows)
	else: # Fallback if row_height is not valid
		_visible_rows_range = [0, _total_rows]

	if _edit_line_edit.visible: _finish_editing(false)
	queue_redraw()


func _on_filter_focus_exited() -> void:
	# Apply the filter also when the text field loses focus
	if _filter_line_edit.visible:
		_apply_filter(_filter_line_edit.text)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_btn_event = event as InputEventMouseButton

		if mouse_btn_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_btn_event.pressed:
				var m_pos = mouse_btn_event.position

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
						_handle_cell_click(m_pos, mouse_btn_event)

						if _is_clicking_progress_bar(m_pos):
							_dragging_progress = true

					if _mouse_over_divider >= 0:
						_resizing_column = _mouse_over_divider
						_resizing_start_pos = m_pos.x
						_resizing_start_width = _column_widths[_resizing_column]

			else:
				# Mouse button released
				_resizing_column = -1
				_dragging_progress = false
				_progress_drag_row = -1
				_progress_drag_col = -1

		elif mouse_btn_event.button_index == MOUSE_BUTTON_RIGHT and mouse_btn_event.pressed:
			_handle_right_click(mouse_btn_event.position) # Use mouse_btn_event.position

		elif mouse_btn_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _v_scroll.visible:
				_v_scroll.value = max(
					0,
					_v_scroll.value - _v_scroll.step * 1
				)

		elif mouse_btn_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _v_scroll.visible:
				_v_scroll.value = min(
					_v_scroll.max_value,
					_v_scroll.value + _v_scroll.step * 1
				)

	elif event is InputEventMouseMotion:
		var mouse_mot_event = event as InputEventMouseMotion # Cast
		var m_pos = mouse_mot_event.position # Renamed from `mouse_pos`

		if (
			_dragging_progress
			and _progress_drag_row >= 0
			and _progress_drag_col >= 0
		):
			_handle_progress_drag(m_pos)

		elif (
			_resizing_column >= 0
			and _resizing_column < _total_columns - 1
		):
			# Changed from headers.size() to _total_columns
			var delta_x = m_pos.x - _resizing_start_pos
			var new_width = max(
				_resizing_start_width + delta_x,
				_min_column_widths[_resizing_column]
			)

			_column_widths[_resizing_column] = new_width
			_update_scrollbars()
			column_resized.emit(_resizing_column, new_width)
			queue_redraw()

		else:
			_check_mouse_over_divider(m_pos)
			_update_tooltip(m_pos)

	elif (
		event is InputEventKey
		and event.is_pressed()
		and has_focus()
	):
		# Keyboard input handling
		_handle_key_input(event as InputEventKey) # Call the dedicated handler
		# accept_event() or get_viewport().set_input_as_handled()
		# will be called inside _handle_key_input

#endregion
