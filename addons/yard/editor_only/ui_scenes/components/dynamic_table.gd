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

# Selection and focus variables (public)
var selected_rows: Array = [] # Indices of the selected rows
var focused_row: int = -1 # Currently focused row
var focused_col: int = -1 # Currently focused column

# Internal variables
var _columns: Array[ColumnConfig]
var _data: Array[Array] = []
var _full_data: Array = []
var _total_rows := 0
var _visible_rows_range: Array[int] = [0, 0]
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
var _dragging_start_value: Variant # int/float
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
var _enum_editor: PopupMenu
var _enum_editor_last_idx: int = -1
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
	_h_scroll.offset_top = -8 * get_theme_default_base_scale()
	_h_scroll.value_changed.connect(_on_h_scroll_changed)

	_v_scroll = VScrollBar.new()
	_v_scroll.name = "VScrollBar"
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


func _gui_input(event: InputEvent) -> void:
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


func _draw() -> void:
	if not is_inside_tree() or _columns.is_empty() or _full_data.is_empty():
		return

	var frozen_w := _get_frozen_width()
	var scroll_x := frozen_w - _h_scroll_position # screen X of first scrollable column
	var vis_w := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.0)
	var y_offset := header_height

	# ── HEADER BACKGROUND ──────────────────────────────────────────────────────
	draw_rect(Rect2(0, 0, size.x, header_height), header_color)

	# ── PASS 1 : SCROLLABLE COLUMNS ────────────────────────────────────────────
	_draw_header_column_range(n_frozen_columns, _columns.size(), scroll_x, frozen_w, vis_w)

	for row in range(_visible_rows_range[0], _visible_rows_range[1]):
		if row >= _total_rows:
			continue
		var row_y := y_offset + (row - _visible_rows_range[0]) * row_height
		var bg := alternate_row_color if row % 2 == 1 else row_color
		draw_rect(Rect2(0, row_y, vis_w, row_height), bg)
		if selected_rows.has(row):
			draw_rect(Rect2(0, row_y, vis_w, row_height - 1), selected_row_back_color)
		draw_line(Vector2(0, row_y + row_height), Vector2(vis_w, row_y + row_height), grid_color)
		_draw_cells_column_range(row, row_y, n_frozen_columns, _columns.size(), scroll_x, frozen_w, vis_w)

	# ── PASS 2 : FROZEN COLUMNS (drawn on top) ─────────────────────────────────
	if n_frozen_columns > 0:
		for row in range(_visible_rows_range[0], _visible_rows_range[1]):
			if row >= _total_rows:
				continue
			var row_y := y_offset + (row - _visible_rows_range[0]) * row_height
			var bg := alternate_row_color if row % 2 == 1 else row_color
			draw_rect(Rect2(0, row_y, frozen_w, row_height), bg)
			if selected_rows.has(row):
				draw_rect(Rect2(0, row_y, frozen_w, row_height - 1), selected_row_back_color)
			draw_line(Vector2(0, row_y + row_height), Vector2(frozen_w, row_y + row_height), grid_color)
			_draw_cells_column_range(row, row_y, 0, n_frozen_columns, 0.0, 0.0, frozen_w)

		# Frozen header on top of scrollable header
		draw_rect(Rect2(0, 0, frozen_w, header_height), header_color)
		_draw_header_column_range(0, n_frozen_columns, 0.0, 0.0, vis_w)

		# Separator shadow at the frozen/scrollable boundary
		var separator_bottom := header_height + mini(_total_rows, _visible_rows_range[1] - _visible_rows_range[0]) * row_height
		draw_line(Vector2(frozen_w, 0), Vector2(frozen_w, separator_bottom), grid_color.darkened(0.2), 2.0)

		if _v_scroll.visible:
			draw_rect(Rect2(vis_w, header_height, _v_scroll.size.x + 50, size.y), row_color)

#region PUBLIC METHODS

func set_native_theming(delay: int = 0) -> void:
	if delay != 0 and is_inside_tree():
		# Useful because the editor theme isn't instantly changed
		await get_tree().create_timer(delay).timeout

	var root := EditorInterface.get_base_control()
	font = root.get_theme_font(&"main", &"EditorFonts")
	default_font_color = root.get_theme_color(&"font_color", &"Editor")
	font_size = root.get_theme_font_size(&"main_size", &"EditorFonts")
	header_color = root.get_theme_color(&"dark_color_1", &"Editor")
	row_color = root.get_theme_color(&"base_color", &"Editor")
	alternate_row_color = root.get_theme_color(&"dark_color_3", &"Editor")
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
	_reset_column_widths()
	queue_redraw()


func get_column(index: int) -> ColumnConfig:
	return _columns[index] if index in range(_columns.size()) else null


func set_data(new_data: Array) -> void:
	# Store a full copy of the data as the master list
	_full_data = new_data.duplicate(true)
	# The view (_data) contains references to rows in the master list
	_data = _full_data.duplicate(false)

	_total_rows = _data.size()
	_visible_rows_range = [0, min(_total_rows, floori(self.size.y / row_height) if row_height > 0 else 0)]

	selected_rows.clear()
	_resource_thumb_cache.clear()
	_resource_thumb_pending.clear()
	_anchor_row = -1
	focused_row = -1
	focused_col = -1

	var blank: Variant = CELL_INVALID
	for row_data_item: Array in _data:
		while row_data_item.size() < _columns.size():
			row_data_item.append(blank)

	_update_scrollbars()
	queue_redraw()


