# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends Object
## Paths, UIDs and helpers shared by the test suites.
##
## Fixture resources declare their UID in their header, so that importing the project registers
## it. Resources saved while the tests run aren't registered (no UID at all outside the editor),
## so they can't be added to a registry.

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO

## Non-recursive scan: potion, elixir, draft_potion, sword, trinket, gradient.
const ITEMS_DIR := "res://test/fixtures/items"
## Recursive scan of [constant ITEMS_DIR] also finds shield.
const NESTED_ITEMS_DIR := "res://test/fixtures/items/nested"
const ITEM_SCRIPT_PATH := "res://test/fixtures/scripts/yard_test_item.gd"
const WEAPON_SCRIPT_PATH := "res://test/fixtures/scripts/yard_test_weapon.gd"
const TRINKET_SCRIPT_PATH := "res://test/fixtures/scripts/unnamed_trinket.gd"
const NODE_SCRIPT_PATH := "res://test/fixtures/scripts/unnamed_node.gd"
## Holds potion, sword and elixir, with kind, price and stats.power indexed. Never pass it to
## RegistryIO, which would overwrite the file.
const SHOP_REGISTRY_PATH := "res://test/fixtures/registries/shop.tres"
const SHOP_REGISTRY_UID := &"uid://yardtestreg1"

# YardTestItem, price 10, consumable, stats.power 3
const POTION_UID := &"uid://yardtestpot1"
# YardTestItem, price 50, consumable, stats.power 8
const ELIXIR_UID := &"uid://yardtestelx1"
# YardTestItem, price 5, consumable, no stats
const DRAFT_POTION_UID := &"uid://yardtestdrf1"
# YardTestWeapon, price 30, weapon, stats.power 8, damage 12
const SWORD_UID := &"uid://yardtestswd1"
# YardTestWeapon, price 40, armor, no stats, in the nested directory
const SHIELD_UID := &"uid://yardtestshd1"
# Unnamed script, price 15
const TRINKET_UID := &"uid://yardtesttrk1"
# Native Gradient
const GRADIENT_UID := &"uid://yardtestgrd1"


## Returns an empty registry with default settings, saved at [param path]. RegistryIO saves the
## registry on every change, so use a path in a temporary directory.
static func new_registry(path: String) -> Registry:
	var registry := Registry.new()
	registry.take_over_path(path)
	RegistryIO.set_registry_settings(registry, RegistryIO.RegistrySettings.new())
	return registry


## Returns default settings whose default ruleset scans [param scan_directory].
static func scan_settings(
	scan_directory: String,
	class_restrictions: Array[StringName] = [],
) -> RegistryIO.RegistrySettings:
	var settings := RegistryIO.RegistrySettings.new()
	settings.default_scan_ruleset.scan_directories = [scan_directory]
	settings.default_scan_ruleset.class_restrictions = class_restrictions
	return settings
