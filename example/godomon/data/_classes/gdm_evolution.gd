# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
class_name GdmEvolution
extends Resource

enum Method { LEVEL, ITEM, TRADE, HAPPINESS, LEVEL_DAY, LEVEL_NIGHT, HOLD_ITEM, KNOWS_MOVE, LOCATION }

@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://example/godomon/data/monsters.tres") var target: StringName
@export var method: Method = Method.LEVEL
@export var parameter: int = 0
@export var parameter_id: StringName


func _to_string() -> String:
	var elements := []
	elements.append(target if target else &"UNDEFINED")
	elements.append(str(method))
	if parameter:
		elements.append(str(parameter))
	if parameter_id:
		elements.append(str(parameter_id))
	return "(" + ",".join(elements) + ")"