func ordering_data(column_index: int, ascending: bool = true) -> void:
	if not get_column(column_index):
		return
	_finish_editing(false)
	_last_column_sorted = column_index
	_store_selected_rows()
	var column := get_column(column_index)
	_icon_sort = " ▼ " if ascending else " ▲ "

	_data.sort_custom(
		func(a: Array, b: Array) -> bool:
			var ka: Variant = _key_for_sort(a[column_index], column)
			var kb: Variant = _key_for_sort(b[column_index], column)
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

	_restore_selected_rows()
	queue_redraw()


func update_cell(row: int, col: int, value: Variant) -> void:
	if row >= 0 and row < _data.size() and col >= 0 and col < _columns.size():
		while _data[row].size() <= col:
			_data[row].append("")
		_data[row][col] = value
		queue_redraw()


func get_cell_value(row: int, col: int) -> Variant:
	if row < 0 or row >= _data.size() or col < 0 or col >= _data[row].size():
		return null
	var raw: Variant = _data[row][col]
	if is_cell_invalid(row, col):
		return raw
	if get_column(col).is_numeric_column() and not _is_numeric_value(raw):
		return 0
	return raw


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
		var column := get_column(col)
		if column.is_range_column():
			var range_cfg := column.get_range_config()
			_data[row][col] = clamp(value, range_cfg.get(&"min"), range_cfg.get(&"max"))
			queue_redraw()


func select_all_rows() -> void:
	if not _total_rows > 0:
		return

	selected_rows = range(_total_rows)
	if focused_row == -1:
		focused_row = 0
		_anchor_row = 0
		focused_col = 0 if _columns.size() > 0 else -1
	else:
		_anchor_row = focused_row

	_ensure_row_visible(focused_row)
	_ensure_col_visible(focused_col)


func is_cell_invalid(row: int, col: int) -> bool:
	var raw: Variant = _data[row][col]
	return raw is String and raw == CELL_INVALID

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
	if _total_rows == null or row_height == null:
		_total_rows = 0 if _total_rows == null else _total_rows
		row_height = 30.0 if row_height == null or row_height <= 0 else row_height

	var visible_width := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.)
	var visible_height := size.y - (_h_scroll.size.y if _h_scroll.visible else 0.) - header_height

	# H-scroll covers only the scrollable (non-frozen) columns
	var frozen_w := _get_frozen_width()
	var visible_scrollable_w := visible_width - frozen_w
	var total_scrollable_w := 0.0
	for i in range(n_frozen_columns, _columns.size()):
		total_scrollable_w += get_column(i).current_width

	_h_scroll.visible = total_scrollable_w > visible_scrollable_w
	_h_scroll.offset_left = frozen_w
	if _h_scroll.visible:
		_h_scroll.max_value = total_scrollable_w
		_h_scroll.page = visible_scrollable_w
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
	_color_editor.position = cell_rect.get_center() + global_position
	_color_editor.color = cell_value
	_color_editor.show()
	_color_editor.grab_focus()


func _open_resource_editor(row: int, col: int) -> void:
	_editing_cell = [row, col]
	var column := get_column(col)
	_resource_editor.edited_resource = null
	_resource_editor.base_type = "Resource"
	if not column.hint_string.is_empty():
		var valid_types := Array(column.hint_string.split(",", false)).filter(ClassUtils.is_valid)
		if not valid_types.is_empty():
			_resource_editor.base_type = ",".join(valid_types)

	for child in _resource_editor.get_children(true):
		if child is Button and child.tooltip_text == tr("Quick Load"):
			child.pressed.emit()
			break


func _open_path_editor(row: int, col: int) -> void:
	_editing_cell = [row, col]
	var column := get_column(col)
	if column.property_hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_FILE_PATH]:
		_path_editor.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_path_editor.title = "Select a File"
		_path_editor.ok_button_text = "Select"
	if column.property_hint in [PROPERTY_HINT_DIR]:
		_path_editor.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_path_editor.title = "Select a Directory"
	var current_path := ResourceUID.ensure_path(get_cell_value(row, col))
	_path_editor.current_dir = current_path.get_base_dir()
	_path_editor.current_path = current_path
	_path_editor.popup_centered_ratio(0.55)


func _open_enum_editor(row: int, col: int) -> void:
	_editing_cell = [row, col]
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
	if _editing_cell[0] == -1 and _editing_cell[1] == -1:
		return

	if save_changes:
		var column := get_column(_editing_cell[1])
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


func _get_cell_rect(row: int, col: int) -> Rect2:
	if row < _visible_rows_range[0] or row >= _visible_rows_range[1] or col >= _columns.size():
		return Rect2()
	var cell_x := _get_col_x_pos(col)
	var vis_w := size.x - (_v_scroll.size.x if _v_scroll.visible else 0.)
	if cell_x + get_column(col).current_width <= 0 or cell_x >= vis_w:
		return Rect2()
	var row_y := header_height + (row - _visible_rows_range[0]) * row_height
	return Rect2(cell_x, row_y, get_column(col).current_width, row_height)


