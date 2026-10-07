# SPDX-FileCopyrightText: 2023, Giuseppe Pica (jospic) <https://github.com/jospic/dynamicdatatable>
# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Control

signal cell_selected(row_id: StringName, col: StringName)
signal multiple_rows_selected(row_ids: Array[StringName])
signal cell_right_selected(row_id: StringName, col: StringName, mouse_pos: Vector2)
signal header_left_clicked(column: StringName)
signal header_right_clicked(column: StringName)
signal column_resized(column: StringName, new_width: float)
signal progress_changed(row_id: StringName, col: StringName, new_value: float)
signal cell_edited(row_id: StringName, col: StringName, old_value: Variant, new_value: Variant)

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
# Core logic of DataTable.
const ColumnConfig := Namespace.ColumnConfig
const CellStyle := Namespace.CellStyle
const CellType := Namespace.CellType
# YARD-specific. Remove these to use DataTable standalone.
const EditorThemeUtils := Namespace.EditorThemeUtils
const ClassUtils := Namespace.ClassUtils
const YardLogger := Namespace.YardLogger
const Compat := Namespace.Compat
const AnyIcon := Namespace.AnyIcon

# Theming properties
@export_group("Default color")
@export var default_font_color: Color = Color(1.0, 1.0, 1.0)
@export_group("Header")
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

# Show a red overlay on cells, with opacity based on their drawing performance impact.
var _DEBUG_show_cell_draw_profiling: bool = false

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
var _rows: Dictionary[StringName, Dictionary] = { }
var _base_order: Array[StringName] = [] # insertion order, source for filter
var _order: Array[StringName] = [] # current visible filtered / sorted order
var _anchor_row: StringName = &"" # shift-select range anchor

# Column model.
var _column_base_order: Array[ColumnConfig] = []
var _columns: Array[ColumnConfig] = []
var _column_index_by_id: Dictionary[StringName, int] = { } # Position cache into _columns.
var n_frozen_columns: int = 0 ## Derived value

# Scrolling.
var _scroll_container: ScrollContainer
var _scroll_content: Control
var _scroll_panel_style: StyleBoxEmpty # Left margin = frozen width

# Column resizing (dragging a header divider)
var _resizing_column: StringName = &""
var _resizing_start_pos := 0
var _resizing_start_width := 0
var _mouse_over_divider := -1
var _divider_width := 5

# Header sort rendering
var _sort_icon: Texture2D
var _hovered_header_col: StringName = &""
var _is_sort_icon_hovered := false

# Column filter (double-click a header to search within that column)
var _filter_line_edit: LineEdit
var _filtered_column: StringName = &""
var _filter_text: String = ""

# Inline cell editing. The CellType script family is entirely static (never
# instantiated). ColumnConfig resolves which script applies to a column, and
# these two fields are the only editing-related state DataTable keeps: the
# one editor Node that can exist at a time, and the script responsible for it.
var _edited_row: StringName = &""
var _edited_col: StringName = &""
var _current_editor_node: Node
var _current_editor_handler: GDScript # The script extends CellType
var _style: CellStyle

# Live cell interaction claimed via CellType.handle_input (e.g. a Range drag).
# Only one interaction can be in flight. Once claimed, routing for follow-up
# motion/release events is pinned to this (row, col).
var _live_edit_row: StringName = &""
var _live_edit_col: StringName = &""
var _live_edit_start_value: Variant
var _live_edit_state: Dictionary = { }

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

# Rendering
var _pixelated_canvas_rid: RID


func _ready() -> void:
	_style = CellStyle.new()
	_refresh_style()

	if Engine.is_editor_hint() and not EditorThemeUtils.is_in_edited_scene(self):
		EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)
		EditorInterface.get_resource_previewer().preview_invalidated.connect(
			_on_resource_previewer_preview_invalidated
		)
		set_native_theming()

	self.focus_mode = Control.FOCUS_ALL
	self.clip_contents = true

	_setup_components()
	_reset_column_widths()

	resized.connect(_on_resized)

	self.anchor_left = 0.0
	self.anchor_top = 0.0
	self.anchor_right = 1.0
	self.anchor_bottom = 1.0

	queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if _pixelated_canvas_rid.is_valid():
				RenderingServer.free_rid(_pixelated_canvas_rid)
		NOTIFICATION_MOUSE_EXIT:
			_hovered_header_col = &""
			_is_sort_icon_hovered = false
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventKey and event.is_pressed() and has_focus():
		_handle_key_input(event as InputEventKey)


