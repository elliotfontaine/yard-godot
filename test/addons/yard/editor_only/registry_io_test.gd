# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite
## Registry mutations, settings, property index and validation helpers.
## Directory scans are covered in registry_io_scan_test.gd.

const Fixtures := preload("res://test/fixtures/fixtures.gd")
const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO

# create_registry_file() only accepts paths under res://.
const CREATED_REGISTRY_PATH := "res://test/fixtures/registries/created_by_test.tres"

var _registry: Registry


func before_test() -> void:
	_registry = Fixtures.new_registry(create_temp_dir("registry_io").path_join("registry.tres"))


func after_test() -> void:
	clean_temp_dir()
	if FileAccess.file_exists(CREATED_REGISTRY_PATH):
		DirAccess.remove_absolute(CREATED_REGISTRY_PATH)


func _add_entries(uids: Array[StringName]) -> void:
	for uid: StringName in uids:
		assert_int(RegistryIO.add_entry(_registry, uid)).is_equal(OK)


func _restrict_to(class_restrictions: Array[StringName]) -> void:
	var settings := RegistryIO.get_registry_settings(_registry)
	settings.default_scan_ruleset.class_restrictions = class_restrictions
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(OK)


func _index(indexed_props: String) -> void:
	var settings := RegistryIO.get_registry_settings(_registry)
	settings.indexed_props = indexed_props
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(OK)
	assert_int(RegistryIO.rebuild_property_index(_registry)).is_equal(OK)


func _matches(uid: StringName, class_restrictions: Array[StringName]) -> bool:
	return RegistryIO.does_resource_match_class_restrictions(load(uid), class_restrictions)


#region Entries

func test_add_entry_uses_the_file_name_as_string_id() -> void:
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID)).is_equal(OK)
	assert_str(_registry.get_string_id(Fixtures.POTION_UID)).is_equal("potion")


func test_add_entry_with_a_custom_string_id() -> void:
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "  healing  ")).is_equal(OK)
	assert_str(_registry.get_uid(&"healing")).is_equal(Fixtures.POTION_UID)


func test_add_entry_makes_string_ids_unique() -> void:
	RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "item")
	RegistryIO.add_entry(_registry, Fixtures.ELIXIR_UID, "item")
	RegistryIO.add_entry(_registry, Fixtures.SWORD_UID, "item_2")
	assert_array(_registry.get_all_string_ids()).is_equal([&"item", &"item_2", &"item_3"])


func test_add_entry_rejects_invalid_input() -> void:
	assert_int(RegistryIO.add_entry(_registry, &"uid://yardtestnone")).is_equal(
		ERR_CANT_ACQUIRE_RESOURCE,
	)
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "a,b")).is_equal(
		ERR_INVALID_PARAMETER,
	)
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "uid://potion")).is_equal(
		ERR_INVALID_PARAMETER,
	)
	assert_bool(_registry.is_empty()).is_true()


func test_add_entry_rejects_a_uid_already_in_the_registry() -> void:
	_add_entries([Fixtures.POTION_UID])
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID, "other")).is_equal(
		ERR_ALREADY_EXISTS,
	)
	assert_int(_registry.size()).is_equal(1)


func test_add_entry_enforces_class_restrictions() -> void:
	_restrict_to([&"YardTestWeapon"])
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID)).is_equal(
		ERR_DATABASE_CANT_WRITE,
	)
	assert_int(RegistryIO.add_entry(_registry, Fixtures.SWORD_UID)).is_equal(OK)


@warning_ignore("unused_parameter")
func test_add_entry_to_a_v1_registry_without_class_restriction(
	do_skip := true,
	skip_reason := "Known bug: V1 settings turn an empty _class_restriction into [&\"\"]",
) -> void:
	_registry._version = 1
	assert_int(RegistryIO.add_entry(_registry, Fixtures.POTION_UID)).is_equal(OK)


func test_add_entry_saves_the_registry() -> void:
	_add_entries([Fixtures.POTION_UID])
	var saved: Registry = ResourceLoader.load(
		_registry.resource_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	)
	assert_bool(saved.has(&"potion")).is_true()


