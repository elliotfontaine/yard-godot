@tool
extends Object

const EditorThemeUtils := preload("res://addons/yard/editor_only/classes/editor_theme_utils.gd")


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
