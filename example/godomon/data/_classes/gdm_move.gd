# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/explosion.svg")
class_name GdmMove
extends Resource

enum Category {
	PHYSICAL,
	SPECIAL,
	STATUS,
}

## Possible move targets
enum Target {
	NONE, ## no real target (e.g. Splash)
	USER, ## self (buffs)
	NEAR_ALLY, ## an adjacent ally
	USER_OR_NEAR_ALLY, ## self or an adjacent ally
	ALL_ALLIES, ## all allies (except self)
	USER_AND_ALLIES, ## self + allies
	NEAR_FOE, ## an adjacent foe
	RANDOM_NEAR_FOE, ## a random adjacent foe
	ALL_NEAR_FOES, ## all adjacent foes
	FOE, ## any foe
	ALL_FOES, ## all foes
	NEAR_OTHER, ## any adjacent battler (ally or foe)
	ALL_NEAR_OTHERS, ## all adjacent battlers
	OTHER, ## anyone except self
	ALL_BATTLERS, ## everyone, self included
	USER_SIDE, ## the ally side (reflect...)
	FOE_SIDE, ## the foe side (spikes...)
	BOTH_SIDES, ## the whole field (weather...)
}

@export var name: String
@export_multiline var description: String
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://example/godomon/data/elements.tres") var type: StringName = &"wild"
@export var category: Category = Category.PHYSICAL

@export_group("Effect")
@export var target: Target = Target.NEAR_FOE
@export var move_handler: StringName = &"none"
@export var flags: Array[StringName]

@export_group("Battle Stats")
@export_range(0, 255, 1) var power: int = 0
@export_range(0, 100, 1) var accuracy: int = 100
@export_range(1, 40, 5) var total_pp: int = 5
@export_range(-6, 6, 1) var priority: int = 0
@export_range(0, 100, 1) var effect_chance: int = 0 ## secondary effect chance in % (0 = always/n.a.)

@export_group("Presentation")
@export var animation: PackedScene # or a StringName into an animation registry
@export var sound: AudioStream
