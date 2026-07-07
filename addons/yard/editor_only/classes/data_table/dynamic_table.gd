# Originally based on dynamicdatatable by Giuseppe Pica (jospic), MIT licensed.
# https://github.com/jospic/dynamicdatatable
# Heavily modified / rewritten by Elliot Fontaine, 2026

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
const ColumnConfig := Namespace.ColumnConfig
const CellType := Namespace.CellType
const CellStyle := Namespace.CellStyle
const EditorThemeUtils := Namespace.EditorThemeUtils
const AnyIcon := Namespace.AnyIcon
const YardLogger := Namespace.YardLogger

const CELL_INVALID := "<CELL_INVALID>"

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
var mono_font: Font = EditorInterface.get_editor_theme().get_font(&"font", &"CodeEdit")
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
var _filter_text: String = ""

# Inline cell editing. The CellType script family is entirely static (never
# instantiated). ColumnConfig resolves which script applies to a column, and
# these two fields are the only editing-related state DynamicTable keeps: the
# one editor Node that can exist at a time, and the script responsible for it.
var _edited_row: StringName = &""
var _edited_col: StringName = &""
var _current_editor_node: Node
var _current_editor_handler: GDScript # The script extends CellType
var _style: CellStyle

# Progress bar dragging (Range columns). Tracked here for the same reason as
# _edited_row/_edited_col above: only one interaction can be in flight.
var _dragging_row: StringName = &""
var _dragging_col: StringName = &""
var _dragging_start_value: Variant

# Click detection (single vs. double click)
var _double_click_timer: Timer
var _click_count := 0
var _last_click_pos := Vector2.ZERO
var _double_click_threshold := 400 # milliseconds
var _click_position_threshold := 5 # pixels

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
	_style = CellStyle.new()
	_refresh_style()

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
	_style.pixelated_canvas_rid = _pixelated_canvas_rid
	_style.get_thumbnail = _get_or_queue_thumbnail

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
	if not is_inside_tree() or _columns.is_empty():
		return

	var frozen_w := _get_frozen_width()
	_style.frozen_width = frozen_w
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

	_refresh_style()
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
## Re-applies the active filter and sort after rebuilding.
func set_data(rows: Array, row_ids: Array[StringName]) -> void:
	_rows.clear()
	_base_order.clear()
	for i in row_ids.size():
		var row := row_ids[i]
		_rows[row] = rows[i].duplicate() if i < rows.size() else []
		_base_order.append(row)
	_order = _base_order.duplicate()
	_rebuild_filtered_order()

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
	var handler := column_cfg.get_cell_type()

	_order.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var a_cells: Array = _rows.get(a, [])
			var b_cells: Array = _rows.get(b, [])
			var va: Variant = a_cells[column_idx] if column_idx < a_cells.size() else null
			var vb: Variant = b_cells[column_idx] if column_idx < b_cells.size() else null
			var ka: Variant = handler.get_sort_key(va, column_cfg) if va != null else null
			var kb: Variant = handler.get_sort_key(vb, column_cfg) if vb != null else null
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


## Clears the active column filter without rebuilding data.
func clear_filter() -> void:
	_filtered_column = &""
	_filter_text = ""


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
	if base_height_from_line_edit:
		var probe := LineEdit.new()
		add_child(probe)
		header_height = probe.size.y
		row_height = probe.size.y
		probe.queue_free()

	_double_click_timer = Timer.new()
	_double_click_timer.wait_time = _double_click_threshold / 1000.0
	_double_click_timer.one_shot = true
	_double_click_timer.timeout.connect(_on_double_click_timeout)
	add_child(_double_click_timer)


func _refresh_style() -> void:
	_style.font = font
	_style.mono_font = mono_font
	_style.font_size = font_size
	_style.default_font_color = default_font_color
	_style.error_color = get_theme_color(&"error_color", &"Editor")
	_style.checkbox_checked_icon = get_theme_icon(&"checked", &"CheckBox")
	_style.checkbox_unchecked_icon = get_theme_icon(&"unchecked", &"CheckBox")
	_style.file_dead_icon = get_theme_icon(&"FileDead", &"EditorIcons")
	_style.progress_bar_start_color = progress_bar_start_color
	_style.progress_bar_middle_color = progress_bar_middle_color
	_style.progress_bar_end_color = progress_bar_end_color
	_style.progress_background_color = progress_background_color
	_style.progress_border_color = progress_border_color
	_style.progress_text_color_light = progress_text_color_light


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


func _toggle_cell(row: StringName, col: StringName, new_value: Variant) -> void:
	var old_value: Variant = get_cell_value(row, col)
	update_cell(row, col, new_value)
	cell_edited.emit(row, col, old_value, new_value)


func _start_cell_editing(row: StringName, col: StringName) -> void:
	if is_cell_invalid(row, col):
		return

	var column := get_column(col)
	var handler := column.get_editor_cell_type()
	if not handler.has_editor():
		YardLogger.warn("There is no editor for this type of cell.")
		return

	var cell_rect := _get_cell_rect(row, col)
	if not cell_rect:
		return

	_edited_row = row
	_edited_col = col
	_current_editor_handler = handler
	_current_editor_node = handler.create_editor(self, cell_rect, get_cell_value(row, col), column, _on_editor_finished)


