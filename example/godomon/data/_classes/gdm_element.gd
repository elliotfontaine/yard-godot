# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/fire.svg")
class_name GdmElement
extends Resource

@export var name: String
@export var color: Color
@export var icon: Texture2D

@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://example/godomon/data/elements.tres") var strong_against: Array[StringName] # damage x2
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://example/godomon/data/elements.tres") var weak_against: Array[StringName] # damage x0.5
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://example/godomon/data/elements.tres") var immune_targets: Array[StringName] # damage x0