## Dispatches drawing of a single data cell to the correct typed draw function.
func _dispatch_cell_draw(cell_rect: Rect2, row: int, col_idx: int) -> void:
	var col := get_column(col_idx)
	if col.is_range_column():
		_draw_cell_progress(cell_rect, row, col_idx)
	elif col.is_boolean_column():
		_draw_cell_bool(cell_rect, row, col_idx)
	elif col.is_color_column():
		_draw_cell_color(cell_rect, row, col_idx)
	elif col.is_resource_column():
		_draw_cell_resource(cell_rect, row, col_idx)
	elif col.is_path_column():
		_draw_cell_path(cell_rect, row, col_idx)
	elif col.is_enum_column():
		_draw_cell_enum(cell_rect, row, col_idx)
	elif col.is_array_column() or col.is_dictionary_column():
		_draw_cell_collection(cell_rect, row, col_idx)
	else:
		_draw_cell_text(cell_rect, row, col_idx)


## Draws a single header cell (borders, text, sort icon, resize divider).
func _draw_header_cell(col_idx: int, cell_x: float, vis_w: float) -> void:
	var column := get_column(col_idx)
	draw_line(Vector2(cell_x, 0), Vector2(cell_x, header_height), grid_color)
	draw_line(
		Vector2(cell_x, header_height),
		Vector2(minf(cell_x + column.current_width, vis_w), header_height),
		grid_color,
	)

	var header_text := column.header
	var font_color := default_font_color
	if col_idx == _filtering_column:
		font_color = header_filter_active_font_color
		header_text += " (" + str(_data.size()) + ")"

	var x_margin: int = H_ALIGNMENT_MARGINS.get(column.h_alignment)
	var baseline_y := _get_text_baseline_y(0.0, header_height)
	draw_string(
		font,
		Vector2(cell_x + x_margin, baseline_y),
		header_text,
		column.h_alignment,
		column.current_width - abs(x_margin),
		font_size,
		font_color,
	)

	if col_idx == _last_column_sorted:
		var text_size := font.get_string_size(header_text, column.h_alignment, column.current_width, font_size)
		var icon_align := HORIZONTAL_ALIGNMENT_RIGHT \
		if column.h_alignment in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER] \
		else HORIZONTAL_ALIGNMENT_LEFT
		draw_string(
			font,
			Vector2(cell_x, header_height / 2.0 + text_size.y / 2.0 - (font_size / 2.0 - 1.0)),
			_icon_sort,
			icon_align,
			column.current_width,
			int(font_size / 1.3),
			font_color,
		)

	# Resize divider — every column except the last one
	var divider_x := cell_x + column.current_width
	if col_idx < _columns.size() - 1 and divider_x < vis_w:
		draw_line(
			Vector2(divider_x, 0),
			Vector2(divider_x, header_height),
			grid_color,
			2.0 if _mouse_over_divider == col_idx else 1.0,
		)


## Draws header cells for columns [col_from, col_to), clipped to [clip_left, vis_w).
func _draw_header_column_range(col_from: int, col_to: int, start_x: float, clip_left: float, vis_w: float) -> void:
	var hx := start_x
	for col_idx in range(col_from, col_to):
		var col := get_column(col_idx)
		if hx + col.current_width > clip_left and hx < vis_w:
			_draw_header_cell(col_idx, hx, vis_w)
		hx += col.current_width


## Draws data cells for columns [col_from, col_to) for one row, clipped to [clip_left, vis_w).
## Also draws the table's right border when col_to is the last column.
func _draw_cells_column_range(row: int, row_y: float, col_from: int, col_to: int, start_x: float, clip_left: float, vis_w: float) -> void:
	var col_x := start_x
	for col_idx in range(col_from, col_to):
		var col := get_column(col_idx)
		if col_x + col.current_width > clip_left and col_x < vis_w:
			var cell_rect := Rect2(col_x, row_y, col.current_width, row_height)
			draw_line(Vector2(col_x, row_y), Vector2(col_x, row_y + row_height), grid_color)
			_dispatch_cell_draw(cell_rect, row, col_idx)
			if row == focused_row and col_idx == focused_col:
				draw_rect(cell_rect.grow_individual(-1, -1, -2, -2), selected_cell_back_color, false, 2.0)
		col_x += col.current_width
	# Right border of the last column in the whole table
	if col_to == _columns.size() and col_x <= vis_w and col_x > clip_left:
		draw_line(Vector2(col_x, row_y), Vector2(col_x, row_y + row_height), grid_color)


func _draw_cell_progress(rect: Rect2, row: int, col: int) -> void:
	var cell_value: float = get_cell_value(row, col)
	var range_cfg := get_column(col).get_range_config()
	var progress: float = inverse_lerp(range_cfg.get(&"min"), range_cfg.get(&"max"), cell_value)
	var progress_color := _get_interpolated_three_colors(progress_bar_start_color, progress_bar_middle_color, progress_bar_end_color, progress)

	var bar := rect.grow(-2.0 * EditorThemeUtils.scale)
	var fill := Rect2(bar.position, Vector2(bar.size.x * minf(progress, 1.0), bar.size.y))

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