func _draw() -> void:
	RenderingServer.canvas_item_clear(_pixelated_canvas_rid)
	if not is_inside_tree() or _columns.is_empty():
		return

	var frozen_width := _get_frozen_width()
	_style.frozen_width = frozen_width
	var scrollable_start_x := frozen_width - _scroll_container.scroll_horizontal
	var visible_width := _get_visible_width()
	var visible_rows := _get_visible_row_range()
	RenderingServer.canvas_item_set_clip(_pixelated_canvas_rid, true)
	RenderingServer.canvas_item_set_custom_rect(
		_pixelated_canvas_rid,
		true,
		Rect2(
			frozen_width,
			header_height,
			maxf(0.0, visible_width - frozen_width),
			maxf(0.0, size.y - header_height),
		),
	)

	# Pass 1: scrollable columns
	for row_idx in range(visible_rows.x, visible_rows.y):
		var row := _order[row_idx]
		var row_y := _get_row_y(row_idx)
		var bg := alternate_row_color if row_idx % 2 == 1 else row_color
		draw_rect(Rect2(0, row_y, visible_width, row_height), bg)
		if selected_rows.has(row):
			draw_rect(Rect2(0, row_y, visible_width, row_height - 1), selected_row_back_color)
		draw_line(
			Vector2(0, row_y + row_height),
			Vector2(visible_width, row_y + row_height),
			grid_color,
		)
		_draw_cells_column_range(
			row,
			row_y,
			n_frozen_columns,
			_columns.size(),
			scrollable_start_x,
			frozen_width,
			visible_width,
		)

	# Pass 2: frozen columns drawn on top
	if n_frozen_columns > 0:
		for row_idx in range(visible_rows.x, visible_rows.y):
			var row := _order[row_idx]
			var row_y := _get_row_y(row_idx)
			var bg := alternate_row_color if row_idx % 2 == 1 else row_color
			draw_rect(Rect2(0, row_y, frozen_width, row_height), bg)
			if selected_rows.has(row):
				draw_rect(Rect2(0, row_y, frozen_width, row_height - 1), selected_row_back_color)
			draw_line(
				Vector2(0, row_y + row_height),
				Vector2(frozen_width, row_y + row_height),
				grid_color,
			)
			_draw_cells_column_range(row, row_y, 0, n_frozen_columns, 0.0, 0.0, frozen_width)

	# Pass 3: header drawn last, over the partially scrolled-out top row
	draw_rect(Rect2(0, 0, size.x, header_height), header_color)
	_draw_header_column_range(
		n_frozen_columns,
		_columns.size(),
		scrollable_start_x,
		frozen_width,
		visible_width,
	)

	if n_frozen_columns > 0:
		draw_rect(Rect2(0, 0, frozen_width, header_height), header_color)
		_draw_header_column_range(0, n_frozen_columns, 0.0, 0.0, visible_width)

		var separator_bottom := minf(_get_row_y(_order.size()), size.y)
		draw_line(
			Vector2(frozen_width, 0),
			Vector2(frozen_width, separator_bottom),
			grid_color.darkened(0.2),
			2.0,
		)

		var v_scroll_bar := _scroll_container.get_v_scroll_bar()
		if v_scroll_bar.visible:
			draw_rect(
				Rect2(visible_width, header_height, v_scroll_bar.size.x + 50, size.y),
				row_color,
			)


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
	if (
		Compat.is_engine_version_equal_or_newer(4, 6)
		and editor_settings.get_setting("interface/theme/style") == "Modern"
	):
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
	progress_background_color = root.get_theme_color(&"background", &"Editor")
	progress_border_color = root.get_theme_color(&"extra_border_color_2", &"Editor")
	progress_text_color_light = default_font_color
	progress_text_color_dark = root.get_theme_color(&"dark_color_1", &"Editor")
	progress_bar_start_color = root.get_theme_color(&"axis_x_color", &"Editor")
	progress_bar_middle_color = root.get_theme_color(&"executing_line_color", &"CodeEdit")
	progress_bar_end_color = root.get_theme_color(&"success_color", &"Editor")

	row_height = font_size * 2
	header_height = font_size * 2
	if _scroll_container:
		_scroll_container.offset_top = header_height
		_update_content_size()

	_refresh_style()
	queue_redraw()


func set_columns(columns: Array[ColumnConfig]) -> void:
	_column_base_order = columns
	_rebuild_display_columns()
	_reset_column_widths()
	queue_redraw()


func get_column(col: StringName) -> ColumnConfig:
	var idx: int = _column_index_by_id.get(col, -1)
	return _columns[idx] if idx >= 0 else null


## Returns all columns, in display order.
func get_all_columns() -> Array[ColumnConfig]:
	return _columns.duplicate()


## Toggles freeze on a single column by identifier, preserving relative order
## within both the frozen and scrollable groups. No-op if the column doesn't exist.
func set_column_frozen(identifier: StringName, frozen: bool) -> void:
	var column := get_column(identifier)
	if not column or column.frozen == frozen:
		return
	column.frozen = frozen
	_rebuild_display_columns()
	refresh_layout()


## Replace all rows. Preserves focused_row and selected_rows for keys that still exist.
## Re-applies the active filter and sort after rebuilding.
func set_data(rows: Array[Dictionary], row_ids: Array[StringName]) -> void:
	_rows.clear()
	_base_order.clear()
	for i in row_ids.size():
		var row_id := row_ids[i]
		_rows[row_id] = rows[i].duplicate() if i < rows.size() else { }
		_base_order.append(row_id)
	_order = _base_order.duplicate()
	_rebuild_filtered_order()

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

	_update_content_size()
	queue_redraw()


