# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite
## Parsing, sort keys, filter keys and text produced by the cell types. Drawing and editors are
## left out: they need a canvas and editor nodes.

const Fixtures := preload("res://test/fixtures/fixtures.gd")
const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ColumnConfig := Namespace.ColumnConfig
const CellStyle := Namespace.CellStyle
const CellType := Namespace.CellType
const NumericCellType := Namespace.NumericCellType
const BooleanCellType := Namespace.BooleanCellType
const ColorCellType := Namespace.ColorCellType
const ResourceCellType := Namespace.ResourceCellType
const EnumCellType := Namespace.EnumCellType
const BitFlagsCellType := Namespace.BitFlagsCellType
const RegistryEntryCellType := Namespace.RegistryEntryCellType
const CollectionCellType := Namespace.CollectionCellType
const RegistryIO := Namespace.RegistryIO

# Custom hints have no PropertyHint member.
@warning_ignore("int_as_enum_without_match")
const REGISTRY_HINT := Registry.PROPERTY_HINT_CUSTOM as PropertyHint


func _column(
	type: Variant.Type,
	hint: PropertyHint = PROPERTY_HINT_NONE,
	hint_string: String = "",
) -> ColumnConfig:
	var column := ColumnConfig.new(&"column", "Column", type)
	column.property_hint = hint
	column.hint_string = hint_string
	return column


#region CellType

func test_parse_enum_hint_string() -> void:
	assert_dict(CellType.parse_enum_hint_string("A,B,C")).is_equal({ 0: "A", 1: "B", 2: "C" })
	assert_dict(CellType.parse_enum_hint_string("A,B:4,C")).is_equal({ 0: "A", 4: "B", 5: "C" })
	assert_dict(CellType.parse_enum_hint_string("Low:-1,High")).is_equal({ -1: "Low", 0: "High" })
	assert_dict(CellType.parse_enum_hint_string("")).is_empty()


func test_default_keys_are_the_value_as_text() -> void:
	var column := _column(TYPE_VECTOR2)
	assert_that(CellType.get_sort_key(Vector2(1, 2), column)).is_equal("(1.0, 2.0)")
	assert_that(CellType.get_filter_key(Vector2(1, 2), column)).is_equal("(1.0, 2.0)")
	assert_str(CellType.get_tooltip(Vector2(1, 2), column)).is_equal("Vector2(1, 2)")

#endregion


#region Numeric and boolean

func test_numeric_sort_key_is_a_float() -> void:
	assert_that(NumericCellType.get_sort_key(3, _column(TYPE_INT))).is_equal(3.0)


func test_numeric_read_editor_value() -> void:
	var line_edit: LineEdit = auto_free(LineEdit.new())
	line_edit.text = "42"
	assert_that(NumericCellType.read_editor_value(line_edit, _column(TYPE_INT))).is_equal(42)
	line_edit.text = "4.5"
	assert_that(NumericCellType.read_editor_value(line_edit, _column(TYPE_INT))).is_null()
	assert_that(NumericCellType.read_editor_value(line_edit, _column(TYPE_FLOAT))).is_equal(4.5)
	line_edit.text = "abc"
	assert_that(NumericCellType.read_editor_value(line_edit, _column(TYPE_FLOAT))).is_null()


func test_boolean_sort_key() -> void:
	assert_that(BooleanCellType.get_sort_key(true, _column(TYPE_BOOL))).is_equal(1)
	assert_that(BooleanCellType.get_sort_key(false, _column(TYPE_BOOL))).is_equal(0)


func test_boolean_toggles_on_ui_accept() -> void:
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	var result := BooleanCellType.handle_input(
		accept,
		Rect2(0, 0, 100, 30),
		false,
		_column(TYPE_BOOL),
		CellStyle.new(),
		{ },
	)
	assert_dict(result).is_equal({ &"value": true, &"commit": true })


func test_boolean_ignores_other_input() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	var result := BooleanCellType.handle_input(
		key,
		Rect2(0, 0, 100, 30),
		false,
		_column(TYPE_BOOL),
		CellStyle.new(),
		{ },
	)
	assert_dict(result).is_empty()

#endregion


#region Color

func test_color_sort_key_orders_by_hue() -> void:
	var column := _column(TYPE_COLOR)
	assert_array(ColorCellType.get_sort_key(Color.RED, column)).is_equal([0.0, 1.0, 1.0, 1.0])
	var red_key: Array = ColorCellType.get_sort_key(Color.RED, column)
	var blue_key: Array = ColorCellType.get_sort_key(Color.BLUE, column)
	assert_float(red_key[0]).is_less(blue_key[0])


func test_color_tooltip() -> void:
	assert_str(ColorCellType.get_tooltip(Color(1, 0.5, 0, 1), _column(TYPE_COLOR))).is_equal(
		"R: 1.00\nG: 0.50\nB: 0.00\nA: 1.00\n",
	)

#endregion


#region Enum and bit flags

