# SPDX-FileCopyrightText: 2020-present, Emilio Coppola <https://github.com/dialogic-godot/dialogic>
# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Node

## Checks GitHub releases for newer versions of the plugin and installs them.
## Purely reactive: never does anything until asked. The UI that drives it
## lives in registry_editor.gd / update_install_window.gd.

signal update_check_completed(result: UpdateCheckResult)
signal download_completed(result: DownloadResult)

enum UpdateCheckResult {
	UPDATE_AVAILABLE,
	UP_TO_DATE,
	NO_ACCESS,
}
enum DownloadResult {
	SUCCESS,
	FAILURE,
}
enum ReleaseState {
	ALPHA,
	BETA,
	STABLE,
}

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const YardLogger := Namespace.YardLogger

const REMOTE_RELEASES_URL := "https://api.github.com/repos/elliotfontaine/yard-godot/releases"
const TEMP_FILE_NAME := "user://yard_update.zip"

# The very first HTTPRequest fired right as the editor boots can fail (DNS/TLS not warmed up yet)
# even with a working connection. This avoids reporting a false NO_ACCESS.
const MAX_UPDATE_CHECK_ATTEMPTS := 3
const RETRY_DELAY_SECONDS := 1.0

var update_info: Dictionary
var current_info: Dictionary

var _update_check_attempts_left := 0

@onready var _update_check_request: HTTPRequest = $UpdateCheckRequest
@onready var _download_request: HTTPRequest = $DownloadRequest


func get_current_version() -> String:
	var plugin_cfg := ConfigFile.new()
	plugin_cfg.load(Namespace.PluginCFG)
	return plugin_cfg.get_value("plugin", "version", "unknown version")


func request_update_check() -> void:
	_update_check_attempts_left = MAX_UPDATE_CHECK_ATTEMPTS
	_start_update_check_request()


func _start_update_check_request() -> void:
	if _update_check_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_update_check_attempts_left -= 1
		_update_check_request.request(REMOTE_RELEASES_URL)


func _retry_update_check_or_give_up() -> bool:
	if _update_check_attempts_left <= 0:
		return false
	await get_tree().create_timer(RETRY_DELAY_SECONDS).timeout
	_start_update_check_request()
	return true


func request_update_download() -> void:
	# Safeguard the actual repo from accidentally updating itself
	if DirAccess.dir_exists_absolute("res://test/project/"):
		YardLogger.warn(
			"Looks like you are working on the addon itself. You can't update it from within itself."
		)
		download_completed.emit(DownloadResult.FAILURE)
		return

	_download_request.request(update_info.zipball_url)


func get_release_tag_info(release_tag: String) -> Dictionary:
	release_tag = release_tag.strip_edges().trim_prefix('v')
	release_tag = release_tag.substr(0, release_tag.find('('))
	release_tag = release_tag.to_lower()

	var regex := RegEx.create_from_string(
		r"^(?<major>\d+)\.(?<minor>\d+)(-(?<state>alpha|beta)-(?<stateversion>\d+))?(\.(?<patch>\d+))?"
	)

	var result: RegExMatch = regex.search(release_tag)
	if !result:
		return { }

	var info: Dictionary = { 'tag': release_tag }
	info['major'] = int(result.get_string('major'))
	info['minor'] = int(result.get_string('minor'))
	info['patch'] = int(result.get_string('patch'))

	match result.get_string('state'):
		'alpha':
			info['state'] = ReleaseState.ALPHA
		'beta':
			info['state'] = ReleaseState.BETA
		_:
			info['state'] = ReleaseState.STABLE

	info['state_version'] = int(result.get_string('stateversion'))

	return info


## Returns true if `release` is strictly newer than `current_release_info`.
## As a side effect, caches the exact match for `current_release_info` in
## `current_info` so the "you are up to date" popup can show its changelog.
func compare_versions(release: Dictionary, current_release_info: Dictionary) -> bool:
	var checked_release_info := get_release_tag_info(release.tag_name)
	if checked_release_info.is_empty():
		return false

	if checked_release_info.major != current_release_info.major:
		return checked_release_info.major > current_release_info.major

	if checked_release_info.minor != current_release_info.minor:
		return checked_release_info.minor > current_release_info.minor

	if checked_release_info.state != current_release_info.state:
		return checked_release_info.state > current_release_info.state

	if checked_release_info.state == ReleaseState.STABLE:
		if checked_release_info.patch != current_release_info.patch:
			return checked_release_info.patch > current_release_info.patch
		current_info = release
		return false

	if checked_release_info.state_version != current_release_info.state_version:
		return checked_release_info.state_version > current_release_info.state_version

	current_info = release
	return false


func _on_update_check_request_completed(
	result: int,
	_response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		if await _retry_update_check_or_give_up():
			return
		update_check_completed.emit(UpdateCheckResult.NO_ACCESS)
		return

	# Work out the next version from the releases information on GitHub
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(response) != TYPE_ARRAY:
		if await _retry_update_check_or_give_up():
			return
		update_check_completed.emit(UpdateCheckResult.NO_ACCESS)
		return

	var current_release_info := get_release_tag_info(get_current_version())

	# GitHub releases are in order of creation, not order of version
	var versions: Array = (response as Array).filter(compare_versions.bind(current_release_info))
	if versions.size() > 0:
		update_info = versions[0]
		update_check_completed.emit(UpdateCheckResult.UPDATE_AVAILABLE)
	else:
		update_info = current_info
		update_check_completed.emit(UpdateCheckResult.UP_TO_DATE)


func _on_download_request_completed(
	result: int,
	_response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		download_completed.emit(DownloadResult.FAILURE)
		return

	# Save the downloaded zip
	var zip_file := FileAccess.open(TEMP_FILE_NAME, FileAccess.WRITE)
	zip_file.store_buffer(body)
	zip_file.close()

	OS.move_to_trash(ProjectSettings.globalize_path("res://addons/yard"))

	var zip_reader := ZIPReader.new()
	zip_reader.open(TEMP_FILE_NAME)
	var files: PackedStringArray = zip_reader.get_files()

	var base_path: String = files[0].path_join('addons/')
	for path in files:
		if not "yard/" in path:
			continue

		var new_file_path: String = path.replace(base_path, "")
		if path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute("res://addons/".path_join(new_file_path))
		else:
			var file := FileAccess.open("res://addons/".path_join(new_file_path), FileAccess.WRITE)
			file.store_buffer(zip_reader.read_file(path))

	zip_reader.close()
	DirAccess.remove_absolute(TEMP_FILE_NAME)

	download_completed.emit(DownloadResult.SUCCESS)