## Update a single row in place without rebuilding the full dataset.
func update_row(row: StringName, cells: Dictionary[StringName, Variant]) -> void:
	if not _rows.has(row):
		return
	_rows[row] = cells.duplicate()
	queue_redraw()


## Append a new row. No-op if the row already exists.
func add_row(row: StringName, cells: Dictionary[StringName, Variant]) -> void:
	if _rows.has(row):
		return
	_rows[row] = cells.duplicate()
	_base_order.append(row)
	_order.append(row)
	_update_content_size()
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
	_update_content_size()
	queue_redraw()


func ordering_data(column: StringName, ascending: bool = true) -> void:
	var column_cfg := get_column(column)
	if not column_cfg:
		return
	_finish_cell_editing(false)
	sort_column = column
	sort_ascending = ascending
	var handler := column_cfg.get_cell_type()

	_order.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var a_cells: Dictionary[StringName, Variant] = _rows.get(a, { })
			var b_cells: Dictionary[StringName, Variant] = _rows.get(b, { })
			var va: Variant = a_cells.get(column, null)
			var vb: Variant = b_cells.get(column, null)
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
			return str(ka) < str(kb) if ascending else str(ka) > str(kb),
	)

	queue_redraw()


func update_cell(row: StringName, col: StringName, value: Variant) -> void:
	if not is_cell_valid(row, col):
		return
	_rows[row][col] = value
	queue_redraw()


func get_cell_value(row: StringName, col: StringName) -> Variant:
	if not is_cell_valid(row, col):
		return null
	return _rows[row][col]


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


func is_cell_valid(row: StringName, col: StringName) -> bool:
	return _rows.has(row) and _rows[row].has(col)


## Returns the rows currently visible (after sort/filter), in display order.
## /!\ These are not the rows in view (when there is overflow + HScrollbar)
func get_displayed_rows() -> Array[StringName]:
	return _order.duplicate()


## Clears the active column filter without rebuilding data.
func clear_filter() -> void:
	_filtered_column = &""
	_filter_text = ""


## Call after changing column widths or other layout properties. (Freeze
## changes via set_column_frozen()/set_columns() already call this.)
func refresh_layout() -> void:
	_update_content_size()
	queue_redraw()

#endregion


#region PRIVATE METHODS

func _setup_components() -> void:
	_double_click_timer = Timer.new()
	_double_click_timer.wait_time = _double_click_threshold / 1000.0
	_double_click_timer.one_shot = true
	_double_click_timer.timeout.connect(_on_double_click_timeout)
	add_child(_double_click_timer)

	_filter_line_edit = LineEdit.new()
	_filter_line_edit.visible = false
	_filter_line_edit.right_icon = get_theme_icon(&"Search", &"EditorIcons")
	_filter_line_edit.text_submitted.connect(_apply_filter)
	_filter_line_edit.editing_toggled.connect(_on_filter_editing_toggled)
	_filter_line_edit.focus_exited.connect(_on_filter_focus_exited)
	add_child(_filter_line_edit)

	_pixelated_canvas_rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_pixelated_canvas_rid, get_canvas_item())
	RenderingServer.canvas_item_set_default_texture_filter(
		_pixelated_canvas_rid,
		RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
	)
	_style.pixelated_canvas_rid = _pixelated_canvas_rid
	_style.get_thumbnail = _get_or_queue_thumbnail

	_scroll_content = Control.new()
	_scroll_content.mouse_filter = MOUSE_FILTER_IGNORE

	# Its left margin moves both the viewport and the HScrollBar past the frozen
	# columns, while the container still catches wheel input over them.
	_scroll_panel_style = StyleBoxEmpty.new()

	_scroll_container = ScrollContainer.new()
	_scroll_container.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll_container.offset_top = header_height
	_scroll_container.mouse_filter = MOUSE_FILTER_PASS
	_scroll_container.focus_mode = FOCUS_NONE
	_scroll_container.add_theme_stylebox_override(&"panel", _scroll_panel_style)
	_scroll_container.add_child(_scroll_content)
	for scroll_bar: ScrollBar in [
		_scroll_container.get_h_scroll_bar(),
		_scroll_container.get_v_scroll_bar(),
	]:
		scroll_bar.focus_mode = FOCUS_NONE
		scroll_bar.value_changed.connect(_on_scroll_value_changed)
	add_child(_scroll_container)


func _refresh_style() -> void:
	_style.font = font
	_style.mono_font = mono_font
	_style.font_size = font_size
	_style.default_font_color = default_font_color
	_style.readonly_font_color = get_theme_color(&"readonly_color", &"EditorProperty")
	_style.readonly_texture_modulate = get_theme_color(&"icon_disabled_color", &"Button")
	_style.error_color = get_theme_color(&"error_color", &"Editor")
	_style.checkbox_checked_icon = get_theme_icon(&"checked", &"CheckBox")
	_style.checkbox_unchecked_icon = get_theme_icon(&"unchecked", &"CheckBox")
	_style.checkbox_checked_disabled_icon = get_theme_icon(&"checked_disabled", &"CheckBox")
	_style.checkbox_unchecked_disabled_icon = get_theme_icon(&"unchecked_disabled", &"CheckBox")
	_style.file_dead_icon = get_theme_icon(&"FileDead", &"EditorIcons")
	_sort_icon = get_theme_icon(&"Sort", &"EditorIcons")
	_style.progress_bar_start_color = progress_bar_start_color
	_style.progress_bar_middle_color = progress_bar_middle_color
	_style.progress_bar_end_color = progress_bar_end_color
	_style.progress_background_color = progress_background_color
	_style.progress_border_color = progress_border_color
	_style.progress_text_color_light = progress_text_color_light


