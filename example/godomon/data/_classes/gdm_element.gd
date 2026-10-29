# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/fire.svg")
class_name GdmElement
extends Resource

const REGISTRY_HINT := Registry.PROPERTY_HINT_CUSTOM
const ELEMENTS := "res://example/godomon/data/elements.tres"

@export var name: String
@export var color: Color
@export var icon: Texture2D

@export_custom(REGISTRY_HINT, ELEMENTS) var strong_against: Array[StringName] # damage x2
@export_custom(REGISTRY_HINT, ELEMENTS) var weak_against: Array[StringName] # damage x0.5
@export_custom(REGISTRY_HINT, ELEMENTS) var immune_targets: Array[StringName] # damage x0
