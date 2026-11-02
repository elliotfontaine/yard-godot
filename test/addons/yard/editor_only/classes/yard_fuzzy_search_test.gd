# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const YardFuzzySearch := Namespace.YardFuzzySearch
const FuzzySearchResult := YardFuzzySearch.FuzzySearchResult

const MONSTERS: PackedStringArray = ["Bulbasaur", "Ivysaur", "Charmander", "Charizard", "Squirtle"]


func _search_all(query: String, targets: PackedStringArray, max_misses: int = 2) -> Array[String]:
	var fuzzy := YardFuzzySearch.new()
	fuzzy.max_misses = max_misses
	fuzzy.set_query(query)
	var results: Array[FuzzySearchResult] = []
	fuzzy.search_all(targets, results)
	var matched_targets: Array[String] = []
	for result: FuzzySearchResult in results:
		matched_targets.append(result.target)
	return matched_targets


func test_search_matches_a_substring() -> void:
	var fuzzy := YardFuzzySearch.new()
	fuzzy.set_query("saur")
	assert_bool(fuzzy.search("Bulbasaur", FuzzySearchResult.new())).is_true()
	assert_bool(fuzzy.search("Ditto", FuzzySearchResult.new())).is_false()


func test_search_all_returns_only_matches() -> void:
	assert_array(_search_all("saur", MONSTERS)).contains_exactly_in_any_order(
		["Bulbasaur", "Ivysaur"],
	)
	assert_array(_search_all("xyz", MONSTERS)).is_empty()


func test_lowercase_query_ignores_case() -> void:
	assert_array(_search_all("squirtle", MONSTERS)).is_equal(["Squirtle"])


func test_query_with_uppercase_is_case_sensitive() -> void:
	assert_array(_search_all("Squirtle", ["Squirtle", "squirtle"], 0)).is_equal(["Squirtle"])


func test_every_token_must_match() -> void:
	assert_array(_search_all("char mand", MONSTERS, 0)).is_equal(["Charmander"])


func test_subsequences_can_skip_characters_of_the_target() -> void:
	assert_array(_search_all("chrmndr", MONSTERS, 0)).is_equal(["Charmander"])


func test_misses_tolerate_query_characters_absent_from_the_target() -> void:
	assert_array(_search_all("charmanxer", MONSTERS)).contains(["Charmander"])
	assert_array(_search_all("charmanxer", MONSTERS, 0)).is_empty()


func test_exact_matching_rejects_subsequences() -> void:
	var fuzzy := YardFuzzySearch.new()
	fuzzy.allow_subsequences = false
	fuzzy.set_query("chrm")
	assert_bool(fuzzy.search("Charmander", FuzzySearchResult.new())).is_false()
	fuzzy.set_query("charm")
	assert_bool(fuzzy.search("Charmander", FuzzySearchResult.new())).is_true()


func test_results_are_ranked_best_first() -> void:
	var results := _search_all("pot", ["teapot", "draft_potion", "potion"])
	assert_str(results.front()).is_equal("potion")


func test_max_results_limits_the_results() -> void:
	var fuzzy := YardFuzzySearch.new()
	fuzzy.max_results = 1
	fuzzy.set_query("saur")
	var results: Array[FuzzySearchResult] = []
	fuzzy.search_all(MONSTERS, results)
	assert_int(results.size()).is_equal(1)