func _reset_column_widths() -> void:
	for column in _columns:
		column.minimum_width = default_minimum_column_width
		var header_size := font.get_string_size(
			column.header,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
		) + Vector2(font_size * 2, 0)
		column.current_width = header_size.x


func _rebuild_display_columns() -> void:
	var frozen_cols: Array[ColumnConfig] = []
	var scrollable_cols: Array[ColumnConfig] = []
	for col in _column_base_order:
		(frozen_cols if col.frozen else scrollable_cols).append(col)
	_columns = frozen_cols + scrollable_cols
	n_frozen_columns = frozen_cols.size()
	_column_index_by_id.clear()
	for i in _columns.size():
		_column_index_by_id[_columns[i].identifier] = i


func _update_content_size() -> void:
	if not _scroll_container:
		return
	if row_height <= 0:
		row_height = 30.0

	_scroll_panel_style.content_margin_left = _get_frozen_width()

	var scrollable_width := 0.0
	for col_idx in range(n_frozen_columns, _columns.size()):
		scrollable_width += _columns[col_idx].current_width
	_scroll_content.custom_minimum_size = Vector2(scrollable_width, _order.size() * row_height)


func _get_visible_width() -> float:
	var v_scroll_bar := _scroll_container.get_v_scroll_bar()
	return size.x - (v_scroll_bar.size.x if v_scroll_bar.visible else 0.0)


## Rows intersecting the body, as [first, end) indices into _order.
func _get_visible_row_range() -> Vector2i:
	if row_height <= 0:
		return Vector2i.ZERO
	var vertical_scroll := _scroll_container.scroll_vertical
	var first_row_idx := floori(vertical_scroll / row_height)
	var end_row_idx := ceili((vertical_scroll + size.y - header_height) / row_height)
	return Vector2i(first_row_idx, mini(end_row_idx, _order.size()))


func _get_row_y(row_idx: int) -> float:
	return header_height + row_idx * row_height - _scroll_container.scroll_vertical


func _get_column_index(col: StringName) -> int:
	return _column_index_by_id.get(col, -1)


func _is_numeric_value(value: Variant) -> bool:
	if value == null:
		return false
	var str_val := str(value)
	return str_val.is_valid_float() or str_val.is_valid_int()


func _get_page_row_count() -> int:
	return maxi(1, floori((size.y - header_height) / row_height) if row_height > 0 else 10)


func _start_cell_editing(row: StringName, col: StringName) -> void:
	if not is_cell_valid(row, col):
		return

	var column := get_column(col)
	if column.read_only:
		YardLogger.warn("%s is read-only." % column.identifier)
		return
	var handler := column.get_editor_cell_type()
	if not handler.has_editor():
		YardLogger.warn("There is no editor for this type of cell.")
		return

	_ensure_row_visible(row)
	_ensure_col_visible(col)
	var cell_rect := _get_cell_rect(row, col)
	if not cell_rect:
		return

	_edited_row = row
	_edited_col = col
	_current_editor_handler = handler
	_current_editor_node = handler.create_editor(
		self,
		cell_rect,
		get_cell_value(row, col),
		column,
		_on_editor_finished,
	)
	_scroll_container.mouse_filter = MOUSE_FILTER_IGNORE


func _finish_cell_editing(save_changes: bool = true) -> void:
	if _edited_row == &"" and _edited_col == &"":
		return

	if save_changes:
		var column := get_column(_edited_col)
		var old_value: Variant = get_cell_value(_edited_row, _edited_col)
		var new_value: Variant = _current_editor_handler.read_editor_value(
			_current_editor_node,
			column,
		)

		var converted: Variant = type_convert(new_value, column.type)
		update_cell(_edited_row, _edited_col, converted)
		cell_edited.emit(_edited_row, _edited_col, old_value, converted)

	_edited_row = &""
	_edited_col = &""
	if _current_editor_node:
		_current_editor_node.queue_free()
		_current_editor_node = null
	_current_editor_handler = null
	_scroll_container.mouse_filter = MOUSE_FILTER_PASS
	queue_redraw()


func _get_cell_rect(row: StringName, col: StringName) -> Rect2:
	var row_idx := _order.find(row)
	var col_idx := _get_column_index(col)
	if row_idx < 0 or col_idx < 0:
		return Rect2()
	var row_y := _get_row_y(row_idx)
	if row_y + row_height <= header_height or row_y >= size.y:
		return Rect2()
	var cell_x := _get_col_x_pos(col_idx)
	var col_cfg := get_column(col)
	if cell_x + col_cfg.current_width <= 0 or cell_x >= _get_visible_width():
		return Rect2()
	return Rect2(cell_x, row_y, col_cfg.current_width, row_height)


