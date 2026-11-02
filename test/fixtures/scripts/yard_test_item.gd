# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

class_name YardTestItem
extends Resource
## Test fixture: a named script class, matched by name in class restrictions.

const ItemStats := preload("res://test/fixtures/scripts/item_stats.gd")

@export var price: int = 0
@export var kind: StringName = &""
@export var stats: ItemStats
