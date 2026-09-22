# SPDX-FileCopyrightText: 2020-present, Emilio Coppola <https://github.com/dialogic-godot/dialogic>
# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Control

signal install_requested
signal refresh_requested
signal close_requested

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const EditorThemeUtils := Namespace.EditorThemeUtils
const UpdateManager := Namespace.UpdateManager

var current_info := { }


func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == self:
		return

	theme = EditorThemeUtils.editor_theme
	%Install.icon = EditorThemeUtils.editor_theme.get_icon(&"AssetStore", &"EditorIcons")
	%LoadingIcon.texture = EditorThemeUtils.editor_theme.get_icon(&"KeyTrackScale", &"EditorIcons")
	%InstallWarning.modulate = EditorThemeUtils.color_warning
	%CloseButton.icon = EditorThemeUtils.editor_theme.get_icon(&"Close", &"EditorIcons")


func load_info(info: Dictionary, result: UpdateManager.UpdateCheckResult) -> void:
	current_info = info
	if result == UpdateManager.UpdateCheckResult.NO_ACCESS:
		%State.text = "No Information Available"
		%UpdateName.text = "Unable to access versions."
		%UpdateName.add_theme_color_override("font_color", EditorThemeUtils.color_message)
		%Content.text = "You are probably not connected to the internet. Fair enough."
		%ShortInfo.text = "Huh, what happened here?"
		%ReadFull.hide()
		%Install.disabled = true
		return

	# If we are up to date (or beyond):
	if info.is_empty():
		info['name'] = "You are in the future, Marty!"
		info["body"] = "# 😎 You are using the WIP branch!\nSeems like you are using a version that isn't even released yet. Be careful and give us your feedback ;)"
		info["published_at"] = "????T"
		info["author"] = { 'login': "???" }
		%State.text = "Where are we Doc?"
		%UpdateName.add_theme_color_override("font_color", EditorThemeUtils.color_message)
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
	%Content.text = markdown_to_bbcode(info.body).get_slice("\n[font_size", 0).strip_edges()
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


func markdown_to_bbcode(text: String) -> String:
	var font_sizes := { 1: 20, 2: 16, 3: 16, 4: 14, 5: 14 }
	var title_regex := RegEx.create_from_string('(^|\n)((?<level>#+)(?<title>.*))\\n')
	var res := title_regex.search(text)
	while res:
		text = text.replace(
			res.get_string(2),
			'[font_size=' + str(font_sizes[len(res.get_string('level'))])
			+ ']' + res.get_string('title').strip_edges() + '[/font_size]',
		)
		res = title_regex.search(text)

	var link_regex := RegEx.create_from_string('(?<!\\!)\\[(?<text>[^\\]]*)]\\((?<link>[^)]*)\\)')
	res = link_regex.search(text)
	while res:
		text = text.replace(
			res.get_string(),
			'[url=' + res.get_string('link') + ']' + res.get_string('text').strip_edges() + '[/url]',
		)
		res = link_regex.search(text)

	var image_regex := RegEx.create_from_string('\\!\\[(?<text>[^\\]]*)]\\((?<link>[^)]*)\\)\n*')
	res = image_regex.search(text)
	while res:
		text = text.replace(
			res.get_string(),
			'[url=' + res.get_string('link') + ']' + res.get_string('text').strip_edges() + '[/url]',
		)
		res = image_regex.search(text)

	var italics_regex := RegEx.create_from_string('\\*(?<text>[^\\*\\n]*)\\*')
	res = italics_regex.search(text)
	while res:
		text = text.replace(res.get_string(), '[i]' + res.get_string('text').strip_edges() + '[/i]')
		res = italics_regex.search(text)

	var bullets_regex := RegEx.create_from_string('(?<=\\n)(\\*|-)(?<text>[^\\*\\n]*)\\n')
	res = bullets_regex.search(text)
	while res:
		text = text.replace(
			res.get_string(),
			'[ul]' + res.get_string('text').strip_edges() + '[/ul]\n',
		)
		res = bullets_regex.search(text)

	var small_code_regex := RegEx.create_from_string('(?<!`)`(?<text>[^`]+)`')
	res = small_code_regex.search(text)
	while res:
		text = text.replace(
			res.get_string(),
			'[code][color='
			+ EditorThemeUtils.editor_theme.get_color("accent_color", "Editor").to_html()
			+ ']' + res.get_string('text').strip_edges() + '[/color][/code]',
		)
		res = small_code_regex.search(text)

	var big_code_regex := RegEx.create_from_string('(?<!`)```(?<text>[^`]+)```')
	res = big_code_regex.search(text)
	while res:
		text = text.replace(
			res.get_string(),
			'[code][bgcolor='
			+ EditorThemeUtils
			.editor_theme
			.get_color("box_selection_fill_color", "Editor")
			.to_html()
			+ ']' + res.get_string('text').strip_edges() + '[/bgcolor][/code]',
		)
		res = big_code_regex.search(text)

	return text


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


func _on_content_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


func _on_install_mouse_entered() -> void:
	if not %Install.disabled:
		%InstallWarning.show()


func _on_install_mouse_exited() -> void:
	%InstallWarning.hide()


func _on_restart_pressed() -> void:
	EditorInterface.restart_editor(true)


func _on_close_button_pressed() -> void:
	close_requested.emit()