func _draw_cell_bool(rect: Rect2, row: int, col: int) -> void:
	if not row < _data.size() and col < _data[row].size():
		return

	var cell_value: Variant = _data[row][col]
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


func _draw_cell_color(rect: Rect2, row: int, col: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not value is Color:
		_draw_cell_text(rect, row, col)
		return

	var color: Color = value
	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var border_alpha := 0.65 if color.a < 0.25 else 0.35

	# Checkerboard background to visualize transparency
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


func _draw_cell_resource(rect: Rect2, row: int, col: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not value is Resource:
		_draw_cell_text(rect, row, col)
		return

	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var texture := _get_or_queue_thumbnail(value)
	if texture == null:
		draw_rect(inner, Color(1, 1, 1, 0.06), true)
		draw_rect(inner, Color(1, 1, 1, 0.18), false, 1.0)
		return

	draw_texture_rect(texture, _fit_texture_rect(texture, inner), false)


func _draw_cell_path(rect: Rect2, row: int, col: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not (
		get_column(col).property_hint == PROPERTY_HINT_FILE
		and ResourceUID.has_id(ResourceUID.text_to_id(value))
	):
		_draw_cell_text(rect, row, col)
		return

	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var thumb_width := 0.0
	var texture := _get_or_queue_thumbnail(load(value))
	if texture != null:
		var thumb_rect := _fit_texture_rect(texture, inner, true)
		thumb_rect.position.x += x_margin_val
		draw_texture_rect(texture, thumb_rect, false)
		thumb_width = thumb_rect.size.x

	var text_rect := inner.grow_individual(-thumb_width - x_margin_val, 0, 0, 0)
	_draw_cell_text(text_rect, row, col)


func _draw_cell_text(rect: Rect2, row: int, col: int) -> void:
	var cell_value := str(get_cell_value(row, col))
	if cell_value == CELL_INVALID:
		_draw_cell_invalid(rect, row, col)
		return

	var column := get_column(col)
	var text_font: Font = font
	var h_alignment := column.h_alignment
	if column.custom_font:
		text_font = column.custom_font
	elif column.is_path_column():
		text_font = mono_font

	if column.is_resource_column() and _data[row][col] == null:
		cell_value = "<empty>"
		h_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var x_margin_val: int = H_ALIGNMENT_MARGINS.get(h_alignment)
	var baseline_y := _get_text_baseline_y(rect.position.y)
	var display_text := _get_display_text(cell_value, text_font, rect.size.x - absf(x_margin_val))
	var text_color := column.custom_font_color if column.custom_font_color else default_font_color
	text_color = get_theme_color("error_color", "Editor") if cell_value.begins_with("(!) ") else text_color # TODO: registry-specific. Refactor outside — e.g. give the ability to set colors for specific rows.

	draw_string(
		text_font,
		Vector2(rect.position.x + x_margin_val, baseline_y),
		display_text,
		h_alignment,
		max(0.001, rect.size.x - abs(x_margin_val)),
		font_size,
		text_color,
	)


func _draw_cell_enum(rect: Rect2, row: int, col: int) -> void:
	var cell_value: Variant = get_cell_value(row, col)
	var column := get_column(col)
	var hint_arr: Array = column.hint_string.split(",", false)
	var value_str := ""

	if not column.is_numeric_column():
		var label := str(cell_value)
		for entry: String in hint_arr:
			var colon := entry.rfind(":")
			var entry_label := entry.substr(0, colon) if colon != -1 else entry
			if entry_label == label:
				value_str = label
	else:
		var value_map: Dictionary = { }
		var next_implicit := 0
		for entry: String in hint_arr:
			var colon := entry.rfind(":")
			if colon == -1:
				value_map[next_implicit] = entry
				next_implicit += 1
			else:
				var explicit_val := entry.substr(colon + 1).to_int()
				value_map[explicit_val] = entry.substr(0, colon)
				next_implicit = explicit_val + 1

		var int_value := cell_value as int
		value_str = "%s:%s" % [value_map[int_value], int_value] if value_map.has(int_value) else "?:%d" % int_value

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


func _draw_cell_invalid(rect: Rect2, _row: int, _col: int) -> void:
	draw_rect(rect, invalid_cell_color, true)


func _draw_cell_collection(rect: Rect2, row: int, col: int) -> void:
	var value: Variant = get_cell_value(row, col)
	if not (value is Array or value is Dictionary):
		_draw_cell_text(rect, row, col)
		return
	var text := _format_collection_value(value)
	var x_margin: int = H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_LEFT)
	var baseline_y := _get_text_baseline_y(rect.position.y)
	var display_text := _get_display_text(text, font, rect.size.x - absf(x_margin))
	draw_string(
		font,
		Vector2(rect.position.x + x_margin, baseline_y),
		display_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - absf(x_margin),
		font_size,
		default_font_color,
	)


static func _format_collection_elem(elem: Variant) -> String:
	if elem is Array:
		return "Array(%d)" % (elem as Array).size()
	if elem is Dictionary:
		return "Dict(%d)" % (elem as Dictionary).size()
	return str(elem)


static func _format_collection_value(value: Variant) -> String:
	var is_dict := value is Dictionary
	var items: Array = (value as Dictionary).keys() if is_dict else (value as Array)

	var parts: Array[String] = []
	for i in mini(items.size(), 3):
		if is_dict:
			var key: Variant = items[i]
			parts.append("%s: %s" % [str(key), _format_collection_elem((value as Dictionary)[key])])
		else:
			parts.append(_format_collection_elem(items[i]))

	var result := ", ".join(parts)
	var remaining := items.size() - 3
	if remaining > 0:
		result += " and %d more" % remaining
	return "{ %s }" % result if is_dict else "[%s]" % result


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


func _get_interpolated_three_colors(start_c: Color, mid_c: Color, end_c: Color, t_val: float) -> Color:
	var clamped_t := clampf(t_val, 0.0, 1.0)
	if clamped_t <= 0.5:
		return start_c.lerp(mid_c, clamped_t * 2.0)
	else:
		return mid_c.lerp(end_c, (clamped_t - 0.5) * 2.0)


func _start_filtering(col_idx: int) -> void:
	if _filtering_column == col_idx and _filter_line_edit.visible:
		return # Already in filter mode on this column

	var col_x := _get_col_x_pos(col_idx)
	var header_rect := Rect2(col_x, 0, get_column(col_idx).current_width, header_height)
	_filtering_column = col_idx
	_filter_line_edit.position = header_rect.position + Vector2(1, 1)
	_filter_line_edit.size = header_rect.size - Vector2(2, 2)
	_filter_line_edit.text = ""
	_filter_line_edit.visible = true
	_filter_line_edit.grab_focus()


func _get_resource_key(res: Resource) -> String:
	var key := res.resource_path
	if key.is_empty():
		key = "iid:%d" % res.get_instance_id()
	return key


func _get_or_queue_thumbnail(res: Resource) -> Texture2D:
	var key := _get_resource_key(res)
	if _resource_thumb_cache.has(key):
		return _resource_thumb_cache[key]
	if not _resource_thumb_pending.has(key):
		_resource_thumb_pending[key] = true
		EditorInterface.get_resource_previewer().queue_edited_resource_preview(
			res,
			self,
			"_on_resource_cell_thumb_ready",
			{ "key": key, "class": ClassUtils.get_type_name(res) },
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
		var key_lower := search_key.to_lower()
		for row_data: Array in _full_data:
			if _filtering_column < row_data.size() and row_data[_filtering_column] != null:
				var cell_value := str(row_data[_filtering_column]).to_lower()
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
		if value is Resource: # might be <empty>
			var r: Resource = value
			if r.resource_path != "":
				return r.resource_path.get_file()
			return str(r.get_class()) + ":" + str(r.get_instance_id())
		return str(value)
	return str(value)


## Returns the column index under screen x, or -1 if none.
## Frozen columns take priority: a click in the frozen zone always hits a frozen column.
func _get_col_at_x(x: float) -> int:
	var frozen_w := _get_frozen_width()
	var col_x := 0.0

	if x < frozen_w:
		for col_idx in n_frozen_columns:
			if x < col_x + get_column(col_idx).current_width:
				return col_idx
			col_x += get_column(col_idx).current_width
		return -1

	col_x = frozen_w - _h_scroll_position
	for col_idx in range(n_frozen_columns, _columns.size()):
		var col_end := col_x + get_column(col_idx).current_width
		if x >= maxf(col_x, frozen_w) and x < col_end:
			return col_idx
		col_x = col_end
	return -1


## Returns the row index under y, or -1 if above the header or out of range.
func _get_row_at_y(y: float) -> int:
	if y < header_height or row_height <= 0:
		return -1
	var row: int = floori((y - header_height) / row_height) + _visible_rows_range[0]
	return row if row < _total_rows else -1


## Returns the baseline Y for drawing text vertically centered in a cell.
func _get_text_baseline_y(cell_y: float, cell_height: float = -1.0) -> float:
	var h := cell_height if cell_height >= 0.0 else row_height
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	return cell_y + (h + ascent - descent) / 2.0


## Total width of frozen (pinned) columns.
func _get_frozen_width() -> float:
	var w := 0.0
	for i in mini(n_frozen_columns, _columns.size()):
		w += get_column(i).current_width
	return w


## Screen X of the left edge of column col_idx, accounting for freeze and scroll.
## Frozen columns sit at fixed positions; scrollable columns follow the h-scroll.
func _get_col_x_pos(col_idx: int) -> float:
	if col_idx < n_frozen_columns:
		var x := 0.0
		for i in col_idx:
			x += get_column(i).current_width
		return x
	else:
		var x := _get_frozen_width() - _h_scroll_position
		for i in range(n_frozen_columns, col_idx):
			x += get_column(i).current_width
		return x


func _check_mouse_over_divider(mouse_pos: Vector2) -> void:
	_mouse_over_divider = -1
	mouse_default_cursor_shape = CURSOR_ARROW

	if mouse_pos.y < header_height:
		for col_idx in _columns.size():
			var divider_x := _get_col_x_pos(col_idx) + get_column(col_idx).current_width
			# Skip dividers of scrollable columns hidden behind the frozen zone
			if col_idx >= n_frozen_columns and divider_x <= _get_frozen_width():
				continue
			var divider_rect := Rect2(divider_x - _divider_width / 2.0, 0, _divider_width, header_height)
			if divider_rect.has_point(mouse_pos):
				_mouse_over_divider = col_idx
				mouse_default_cursor_shape = CURSOR_HSIZE
				break

	queue_redraw()


func _update_tooltip(mouse_pos: Vector2) -> void:
	var current_cell := [-1, -1]
	var new_tooltip := ""

	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx == -1:
		if current_cell != _tooltip_cell:
			_tooltip_cell = current_cell
			self.tooltip_text = new_tooltip
		return

	if mouse_pos.y < header_height:
		new_tooltip = get_column(col_idx).header
		current_cell = [-2, col_idx]
	else:
		var row_idx := _get_row_at_y(mouse_pos.y)
		if row_idx >= 0:
			var column := get_column(col_idx)
			if not column.is_range_column() and not column.is_boolean_column():
				new_tooltip = str(get_cell_value(row_idx, col_idx))
			current_cell = [row_idx, col_idx]

	if current_cell != _tooltip_cell:
		_tooltip_cell = current_cell
		self.tooltip_text = new_tooltip


func _is_clicking_progress_bar(mouse_pos: Vector2) -> bool:
	var row := _get_row_at_y(mouse_pos.y)
	var col := _get_col_at_x(mouse_pos.x)
	if -1 in [row, col]:
		return false
	return get_column(col).is_range_column()


func _toggle_checkbox(row: int, col: int) -> void:
	var old_val := bool(get_cell_value(row, col))
	var new_val := !old_val
	update_cell(row, col, new_val)
	cell_edited.emit(row, col, old_val, new_val)


func _ensure_row_visible(row_idx: int) -> void:
	if _total_rows == 0 or row_height == 0 or not _v_scroll.visible:
		return

	var visible_area_height: float = size.y - header_height - (_h_scroll.size.y if _h_scroll.visible else 0.0)
	var num_visible_rows_in_page := floori(visible_area_height / row_height)
	var first_fully_visible_row: int = _visible_rows_range[0]

	if row_idx < first_fully_visible_row:
		_v_scroll.value = row_idx * row_height
	elif row_idx >= first_fully_visible_row + num_visible_rows_in_page:
		_v_scroll.value = (row_idx - num_visible_rows_in_page + 1) * row_height

	_v_scroll.value = clamp(_v_scroll.value, 0, _v_scroll.max_value)


func _ensure_col_visible(col_idx: int) -> void:
	if _columns.is_empty() or col_idx < 0 or col_idx >= _columns.size() or not _h_scroll.visible:
		return
	if col_idx < n_frozen_columns:
		return # Frozen columns are always visible

	# Scroll-space: position relative to start of scrollable content
	var col_scroll_pos := 0.0
	for i in range(n_frozen_columns, col_idx):
		col_scroll_pos += get_column(i).current_width
	var col_scroll_end := col_scroll_pos + get_column(col_idx).current_width
	var visible_scrollable_w := _h_scroll.page

	if col_scroll_pos < _h_scroll.value:
		_h_scroll.value = col_scroll_pos
	elif col_scroll_end > _h_scroll.value + visible_scrollable_w:
		_h_scroll.value = (
			col_scroll_end - visible_scrollable_w
			if get_column(col_idx).current_width <= visible_scrollable_w
			else col_scroll_pos
		)
	_h_scroll.value = clamp(_h_scroll.value, 0.0, _h_scroll.max_value)


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	_apply_pan_axis(event.delta.y, _v_scroll, Vector2.AXIS_Y)
	if abs(event.delta.x) > 0.05:
		_apply_pan_axis(event.delta.x, _h_scroll, Vector2.AXIS_X)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var m_pos := event.position

	if (
		_dragging_progress
		and _progress_drag_row >= 0
		and _progress_drag_col >= 0
	):
		_handle_progress_drag(m_pos)

	elif _resizing_column in range(_columns.size()):
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
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_left_press(event)
			else:
				_handle_left_release()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_handle_right_click(event.position)
		MOUSE_BUTTON_WHEEL_UP:
			_v_scroll.value = maxf(0.0, _v_scroll.value - _v_scroll.step)
		MOUSE_BUTTON_WHEEL_DOWN:
			_v_scroll.value = minf(_v_scroll.max_value, _v_scroll.value + _v_scroll.step)


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
			_progress_drag_row = _get_row_at_y(m_pos.y)
			_progress_drag_col = _get_col_at_x(m_pos.x)
			_dragging_start_value = get_cell_value(_progress_drag_row, _progress_drag_col)
			_dragging_progress = true

	if _mouse_over_divider >= 0:
		_resizing_column = _mouse_over_divider
		_resizing_start_pos = int(m_pos.x)
		_resizing_start_width = int(get_column(_resizing_column).current_width)


func _handle_left_release() -> void:
	if _dragging_progress:
		var new_val: Variant = get_cell_value(_progress_drag_row, _progress_drag_col)
		update_cell(_progress_drag_row, _progress_drag_col, new_val)
		cell_edited.emit(_progress_drag_row, _progress_drag_col, _dragging_start_value, new_val)
	_resizing_column = -1
	_dragging_progress = false
	_progress_drag_row = -1
	_progress_drag_col = -1


func _handle_progress_drag(mouse_pos: Vector2) -> void:
	if (
		_progress_drag_row < 0
		or _progress_drag_col < 0
		or _progress_drag_col >= _columns.size()
	):
		return

	var margin := 4.0
	var bar_x := _get_col_x_pos(_progress_drag_col) + margin
	var bar_w := get_column(_progress_drag_col).current_width - margin * 2.0
	if bar_w <= 0:
		return

	var range_cfg := get_column(_progress_drag_col).get_range_config()
	var weight := (mouse_pos.x - bar_x) / bar_w
	var new_progress: float = snappedf(
		lerpf(range_cfg.get(&"min"), range_cfg.get(&"max"), weight),
		range_cfg.get(&"step"),
	)
	if not range_cfg.has(&"or_greater"):
		new_progress = min(new_progress, range_cfg.get(&"max"))
	if not range_cfg.has(&"or_less"):
		new_progress = max(new_progress, range_cfg.get(&"min"))

	if _progress_drag_row < _data.size() and _progress_drag_col < _data[_progress_drag_row].size():
		_data[_progress_drag_row][_progress_drag_col] = new_progress
		progress_changed.emit(_progress_drag_row, _progress_drag_col, new_progress)
		queue_redraw()


func _handle_checkbox_click(mouse_pos: Vector2) -> bool:
	var row := _get_row_at_y(mouse_pos.y)
	var col := _get_col_at_x(mouse_pos.x)
	if -1 in [row, col]:
		return false

	if not get_column(col).is_boolean_column():
		return false

	var rect := _get_cell_rect(row, col)
	var icon: Texture2D = get_theme_icon(&"checked", &"CheckBox")
	var icon_rect := Rect2(rect.get_center() - icon.get_size() / 2, icon.get_size())
	if icon_rect.has_point(mouse_pos):
		_toggle_checkbox(row, col)
		return true

	return false


func _handle_cell_click(mouse_pos: Vector2, event: InputEventMouseButton) -> void:
	if _editing_cell[1] >= 0:
		var column := get_column(_editing_cell[1])
		var save := not (column.is_resource_column() or column.is_path_column() or column.is_enum_column())
		_finish_editing(save)

	var clicked_row := _get_row_at_y(mouse_pos.y)
	var clicked_col := _get_col_at_x(mouse_pos.x)
	if clicked_row < 0 or clicked_col == -1:
		return

	focused_row = clicked_row
	focused_col = clicked_col

	if event.is_shift_pressed() and _anchor_row != -1:
		selected_rows.clear()
		for i in range(mini(_anchor_row, focused_row), maxi(_anchor_row, focused_row) + 1):
			selected_rows.append(i)
	elif event.is_ctrl_pressed() or event.is_meta_pressed():
		if selected_rows.has(focused_row):
			selected_rows.erase(focused_row)
		else:
			selected_rows.append(focused_row)
		_anchor_row = focused_row
	else:
		selected_rows.clear()
		selected_rows.append(focused_row)
		_anchor_row = focused_row

	cell_selected.emit(focused_row, focused_col)
	_ensure_col_visible(focused_col)

	if selected_rows.size() > 1:
		multiple_rows_selected.emit(selected_rows)

	queue_redraw()


func _handle_right_click(mouse_pos: Vector2) -> void:
	var clicked_row := _get_row_at_y(mouse_pos.y)
	var clicked_col := _get_col_at_x(mouse_pos.x)

	if selected_rows.size() <= 1:
		set_selected_cell(clicked_row, clicked_col)

	cell_right_selected.emit(clicked_row, clicked_col, get_global_mouse_position())


func _handle_double_click(mouse_pos: Vector2) -> void:
	if mouse_pos.y < header_height:
		return

	var row := _get_row_at_y(mouse_pos.y)
	if row >= 0:
		var col := _get_col_at_x(mouse_pos.x)
		if col != -1:
			if not (selected_rows.size() == 1 and selected_rows[0] == row and focused_row == row and focused_col == col):
				set_selected_cell(row, col)
			_start_cell_editing(row, col)


func _handle_header_click(mouse_pos: Vector2) -> void:
	for col_idx in _columns.size():
		var col_x := _get_col_x_pos(col_idx)
		if (
			mouse_pos.x >= col_x + _divider_width / 2.0
			and mouse_pos.x < col_x + get_column(col_idx).current_width - _divider_width / 2.0
		):
			_finish_editing(false)
			_ascending = not _ascending if _last_column_sorted == col_idx else true
			ordering_data(col_idx, _ascending)
			header_clicked.emit(col_idx)
			break


func _handle_header_double_click(mouse_pos: Vector2) -> void:
	_finish_editing(false)
	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx != -1:
		_ensure_col_visible(col_idx)
		_start_filtering(col_idx)


func _handle_key_input(event: InputEventKey) -> void:
	if _text_editor_line_edit.visible:
		if event.keycode == KEY_ESCAPE:
			_finish_editing(false)
			get_viewport().set_input_as_handled()
		return

	var keycode := event.keycode
	var is_shift := event.is_shift_pressed()
	var is_ctrl_cmd := event.is_ctrl_pressed() or event.is_meta_pressed()
	var is_cell_focused := focused_row != -1 and focused_col != -1

	var new_row := focused_row
	var new_col := focused_col

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
			if is_ctrl_cmd and _total_rows > 0:
				select_all_rows()
				multiple_rows_selected.emit(selected_rows)
				_finalize_key_operation()
			return
		KEY_ESCAPE:
			if selected_rows.is_empty() and focused_row == -1:
				return
			set_selected_cell(-1, -1)
			_previous_sort_selected_rows.clear()
			_finalize_key_operation()
			return
		KEY_HOME:
			if _total_rows == 0:
				return
			new_row = 0
			new_col = 0 if not _columns.is_empty() else -1
		KEY_END:
			if _total_rows == 0:
				return
			new_row = _total_rows - 1
			new_col = _columns.size() - 1 if not _columns.is_empty() else -1
		KEY_UP:
			if not is_cell_focused:
				return
			new_row = maxi(0, focused_row - 1)
		KEY_DOWN:
			if not is_cell_focused:
				return
			new_row = mini(_total_rows - 1, focused_row + 1)
		KEY_LEFT:
			if not is_cell_focused:
				return
			new_col = maxi(0, focused_col - 1)
		KEY_RIGHT:
			if not is_cell_focused:
				return
			new_col = mini(_columns.size() - 1, focused_col + 1)
		KEY_PAGEUP:
			if not is_cell_focused:
				return
			new_row = maxi(0, focused_row - _page_row_count())
		KEY_PAGEDOWN:
			if not is_cell_focused:
				return
			new_row = mini(_total_rows - 1, focused_row + _page_row_count())
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

	var old_row := focused_row
	focused_row = new_row
	focused_col = new_col

	_update_selection_after_navigation(old_row, is_shift, is_ctrl_cmd)

	if focused_row != -1:
		_ensure_row_visible(focused_row)
		_ensure_col_visible(focused_col)

	if old_row != focused_row or new_col != focused_col:
		cell_selected.emit(focused_row, focused_col)

	_finalize_key_operation()


func _page_row_count() -> int:
	return maxi(1, floori((size.y - header_height) / row_height) if row_height > 0 else 10)


func _update_selection_after_navigation(old_row: int, is_shift: bool, is_ctrl_cmd: bool) -> void:
	if is_shift:
		if _anchor_row == -1:
			_anchor_row = old_row if old_row != -1 else 0
		if focused_row == -1:
			return
		selected_rows.clear()
		for i in range(mini(_anchor_row, focused_row), maxi(_anchor_row, focused_row) + 1):
			if i >= 0 and i < _total_rows:
				selected_rows.append(i)
		if selected_rows.size() > 1:
			multiple_rows_selected.emit(selected_rows)
	elif is_ctrl_cmd:
		pass # Move focus only, preserve selection
	else:
		if focused_row != -1:
			selected_rows.clear()
			selected_rows.append(focused_row)
			_anchor_row = focused_row
		else:
			selected_rows.clear()
			_anchor_row = -1


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
		scroll.value += sign(_pan_delta_accumulation[axis]) * _v_scroll.step #scroll.step
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
	# for '_on_enum_editor_id_pressed' to trigger first
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
	_v_scroll_position = int(value)
	if row_height > 0: # Avoid division by zero
		_visible_rows_range[0] = floori(value / row_height)
		_visible_rows_range[1] = _visible_rows_range[0] + floori((size.y - header_height) / row_height) + 1
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


func _on_resource_previewer_preview_invalidated(path: String) -> void:
	#push_warning("RESOURCE PREVIEW INVALIDATED: %s" % path)
	if _resource_thumb_cache.has(path):
		_resource_thumb_cache.erase(path)


func _on_resource_cell_thumb_ready(_path: String, preview: Texture2D, thumbnail_preview: Texture2D, userdata: Variant) -> void:
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
		h_alignment = p_alignment


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


	func get_range_config() -> Dictionary[StringName, Variant]:
		if not is_range_column():
			return { }
		var hint_elements := hint_string.split(",", false)
		var r_min := float(hint_elements[0]) if hint_elements.size() > 0 else 0.0
		var r_max := float(hint_elements[1]) if hint_elements.size() > 1 else 1.0
		var r_step := float(hint_elements[2]) if hint_elements.size() > 2 else (0.001 if is_float_column() else 1.0)
		var result: Dictionary[StringName, Variant] = { &"min": r_min, &"max": r_max, &"step": r_step }
		for hint_str in hint_elements.slice(3):
			match hint_str:
				"or_greater":
					result.set(&"or_greater", true)
				"or_less":
					result.set(&"or_less", true)

		return result
