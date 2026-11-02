# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite
## Directory scans: RegistryIO.sync_from_scan_directories() and the rulesets that drive it.

const Fixtures := preload("res://test/fixtures/fixtures.gd")
const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO

var _registry: Registry


func before_test() -> void:
	_registry = Fixtures.new_registry(
		create_temp_dir("registry_io_scan").path_join("registry.tres")
	)


func after_test() -> void:
	clean_temp_dir()


## Applies [param settings], syncs the registry and returns its string IDs.
func _sync(settings: RegistryIO.RegistrySettings) -> Array[StringName]:
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(OK)
	RegistryIO.sync_from_scan_directories(_registry)
	return _registry.get_all_string_ids()


func test_sync_adds_every_resource_of_the_directory() -> void:
	assert_array(_sync(Fixtures.scan_settings(Fixtures.ITEMS_DIR))).contains_exactly_in_any_order(
		[&"potion", &"elixir", &"draft_potion", &"sword", &"trinket", &"gradient"],
	)


func test_sync_recursive_scan_includes_subdirectories() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR)
	settings.default_scan_ruleset.recursive_scan = true
	assert_array(_sync(settings)).contains([&"shield", &"potion"])
	assert_int(_registry.size()).is_equal(7)


func test_sync_with_named_class_restriction_includes_subclasses() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestItem"])
	assert_array(_sync(settings)).contains_exactly_in_any_order(
		[&"potion", &"elixir", &"draft_potion", &"sword"],
	)


func test_sync_with_subclass_restriction() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	settings.default_scan_ruleset.recursive_scan = true
	assert_array(_sync(settings)).contains_exactly_in_any_order([&"sword", &"shield"])


func test_sync_with_quoted_script_restriction() -> void:
	var quoted_trinket_script := StringName("\"%s\"" % Fixtures.TRINKET_SCRIPT_PATH)
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [quoted_trinket_script])
	assert_array(_sync(settings)).is_equal([&"trinket"])


func test_sync_with_native_class_restriction() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"Gradient"])
	assert_array(_sync(settings)).is_equal([&"gradient"])


func test_sync_with_exclude_regex() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestItem"])
	settings.default_scan_ruleset.scan_regex_exclude = "^draft_"
	assert_array(_sync(settings)).contains_exactly_in_any_order([&"potion", &"elixir", &"sword"])


func test_sync_with_include_regex() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR)
	settings.default_scan_ruleset.scan_regex_include = "potion"
	assert_array(_sync(settings)).contains_exactly_in_any_order([&"potion", &"draft_potion"])


func test_include_regex_matches_paths_relative_to_the_scan_directory() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR)
	settings.default_scan_ruleset.recursive_scan = true
	settings.default_scan_ruleset.scan_regex_include = "^nested/"
	assert_array(_sync(settings)).is_equal([&"shield"])


func test_exclude_regex_skips_whole_subdirectories() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	settings.default_scan_ruleset.recursive_scan = true
	settings.default_scan_ruleset.scan_regex_exclude = "^nested"
	assert_array(_sync(settings)).is_equal([&"sword"])


func test_sync_with_allowed_file_extensions() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	settings.default_scan_ruleset.allowed_file_extensions = ["tres"]
	assert_array(_sync(settings)).is_equal([&"sword"])
	settings.default_scan_ruleset.allowed_file_extensions = ["png", "jpg"]
	assert_array(_sync(settings)).is_empty()


@warning_ignore("unused_parameter")
func test_allowed_file_extensions_match_whole_extensions(
	do_skip := true,
	skip_reason := "Known bug: the extension filter uses ends_with(), so 'res' also matches .tres",
) -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	settings.default_scan_ruleset.allowed_file_extensions = ["res"]
	assert_array(_sync(settings)).is_empty()


func test_sync_with_additional_ruleset() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	var gradient_ruleset := RegistryIO.RegistryScanRuleset.new()
	gradient_ruleset.class_restrictions = [&"Gradient"]
	gradient_ruleset.override_properties = [&"class_restrictions"]
	settings.additional_scan_rulesets = [gradient_ruleset]
	assert_array(_sync(settings)).contains_exactly_in_any_order([&"sword", &"gradient"])


func test_sync_keeps_existing_entries_as_they_are() -> void:
	RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "healing")
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestItem"])
	assert_array(_sync(settings)).contains_exactly_in_any_order(
		[&"healing", &"elixir", &"draft_potion", &"sword"],
	)


func test_sync_removes_unmatched_entries() -> void:
	RegistryIO.add_entry(_registry, Fixtures.SHIELD_UID)
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	assert_array(_sync(settings)).is_equal([&"sword"])


func test_sync_keeps_unmatched_entries_when_asked_to() -> void:
	RegistryIO.add_entry(_registry, Fixtures.SHIELD_UID)
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"])
	settings.remove_unmatched = false
	assert_array(_sync(settings)).is_equal([&"shield", &"sword"])


# Issue #95: registries from YARD 1.1.0 store no class restriction when there is none. Every scan
# used to find no resource and remove all their entries.
func test_sync_keeps_the_entries_of_a_v1_registry_without_class_restriction() -> void:
	RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "healing")
	_registry._version = 0
	_registry._scan_directory = Fixtures.ITEMS_DIR
	RegistryIO.sync_from_scan_directories(_registry)
	assert_array(_registry.get_all_string_ids()).contains_exactly_in_any_order(
		[&"healing", &"elixir", &"draft_potion", &"sword", &"trinket", &"gradient"],
	)


func test_sync_without_scan_directory_does_nothing() -> void:
	RegistryIO.add_entry(_registry, Fixtures.SHIELD_UID)
	assert_array(_sync(RegistryIO.RegistrySettings.new())).is_equal([&"shield"])


func test_sync_saves_the_registry() -> void:
	_sync(Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestWeapon"]))
	var saved: Registry = ResourceLoader.load(
		_registry.resource_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	)
	assert_bool(saved.has(&"sword")).is_true()


func test_dir_has_matching_resource() -> void:
	var ruleset := RegistryIO.RegistryScanRuleset.new()
	ruleset.class_restrictions = [&"YardTestWeapon"]
	var nested_dir := Fixtures.NESTED_ITEMS_DIR
	assert_bool(RegistryIO.dir_has_matching_resource(nested_dir, ruleset, nested_dir)).is_true()

	ruleset.class_restrictions = [&"Texture2D"]
	assert_bool(
		RegistryIO.dir_has_matching_resource(Fixtures.ITEMS_DIR, ruleset, Fixtures.ITEMS_DIR),
	).is_false()


func test_dir_has_matching_resource_in_subdirectories() -> void:
	var ruleset := RegistryIO.RegistryScanRuleset.new()
	ruleset.class_restrictions = [&"YardTestWeapon"]
	ruleset.scan_regex_exclude = "^sword"
	assert_bool(
		RegistryIO.dir_has_matching_resource(Fixtures.ITEMS_DIR, ruleset, Fixtures.ITEMS_DIR),
	).is_false()
	ruleset.recursive_scan = true
	assert_bool(
		RegistryIO.dir_has_matching_resource(Fixtures.ITEMS_DIR, ruleset, Fixtures.ITEMS_DIR),
	).is_true()