func test_erase_entry_by_string_id_or_uid() -> void:
	_add_entries([Fixtures.POTION_UID, Fixtures.SWORD_UID])
	assert_int(RegistryIO.erase_entry(_registry, &"potion")).is_equal(OK)
	assert_int(RegistryIO.erase_entry(_registry, Fixtures.SWORD_UID)).is_equal(OK)
	assert_bool(_registry.is_empty()).is_true()
	assert_int(RegistryIO.erase_entry(_registry, &"potion")).is_equal(ERR_INVALID_PARAMETER)


func test_rename_entry() -> void:
	_add_entries([Fixtures.POTION_UID])
	assert_int(RegistryIO.rename_entry(_registry, &"potion", &" healing ")).is_equal(OK)
	assert_bool(_registry.has_string_id(&"potion")).is_false()
	assert_str(_registry.get_string_id(Fixtures.POTION_UID)).is_equal("healing")


func test_rename_entry_to_a_taken_string_id_makes_it_unique() -> void:
	_add_entries([Fixtures.POTION_UID, Fixtures.SWORD_UID])
	assert_int(RegistryIO.rename_entry(_registry, &"sword", &"potion")).is_equal(OK)
	assert_str(_registry.get_string_id(Fixtures.SWORD_UID)).is_equal("potion_2")


func test_rename_entry_rejects_commas() -> void:
	_add_entries([Fixtures.POTION_UID])
	assert_int(RegistryIO.rename_entry(_registry, &"potion", &"a,b")).is_equal(
		ERR_INVALID_PARAMETER,
	)
	assert_bool(_registry.has_string_id(&"potion")).is_true()


func test_change_entry_uid_keeps_the_string_id() -> void:
	_add_entries([Fixtures.POTION_UID])
	assert_int(RegistryIO.change_entry_uid(_registry, &"potion", Fixtures.ELIXIR_UID)).is_equal(OK)
	assert_str(_registry.get_uid(&"potion")).is_equal(Fixtures.ELIXIR_UID)
	assert_bool(_registry.has_uid(Fixtures.POTION_UID)).is_false()


func test_change_entry_uid_rejects_a_uid_already_in_the_registry() -> void:
	_add_entries([Fixtures.POTION_UID, Fixtures.ELIXIR_UID])
	assert_int(RegistryIO.change_entry_uid(_registry, &"potion", Fixtures.ELIXIR_UID)).is_equal(
		ERR_INVALID_PARAMETER,
	)
	assert_str(_registry.get_uid(&"potion")).is_equal(Fixtures.POTION_UID)


func test_change_entry_uid_enforces_class_restrictions() -> void:
	_restrict_to([&"YardTestItem"])
	_add_entries([Fixtures.POTION_UID])
	assert_int(RegistryIO.change_entry_uid(_registry, &"potion", Fixtures.GRADIENT_UID)).is_equal(
		ERR_INVALID_PARAMETER,
	)
	assert_str(_registry.get_uid(&"potion")).is_equal(Fixtures.POTION_UID)

#endregion


#region Settings

func test_new_registry_settings() -> void:
	var settings := RegistryIO.get_registry_settings(_registry)
	assert_int(settings.version).is_equal(Registry._REGISTRY_FORMAT_VERSION)
	assert_bool(settings.auto_rescan).is_true()
	assert_bool(settings.remove_unmatched).is_true()
	assert_bool(settings.has_any_class_restriction()).is_false()
	assert_bool(settings.has_any_scan_directory()).is_false()