func _dispatch_cell_draw(cell_rect: Rect2, row: StringName, col: StringName) -> void:
	if not is_cell_valid(row, col):
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
	var font_color: Color = _style.readonly_font_color if column.read_only else default_font_color
	if column.identifier == _filtered_column:
		font_color = header_filter_active_font_color
		header_text += " (" + str(_order.size()) + ")"

	var is_sorted := column.identifier == sort_column
	var is_hovered := column.identifier == _hovered_header_col
	var show_sort_icon := _sort_icon != null and (is_sorted or is_hovered)

	var header_alignment := HORIZONTAL_ALIGNMENT_LEFT
	var x_margin: int = CellType.H_ALIGNMENT_MARGINS.get(header_alignment)
	var text_width: float = column.current_width - absi(x_margin)
	var sort_icon_rect := Rect2()
	if show_sort_icon:
		sort_icon_rect = _get_sort_icon_rect(cell_x, column)
		text_width = sort_icon_rect.position.x - (cell_x + x_margin)
	var baseline_y := CellType.get_text_baseline_y(font, font_size, 0.0, header_height)
	draw_string(
		font,
		Vector2(cell_x + x_margin, baseline_y),
		header_text,
		header_alignment,
		text_width,
		font_size,
		font_color,
	)

	if show_sort_icon:
		# Mirror it around its horizontal center line for ascending.
		if not is_sorted or (is_sorted and sort_ascending):
			draw_set_transform(
				Vector2(0.0, sort_icon_rect.get_center().y * 2.0),
				0.0,
				Vector2(1.0, -1.0),
			)
		var is_icon_active := is_sorted or (is_hovered and _is_sort_icon_hovered)
		var icon_modulate := Color.WHITE if is_icon_active else Color(1.0, 1.0, 1.0, 0.5)
		draw_texture_rect(_sort_icon, sort_icon_rect, false, icon_modulate)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	var divider_x := cell_x + column.current_width
	if col_idx < _columns.size() - 1 and divider_x < vis_w:
		draw_line(
			Vector2(divider_x, 0),
			Vector2(divider_x, header_height),
			grid_color,
			2.0 if _mouse_over_divider == col_idx else 1.0,
		)


func _draw_header_column_range(
	col_from: int,
	col_to: int,
	start_x: float,
	clip_left: float,
	vis_w: float,
) -> void:
	var hx := start_x
	for col_idx in range(col_from, col_to):
		var col := _columns[col_idx]
		if hx + col.current_width > clip_left and hx < vis_w:
			_draw_header_cell(col_idx, hx, vis_w)
		hx += col.current_width


func _draw_cells_column_range(
	row: StringName,
	row_y: float,
	col_from: int,
	col_to: int,
	start_x: float,
	clip_left: float,
	vis_w: float,
) -> void:
	var col_x := start_x
	for col_idx in range(col_from, col_to):
		var col := _columns[col_idx]
		if col_x + col.current_width > clip_left and col_x < vis_w:
			var cell_rect := Rect2(col_x, row_y, col.current_width, row_height)
			draw_line(Vector2(col_x, row_y), Vector2(col_x, row_y + row_height), grid_color)
			var profiling_start := Time.get_ticks_msec() if _DEBUG_show_cell_draw_profiling else 0
			_dispatch_cell_draw(cell_rect, row, col.identifier)
			var profiling_end := Time.get_ticks_msec() if _DEBUG_show_cell_draw_profiling else 0
			if _DEBUG_show_cell_draw_profiling:
				var ms: float = (profiling_end - profiling_start) / 1000.0
				draw_rect(cell_rect, Color(1.0, 0.0, 0.0, ms * 100), true)
			if row == focused_row and col.identifier == focused_col:
				draw_rect(
					cell_rect.grow_individual(-1, -1, -2, -2),
					selected_cell_back_color,
					false,
					2.0,
				)
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

	var col_idx := _get_column_index(col)
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
	_scroll_container.scroll_vertical = 0

	# Keep selection only for rows still visible after filter
	var kept: Array[StringName] = []
	for row in selected_rows:
		if _order.has(row):
			kept.append(row)
	selected_rows = kept
	if not _order.has(focused_row):
		focused_row = &""

	sort_column = &""

	_update_content_size()
	queue_redraw()


func _rebuild_filtered_order() -> void:
	if _filtered_column == &"" or _filter_text.is_empty():
		_order = _base_order.duplicate()
		return
	var column := get_column(_filtered_column)
	var cell_type := column.get_cell_type()
	_order.clear()
	var key_lower := _filter_text.to_lower()
	for row in _base_order:
		var row_data: Dictionary[StringName, Variant] = _rows.get(row, { })
		if is_cell_valid(row, _filtered_column):
			var filter_key: String = cell_type.get_filter_key(row_data[_filtered_column], column)
			if filter_key.to_lower().contains(key_lower):
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

	col_x = frozen_w - _scroll_container.scroll_horizontal
	for col_idx in range(n_frozen_columns, _columns.size()):
		var col_end := col_x + _columns[col_idx].current_width
		if x >= maxf(col_x, frozen_w) and x < col_end:
			return col_idx
		col_x = col_end
	return -1