func test_numeric_enum_choices() -> void:
	var column := _column(TYPE_INT, PROPERTY_HINT_ENUM, "Low,High:5")
	assert_dict(EnumCellType._get_choices(column)).is_equal({ 0: "Low", 5: "High" })
	assert_that(EnumCellType.get_sort_key(5, column)).is_equal(5.0)


func test_string_enum_choices() -> void:
	var column := _column(TYPE_STRING, PROPERTY_HINT_ENUM, "red,green")
	assert_dict(EnumCellType._get_choices(column)).is_equal({ "red": "red", "green": "green" })
	assert_that(EnumCellType.get_sort_key("red", column)).is_equal("red")


func test_bit_flags_implicit_values_follow_item_position() -> void:
	var column := _column(TYPE_INT, PROPERTY_HINT_FLAGS, "A,B,C:8")
	assert_dict(BitFlagsCellType._get_flags(column)).is_equal({ 1: "A", 2: "B", 8: "C" })


func test_bit_flags_filter_key_lists_the_set_flags() -> void:
	var column := _column(TYPE_INT, PROPERTY_HINT_FLAGS, "Fire,Water,Earth")
	assert_that(BitFlagsCellType.get_filter_key(5, column)).is_equal("Fire Earth")
	assert_that(BitFlagsCellType.get_filter_key(0, column)).is_equal("")
	assert_that(BitFlagsCellType.get_sort_key(5, column)).is_equal("5")

#endregion


#region Collections

func test_array_text() -> void:
	var column := _column(TYPE_ARRAY)
	assert_that(CollectionCellType.get_sort_key([1, "a", null], column)).is_equal('[1, "a", null]')
	assert_that(CollectionCellType.get_filter_key([], column)).is_equal("[]")


func test_nested_collections_show_their_size() -> void:
	var column := _column(TYPE_ARRAY)
	assert_that(CollectionCellType.get_sort_key([[1, 2], { "a": 1 }], column)).is_equal(
		"[Array(2), Dict(1)]",
	)


func test_enum_array_shows_labels() -> void:
	var column := _column(TYPE_ARRAY, PROPERTY_HINT_TYPE_STRING, "2/2:Low,High")
	assert_that(CollectionCellType.get_sort_key([0, 1, 7], column)).is_equal("[Low, High, ?:7]")


func test_dictionary_text() -> void:
	var column := _column(TYPE_DICTIONARY)
	assert_that(CollectionCellType.get_sort_key({ &"potion": 3 }, column)).is_equal(
		'{ &"potion": 3 }',
	)


func test_dictionary_with_enum_keys_shows_labels() -> void:
	var column := _column(TYPE_DICTIONARY, PROPERTY_HINT_TYPE_STRING, "2/2:Low,High;4:")
	assert_that(CollectionCellType.get_sort_key({ 1: "x" }, column)).is_equal('{ High: "x" }')


func test_resource_array_shows_labels_and_empty_slots() -> void:
	var column := _column(TYPE_ARRAY, PROPERTY_HINT_TYPE_STRING, "24/17:Resource")
	var potion: Resource = load(Fixtures.POTION_UID)
	assert_that(CollectionCellType.get_sort_key([potion, null], column)).is_equal(
		"[<potion.tres>, <empty>]",
	)


func test_collection_tooltip_is_indented() -> void:
	var column := _column(TYPE_ARRAY)
	assert_str(CollectionCellType.get_tooltip([1, [2]], column)).is_equal(
		"[\n    1,\n    [\n        2\n    ]\n]",
	)

#endregion


#region Resources and registry entries

func test_resource_label_falls_back_to_the_file_name() -> void:
	var potion: Resource = load(Fixtures.POTION_UID)
	assert_str(ResourceCellType.get_label(potion)).is_equal("potion.tres")
	var named := Gradient.new()
	named.resource_name = "Sunset"
	assert_str(ResourceCellType.get_label(named)).is_equal("Sunset")
	assert_str(ResourceCellType.get_label(Gradient.new())).is_equal("Gradient")


func test_resource_keys() -> void:
	var column := _column(TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Resource")
	var potion: Resource = load(Fixtures.POTION_UID)
	assert_that(ResourceCellType.get_sort_key(potion, column)).is_equal("potion.tres")
	assert_that(ResourceCellType.get_filter_key(null, column)).is_equal("<empty>")


func test_registry_entry_choices_follow_the_sort_option() -> void:
	var custom_hint := RegistryIO.CustomHint.parse("%s,sort=-price" % Fixtures.SHOP_REGISTRY_PATH)
	assert_array(RegistryEntryCellType._get_choices(custom_hint).keys()).is_equal(
		["elixir", "sword", "potion"],
	)


func test_registry_entry_tooltip_names_the_registry() -> void:
	var column := _column(TYPE_STRING_NAME, REGISTRY_HINT, Fixtures.SHOP_REGISTRY_PATH)
	assert_str(RegistryEntryCellType.get_tooltip(&"potion", column)).is_equal(
		'Registry: shop.tres\n&"potion"',
	)

#endregion
