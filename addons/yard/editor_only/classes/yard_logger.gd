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
		"[color=%s]YARD - %s[/color]" % [
			EditorThemeUtils.color_message.to_html(true),
			message,
		],
	)


static func warn(message: String) -> void:
	var caller: Dictionary = get_stack()[1]
	var line: int = caller.get("line", "")
	var source: String = caller.get("source", "")

	print_rich(
		"[color=%s]● [b]WARNING:[/b] [url]%s[/url] - YARD: %s[/color]" % [
			EditorThemeUtils.color_warning.to_html(true),
			"%s:%s" % [source, line],
			message,
		],
	)


static func error(message: String) -> void:
	var caller: Dictionary = get_stack()[1]
	var line: int = caller.get("line", "")
	var source: String = caller.get("source", "")

	print_rich(
		"[color=%s]● [b]ERROR:[/b] [url]%s[/url] - YARD: %s[/color]" % [
			EditorThemeUtils.color_error.to_html(true),
			"%s:%s" % [source, line],
			message,
		],
	)
