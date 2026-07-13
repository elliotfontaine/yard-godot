# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Button

@export var icon_name := "Node":
	set(v):
		icon_name = v
		if has_theme_icon(v, &"EditorIcons"):
			icon = get_theme_icon(v, &"EditorIcons")


func _ready() -> void:
	self.icon_name = (icon_name)
