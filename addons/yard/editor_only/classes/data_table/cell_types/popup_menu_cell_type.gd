# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Shared PopupMenu-based editor for EnumCellType, BitFlagsCellType, etc.
## Subclasses fill a PopupMenu (item metadata = value) in their create_editor(),
##  then open it with popup_single_choice() or popup_multiple_choice().


static func has_editor() -> bool:
	return true


## Single choice: the checked item's metadata. Multiple choice subclasses
## override this to combine every checked item.
static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var popup_menu: PopupMenu = editor
	for idx in popup_menu.item_count:
		if popup_menu.is_item_checked(idx):
			return popup_menu.get_item_metadata(idx)
	return null


## For radio items: picking one commits, dismissing the menu cancels.
static func popup_single_choice(
	popup_menu: PopupMenu,
	owner: Control,
	rect: Rect2,
	on_finished: Callable,
) -> PopupMenu:
	popup_menu.index_pressed.connect(
		func(idx: int) -> void:
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
