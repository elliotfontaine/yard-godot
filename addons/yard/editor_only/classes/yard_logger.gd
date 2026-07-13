# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Object

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const EditorThemeUtils := Namespace.EditorThemeUtils


static func info(message: String) -> void:
	print_rich(
		"[color=%s]%s[/color]" % [
			EditorThemeUtils.color_message.to_html(true),
			message,
		],
	)


static func warn(message: String) -> void:
	print_rich(
		"[color=%s]● [b]WARNING:[/b] %s[/color]" % [
			EditorThemeUtils.color_warning.to_html(true),
			message,
		],
	)


static func error(message: String) -> void:
	print_rich(
		"[color=%s]● [b]ERROR:[/b] %s[/color]" % [
			EditorThemeUtils.color_error.to_html(true),
			message,
		],
	)
