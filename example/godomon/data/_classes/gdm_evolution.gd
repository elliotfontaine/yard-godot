# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/atom.svg")
@tool
class_name GdmEvolution
extends Resource

## When the evolution check is run.
enum Trigger {
	LEVEL_UP, ## after the monster gains a level
	ITEM, ## an item is used on the monster
	TRADE, ## the monster is received in a trade
	AFTER_BATTLE, ## after a battle the player did not lose
	EVENT, ## triggered manually from a script
}

## Extra requirement the monster must satisfy. Most take a parameter.
## Available values depend on the trigger.
enum Requirement {
	NONE,
	HAPPINESS, ## happiness is greater than or equal to the parameter
	HOLD_ITEM, ## holds the item (consumed when the evolution happens)
	KNOWS_MOVE, ## knows the move
	KNOWS_ELEMENT, ## knows at least one move of the element
	PARTY_HAS_SPECIES, ## another party member is of the species
	PARTY_HAS_ELEMENT, ## another party member has the element
	LOCATION_FLAG, ## the current map declares the flag
	REGION, ## the current map belongs to the region id
	ATTACK_GREATER, ## Attack is greater than Defense
	ATK_DEF_EQUAL, ## Attack is equal to Defense
	DEFENSE_GREATER, ## Attack is lower than Defense
	FOR_SPECIES, ## the monster traded away was of the species
	CRITICAL_HITS, ## dealt at least that many critical hits in the battle
	DAMAGE_TAKEN, ## took at least that much damage in a battle beforehand
}

## Transient state required when the check runs.
## Available values depend on the trigger.
enum Context {
	ANY,
	MALE,
	FEMALE,
	DAY,
	NIGHT,
	MORNING,
	AFTERNOON,
	EVENING,
	CLEAR_WEATHER,
	SUN,
	RAIN,
	SNOW,
	SANDSTORM,
	CYCLING,
	SURFING,
	DIVING,
	DARKNESS,
}

enum ParamKind {
	NONE,
	INT,
	TEXT,
	ITEM,
	MOVE,
	SPECIES,
	ELEMENT,
}

const ITEMS := "res://example/godomon/data/items.tres"
const MOVES := "res://example/godomon/data/moves.tres"
const MONSTERS := "res://example/godomon/data/monsters.tres"
const ELEMENTS := "res://example/godomon/data/elements.tres"

const ALLOWED_REQUIREMENTS := {
	Trigger.LEVEL_UP: [
		Requirement.NONE,
		Requirement.HAPPINESS,
		Requirement.HOLD_ITEM,
		Requirement.KNOWS_MOVE,
		Requirement.KNOWS_ELEMENT,
		Requirement.PARTY_HAS_SPECIES,
		Requirement.PARTY_HAS_ELEMENT,
		Requirement.LOCATION_FLAG,
		Requirement.REGION,
		Requirement.ATTACK_GREATER,
		Requirement.ATK_DEF_EQUAL,
		Requirement.DEFENSE_GREATER,
	],
	Trigger.ITEM: [Requirement.NONE, Requirement.HAPPINESS],
	Trigger.TRADE: [Requirement.NONE, Requirement.HOLD_ITEM, Requirement.FOR_SPECIES],
	Trigger.AFTER_BATTLE: [Requirement.CRITICAL_HITS],
	Trigger.EVENT: [Requirement.NONE, Requirement.DAMAGE_TAKEN],
}

const ALLOWED_CONTEXTS := {
	Trigger.LEVEL_UP: [
		Context.ANY,
		Context.MALE,
		Context.FEMALE,
		Context.DAY,
		Context.NIGHT,
		Context.MORNING,
		Context.AFTERNOON,
		Context.EVENING,
		Context.CLEAR_WEATHER,
		Context.SUN,
		Context.RAIN,
		Context.SNOW,
		Context.SANDSTORM,
		Context.CYCLING,
		Context.SURFING,
		Context.DIVING,
		Context.DARKNESS,
	],
	Trigger.ITEM: [Context.ANY, Context.MALE, Context.FEMALE, Context.DAY, Context.NIGHT],
	Trigger.TRADE: [Context.ANY, Context.MALE, Context.FEMALE, Context.DAY, Context.NIGHT],
	Trigger.AFTER_BATTLE: [Context.ANY, Context.MALE, Context.FEMALE, Context.DAY, Context.NIGHT],
	Trigger.EVENT: [Context.ANY],
}