func test_registry_settings_round_trip() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestItem"])
	settings.indexed_props = "price, kind"
	settings.auto_rescan = false
	settings.remove_unmatched = false
	settings.default_scan_ruleset.recursive_scan = true
	settings.default_scan_ruleset.scan_regex_exclude = "^draft_"
	var nested_ruleset := RegistryIO.RegistryScanRuleset.new()
	nested_ruleset.scan_directories = [Fixtures.NESTED_ITEMS_DIR]
	nested_ruleset.override_properties = [&"scan_directories"]
	settings.additional_scan_rulesets = [nested_ruleset]
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(OK)

	var saved: Registry = ResourceLoader.load(
		_registry.resource_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	)
	var read := RegistryIO.get_registry_settings(saved)
	assert_array(saved.get_indexed_properties()).contains_exactly_in_any_order([&"price", &"kind"])
	assert_bool(read.auto_rescan).is_false()
	assert_bool(read.remove_unmatched).is_false()
	assert_bool(read.default_scan_ruleset.matches_other_ruleset(settings.default_scan_ruleset)).is_true()
	assert_int(read.additional_scan_rulesets.size()).is_equal(1)
	assert_array(read.additional_scan_rulesets[0].override_properties).is_equal(
		[&"scan_directories"]
	)
	assert_array(read.get_all_scan_directories()).is_equal(
		[Fixtures.ITEMS_DIR, Fixtures.NESTED_ITEMS_DIR],
	)


func test_additional_ruleset_inherits_non_overridden_properties() -> void:
	var settings := Fixtures.scan_settings(Fixtures.ITEMS_DIR, [&"YardTestItem"])
	settings.default_scan_ruleset.recursive_scan = true
	var gradient_ruleset := RegistryIO.RegistryScanRuleset.new()
	gradient_ruleset.class_restrictions = [&"Gradient"]
	gradient_ruleset.override_properties = [&"class_restrictions"]
	settings.additional_scan_rulesets = [gradient_ruleset]

	var compiled := settings.get_compiled_rulesets()[1]
	assert_array(compiled.class_restrictions).is_equal([&"Gradient"])
	assert_array(compiled.scan_directories).is_equal([Fixtures.ITEMS_DIR])
	assert_bool(compiled.recursive_scan).is_true()
	assert_array(settings.get_all_class_restrictions()).is_equal([&"YardTestItem", &"Gradient"])


func test_set_registry_settings_rejects_invalid_values() -> void:
	var settings := RegistryIO.RegistrySettings.new()
	settings.default_scan_ruleset.class_restrictions = [&"NotAClass"]
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(ERR_DOES_NOT_EXIST)
	settings.default_scan_ruleset.class_restrictions = [&"Node"]
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(ERR_DOES_NOT_EXIST)

	settings = Fixtures.scan_settings("res://test/fixtures/missing")
	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(ERR_DOES_NOT_EXIST)
	assert_bool(RegistryIO.get_registry_settings(_registry).has_any_scan_directory()).is_false()


func test_set_registry_settings_erases_entries_that_no_longer_match() -> void:
	_add_entries([Fixtures.POTION_UID, Fixtures.SWORD_UID])
	var settings := RegistryIO.get_registry_settings(_registry)
	settings.default_scan_ruleset.class_restrictions = [&"YardTestWeapon"]
	assert_bool(RegistryIO.would_erase_entries(_registry, settings)).is_true()

	assert_int(RegistryIO.set_registry_settings(_registry, settings)).is_equal(OK)
	assert_array(_registry.get_all_string_ids()).is_equal([&"sword"])
	assert_bool(RegistryIO.would_erase_entries(_registry, settings)).is_false()

#endregion


#region Property index

func test_rebuild_property_index() -> void:
	_add_entries([Fixtures.POTION_UID, Fixtures.SWORD_UID, Fixtures.ELIXIR_UID])
	_index("kind,price,stats.power")
	assert_array(_registry.filter(&"kind", &"consumable")).contains_exactly_in_any_order(
		[&"potion", &"elixir"],
	)
	assert_array(_registry.filter(&"price", 30)).is_equal([&"sword"])
	assert_array(_registry.filter(&"stats.power", 8)).contains_exactly_in_any_order(
		[&"sword", &"elixir"],
	)


func test_rebuild_property_index_skips_missing_values() -> void:
	_add_entries([Fixtures.POTION_UID, Fixtures.DRAFT_POTION_UID])
	_index("stats.power")
	var all_powers := _registry.filter(
		&"stats.power",
		func(_power: int) -> bool:
			return true,
	)
	assert_array(all_powers).is_equal([&"potion"])


