# SPDX-FileCopyrightText: 2020-present, Emilio Coppola <https://github.com/dialogic-godot/dialogic>
# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends AcceptDialog

## Displays release info and drives an update. Knows nothing about its
## container: it only asks for things via signals, and gets fed data through
## load_info()/set_download_result(). Closing is handled by AcceptDialog's
## own OK button (relabeled "Close"), nothing to wire up for that.

signal install_requested
signal refresh_requested

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const Compat := Namespace.Compat
const EditorThemeUtils := Namespace.EditorThemeUtils
const UpdateManager := Namespace.UpdateManager

const INSTALL_WARNING := (
	"Be careful. This will delete the addons/yard folder and install the new version."
	+ " Any custom changes in that folder will be lost.\nTo be on the safe side, use version control!"
)

var current_info := { }

@onready var content: RichTextLabel = %Content


func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == self:
		return

	var download_icon := &"AssetStore" if Compat.is_engine_version_equal_or_newer(4, 7) else &"AssetLib"
	%Install.icon = EditorThemeUtils.editor_theme.get_icon(download_icon, &"EditorIcons")
	%Install.tooltip_text = INSTALL_WARNING
	%LoadingIcon.texture = EditorThemeUtils.editor_theme.get_icon(&"KeyTrackScale", &"EditorIcons")

	var mono: Font = get_theme_font(&"font", &"CodeEdit")
	content.add_theme_font_override(&"mono_font", mono)
	content.add_theme_color_override(
		&"table_even_row_bg",
		get_theme_color(&"prop_section", &"Editor"),
	)
	content.add_theme_color_override(
		&"table_odd_row_bg",
		get_theme_color(&"separator_color", &"Editor"),
	)

	content.h2.font_color = get_theme_color(&"accent_color", &"Editor")
	content.h3.font_color = get_theme_color(&"font_focus_color", &"Editor")

	content.code_color = get_theme_color(&"warning_color", &"Editor")
	content.code_background_color = get_theme_color(&"background", &"Editor")


func load_info(info: Dictionary, result: UpdateManager.UpdateCheckResult) -> void:
	current_info = info
	if result == UpdateManager.UpdateCheckResult.NO_ACCESS:
		%State.text = "No Information Available"
		%UpdateName.text = "Unable to access versions."
		%UpdateName.remove_theme_color_override("font_color")
		%Content.text = "You are probably not connected to the internet. Fair enough."
		%ShortInfo.text = "Huh, what happened here?"
		%ReadFull.hide()
		%Reactions.hide()
		%Install.disabled = true
		return

	# If we are up to date (or beyond):
	if info.is_empty():
		info['name'] = "You are in the future, Marty!"
		info["body"] = "# 😎 You are using the WIP branch!\nSeems like you are using a version that isn't even released yet. Be careful and give us your feedback ;)"
		info["published_at"] = "????T"
		info["author"] = { 'login': "???" }
		%State.text = "Where are we Doc?"
		%UpdateName.remove_theme_color_override("font_color")
		%Install.disabled = true

	elif result == UpdateManager.UpdateCheckResult.UPDATE_AVAILABLE:
		%State.text = "Update Available!"
		%UpdateName.add_theme_color_override("font_color", EditorThemeUtils.color_warning)
		%Install.disabled = false
	else:
		%State.text = "You are up to date:"
		%UpdateName.add_theme_color_override("font_color", EditorThemeUtils.color_success)
		%Install.disabled = true

	%UpdateName.text = info.name
	%Content.text = info.body
	%ShortInfo.text = "Published on " + info.published_at.substr(0, info.published_at.find('T')) + " by " + info \
			.author \
			.login
	if info.has("html_url"):
		%ReadFull.uri = info.html_url
		%ReadFull.show()
	else:
		%ReadFull.hide()
	if info.has('reactions'):
		%Reactions.show()
		var reactions := {
			"laugh": "😂",
			"hooray": "🎉",
			"confused": "😕",
			"heart": "❤️",
			"rocket": "🚀",
			"eyes": "👀",
		}
		for i: String in reactions:
			%Reactions.get_node(i.capitalize()).visible = info.reactions[i] > 0
			%Reactions.get_node(i.capitalize()).text = (
				reactions[i] + " " + str(int(info.reactions[i]))
				if info.reactions[i] > 0
				else reactions[i]
			)
		if info.reactions['+1'] + info.reactions['-1'] > 0:
			%Reactions.get_node("Likes").visible = true
			%Reactions.get_node("Likes").text = "👍 " + str(
				int(info.reactions['+1'] + info.reactions['-1'])
			)
		else:
			%Reactions.get_node("Likes").visible = false
	else:
		%Reactions.hide()


func set_download_result(result: UpdateManager.DownloadResult) -> void:
	%Loading.hide()
	match result:
		UpdateManager.DownloadResult.SUCCESS:
			%InfoLabel.text = "Installed successfully. Restart needed!"
			%InfoLabel.modulate = EditorThemeUtils.color_success
			%Restart.show()
			%Restart.grab_focus()
		UpdateManager.DownloadResult.FAILURE:
			%InfoLabel.text = "Download failed."
			%InfoLabel.modulate = EditorThemeUtils.color_error


func _on_install_pressed() -> void:
	install_requested.emit()

	%InfoLabel.text = "Downloading. This can take a moment."
	%Loading.show()
	%LoadingIcon \
			.create_tween() \
			.set_loops() \
			.tween_property(%LoadingIcon, 'rotation', 2 * PI, 1) \
			.from(0)


func _on_refresh_pressed() -> void:
	refresh_requested.emit()


func _on_restart_pressed() -> void:
	EditorInterface.restart_editor(true)