## Parameter expected by each requirement. Unlisted requirements take none.
const REQUIREMENT_PARAMS := {
	Requirement.HAPPINESS: ParamKind.INT,
	Requirement.REGION: ParamKind.INT,
	Requirement.CRITICAL_HITS: ParamKind.INT,
	Requirement.DAMAGE_TAKEN: ParamKind.INT,
	Requirement.LOCATION_FLAG: ParamKind.TEXT,
	Requirement.HOLD_ITEM: ParamKind.ITEM,
	Requirement.KNOWS_MOVE: ParamKind.MOVE,
	Requirement.KNOWS_ELEMENT: ParamKind.ELEMENT,
	Requirement.PARTY_HAS_ELEMENT: ParamKind.ELEMENT,
	Requirement.PARTY_HAS_SPECIES: ParamKind.SPECIES,
	Requirement.FOR_SPECIES: ParamKind.SPECIES,
}

## Species the monster evolves into.
@export_custom(Registry.PROPERTY_HINT_CUSTOM, MONSTERS) var target_species: StringName

@export var trigger: Trigger = Trigger.LEVEL_UP:
	set(value):
		trigger = value
		if not requirement in ALLOWED_REQUIREMENTS[trigger]:
			requirement = ALLOWED_REQUIREMENTS[trigger][0]
		if not context in ALLOWED_CONTEXTS[trigger]:
			context = Context.ANY
		notify_property_list_changed()

@export var requirement: Requirement = Requirement.NONE:
	set(value):
		requirement = value
		notify_property_list_changed()

@export var context: Context = Context.ANY

@export_group("Trigger Parameter")
## Minimum level required. 0 = any level-up. LEVEL_UP only.
@export_range(0, 100, 1) var min_level: int = 0
## Item that must be used on the monster. ITEM only.
@export_custom(Registry.PROPERTY_HINT_CUSTOM, ITEMS) var trigger_item: StringName
## Id passed to the script that triggers the evolution. EVENT only.
@export var event_id: int = 0

@export_group("Requirement Parameter")
## Happiness threshold, region id, critical hit count, damage amount...
@export var parameter_int: int = 0
## Item, move, species or element id, depending on the requirement.
@export var parameter_id: StringName
## Custom flag.
@export var parameter_text: String


## The kind of parameter the current requirement expects.
func get_param_kind() -> ParamKind:
	return REQUIREMENT_PARAMS.get(requirement, ParamKind.NONE)


func _validate_property(property: Dictionary) -> void:
	match property.name:
		"requirement":
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = _enum_hint(Requirement, ALLOWED_REQUIREMENTS[trigger])
		"context":
			var allowed: Array = ALLOWED_CONTEXTS[trigger]
			if allowed.size() <= 1:
				property.usage &= ~PROPERTY_USAGE_EDITOR
			else:
				property.hint = PROPERTY_HINT_ENUM
				property.hint_string = _enum_hint(Context, allowed)
		"min_level":
			if trigger != Trigger.LEVEL_UP:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"trigger_item":
			if trigger != Trigger.ITEM:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"event_id":
			if trigger != Trigger.EVENT:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"parameter_int":
			if get_param_kind() != ParamKind.INT:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"parameter_text":
			if get_param_kind() != ParamKind.TEXT:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"parameter_id":
			match get_param_kind():
				ParamKind.ITEM:
					property.hint = Registry.PROPERTY_HINT_CUSTOM
					property.hint_string = ITEMS
				ParamKind.MOVE:
					property.hint = Registry.PROPERTY_HINT_CUSTOM
					property.hint_string = MOVES
				ParamKind.SPECIES:
					property.hint = Registry.PROPERTY_HINT_CUSTOM
					property.hint_string = MONSTERS
				ParamKind.ELEMENT:
					property.hint = Registry.PROPERTY_HINT_CUSTOM
					property.hint_string = ELEMENTS
				_:
					property.usage &= ~PROPERTY_USAGE_EDITOR


func _to_string() -> String:
	var parts: Array[String] = []

	parts.append(str(target_species) if target_species else "UNDEFINED")
	parts.append(Trigger.keys()[trigger])

	match trigger:
		Trigger.LEVEL_UP:
			if min_level > 0:
				parts.append("Lv%d" % min_level)
		Trigger.ITEM:
			parts.append(str(trigger_item) if trigger_item else "?")
		Trigger.EVENT:
			parts.append("#%d" % event_id)

	if requirement != Requirement.NONE:
		var req: String = Requirement.keys()[requirement]
		match get_param_kind():
			ParamKind.NONE:
				parts.append(req)
			ParamKind.TEXT:
				parts.append("%s=%s" % [req, parameter_text])
			ParamKind.INT:
				parts.append("%s=%d" % [req, parameter_int])
			_:
				parts.append("%s=%s" % [req, parameter_id])

	if context != Context.ANY:
		parts.append(Context.keys()[context])

	return "(" + ", ".join(parts) + ")"


## Builds an enum hint restricted to `allowed`, preserving the underlying values.
static func _enum_hint(enum_dict: Dictionary, allowed: Array) -> String:
	var parts: PackedStringArray = []
	for value: int in allowed:
		var key: String = enum_dict.find_key(value)
		parts.append("%s:%d" % [key.capitalize(), value])
	return ",".join(parts)