func test_rebuild_property_index_drops_stale_values() -> void:
	_add_entries([Fixtures.POTION_UID])
	_index("price")
	RegistryIO.erase_entry(_registry, &"potion")
	assert_int(RegistryIO.rebuild_property_index(_registry)).is_equal(OK)
	assert_array(_registry.filter(&"price", 10)).is_empty()
	assert_bool(_registry.is_property_indexed(&"price")).is_true()


func test_removing_an_indexed_property_drops_its_index() -> void:
	_add_entries([Fixtures.POTION_UID])
	_index("price,kind")
	_index("kind")
	assert_array(_registry.get_indexed_properties()).is_equal([&"kind"])


func test_get_string_ids_sorted_by() -> void:
	_add_entries([Fixtures.SWORD_UID, Fixtures.ELIXIR_UID, Fixtures.POTION_UID])
	_add_entries([Fixtures.DRAFT_POTION_UID])
	_index("price")
	assert_array(RegistryIO.get_string_ids_sorted_by(_registry, "price")).is_equal(
		[&"draft_potion", &"potion", &"sword", &"elixir"],
	)
	assert_array(RegistryIO.get_string_ids_sorted_by(_registry, "-price")).is_equal(
		[&"elixir", &"sword", &"potion", &"draft_potion"],
	)


func test_get_string_ids_sorted_by_keeps_ties_in_order_and_missing_values_last() -> void:
	_add_entries([Fixtures.DRAFT_POTION_UID, Fixtures.ELIXIR_UID, Fixtures.POTION_UID])
	_add_entries([Fixtures.SWORD_UID])
	_index("stats.power")
	assert_array(RegistryIO.get_string_ids_sorted_by(_registry, "stats.power")).is_equal(
		[&"potion", &"elixir", &"sword", &"draft_potion"],
	)
	assert_array(RegistryIO.get_string_ids_sorted_by(_registry, "-stats.power")).is_equal(
		[&"elixir", &"sword", &"potion", &"draft_potion"],
	)


func test_get_string_ids_sorted_by_nothing_keeps_registry_order() -> void:
	_add_entries([Fixtures.SWORD_UID, Fixtures.POTION_UID])
	var registry_order: Array[StringName] = [&"sword", &"potion"]
	assert_array(RegistryIO.get_string_ids_sorted_by(_registry, "")).is_equal(registry_order)
	assert_array(RegistryIO.get_string_ids_sorted_by(_registry, "price")).is_equal(registry_order)


func test_index_values_sort_numbers_first_then_strings_naturally() -> void:
	var values: Array = ["item_10", 3, "item_2", 1.5, &"Apple", true]
	values.sort_custom(RegistryIO._is_index_value_less)
	assert_array(values).is_equal([true, 1.5, 3, &"Apple", "item_2", "item_10"])

#endregion


#region Validation helpers

func test_is_valid_registry_output_path() -> void:
	assert_bool(RegistryIO.is_valid_registry_output_path("res://test/fixtures/new.tres")).is_true()
	assert_bool(RegistryIO.is_valid_registry_output_path("test/fixtures/new.tres")).is_true()
	assert_bool(RegistryIO.is_valid_registry_output_path("res://missing/new.tres")).is_false()
	assert_bool(RegistryIO.is_valid_registry_output_path("res://test/fixtures/")).is_false()
	assert_bool(RegistryIO.is_valid_registry_output_path("res://test/fixtures/a:b.tres")).is_false()
	assert_bool(RegistryIO.is_valid_registry_output_path("  ")).is_false()