func _get_row_at_y(y: float) -> int:
	if y < header_height or row_height <= 0:
		return -1
	var row: int = floori((y - header_height + _scroll_container.scroll_vertical) / row_height)
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
		var x := _get_frozen_width() - _scroll_container.scroll_horizontal
		for i in range(n_frozen_columns, col_idx):
			x += _columns[i].current_width
		return x


func _get_sort_icon_rect(cell_x: float, column: ColumnConfig) -> Rect2:
	var icon_size := _sort_icon.get_size()
	var margin: int = absi(CellType.H_ALIGNMENT_MARGINS.get(HORIZONTAL_ALIGNMENT_RIGHT))
	return Rect2(
		Vector2(
			cell_x + column.current_width - icon_size.x - margin,
			(header_height - icon_size.y) / 2.0,
		),
		icon_size,
	)


## Returns the index of the column whose sort icon is under mouse_pos, or -1.
func _get_sort_icon_col_at(mouse_pos: Vector2) -> int:
	if not _sort_icon or mouse_pos.y >= header_height:
		return -1
	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx == -1:
		return -1
	var icon_rect := _get_sort_icon_rect(_get_col_x_pos(col_idx), _columns[col_idx])
	return col_idx if icon_rect.has_point(mouse_pos) else -1


func _check_mouse_over_divider(mouse_pos: Vector2) -> void:
	_mouse_over_divider = -1
	mouse_default_cursor_shape = CURSOR_ARROW

	if mouse_pos.y < header_height:
		for col_idx in _columns.size():
			var divider_x := _get_col_x_pos(col_idx) + _columns[col_idx].current_width
			if col_idx >= n_frozen_columns and divider_x <= _get_frozen_width():
				continue
			var divider_rect := Rect2(
				divider_x - _divider_width / 2.0,
				0,
				_divider_width,
				header_height,
			)
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
			var cell_type := column.get_cell_type()
			if not cell_type.suppresses_tooltip():
				new_tooltip = cell_type.get_tooltip(get_cell_value(new_row, col), column)

	if new_row != _tooltip_row or new_col != _tooltip_col:
		_tooltip_row = new_row
		_tooltip_col = new_col
		self.tooltip_text = new_tooltip


func _ensure_row_visible(row: StringName) -> void:
	var row_idx := _order.find(row)
	if row_idx < 0:
		return

	var row_top := row_idx * row_height
	var row_bottom := row_top + row_height
	var viewport_height := _scroll_container.get_v_scroll_bar().page
	if row_top < _scroll_container.scroll_vertical:
		_scroll_container.scroll_vertical = floori(row_top)
	elif row_bottom > _scroll_container.scroll_vertical + viewport_height:
		_scroll_container.scroll_vertical = ceili(row_bottom - viewport_height)


func _ensure_col_visible(col: StringName) -> void:
	var col_idx := _get_column_index(col)
	if col_idx < 0 or col_idx < n_frozen_columns:
		return

	var col_scroll_pos := 0.0
	for i in range(n_frozen_columns, col_idx):
		col_scroll_pos += _columns[i].current_width
	var col_scroll_end := col_scroll_pos + _columns[col_idx].current_width
	var viewport_width := _scroll_container.get_h_scroll_bar().page

	if col_scroll_pos < _scroll_container.scroll_horizontal:
		_scroll_container.scroll_horizontal = floori(col_scroll_pos)
	elif col_scroll_end > _scroll_container.scroll_horizontal + viewport_width:
		if _columns[col_idx].current_width <= viewport_width:
			_scroll_container.scroll_horizontal = ceili(col_scroll_end - viewport_width)
		else:
			_scroll_container.scroll_horizontal = floori(col_scroll_pos)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var m_pos := event.position

	if _live_edit_row != &"":
		_dispatch_cell_input(event, _live_edit_row, _live_edit_col)
	elif _resizing_column != &"":
		var delta_x: float = m_pos.x - _resizing_start_pos
		var new_width: float = max(
			_resizing_start_width + delta_x,
			get_column(_resizing_column).minimum_width,
		)
		get_column(_resizing_column).current_width = new_width
		_update_content_size()
		column_resized.emit(_resizing_column, new_width)
		queue_redraw()
	else:
		_check_mouse_over_divider(m_pos)
		if _mouse_over_divider == -1:
			var col_idx := _get_col_at_x(m_pos.x) if m_pos.y < header_height else -1
			var hovered_col: StringName = _columns[col_idx].identifier if col_idx != -1 else &""
			_hovered_header_col = hovered_col
			_is_sort_icon_hovered = _get_sort_icon_col_at(m_pos) != -1
		else:
			_hovered_header_col = &""
			_is_sort_icon_hovered = false
		_update_tooltip(m_pos)
		queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_left_press(event)
			MOUSE_BUTTON_RIGHT:
				_handle_right_click(event.position)
	else:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_left_release(event)


