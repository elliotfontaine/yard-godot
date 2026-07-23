# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/gem.svg")
class_name GdmItem
extends Resource

## How the item can be used from the bag in the overworld
enum FieldUse {
	NONE, ## not usable in the field
	ON_MONSTER, ## used on a party member (potions, evolution stones...)
	DIRECT, ## used directly, no target (repel, escape rope...)
	TM, ## teaches a move, reusable
	HM, ## teaches a move, reusable and unforgettable
	TR, ## teaches a move, single-use
}

## How the item can be used during battle
enum BattleUse {
	NONE, ## not usable in battle
	ON_MONSTER, ## used on a party member (potions, revives...)
	ON_MOVE, ## used on one of a party member's moves (ethers...)
	ON_BATTLER, ## used on an active battler (Stat boost...)
	ON_FOE, ## used on a foe (capture capsule)
	DIRECT, ## used directly, no target (escape items...)
}

@export var name: String
@export var name_plural: String
@export_multiline var description: String

@export_group("Effect")
@export var field_use: FieldUse = FieldUse.NONE
@export var battle_use: BattleUse = BattleUse.NONE
@export var flags: Array[StringName]
##Identifier for the item's effect
@export var item_handler: StringName = &"none"
## Whether the item is consumed when used.
@export var consumable: bool = true
## The move taught, if this item is a TM/HM/TR (field_use above)
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://example/godomon/data/moves.tres") var move: StringName

@export_group("Bag")
## Bag pocket this item is sorted into (adapt to your bag structure)
@export var pocket: StringName = &"misc"
## Whether the quantity is shown in the bag (hidden for key items)
@export var show_quantity: bool = true

## Optional. For items counted in containers rather than units
## (e.g. name = "Stardust", portion_name = "bag of Stardust")
@export_group("Portion Naming")
@export var portion_name: String
@export var portion_name_plural: String

@export_group("Economy")
@export var price: int = 0 # buy price; 0 = cannot be bought
@export var sell_price: int = -1 # -1 = defaults to price / 2
@export_group("", "")

@export_group("Presentation")
@export var icon: Texture2D
@export var use_sound: AudioStream