func test_is_resource_class_string() -> void:
	assert_bool(RegistryIO.is_resource_class_string("Resource")).is_true()
	assert_bool(RegistryIO.is_resource_class_string(" Texture2D ")).is_true()
	assert_bool(RegistryIO.is_resource_class_string("YardTestWeapon")).is_true()
	assert_bool(RegistryIO.is_resource_class_string("\"%s\"" % Fixtures.TRINKET_SCRIPT_PATH)).is_true()
	assert_bool(RegistryIO.is_resource_class_string("'%s'" % Fixtures.TRINKET_SCRIPT_PATH)).is_true()
	assert_bool(RegistryIO.is_resource_class_string("")).is_false()
	assert_bool(RegistryIO.is_resource_class_string("Node")).is_false()
	assert_bool(RegistryIO.is_resource_class_string("NotAClass")).is_false()
	assert_bool(RegistryIO.is_resource_class_string(Fixtures.TRINKET_SCRIPT_PATH)).is_false()
	assert_bool(RegistryIO.is_resource_class_string("\"res://test/missing.gd\"")).is_false()


@warning_ignore("unused_parameter")
func test_is_resource_class_string_rejects_quoted_non_resource_scripts(
	do_skip := true,
	skip_reason := "Known bug: ClassUtils sees any unnamed script as a GDScript, i.e. a Resource",
) -> void:
	assert_bool(RegistryIO.is_resource_class_string("\"%s\"" % Fixtures.NODE_SCRIPT_PATH)).is_false()


func test_does_resource_match_class_restrictions() -> void:
	assert_bool(RegistryIO.does_resource_match_class_restrictions(null, [])).is_false()
	assert_bool(_matches(Fixtures.POTION_UID, [])).is_true()

	assert_bool(_matches(Fixtures.POTION_UID, [&"YardTestItem"])).is_true()
	assert_bool(_matches(Fixtures.SWORD_UID, [&"YardTestItem"])).is_true()
	assert_bool(_matches(Fixtures.POTION_UID, [&"YardTestWeapon"])).is_false()
	assert_bool(_matches(Fixtures.TRINKET_UID, [&"YardTestItem"])).is_false()

	assert_bool(_matches(Fixtures.GRADIENT_UID, [&"Gradient"])).is_true()
	assert_bool(_matches(Fixtures.POTION_UID, [&"Gradient"])).is_false()
	assert_bool(_matches(Fixtures.TRINKET_UID, [&"Resource"])).is_true()

	var quoted_trinket_script := StringName("\"%s\"" % Fixtures.TRINKET_SCRIPT_PATH)
	assert_bool(_matches(Fixtures.TRINKET_UID, [quoted_trinket_script])).is_true()
	assert_bool(_matches(Fixtures.POTION_UID, [quoted_trinket_script])).is_false()

	var weapon_or_gradient: Array[StringName] = [&"YardTestWeapon", &"Gradient"]
	assert_bool(_matches(Fixtures.SWORD_UID, weapon_or_gradient)).is_true()
	assert_bool(_matches(Fixtures.GRADIENT_UID, weapon_or_gradient)).is_true()
	assert_bool(_matches(Fixtures.POTION_UID, weapon_or_gradient)).is_false()


func test_quoted_strings() -> void:
	assert_bool(RegistryIO.is_quoted_string("\"a\"")).is_true()
	assert_bool(RegistryIO.is_quoted_string("'a'")).is_true()
	assert_bool(RegistryIO.is_quoted_string("\"a'")).is_false()
	assert_bool(RegistryIO.is_quoted_string("\"")).is_false()
	assert_bool(RegistryIO.is_quoted_string("a")).is_false()
	assert_str(RegistryIO.unquote("\"abc\"")).is_equal("abc")


func test_is_valid_regex_pattern() -> void:
	assert_bool(RegistryIO.is_valid_regex_pattern("")).is_true()
	assert_bool(RegistryIO.is_valid_regex_pattern("^draft_")).is_true()
	assert_bool(RegistryIO.is_valid_regex_pattern("(")).is_false()


func test_is_uid_valid() -> void:
	assert_bool(RegistryIO.is_uid_valid(Fixtures.POTION_UID)).is_true()
	assert_bool(RegistryIO.is_uid_valid("uid://yardtestnone")).is_false()
	assert_bool(RegistryIO.is_uid_valid("res://test/fixtures/items/potion.tres")).is_false()

#endregion


#region Custom hint

