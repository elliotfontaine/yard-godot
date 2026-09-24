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

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const YardLogger := Namespace.YardLogger
const YardSettings := Namespace.YardSettings

const REMOTE_RELEASES_URL := "https://api.github.com/repos/elliotfontaine/yard-godot/releases"
const TEMP_FILE_NAME := "user://yard_update.zip"

# The very first HTTPRequest fired right as the editor boots can fail (DNS/TLS not warmed up yet)
# even with a working connection. This avoids reporting a false NO_ACCESS.
const MAX_UPDATE_CHECK_ATTEMPTS := 3
const RETRY_DELAY_SECONDS := 1.0

var update_info: Dictionary

var _update_check_attempts_left := 0

@onready var _update_check_request: HTTPRequest = $UpdateCheckRequest
@onready var _download_request: HTTPRequest = $DownloadRequest
@onready var _retry_timer: Timer = $RetryTimer


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


func _handle_update_check_failure() -> void:
	if _update_check_attempts_left > 0:
		_retry_timer.start(RETRY_DELAY_SECONDS)
	else:
		update_check_completed.emit(UpdateCheckResult.NO_ACCESS)


func _on_retry_timer_timeout() -> void:
	_start_update_check_request()


func request_update_download() -> void:
	# Safeguard the actual repo from accidentally updating itself
	if DirAccess.dir_exists_absolute("res://test/project/"):
		YardLogger.warn(
			"Looks like you are working on the addon itself. You can't update it from within itself."
		)
		call_deferred(&"emit_signal", &"download_completed", DownloadResult.FAILURE)
		return

	_download_request.request(update_info.zipball_url)


## Parses a SemVer 2.0.0 tag (an optional leading "v"/"V" is stripped first,
## since that's how git tags for this repo are named, e.g. "v1.2.0-beta.1").
## Returns {} if the tag isn't valid SemVer. See https://semver.org/
func parse_semver(tag: String) -> Dictionary:
	tag = tag.strip_edges().trim_prefix('v').trim_prefix('V')

	var regex := RegEx.create_from_string(
		r"^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+(?<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
	)

	var result: RegExMatch = regex.search(tag)
	if not result:
		return { }

	var prerelease_str := result.get_string('prerelease')

	return {
		'tag': tag,
		'major': int(result.get_string('major')),
		'minor': int(result.get_string('minor')),
		'patch': int(result.get_string('patch')),
		# Empty array means "no pre-release identifiers", i.e. a final release.
		# Build metadata (the "+..." suffix) is parsed but never used below:
		# SemVer explicitly excludes it from precedence comparisons.
		'prerelease': prerelease_str.split('.') if prerelease_str else PackedStringArray(),
	}


## Returns true if `a` has strictly higher SemVer 2.0.0 precedence than `b`.
## See https://semver.org/#spec-item-11
func is_version_newer(a: Dictionary, b: Dictionary) -> bool:
	if a.major != b.major:
		return a.major > b.major
	if a.minor != b.minor:
		return a.minor > b.minor
	if a.patch != b.patch:
		return a.patch > b.patch

	var a_prerelease: Array = a.prerelease
	var b_prerelease: Array = b.prerelease

	# A version without a pre-release has higher precedence than one with,
	# for an otherwise identical major.minor.patch (covers the "both empty",
	# i.e. equal, case too since size() > size() is then false).
	if a_prerelease.is_empty() or b_prerelease.is_empty():
		return b_prerelease.size() > a_prerelease.size()

	for i in range(min(a_prerelease.size(), b_prerelease.size())):
		var cmp := _compare_prerelease_identifiers(a_prerelease[i], b_prerelease[i])
		if cmp != 0:
			return cmp > 0

	# All shared identifiers are equal: the longer set has higher precedence.
	return a_prerelease.size() > b_prerelease.size()


## Compares two dot-separated pre-release identifiers per SemVer rule 11:
## numeric identifiers compare numerically, alphanumeric identifiers compare
## lexically (ASCII order), and numeric identifiers always have lower
## precedence than alphanumeric ones. Returns -1, 0 or 1.
func _compare_prerelease_identifiers(a: String, b: String) -> int:
	var a_is_numeric := a.is_valid_int()
	var b_is_numeric := b.is_valid_int()

	if a_is_numeric and b_is_numeric:
		var a_num := a.to_int()
		var b_num := b.to_int()
		if a_num == b_num:
			return 0
		return -1 if a_num < b_num else 1

	if a_is_numeric != b_is_numeric:
		return -1 if a_is_numeric else 1 # numeric identifiers sort lower

	if a == b:
		return 0
	return -1 if a < b else 1


## True if `release` should be excluded from the update suggestions shown to
## users on the stable channel. Combines two independent signals so a
## maintainer mistake in either one alone still gets caught: the SemVer tag
## itself (e.g. "-beta.1") and GitHub's own "This is a pre-release" checkbox.
func _is_prerelease(release: Dictionary, release_info: Dictionary) -> bool:
	return not release_info.prerelease.is_empty() or bool(release.get('prerelease', false))


## Finds the fetched release whose tag has the exact same SemVer precedence
## as `target`, or an empty dict if none matches (e.g. a local/unreleased
## build that isn't exactly any published tag).
func _find_matching_release(releases: Array, target: Dictionary) -> Dictionary:
	for release: Dictionary in releases:
		var release_info := parse_semver(release.tag_name)
		if release_info.is_empty():
			continue
		if not is_version_newer(release_info, target) and not is_version_newer(target, release_info):
			return release
	return { }


func _on_update_check_request_completed(
	result: int,
	_response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_update_check_failure()
		return

	# Work out the next version from the releases information on GitHub
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(response) != TYPE_ARRAY:
		_handle_update_check_failure()
		return

	var releases: Array = response
	var current_release_info := parse_semver(get_current_version())
	var allow_prereleases: bool = (
		ProjectSettings.get_setting(YardSettings.UPDATE_CHANNEL, "Stable") != "Stable"
	)

	# GitHub releases are in order of creation, not order of version
	var newer_releases := releases.filter(
		func(release: Dictionary) -> bool:
			var release_info := parse_semver(release.tag_name)
			return (
				not release_info.is_empty()
				and (allow_prereleases or not _is_prerelease(release, release_info))
				and is_version_newer(release_info, current_release_info)
			),
	)
	if newer_releases.size() > 0:
		update_info = newer_releases[0]
		update_check_completed.emit(UpdateCheckResult.UPDATE_AVAILABLE)
	else:
		update_info = _find_matching_release(releases, current_release_info)
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
