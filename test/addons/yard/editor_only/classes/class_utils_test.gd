# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite

const Fixtures := preload("res://test/fixtures/fixtures.gd")
const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ClassUtils := Namespace.ClassUtils

const ItemScript := preload("res://test/fixtures/scripts/yard_test_item.gd")
const WeaponScript := preload("res://test/fixtures/scripts/yard_test_weapon.gd")
const TrinketScript := preload("res://test/fixtures/scripts/unnamed_trinket.gd")


func test_get_inheritance_list_of_a_native_class() -> void:
	assert_array(ClassUtils.get_inheritance_list("Resource")).is_equal(["RefCounted", "Object"])
	assert_array(ClassUtils.get_inheritance_list("Resource", true)).is_equal(
		["Resource", "RefCounted", "Object"],
	)


func test_get_inheritance_list_of_a_named_script() -> void:
	assert_array(ClassUtils.get_inheritance_list("YardTestWeapon", true)).is_equal(
		["YardTestWeapon", "YardTestItem", "Resource", "RefCounted", "Object"],
	)
	assert_array(ClassUtils.get_inheritance_list(WeaponScript)).is_equal(
		["YardTestItem", "Resource", "RefCounted", "Object"],
	)


func test_get_script_inheritance_list() -> void:
	assert_array(ClassUtils.get_script_inheritance_list(WeaponScript, true)).is_equal(
		[WeaponScript, ItemScript],
	)
	assert_array(ClassUtils.get_script_inheritance_list(WeaponScript)).is_equal([ItemScript])
	assert_array(ClassUtils.get_script_inheritance_list(TrinketScript)).is_empty()


func test_get_script_inheritance_list_strings() -> void:
	var weapon_chain := ClassUtils.get_script_inheritance_list_strings(WeaponScript, true)
	assert_array(weapon_chain.slice(0, 2)).is_equal(["YardTestWeapon", "YardTestItem"])
	assert_str(weapon_chain.back()).is_equal("Object")

	# Unnamed scripts are listed by path. Their native ancestors aren't reliable: ClassUtils doesn't
	# support unnamed scripts (see its class description).
	var trinket_chain := ClassUtils.get_script_inheritance_list_strings(TrinketScript, true)
	assert_str(trinket_chain.front()).is_equal(Fixtures.TRINKET_SCRIPT_PATH)


func test_sort_by_inheritance_puts_parents_first() -> void:
	assert_array(ClassUtils.sort_by_inheritance(["YardTestWeapon", "Resource", "YardTestItem"])).is_equal(
		["Resource", "YardTestItem", "YardTestWeapon"],
	)
	assert_array(ClassUtils.sort_by_inheritance([Fixtures.TRINKET_SCRIPT_PATH, "Resource"])).is_equal(
		["Resource", Fixtures.TRINKET_SCRIPT_PATH],
	)


func test_sort_by_inheritance_keeps_the_order_of_unrelated_classes() -> void:
	assert_array(ClassUtils.sort_by_inheritance(["Texture2D", "Gradient", "Curve"])).is_equal(
		["Texture2D", "Gradient", "Curve"],
	)


func test_is_class_of() -> void:
	assert_bool(ClassUtils.is_class_of("YardTestWeapon", "YardTestItem")).is_true()
	assert_bool(ClassUtils.is_class_of("YardTestItem", "YardTestWeapon")).is_false()
	assert_bool(ClassUtils.is_class_of("YardTestItem", "YardTestItem")).is_true()
	assert_bool(ClassUtils.is_class_of(&"Gradient", &"Resource")).is_true()
	assert_bool(ClassUtils.is_class_of("Node", "Resource")).is_false()
	assert_bool(ClassUtils.is_class_of("NotAClass", "Resource")).is_false()
	assert_bool(ClassUtils.is_class_of(3, "Resource")).is_false()


func test_is_class_of_accepts_scripts_and_instances() -> void:
	assert_bool(ClassUtils.is_class_of(WeaponScript, "Resource")).is_true()
	assert_bool(ClassUtils.is_class_of(load(Fixtures.SWORD_UID), "YardTestItem")).is_true()
	assert_bool(ClassUtils.is_class_of(load(Fixtures.POTION_UID), WeaponScript)).is_false()
	assert_bool(ClassUtils.is_class_of(Gradient.new(), "Resource")).is_true()


func test_get_type_name() -> void:
	assert_str(ClassUtils.get_type_name(null)).is_equal("Nil")
	assert_str(ClassUtils.get_type_name(3)).is_equal("int")
	assert_str(ClassUtils.get_type_name(Gradient.new())).is_equal("Gradient")
	assert_str(ClassUtils.get_type_name(WeaponScript)).is_equal("YardTestWeapon")
	assert_str(ClassUtils.get_type_name(load(Fixtures.SWORD_UID))).is_equal("YardTestWeapon")


func test_get_type_name_of_typed_collections() -> void:
	var ints: Array[int] = []
	var items: Array[ItemScript] = []
	var prices: Dictionary[StringName, int] = { }
	var anything: Dictionary[StringName, Variant] = { }
	assert_str(ClassUtils.get_type_name([])).is_equal("Array")
	assert_str(ClassUtils.get_type_name(ints)).is_equal("Array[int]")
	assert_str(ClassUtils.get_type_name(items)).is_equal("Array[YardTestItem]")
	assert_str(ClassUtils.get_type_name({ })).is_equal("Dictionary")
	assert_str(ClassUtils.get_type_name(prices)).is_equal("Dictionary[StringName,int]")
	assert_str(ClassUtils.get_type_name(anything)).is_equal("Dictionary[StringName,any]")