func test_custom_hint_parse() -> void:
	var hint_string := "%s,true,sort=-price,dict=keys" % Fixtures.SHOP_REGISTRY_PATH
	var custom_hint := RegistryIO.CustomHint.parse(hint_string)
	assert_str(custom_hint.registry_path).is_equal(Fixtures.SHOP_REGISTRY_PATH)
	assert_bool(custom_hint.suggestion).is_true()
	assert_str(custom_hint.sort).is_equal("-price")
	assert_str(custom_hint.dict_side).is_equal("keys")
	assert_bool(custom_hint.load_registry().has(&"potion")).is_true()


func test_custom_hint_parse_defaults() -> void:
	var custom_hint := RegistryIO.CustomHint.parse(Fixtures.SHOP_REGISTRY_UID)
	assert_str(custom_hint.registry_path).is_equal(Fixtures.SHOP_REGISTRY_UID)
	assert_bool(custom_hint.suggestion).is_false()
	assert_str(custom_hint.sort).is_empty()
	assert_str(custom_hint.dict_side).is_empty()


func test_custom_hint_parse_tolerates_spaces() -> void:
	var custom_hint := RegistryIO.CustomHint.parse(
		" %s , true , sort = price " % Fixtures.SHOP_REGISTRY_PATH
	)
	assert_str(custom_hint.registry_path).is_equal(Fixtures.SHOP_REGISTRY_PATH)
	assert_bool(custom_hint.suggestion).is_true()
	assert_str(custom_hint.sort).is_equal("price")


func test_custom_hint_parse_rejects_invalid_registry_paths() -> void:
	for hint_string: String in ["", "data/shop.tres", "res://test/missing.tres"]:
		var custom_hint := RegistryIO.CustomHint.parse(hint_string)
		assert_str(custom_hint.registry_path).is_empty()
		assert_object(custom_hint.load_registry()).is_null()


func test_custom_hint_parse_ignores_unknown_options() -> void:
	var hint_string := "%s,maybe,dict=sideways,color=red" % Fixtures.SHOP_REGISTRY_PATH
	var custom_hint := RegistryIO.CustomHint.parse(hint_string)
	assert_str(custom_hint.registry_path).is_equal(Fixtures.SHOP_REGISTRY_PATH)
	assert_bool(custom_hint.suggestion).is_false()
	assert_str(custom_hint.dict_side).is_empty()

#endregion


#region Registry file creation

func test_create_registry_file() -> void:
	var settings := RegistryIO.RegistrySettings.new()
	settings.indexed_props = "price"
	assert_int(RegistryIO.create_registry_file(CREATED_REGISTRY_PATH, settings)).is_equal(OK)

	var created: Registry = ResourceLoader.load(
		CREATED_REGISTRY_PATH,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	)
	assert_int(created._version).is_equal(Registry._REGISTRY_FORMAT_VERSION)
	assert_bool(created.is_empty()).is_true()
	assert_bool(created.is_property_indexed(&"price")).is_true()


func test_create_registry_file_does_not_overwrite() -> void:
	assert_int(RegistryIO.create_registry_file(CREATED_REGISTRY_PATH)).is_equal(OK)
	assert_int(RegistryIO.create_registry_file(CREATED_REGISTRY_PATH)).is_equal(ERR_FILE_CANT_WRITE)


func test_create_registry_file_rejects_invalid_input() -> void:
	assert_int(RegistryIO.create_registry_file("")).is_equal(ERR_FILE_BAD_PATH)
	assert_int(RegistryIO.create_registry_file("res://missing/registry.tres")).is_equal(
		ERR_FILE_BAD_PATH,
	)

	var settings := RegistryIO.RegistrySettings.new()
	settings.default_scan_ruleset.class_restrictions = [&"NotAClass"]
	assert_int(RegistryIO.create_registry_file(CREATED_REGISTRY_PATH, settings)).is_equal(
		ERR_DOES_NOT_EXIST,
	)
	assert_bool(FileAccess.file_exists(CREATED_REGISTRY_PATH)).is_false()

#endregion
