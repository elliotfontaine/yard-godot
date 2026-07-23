# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/magic_wand.svg")
class_name GdmAbility
extends Resource

@export var name: String
@export_multiline var description: String
@export var flags: Array[StringName]
@export var ability_handler: StringName = &"none"
