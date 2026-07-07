@tool
extends "res://addons/yard/editor_only/ui_scenes/components/cell_types/cell_type.gd"
## Color columns. The picker popup is built programmatically (see Popup below)
## rather than from a separate scene. Clicking away from an open editor still
## commits the current color (it behaves like an inline picker, despite the
## dialog-like buttons).

const EditorIconButton := Namespace.EditorIconButton


static func matches(column: ColumnConfig) -> bool:
	return column.is_color_column()


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	if value is not Color:
		draw_text(canvas, rect, str(value) if value != null else "", resolve_font(column, style.font), style.font_size, column.h_alignment, resolve_text_color(column, style))
		return

	var color: Color = value
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
				canvas.draw_rect(Rect2(Vector2(x, y), Vector2(min(tile, x1 - x), min(tile, y1 - y))), bg, true)
				x += tile
				col_i += 1
			y += tile
			row_i += 1

	canvas.draw_rect(inner, color, true)
	canvas.draw_rect(inner, Color(1, 1, 1, border_alpha), false, 1.0)


static func has_editor() -> bool:
	return true


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	var c := Color(value)
	return [c.h, c.s, c.v, c.a]


static func create_editor(owner: Control, rect: Rect2, value: Variant, _column: ColumnConfig, on_finished: Callable) -> Node:
	var popup := ColorPopup.new()
	owner.add_child(popup)
	popup.position = rect.get_center() + owner.global_position
	popup.color = value
	popup.color_selected.connect(func(_c: Color) -> void: on_finished.call(true))
	popup.canceled.connect(func() -> void: on_finished.call(false))
	popup.show()
	popup.grab_focus()
	return popup


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var color_popup: ColorPopup = editor
	return color_popup.color


class ColorPopup extends PanelContainer:
	signal color_selected(color: Color)
	signal canceled

	var color_picker: ColorPicker

	var color: Color:
		set(value):
			color_picker.color = value
		get:
			return color_picker.color


	func _init() -> void:
		top_level = true
		focus_mode = Control.FOCUS_ALL

		var margin := MarginContainer.new()
		for side: String in [&"left", &"top", &"right", &"bottom"]:
			margin.add_theme_constant_override(&"margin_%s" % side, 8)
		add_child(margin)

		var vbox := VBoxContainer.new()
		margin.add_child(vbox)

		color_picker = ColorPicker.new()
		color_picker.deferred_mode = true
		color_picker.presets_visible = false
		vbox.add_child(color_picker)

		var hbox := HBoxContainer.new()
		vbox.add_child(hbox)

		var cancel_button := Button.new()
		cancel_button.text = tr("Cancel")
		cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN | Control.SIZE_EXPAND
		cancel_button.pressed.connect(func() -> void: canceled.emit())
		hbox.add_child(cancel_button)

		var select_button := EditorIconButton.new()
		select_button.text = tr("Select")
		select_button.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
		select_button.icon_name = &"ArrowRight"
		select_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		select_button.pressed.connect(func() -> void: color_selected.emit(color_picker.color))
		hbox.add_child(select_button)


	func _ready() -> void:
		add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"PopupMenu"))