func _finish_editing(save_changes: bool = true) -> void:
	if _edited_row == &"" and _edited_col == &"":
		return

	if save_changes:
		var column := get_column(_edited_col)
		var old_value: Variant = get_cell_value(_edited_row, _edited_col)
		var new_value: Variant = _current_editor_handler.read_editor_value(_current_editor_node, column)
		if typeof(new_value) == column.type:
			update_cell(_edited_row, _edited_col, new_value)
			cell_edited.emit(_edited_row, _edited_col, old_value, new_value)

	_edited_row = &""
	_edited_col = &""
	if _current_editor_node:
		_current_editor_node.queue_free()
		_current_editor_node = null
	_current_editor_handler = null
	queue_redraw()


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
	if is_cell_invalid(row, col):
		draw_rect(cell_rect, invalid_cell_color, true)
		return
	var column := get_column(col)
	column.get_cell_type().draw_cell(self, cell_rect, get_cell_value(row, col), column, _style)


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
	var x_margin: int = CellType.H_ALIGNMENT_MARGINS.get(header_alignment)
	var baseline_y := CellType.get_text_baseline_y(font, font_size, 0.0, header_height)
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
		_filtered_column = &""
		_filter_text = ""
	else:
		_filter_text = search_key

	_rebuild_filtered_order()
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


func _rebuild_filtered_order() -> void:
	if _filtered_column == &"" or _filter_text.is_empty():
		_order = _base_order.duplicate()
		return
	_order.clear()
	var col_idx := _column_index(_filtered_column)
	var key_lower := _filter_text.to_lower()
	for row in _base_order:
		var row_data: Array = _rows.get(row, [])
		if col_idx >= 0 and col_idx < row_data.size() and row_data[col_idx] != null:
			if str(row_data[col_idx]).to_lower().contains(key_lower):
				_order.append(row)


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
			if not column.get_cell_type().suppresses_tooltip():
				new_tooltip = str(get_cell_value(new_row, col))

	if new_row != _tooltip_row or new_col != _tooltip_col:
		_tooltip_row = new_row
		_tooltip_col = new_col
		self.tooltip_text = new_tooltip


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

	if _dragging_row != &"":
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
		var row_idx := _get_row_at_y(m_pos.y)
		var col_idx := _get_col_at_x(m_pos.x)
		var row: StringName = _order[row_idx] if row_idx >= 0 else &""
		var col: StringName = _columns[col_idx].identifier if col_idx != -1 else &""

		if row != &"" and col != &"":
			var column := get_column(col)
			var cell_value: Variant = get_cell_value(row, col)
			var cell_type := column.get_cell_type()
			var result: Dictionary = cell_type.handle_click(m_pos, _get_cell_rect(row, col), cell_value, column, _style)
			match result.get(&"action", &""):
				&"toggle":
					_toggle_cell(row, col, result[&"value"])
				&"drag":
					_dragging_row = row
					_dragging_col = col
					_dragging_start_value = cell_value

		_handle_cell_click(m_pos, event)

	if _mouse_over_divider >= 0:
		_resizing_column = _columns[_mouse_over_divider].identifier
		_resizing_start_pos = int(m_pos.x)
		_resizing_start_width = int(get_column(_resizing_column).current_width)


func _handle_left_release() -> void:
	if _dragging_row != &"":
		var new_val: Variant = get_cell_value(_dragging_row, _dragging_col)
		update_cell(_dragging_row, _dragging_col, new_val)
		cell_edited.emit(_dragging_row, _dragging_col, _dragging_start_value, new_val)
		_dragging_row = &""
		_dragging_col = &""
		_dragging_start_value = null
	_resizing_column = &""


func _handle_progress_drag(mouse_pos: Vector2) -> void:
	var col_idx := _column_index(_dragging_col)
	if col_idx < 0:
		return

	var cell_x := _get_col_x_pos(col_idx)
	var column := get_column(_dragging_col)
	var new_value: Variant = column.get_cell_type().compute_drag_value(mouse_pos, column, cell_x, column.current_width)
	if new_value == null:
		return

	if _rows.has(_dragging_row) and col_idx < _rows[_dragging_row].size():
		_rows[_dragging_row][col_idx] = new_value
		progress_changed.emit(_dragging_row, _dragging_col, new_value)
		queue_redraw()


func _handle_cell_click(mouse_pos: Vector2, event: InputEventMouseButton) -> void:
	if _edited_col != &"":
		var save: bool = _current_editor_handler == null or _current_editor_handler.commits_on_click_away()
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
	if _current_editor_node != null and _current_editor_node is LineEdit:
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
			var column := get_column(focused_col)
			var result: Dictionary = column.get_cell_type().handle_enter(get_cell_value(focused_row, focused_col), column)
			if result.has(&"action"):
				_toggle_cell(focused_row, focused_col, result[&"value"])
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


func _on_editor_finished(save_changes: bool) -> void:
	_finish_editing(save_changes)


func _on_double_click_timeout() -> void:
	_click_count = 0


func _on_h_scroll_changed(value: float) -> void:
	_h_scroll_position = int(value)
	if _current_editor_node != null and _current_editor_node is LineEdit:
		_finish_editing(false)
	queue_redraw()


func _on_v_scroll_value_changed(value: float) -> void:
	if row_height > 0:
		_visible_rows_range[0] = floori(value / row_height)
		_visible_rows_range[1] = _visible_rows_range[0] + floori((size.y - header_height) / row_height) + 1
		_visible_rows_range[1] = min(_visible_rows_range[1], _order.size())
	else:
		_visible_rows_range = [0, _order.size()]

	if _current_editor_node != null and _current_editor_node is LineEdit:
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