func _handle_left_press(event: InputEventMouseButton) -> void:
	var m_pos := event.position
	var is_double_click := (
		_click_count == 1 and _double_click_timer.time_left > 0
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

		var is_select_modifier := event.shift_pressed or event.ctrl_pressed or event.meta_pressed
		if not is_select_modifier:
			_dispatch_cell_input(event, row, col)
		_handle_cell_click(m_pos, event)

	if _mouse_over_divider >= 0:
		_resizing_column = _columns[_mouse_over_divider].identifier
		_resizing_start_pos = int(m_pos.x)
		_resizing_start_width = int(get_column(_resizing_column).current_width)


func _handle_left_release(event: InputEventMouseButton) -> void:
	if _live_edit_row != &"":
		_dispatch_cell_input(event, _live_edit_row, _live_edit_col)
	_resizing_column = &""


func _handle_cell_click(mouse_pos: Vector2, event: InputEventMouseButton) -> void:
	if _edited_col != &"":
		_finish_cell_editing(false)

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
	_ensure_row_visible(focused_row)
	_ensure_col_visible(focused_col)

	if selected_rows.size() > 1:
		multiple_rows_selected.emit(selected_rows)

	queue_redraw()


func _handle_right_click(mouse_pos: Vector2) -> void:
	if mouse_pos.y < header_height:
		_handle_header_right_click(mouse_pos)
		return

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
			if not (
				selected_rows.size() == 1 and selected_rows[0] == row
				and focused_row == row and focused_col == col
			):
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
			_finish_cell_editing(false)
			if _get_sort_icon_col_at(mouse_pos) == col_idx:
				sort_ascending = not sort_ascending if sort_column == col else true
				ordering_data(col, sort_ascending)
			header_left_clicked.emit(col)
			break


func _handle_header_right_click(mouse_pos: Vector2) -> void:
	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx == -1:
		return
	_finish_cell_editing(false)
	header_right_clicked.emit(_columns[col_idx].identifier)


func _handle_header_double_click(mouse_pos: Vector2) -> void:
	# Rapid clicks on the sort icon keep toggling the sort, not open the filter.
	if _get_sort_icon_col_at(mouse_pos) != -1:
		_handle_header_click(mouse_pos)
		return
	_finish_cell_editing(false)
	var col_idx := _get_col_at_x(mouse_pos.x)
	if col_idx != -1:
		var col := _columns[col_idx].identifier
		_ensure_col_visible(col)
		_start_filtering(col)


func _handle_key_input(event: InputEventKey) -> void:
	var is_any_cell_focused := focused_row != &"" and focused_col != &""
	var focused_row_idx := _order.find(focused_row) if focused_row != &"" else -1
	var focused_col_idx := _get_column_index(focused_col) if focused_col != &"" else -1

	# EDIT CELL
	if event.is_action_pressed(&"ui_accept"):
		if not is_any_cell_focused:
			return
		if not _dispatch_cell_input(event, focused_row, focused_col):
			_start_cell_editing(focused_row, focused_col)

	# SELECT ALL ROWS
	elif event.is_action_pressed(&"ui_text_select_all"):
		if _order.is_empty():
			return
		select_all_rows()
		multiple_rows_selected.emit(selected_rows)

	# UNSELECT
	elif event.is_action_pressed(&"ui_cancel"):
		if selected_rows.is_empty() and focused_row == &"":
			return
		set_selected_cell(&"", &"")

	# SELECT FOCUSED CELL
	elif event.is_action_pressed(&"ui_select"):
		if not is_any_cell_focused:
			return
		if selected_rows.has(focused_row):
			selected_rows.erase(focused_row)
		else:
			selected_rows.append(focused_row)
		_anchor_row = focused_row
		cell_selected.emit(focused_row, focused_col)

	# NAVIGATE TO FIRST ROW
	elif event.is_action_pressed(&"ui_home"):
		if _order.is_empty():
			return
		var new_row_idx := 0 if not _order.is_empty() else -1
		var new_col_idx := 0 if not _columns.is_empty() else -1
		_navigate_to(new_row_idx, new_col_idx, event)

	# NAVIGATE TO LAST ROW
	elif event.is_action_pressed(&"ui_end"):
		if _order.is_empty():
			return
		var new_row_idx := _order.size() - 1
		var new_col_idx := _columns.size() - 1
		_navigate_to(new_row_idx, new_col_idx, event)

	# NAVIGATE UP
	elif event.is_action_pressed(&"ui_up", true):
		if not is_any_cell_focused:
			return
		var new_row_idx := maxi(0, focused_row_idx - 1)
		_navigate_to(new_row_idx, focused_col_idx, event)

	# NAVIGATE DOWN
	elif event.is_action_pressed(&"ui_down", true):
		if not is_any_cell_focused:
			return
		var new_row_idx := mini(_order.size() - 1, focused_row_idx + 1)
		_navigate_to(new_row_idx, focused_col_idx, event)

	# NAVIGATE LEFT
	elif event.is_action_pressed(&"ui_left", true):
		if not is_any_cell_focused:
			return
		var new_col_idx := maxi(0, focused_col_idx - 1)
		_navigate_to(focused_row_idx, new_col_idx, event)

	# NAVIGATE RIGHT
	elif event.is_action_pressed(&"ui_right", true):
		if not is_any_cell_focused:
			return
		var new_col_idx := mini(_columns.size() - 1, focused_col_idx + 1)
		_navigate_to(focused_row_idx, new_col_idx, event)

	# NAVIGATE 1 PAGE UP
	elif event.is_action_pressed(&"ui_page_up", true):
		if not is_any_cell_focused:
			return
		var new_row_idx := maxi(0, focused_row_idx - _get_page_row_count())
		_navigate_to(new_row_idx, focused_col_idx, event)

	# NAVIGATE 1 PAGE DOWN
	elif event.is_action_pressed(&"ui_page_down", true):
		if not is_any_cell_focused:
			return
		var new_row_idx := mini(_order.size() - 1, focused_row_idx + _get_page_row_count())
		_navigate_to(new_row_idx, focused_col_idx, event)

	else:
		return

	queue_redraw()
	get_viewport().set_input_as_handled()


func _navigate_to(new_idx: int, new_col_idx: int, key_event: InputEventKey) -> void:
	var new_row := _order[new_idx] if new_idx >= 0 and new_idx < _order.size() else &""
	var new_col := (
		_columns[new_col_idx].identifier
		if (new_col_idx >= 0 and new_col_idx < _columns.size())
		else &""
	)
	var old_row := focused_row
	var old_col := focused_col

	focused_row = new_row
	focused_col = new_col

	if key_event.is_shift_pressed():
		if _anchor_row == &"":
			_anchor_row = (
				old_row
				if old_row != &""
				else (_order[0] if not _order.is_empty() else &"")
			)
		if focused_row != &"":
			var anchor_idx := _order.find(_anchor_row)
			var focus_idx := _order.find(focused_row)
			selected_rows.clear()
			for i in range(mini(anchor_idx, focus_idx), maxi(anchor_idx, focus_idx) + 1):
				if i >= 0 and i < _order.size():
					selected_rows.append(_order[i])
			if selected_rows.size() > 1:
				multiple_rows_selected.emit(selected_rows)
	elif key_event.is_command_or_control_pressed():
		pass
	else:
		selected_rows.clear()
		if focused_row != &"":
			selected_rows.append(focused_row)
			_anchor_row = focused_row
		else:
			_anchor_row = &""

	if focused_row != &"":
		_ensure_row_visible(focused_row)
		_ensure_col_visible(focused_col)

	if old_row != focused_row or old_col != focused_col:
		cell_selected.emit(focused_row, focused_col)


## Lets the CellType at (row, col) claim an InputEvent (true) or pass it
## through (false). On claim, pins live-edit routing so follow-up motion or
## release events keep reaching this cell even after the cursor leaves it.
func _dispatch_cell_input(event: InputEvent, row: StringName, col: StringName) -> bool:
	if row == &"" or col == &"":
		return false

	var column := get_column(col)
	if column.read_only:
		return false
	var cell_value: Variant = get_cell_value(row, col)
	var rect := _get_cell_rect(row, col)
	var is_live_cell := row == _live_edit_row and col == _live_edit_col
	var state: Dictionary = _live_edit_state if is_live_cell else { }
	var result: Dictionary = column.get_cell_type().handle_input(
		event,
		rect,
		cell_value,
		column,
		_style,
		state,
	)
	if result.is_empty():
		return false

	if result.has(&"value"):
		update_cell(row, col, result[&"value"])

	if result.get(&"commit", false):
		var old_value: Variant = _live_edit_start_value if is_live_cell else cell_value
		var new_value: Variant = get_cell_value(row, col)
		if old_value != new_value:
			cell_edited.emit(row, col, old_value, new_value)
		_live_edit_row = &""
		_live_edit_col = &""
		_live_edit_start_value = null
		_live_edit_state = { }
	else:
		if not is_live_cell:
			_live_edit_row = row
			_live_edit_col = col
			_live_edit_start_value = cell_value
		_live_edit_state = result.get(&"state", state)
		if result.has(&"value"):
			progress_changed.emit(row, col, result[&"value"])

	queue_redraw()
	return true

#endregion


#region SIGNAL CALLBACKS

func _on_resized() -> void:
	queue_redraw()


func _on_editor_finished(save_changes: bool) -> void:
	_finish_cell_editing(save_changes)


func _on_double_click_timeout() -> void:
	_click_count = 0


func _on_scroll_value_changed(_value: float) -> void:
	if _current_editor_node:
		_finish_cell_editing(false)
	queue_redraw()


func _on_filter_focus_exited() -> void:
	if _filter_line_edit.visible:
		_apply_filter(_filter_line_edit.text)


func _on_filter_editing_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		# Discard filter edits when pressing `ui_cancel` (Escape)
		_apply_filter(_filter_text)


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


func _on_resource_cell_thumb_ready(
	resource_path: String,
	preview: Texture2D,
	thumbnail_preview: Texture2D,
	userdata: Variant,
) -> void:
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
