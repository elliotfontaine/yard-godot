# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends Control
## Draws the type matchup chart from the elements Registry.
## Rows = attacker, columns = defender.
## Click a cell to cycle its multiplier (x1 -> x2 -> x0.5 -> x0),
## then use the save button to write changes back to disk.

const ELEMENTS: Registry = preload("res://example/godomon/data/elements.tres")

const CELL := Vector2(30, 30)
const HEADER := Vector2(80, 30)
const COLOR_STRONG := Color("3b6d11") # x2
const COLOR_WEAK := Color("a32d2d") # x0.5
const COLOR_IMMUNE := Color("2c2c2a") # x0
const COLOR_NEUTRAL := Color(0.5, 0.5, 0.5, 0.08)

## Cycle order when clicking a cell
const CYCLE: Array[float] = [1.0, 2.0, 0.5, 0.0]

var _ids: Array[StringName] = []
var _elements: Dictionary[StringName, GdmElement] = { }
var _dirty: Dictionary[StringName, bool] = { } # attacker ids with unsaved changes
var _save_button: Button


func _ready() -> void:
	for id in ELEMENTS.get_all_string_ids():
		if id == &"???":
			continue
		_ids.append(id)
	_ids.sort()

	for id in _ids:
		_elements[id] = ELEMENTS.load_entry(id) as GdmElement

	_build_grid()
	_build_save_button()


func _build_grid() -> void:
	var grid := GridContainer.new()
	grid.columns = _ids.size() + 1
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	add_child(grid)

	grid.add_child(_make_header("ATK \\ DEF", HEADER))

	for def_id in _ids:
		var h := _make_header("", CELL)
		var elem := _elements[def_id]
		if elem.icon:
			var icon := TextureRect.new()
			icon.texture = elem.icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			h.add_child(icon)
		else:
			h.get_node("Label").text = elem.name.left(2)
		h.tooltip_text = elem.name
		h.get_node("Bg").color = elem.color
		grid.add_child(h)

	for atk_id in _ids:
		var atk := _elements[atk_id]

		var row_header := _make_header(atk.name, HEADER)
		row_header.get_node("Bg").color = atk.color
		grid.add_child(row_header)

		for def_id in _ids:
			var cell := _make_header("", CELL)
			_update_cell_visual(cell, atk_id, def_id)
			cell.gui_input.connect(_on_cell_input.bind(atk_id, def_id, cell))
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			grid.add_child(cell)


func _build_save_button() -> void:
	_save_button = Button.new()
	_save_button.text = "Save changes"
	_save_button.visible = false
	_save_button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT,
		Control.PRESET_MODE_MINSIZE,
		16,
	)
	_save_button.pressed.connect(_on_save_pressed)
	add_child(_save_button)


func _on_cell_input(event: InputEvent, atk_id: StringName, def_id: StringName, cell: Control) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_cycle_multiplier(atk_id, def_id)
		_update_cell_visual(cell, atk_id, def_id)
		_dirty[atk_id] = true
		_save_button.visible = true
		_save_button.text = "Save changes (%d)" % _dirty.size()


func _cycle_multiplier(atk_id: StringName, def_id: StringName) -> void:
	var atk := _elements[atk_id]
	var current := _get_multiplier(atk, def_id)
	var next: float = CYCLE[(CYCLE.find(current) + 1) % CYCLE.size()]

	# Remove from all lists, then insert into the right one
	atk.strong_against.erase(def_id)
	atk.weak_against.erase(def_id)
	atk.immune_targets.erase(def_id)
	match next:
		2.0:
			atk.strong_against.append(def_id)
		0.5:
			atk.weak_against.append(def_id)
		0.0:
			atk.immune_targets.append(def_id)
		# 1.0: absent from all lists


func _update_cell_visual(cell: Control, atk_id: StringName, def_id: StringName) -> void:
	var atk := _elements[atk_id]
	var mult := _get_multiplier(atk, def_id)
	var label: Label = cell.get_node("Label")
	var bg: ColorRect = cell.get_node("Bg")
	match mult:
		2.0:
			label.text = "2"
			bg.color = COLOR_STRONG
		0.5:
			label.text = "½"
			bg.color = COLOR_WEAK
		0.0:
			label.text = "0"
			bg.color = COLOR_IMMUNE
		_:
			label.text = ""
			bg.color = COLOR_NEUTRAL
	cell.tooltip_text = "%s → %s : ×%s" % [atk.name, _elements[def_id].name, mult]


func _get_multiplier(atk: GdmElement, def_id: StringName) -> float:
	if def_id in atk.immune_targets:
		return 0.0
	if def_id in atk.strong_against:
		return 2.0
	if def_id in atk.weak_against:
		return 0.5
	return 1.0


func _make_header(text: String, p_size: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = p_size

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color.TRANSPARENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)

	var label := Label.new()
	label.name = "Label"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(label)

	return c


func _on_save_pressed() -> void:
	var errors := 0
	for atk_id in _dirty:
		var elem := _elements[atk_id]
		var err := ResourceSaver.save(elem) # saves to elem.resource_path, overwrites
		if err != OK:
			errors += 1
			push_error(
				"Failed to save '%s' (%s): error %d"
				% [atk_id, elem.resource_path, err],
			)
	if errors == 0:
		_dirty.clear()
		_save_button.visible = false
	else:
		_save_button.text = "Save changes (%d failed)" % errors
