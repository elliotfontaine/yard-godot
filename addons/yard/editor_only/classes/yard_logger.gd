# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Object

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const Compat := Namespace.Compat
const EditorThemeUtils := Namespace.EditorThemeUtils


static func info(message: String) -> void:
	var text := "YARD - %s" % message
	if Engine.is_editor_hint():
		text = _colorize(text, EditorThemeUtils.color_message)
	print_rich(text)


static func warn(message: String) -> void:
	var caller: Dictionary = get_stack()[1]
	var line: int = caller.get("line", "")
	var source: String = caller.get("source", "")

	var text := "● [b]WARNING:[/b] [url]%s[/url] - YARD: %s" % ["%s:%s" % [source, line], message]
	if Engine.is_editor_hint():
		text = _colorize(text, EditorThemeUtils.color_warning)
	print_rich(text)


static func error(message: String) -> void:
	var line: String
	var source: String

	if Compat.is_engine_version_equal_or_newer(4, 5):
		var caller: Dictionary = get_stack()[1]
		line = str(caller.get("line", ""))
		source = caller.get("source", "")
	else:
		# For some reason, on 4.4, get_stack() returns an empty array.
		line = "{line}"
		source = "{source}"

	var text := "● [b]ERROR:[/b] [url]%s[/url] - YARD: %s" % ["%s:%s" % [source, line], message]
	if Engine.is_editor_hint():
		text = _colorize(text, EditorThemeUtils.color_error)
	print_rich(text)


## Colors come from the editor theme, which only exists in the editor. Elsewhere (e.g. in
## headless test runs), messages are printed uncolored.
static func _colorize(text: String, color: Color) -> String:
	return "[color=%s]%s[/color]" % [color.to_html(true), text]
