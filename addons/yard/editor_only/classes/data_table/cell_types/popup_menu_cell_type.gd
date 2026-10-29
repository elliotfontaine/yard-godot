# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Shared PopupMenu-based editor for EnumCellType, BitFlagsCellType, etc.
## Subclasses fill a PopupMenu (item metadata = value) in their create_editor(),
##  then open it with popup_single_choice() or popup_multiple_choice().

const StringCellType := Namespace.StringCellType

const SUGGESTIONS_MENU_NAME := "SuggestionsMenu"
const CUSTOM_VALUE_EDIT_NAME := "CustomValueEdit"


static func has_editor() -> bool:
	return true


## Single choice: the checked item's metadata, or the text typed in place of the menu (see
## popup_suggestions()). Multiple choice subclasses override this to combine every checked item.
static func read_editor_value(editor: Node, column: ColumnConfig) -> Variant:
	if editor.has_node(CUSTOM_VALUE_EDIT_NAME):
		return StringCellType.read_editor_value(editor.get_node(CUSTOM_VALUE_EDIT_NAME), column)
	var popup_menu := editor.get_node_or_null(SUGGESTIONS_MENU_NAME) as PopupMenu
	if not popup_menu:
		popup_menu = editor as PopupMenu
	for idx in popup_menu.item_count:
		if popup_menu.is_item_checked(idx):
			return popup_menu.get_item_metadata(idx)
	return null


## For radio items: picking one commits, dismissing the menu cancels. Other items are left
## to the caller.
static func popup_single_choice(
	popup_menu: PopupMenu,
	owner: Control,
	rect: Rect2,
	on_finished: Callable,
) -> PopupMenu:
	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
			if not popup_menu.is_item_radio_checkable(idx):
				return
			for i in popup_menu.item_count:
				popup_menu.set_item_checked(i, i == idx)
			on_finished.call(true), # Not good. Why does it know callback signature?!
	)
	return _popup_under_cell(popup_menu, owner, rect, on_finished.bind(false)) # Same issue


## For check items: picking one toggles it and keeps the menu open, closing the
## menu commits.
static func popup_multiple_choice(
	popup_menu: PopupMenu,
	owner: Control,
	rect: Rect2,
	on_finished: Callable,
) -> PopupMenu:
	popup_menu.hide_on_checkable_item_selection = false
	popup_menu.index_pressed.connect(popup_menu.toggle_item_checked)
	return _popup_under_cell(popup_menu, owner, rect, on_finished.bind(true))


## Like popup_single_choice(), for suggestion lists (PROPERTY_HINT_ENUM_SUGGESTION and alike):
## an empty item precedes the suggestions, and a last item swaps the menu for a LineEdit to type
## any value. A typed value that isn't a suggestion is listed on top.
static func popup_suggestions(
	suggestions: PackedStringArray,
	owner: Control,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	on_finished: Callable,
) -> Control:
	# Holds the menu, then the LineEdit. It sits at the owner's origin, so `rect` applies as is.
	var editor := Control.new()
	editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(editor)

	var text := str(value) if value != null else ""
	var popup_menu := PopupMenu.new()
	popup_menu.name = SUGGESTIONS_MENU_NAME
	if text and text not in suggestions:
		_add_radio_item(popup_menu, text, true)
		popup_menu.add_separator()
	_add_radio_item(popup_menu, "", not text)
	for suggestion in suggestions:
		_add_radio_item(popup_menu, suggestion, suggestion == text)
	popup_menu.add_separator()
	popup_menu.add_icon_item(
		EditorInterface.get_editor_theme().get_icon(&"Edit", &"EditorIcons"),
		editor_tr("Custom Value"),
	)

	var custom_value_idx := popup_menu.item_count - 1
	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
			if idx != custom_value_idx:
				return
			var line_edit := StringCellType.create_editor(editor, rect, text, column, on_finished)
			line_edit.name = CUSTOM_VALUE_EDIT_NAME,
	)
	# The menu also hides when it gives way to the LineEdit: that must not cancel the edit.
	var editor_ref: WeakRef = weakref(editor)
	var finish_unless_typing := func(save_changes: bool) -> void:
		var current_editor := editor_ref.get_ref() as Node
		if current_editor and not current_editor.has_node(CUSTOM_VALUE_EDIT_NAME):
			on_finished.call(save_changes)
	popup_single_choice(popup_menu, editor, rect, finish_unless_typing)
	return editor


static func _add_radio_item(popup_menu: PopupMenu, text: String, checked: bool) -> void:
	popup_menu.add_radio_check_item(text)
	popup_menu.set_item_metadata(popup_menu.item_count - 1, text)
	popup_menu.set_item_checked(popup_menu.item_count - 1, checked)


static func _popup_under_cell(
	popup_menu: PopupMenu,
	owner: Control,
	rect: Rect2,
	on_hidden: Callable,
) -> PopupMenu:
	popup_menu.popup_hide.connect(
		func() -> void:
			await popup_menu.get_tree().create_timer(0.05).timeout
			on_hidden.call(),
	)
	if Compat.is_engine_version_equal_or_newer(4, 7):
		popup_menu.set(&"search_bar_enabled", true)
		popup_menu.set(&"search_bar_min_item_count", 10)
	owner.add_child(popup_menu)
	# Anchored to the cell, not the mouse: editing may have started from the keyboard.
	var bottom_left := owner.get_screen_transform() * Vector2(rect.position.x, rect.end.y)
	popup_menu.position = Vector2i(bottom_left)
	popup_menu.popup()
	return popup_menu


# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: Copyright 2022 Gennady Krupenyov (Don Tnowe) <https://github.com/don-tnowe/godot-resources-as-sheets-plugin>
#
# SPDX-License-Identifier: MIT
static func _hashed_color(text: String) -> Color:
	return Color(text.hash()) + Color(0.25, 0.25, 0.25, 1.0)
# SPDX-SnippetEnd
