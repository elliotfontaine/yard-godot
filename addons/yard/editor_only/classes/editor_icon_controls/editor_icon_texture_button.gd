# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends TextureButton

@export var normal_icon_name := "Node":
	set(v):
		normal_icon_name = v
		if has_theme_icon(v, &"EditorIcons"):
			texture_normal = get_theme_icon(v, &"EditorIcons")

@export var pressed_icon_name := "":
	set(v):
		pressed_icon_name = v
		if has_theme_icon(v, &"EditorIcons"):
			texture_pressed = get_theme_icon(v, &"EditorIcons")

@export var hover_icon_name := "":
	set(v):
		hover_icon_name = v
		if has_theme_icon(v, &"EditorIcons"):
			texture_hover = get_theme_icon(v, &"EditorIcons")

@export var disabled_icon_name := "":
	set(v):
		disabled_icon_name = v
		if has_theme_icon(v, &"EditorIcons"):
			texture_disabled = get_theme_icon(v, &"EditorIcons")

@export var focused_icon_name := "":
	set(v):
		focused_icon_name = v
		if has_theme_icon(v, &"EditorIcons"):
			texture_focused = get_theme_icon(v, &"EditorIcons")


func _ready() -> void:
	self.normal_icon_name = normal_icon_name
	self.pressed_icon_name = pressed_icon_name
	self.hover_icon_name = hover_icon_name
	self.disabled_icon_name = disabled_icon_name
	self.focused_icon_name = focused_icon_name
