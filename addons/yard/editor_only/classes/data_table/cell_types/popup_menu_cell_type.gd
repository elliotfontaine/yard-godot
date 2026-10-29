# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Shared PopupMenu-based editor for EnumCellType, BitFlagsCellType, etc.
## Subclasses describe their choices in their create_editor(), then open them with
## popup_single_choice() or popup_multiple_choice(). The editor keeps the value being edited
## in its VALUE_META metadata, which read_editor_value() returns.

const StringCellType := Namespace.StringCellType

const VALUE_META := &"value"


static func has_editor() -> bool:
	return true


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	return editor.get_meta(VALUE_META, null)


## For radio items, from `choices` (value -> label, in menu order): picking one commits,
## dismissing the menu cancels.
## With `allow_custom` (PROPERTY_HINT_ENUM_SUGGESTION and alike), an empty choice precedes the
## others, and a last item swaps the menu for a LineEdit to type any value. A typed value that
## isn't a choice is listed on top.
static func popup_single_choice(
	owner: Control,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
	choices: Dictionary,
	allow_custom := false,
) -> Control:
	var editor := _create_editor(owner, value)
	var popup_menu := PopupMenu.new()
	var text := str(value) if value != null else ""
	if allow_custom:
		if text and not choices.has(text):
			_add_radio_item(popup_menu, text, text, true)
			popup_menu.add_separator()
		_add_radio_item(popup_menu, "", "", not text)
	for choice: Variant in choices:
		_add_radio_item(popup_menu, choice, choices[choice], choice == value)
	if allow_custom:
		popup_menu.add_separator()
		popup_menu.add_icon_item(
			EditorInterface.get_editor_theme().get_icon(&"Edit", &"EditorIcons"),
			editor_tr("Custom Value"),
		)

	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
			if not popup_menu.is_item_radio_checkable(idx):
				_type_custom_value(editor, popup_menu, rect, text, column, on_finished)
				return
			editor.set_meta(VALUE_META, popup_menu.get_item_metadata(idx))
			on_finished.call(true), # Not good. Why does it know callback signature?!
	)
	_popup_under_cell(popup_menu, editor, rect, on_finished.bind(false)) # Same issue
	return editor


## For check items, from `flags` (bit value -> label, in menu order): picking one toggles its
## bits and keeps the menu open, closing the menu commits.
static func popup_multiple_choice(
	owner: Control,
	rect: Rect2,
	value: Variant,
	on_finished: Callable,
	flags: Dictionary,
) -> Control:
	var editor := _create_editor(owner, value)
	var popup_menu := PopupMenu.new()
	popup_menu.hide_on_checkable_item_selection = false
	for bit: int in flags:
		popup_menu.add_check_item(flags[bit])
		popup_menu.set_item_metadata(popup_menu.item_count - 1, bit)
		popup_menu.set_item_checked(popup_menu.item_count - 1, (value & bit) != 0)

	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
			popup_menu.toggle_item_checked(idx)
			var bit: int = popup_menu.get_item_metadata(idx)
			var bitflags: int = editor.get_meta(VALUE_META)
			if popup_menu.is_item_checked(idx):
				editor.set_meta(VALUE_META, bitflags | bit)
			else:
				editor.set_meta(VALUE_META, bitflags & ~bit),
	)
	_popup_under_cell(popup_menu, editor, rect, on_finished.bind(true))
	return editor


## The node DataTable keeps for the edit: it holds the menu, or what replaces it, and the value
## being edited. It sits at the owner's origin, so cell rects apply as is inside it.
static func _create_editor(owner: Control, value: Variant) -> Control:
	var editor := Control.new()
	editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor.set_meta(VALUE_META, value)
	owner.add_child(editor)
	return editor


static func _add_radio_item(
	popup_menu: PopupMenu,
	value: Variant,
	label: String,
	checked: bool,
) -> void:
	popup_menu.add_radio_check_item(label)
	popup_menu.set_item_metadata(popup_menu.item_count - 1, value)
	popup_menu.set_item_checked(popup_menu.item_count - 1, checked)


## Swaps the menu for a LineEdit, to type a value that isn't one of the choices.
static func _type_custom_value(
	editor: Control,
	popup_menu: PopupMenu,
	rect: Rect2,
	text: String,
	column: ColumnConfig,
	on_finished: Callable,
) -> void:
	editor.set_meta(VALUE_META, text)
	var line_edit: LineEdit = StringCellType.create_editor(editor, rect, text, column, on_finished)
	line_edit.text_changed.connect(
		func(new_text: String) -> void:
			editor.set_meta(VALUE_META, new_text),
	)
	popup_menu.queue_free()


static func _popup_under_cell(
	popup_menu: PopupMenu,
	editor: Control,
	rect: Rect2,
	on_hidden: Callable,
) -> void:
	popup_menu.popup_hide.connect(
		func() -> void:
			await popup_menu.get_tree().create_timer(0.05).timeout
			# Freed once the edit is over, or once the menu gave way to a LineEdit.
			if is_instance_valid(popup_menu):
				on_hidden.call(),
	)
	if Compat.is_engine_version_equal_or_newer(4, 7):
		popup_menu.set(&"search_bar_enabled", true)
		popup_menu.set(&"search_bar_min_item_count", 10)
	editor.add_child(popup_menu)
	# Anchored to the cell, not the mouse: editing may have started from the keyboard.
	var bottom_left := editor.get_screen_transform() * Vector2(rect.position.x, rect.end.y)
	popup_menu.position = Vector2i(bottom_left)
	popup_menu.popup()


# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: Copyright 2022 Gennady Krupenyov (Don Tnowe) <https://github.com/don-tnowe/godot-resources-as-sheets-plugin>
#
# SPDX-License-Identifier: MIT
static func _hashed_color(text: String) -> Color:
	return Color(text.hash()) + Color(0.25, 0.25, 0.25, 1.0)
# SPDX-SnippetEnd
