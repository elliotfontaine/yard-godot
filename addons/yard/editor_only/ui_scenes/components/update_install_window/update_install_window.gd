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
@onready var install_button: Button = %Install
@onready var loading_icon: TextureRect = %LoadingIcon
@onready var state_label: Label = %State
@onready var update_name_label: Label = %UpdateName
@onready var short_info_label: Label = %ShortInfo
@onready var read_full_link: LinkButton = %ReadFull
@onready var reactions_container: HBoxContainer = %Reactions
@onready var loading_container: CenterContainer = %Loading
@onready var info_label: Label = %InfoLabel
@onready var restart_button: Button = %Restart


func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == self:
		return

	var is_above_4_7 := Compat.is_engine_version_equal_or_newer(4, 7)
	if is_above_4_7:
		loading_icon.set(&"offset_transform_enabled", true)
	var download_icon := &"AssetStore" if is_above_4_7 else &"AssetLib"
	install_button.icon = EditorThemeUtils.editor_theme.get_icon(download_icon, &"EditorIcons")
	install_button.tooltip_text = INSTALL_WARNING
	loading_icon.texture = EditorThemeUtils.editor_theme.get_icon(&"KeyTrackScale", &"EditorIcons")

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
		state_label.text = "No Information Available"
		update_name_label.text = "Unable to access versions."
		update_name_label.remove_theme_color_override("font_color")
		content.text = "You are probably not connected to the internet. Fair enough."
		short_info_label.text = "Huh, what happened here?"
		read_full_link.hide()
		reactions_container.hide()
		install_button.disabled = true
		return

	# If we are up to date (or beyond):
	if info.is_empty():
		info['name'] = "You are in the future, Marty!"
		info["body"] = "# 😎 You are using the WIP branch!\nSeems like you are using a version that isn't even released yet. Be careful and give us your feedback ;)"
		info["published_at"] = "????T"
		info["author"] = { 'login': "???" }
		state_label.text = "Where are we Doc?"
		update_name_label.remove_theme_color_override("font_color")
		install_button.disabled = true

	elif result == UpdateManager.UpdateCheckResult.UPDATE_AVAILABLE:
		state_label.text = "Update Available!"
		update_name_label.add_theme_color_override("font_color", EditorThemeUtils.color_warning)
		install_button.disabled = false
	else:
		state_label.text = "You are up to date:"
		update_name_label.add_theme_color_override("font_color", EditorThemeUtils.color_success)
		install_button.disabled = true

	update_name_label.text = info.name
	content.text = info.body
	short_info_label.text = "Published on " + info.published_at.substr(0, info.published_at.find(
			'T'
		)) + " by " + info \
			.author \
			.login
	if info.has("html_url"):
		read_full_link.uri = info.html_url
		read_full_link.show()
	else:
		read_full_link.hide()
	if info.has('reactions'):
		reactions_container.show()
		var reactions := {
			"laugh": "😂",
			"hooray": "🎉",
			"confused": "😕",
			"heart": "❤️",
			"rocket": "🚀",
			"eyes": "👀",
		}
		for i: String in reactions:
			reactions_container.get_node(i.capitalize()).visible = info.reactions[i] > 0
			reactions_container.get_node(i.capitalize()).text = (
				reactions[i] + " " + str(int(info.reactions[i]))
				if info.reactions[i] > 0
				else reactions[i]
			)
		if info.reactions['+1'] + info.reactions['-1'] > 0:
			reactions_container.get_node("Likes").visible = true
			reactions_container.get_node("Likes").text = "👍 " + str(
				int(info.reactions['+1'] + info.reactions['-1'])
			)
		else:
			reactions_container.get_node("Likes").visible = false
	else:
		reactions_container.hide()


func set_download_result(result: UpdateManager.DownloadResult) -> void:
	loading_container.hide()
	match result:
		UpdateManager.DownloadResult.SUCCESS:
			info_label.text = "Installed successfully. Restart needed!"
			info_label.modulate = EditorThemeUtils.color_success
			restart_button.show()
			restart_button.grab_focus()
		UpdateManager.DownloadResult.FAILURE:
			info_label.text = "Download failed."
			info_label.modulate = EditorThemeUtils.color_error


func _on_install_pressed() -> void:
	install_requested.emit()

	var is_above_4_7 := Compat.is_engine_version_equal_or_newer(4, 7)
	var prop := "offset_transform_rotation" if is_above_4_7 else "rotation"
	info_label.text = "Downloading. This can take a moment."
	loading_container.show()
	loading_icon \
			.create_tween() \
			.set_loops() \
			.tween_property(loading_icon, prop, 2 * PI, 1) \
			.from(0)


func _on_refresh_pressed() -> void:
	refresh_requested.emit()


func _on_restart_pressed() -> void:
	EditorInterface.restart_editor(true)
