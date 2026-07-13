# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends EditorContextMenuPlugin

var callback: Callable


func _init(callback_p: Callable) -> void:
	callback = callback_p


func _popup_menu(paths: PackedStringArray) -> void:
	if paths.is_empty():
		add_context_menu_item("New Registry File...", callback, _get_registry_icon())
	else:
		add_context_menu_item("Registry File...", callback, _get_registry_icon())


func _get_registry_icon() -> Texture2D:
	return preload("res://addons/yard/editor_only/assets/yard.svg")