func test_is_native_is_script_and_is_valid() -> void:
	assert_bool(ClassUtils.is_native("Resource")).is_true()
	assert_bool(ClassUtils.is_native("YardTestItem")).is_false()
	assert_bool(ClassUtils.is_native("")).is_false()
	assert_bool(ClassUtils.is_script("YardTestItem")).is_true()
	assert_bool(ClassUtils.is_script(ItemScript)).is_true()
	assert_bool(ClassUtils.is_script("Resource")).is_false()
	assert_bool(ClassUtils.is_valid("YardTestItem")).is_true()
	assert_bool(ClassUtils.is_valid("Gradient")).is_true()
	assert_bool(ClassUtils.is_valid("NotAClass")).is_false()


func test_get_type() -> void:
	assert_object(ClassUtils.get_type("YardTestItem")).is_same(ItemScript)
	assert_object(ClassUtils.get_type("NotAClass")).is_null()


@warning_ignore("unused_parameter")
func test_get_type_of_a_native_class(
	do_skip: bool = ProjectSettings.get_setting("debug/gdscript/warnings/untyped_declaration") == 2,
	skip_reason := "Known bug: get_type_unsafe() compiles untyped code, an error with strict warnings",
) -> void:
	assert_object(ClassUtils.get_type("Gradient")).is_not_null()


func test_get_class_name_or_path_from_prop() -> void:
	var weapon_category := _category_property("yard_test_weapon.gd", Fixtures.WEAPON_SCRIPT_PATH)
	var trinket_category := _category_property("unnamed_trinket.gd", Fixtures.TRINKET_SCRIPT_PATH)
	var native_category := _category_property("Resource", "Resource")
	var price_property := { &"name": "price", &"type": TYPE_INT, &"usage": 0, &"hint_string": "" }
	assert_str(ClassUtils.get_class_name_or_path_from_prop(weapon_category)).is_equal(
		"YardTestWeapon"
	)
	assert_str(ClassUtils.get_class_name_or_path_from_prop(trinket_category)).is_equal(
		Fixtures.TRINKET_SCRIPT_PATH,
	)
	assert_str(ClassUtils.get_class_name_or_path_from_prop(native_category)).is_equal("Resource")
	assert_str(ClassUtils.get_class_name_or_path_from_prop(price_property)).is_empty()


func test_get_class_property_names() -> void:
	assert_array(ClassUtils.get_class_property_names("YardTestWeapon")).contains(
		["damage", "price", "kind", "stats"],
	)
	assert_array(ClassUtils.get_class_property_names("Gradient")).contains(["offsets", "colors"])
	assert_array(ClassUtils.get_class_property_names("")).is_empty()


func test_get_property_declared_types() -> void:
	var sword: Resource = load(Fixtures.SWORD_UID)
	assert_array(ClassUtils.get_property_declared_types(sword, "price")).is_equal(["int"])
	assert_array(ClassUtils.get_property_declared_types(sword, "kind")).is_equal(["StringName"])
	assert_array(ClassUtils.get_property_declared_types(Gradient.new(), "colors")).is_equal(
		["PackedColorArray"],
	)
	assert_array(ClassUtils.get_property_declared_types(sword, "missing")).is_empty()
	assert_array(ClassUtils.get_property_declared_types(3, "price")).is_empty()


func test_convert_implicitly() -> void:
	assert_that(ClassUtils.convert_implicitly(3, ["float"])).is_equal(3.0)
	assert_that(ClassUtils.convert_implicitly(3, ["String"])).is_equal("3")
	assert_that(ClassUtils.convert_implicitly(true, ["int"])).is_equal(1)
	assert_that(ClassUtils.convert_implicitly("a", ["StringName"])).is_equal(&"a")
	assert_that(ClassUtils.convert_implicitly(Vector2(1.5, 2.0), ["Vector2i"])).is_equal(
		Vector2i(1, 2),
	)
	assert_that(ClassUtils.convert_implicitly([1, 2], ["PackedInt32Array"])).is_equal(
		PackedInt32Array([1, 2]),
	)
	assert_that(ClassUtils.convert_implicitly(3, ["Vector2"])).is_equal(3)


func test_is_assignable() -> void:
	assert_bool(ClassUtils.is_assignable(3, ["int"])).is_true()
	assert_bool(ClassUtils.is_assignable(3.0, ["int"])).is_false()
	assert_bool(ClassUtils.is_assignable(null, ["Resource"])).is_true()
	assert_bool(ClassUtils.is_assignable(null, ["int"])).is_false()
	assert_bool(ClassUtils.is_assignable(load(Fixtures.SWORD_UID), ["YardTestItem"])).is_true()
	assert_bool(ClassUtils.is_assignable(load(Fixtures.POTION_UID), ["YardTestWeapon"])).is_false()
	assert_bool(ClassUtils.is_assignable(Gradient.new(), ["Texture2D", "Gradient"])).is_true()


func test_get_type_builtin_default_value() -> void:
	assert_that(ClassUtils.get_type_builtin_default_value(TYPE_INT)).is_equal(0)
	assert_that(ClassUtils.get_type_builtin_default_value(TYPE_STRING_NAME)).is_equal(&"")
	assert_that(ClassUtils.get_type_builtin_default_value(TYPE_COLOR)).is_equal(Color())
	assert_that(ClassUtils.get_type_builtin_default_value(TYPE_NIL)).is_null()


func _category_property(category_name: String, hint_string: String) -> Dictionary:
	return {
		&"name": category_name,
		&"type": TYPE_NIL,
		&"usage": PROPERTY_USAGE_CATEGORY,
		&"hint_string": hint_string,
	}
