# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite
## The registry tab's table, fed with a registry. It calls editor-only APIs, so these tests are
## skipped unless run inside the editor (see test/tools/run_tests_in_editor.gd).

const Fixtures := preload("res://test/fixtures/fixtures.gd")
const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryTableView := Namespace.RegistryTableView

const REQUIRES_EDITOR := "Requires the editor: run test/tools/run_tests_in_editor.gd"

var _view: RegistryTableView


func before_test() -> void:
	if not Engine.is_editor_hint():
		return
	_view = auto_free(Namespace.REGISTRY_TABLE_VIEW_SCENE.instantiate())
	add_child(_view)
	_view.current_registry = load(Fixtures.SHOP_REGISTRY_PATH)


@warning_ignore("unused_parameter")
func test_shows_one_row_per_entry(
	do_skip := not Engine.is_editor_hint(),
	skip_reason := REQUIRES_EDITOR,
) -> void:
	# The order comes from the view state cached by previous sessions, so it isn't checked.
	assert_array(_view.data_table.get_displayed_rows()).contains_exactly_in_any_order(
		[&"potion", &"sword", &"elixir"],
	)
	assert_that(_view.data_table.get_cell_value(&"sword", RegistryTableView.UID_COLUMN)).is_equal(
		Fixtures.SWORD_UID,
	)
	assert_that(_view.data_table.get_cell_value(&"sword", &"price")).is_equal(30)


@warning_ignore("unused_parameter")
func test_shows_the_properties_of_every_entry(
	do_skip := not Engine.is_editor_hint(),
	skip_reason := REQUIRES_EDITOR,
) -> void:
	var column_ids: Array[StringName] = []
	for column: Namespace.ColumnConfig in _view.data_table.get_all_columns():
		column_ids.append(column.identifier)
	assert_array(column_ids).contains(
		[RegistryTableView.STRINGID_COLUMN, RegistryTableView.UID_COLUMN, &"price", &"kind"],
	)
	# Only the sword is a YardTestWeapon.
	assert_array(column_ids).contains([&"damage"])
	assert_that(_view.data_table.get_cell_value(&"potion", &"damage")).is_null()


@warning_ignore("unused_parameter")
func test_clearing_the_registry_empties_the_table(
	do_skip := not Engine.is_editor_hint(),
	skip_reason := REQUIRES_EDITOR,
) -> void:
	_view.current_registry = null
	assert_array(_view.data_table.get_displayed_rows()).is_empty()
	assert_array(_view.data_table.get_all_columns()).is_empty()
