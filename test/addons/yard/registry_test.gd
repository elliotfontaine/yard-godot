# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite
## Runtime API, queried on a registry loaded from disk, as games do.

const Fixtures := preload("res://test/fixtures/fixtures.gd")

var _shop: Registry


func before() -> void:
	_shop = load(Fixtures.SHOP_REGISTRY_PATH)


func test_size_and_is_empty() -> void:
	assert_int(_shop.size()).is_equal(3)
	assert_bool(_shop.is_empty()).is_false()
	assert_int(Registry.new().size()).is_equal(0)
	assert_bool(Registry.new().is_empty()).is_true()


func test_has_accepts_string_ids_and_uids() -> void:
	assert_bool(_shop.has(&"potion")).is_true()
	assert_bool(_shop.has(Fixtures.POTION_UID)).is_true()
	assert_bool(_shop.has(&"shield")).is_false()
	assert_bool(_shop.has(Fixtures.SHIELD_UID)).is_false()


func test_has_uid_and_has_string_id_only_accept_their_own_form() -> void:
	assert_bool(_shop.has_uid(Fixtures.POTION_UID)).is_true()
	assert_bool(_shop.has_uid(&"potion")).is_false()
	assert_bool(_shop.has_string_id(&"potion")).is_true()
	assert_bool(_shop.has_string_id(Fixtures.POTION_UID)).is_false()


func test_get_uid_resolves_both_forms() -> void:
	assert_str(_shop.get_uid(&"potion")).is_equal(Fixtures.POTION_UID)
	assert_str(_shop.get_uid(Fixtures.POTION_UID)).is_equal(Fixtures.POTION_UID)
	assert_str(_shop.get_uid(&"unknown")).is_empty()


func test_get_string_id_resolves_both_forms() -> void:
	assert_str(_shop.get_string_id(Fixtures.POTION_UID)).is_equal("potion")
	assert_str(_shop.get_string_id(&"potion")).is_equal("potion")
	assert_str(_shop.get_string_id(Fixtures.SHIELD_UID)).is_empty()


func test_get_all_ids_keep_registry_order() -> void:
	assert_array(_shop.get_all_string_ids()).is_equal([&"potion", &"sword", &"elixir"])
	assert_array(_shop.get_all_uids()).is_equal(
		[Fixtures.POTION_UID, Fixtures.SWORD_UID, Fixtures.ELIXIR_UID],
	)


func test_get_string_id_of() -> void:
	var potion: Resource = load(Fixtures.POTION_UID)
	assert_str(_shop.get_string_id_of(potion)).is_equal("potion")
	assert_str(_shop.get_string_id_of(load(Fixtures.SHIELD_UID))).is_empty()
	assert_str(_shop.get_string_id_of(potion.duplicate())).is_empty()
	assert_str(_shop.get_string_id_of(null)).is_empty()


func test_load_entry() -> void:
	assert_int(_shop.load_entry(&"potion").get(&"price")).is_equal(10)
	assert_object(_shop.load_entry(Fixtures.SWORD_UID)).is_same(load(Fixtures.SWORD_UID))
	assert_object(_shop.load_entry(&"unknown")).is_null()


func test_load_all_blocking() -> void:
	var loaded := _shop.load_all_blocking()
	assert_array(loaded.keys()).contains_exactly_in_any_order([&"potion", &"sword", &"elixir"])
	assert_int(loaded[&"elixir"].get(&"price")).is_equal(50)


func test_load_all_threaded_request() -> void:
	var tracker := _shop.load_all_threaded_request()
	assert_array(tracker.requested.values()).contains_exactly([true, true, true])

	var frames := 0
	while tracker.progress < 1.0 and frames < 300:
		await await_idle_frame()
		frames += 1

	assert_float(tracker.progress).is_equal(1.0)
	assert_object(tracker.resources[&"sword"]).is_same(load(Fixtures.SWORD_UID))
	assert_int(tracker.status[&"sword"]).is_equal(ResourceLoader.THREAD_LOAD_LOADED)
	assert_str(tracker.uids[&"sword"]).is_equal(Fixtures.SWORD_UID)


func test_indexed_properties() -> void:
	assert_array(_shop.get_indexed_properties()).contains_exactly_in_any_order(
		[&"kind", &"price", &"stats.power"],
	)
	assert_bool(_shop.is_property_indexed(&"price")).is_true()
	assert_bool(_shop.is_property_indexed(&"damage")).is_false()


func test_filter_by_value() -> void:
	assert_array(_shop.filter(&"kind", &"consumable")).contains_exactly_in_any_order(
		[&"potion", &"elixir"],
	)
	assert_array(_shop.filter(&"price", 30)).is_equal([&"sword"])
	assert_array(_shop.filter(&"price", 999)).is_empty()


func test_filter_by_predicate() -> void:
	var expensive := _shop.filter(
		&"price",
		func(price: int) -> bool:
			return price >= 30,
	)
	assert_array(expensive).contains_exactly_in_any_order([&"sword", &"elixir"])


func test_filter_on_subresource_property() -> void:
	assert_array(_shop.filter(&"stats.power", 8)).contains_exactly_in_any_order(
		[&"sword", &"elixir"],
	)


func test_filter_on_non_indexed_property_returns_empty() -> void:
	assert_array(_shop.filter(&"damage", 12)).is_empty()
	assert_array(
		_shop.filter(
			&"damage",
			func(_damage: int) -> bool:
				return true,
		)
	).is_empty()


func test_where_intersects_all_criteria() -> void:
	assert_array(_shop.where({ &"kind": &"consumable", &"stats.power": 8 })).is_equal([&"elixir"])


func test_where_mixes_values_and_predicates() -> void:
	var cheap_consumables := _shop.where(
		{
			&"kind": &"consumable",
			&"price": func(price: int) -> bool:
				return price < 20,
		},
	)
	assert_array(cheap_consumables).is_equal([&"potion"])


func test_where_returns_empty_when_a_property_is_not_indexed() -> void:
	assert_array(_shop.where({ &"kind": &"consumable", &"damage": 12 })).is_empty()


func test_deprecated_filters_match_their_replacements() -> void:
	var is_expensive := func(price: int) -> bool:
		return price >= 30
	assert_array(_shop.filter_by(&"price", is_expensive)).contains_exactly_in_any_order(
		_shop.filter(&"price", is_expensive),
	)
	assert_array(_shop.filter_by_value(&"kind", &"weapon")).is_equal(
		_shop.filter(&"kind", &"weapon"),
	)
	assert_array(_shop.filter_by_values({ &"kind": &"consumable", &"stats.power": 8 })).is_equal(
		[&"elixir"],
	)
