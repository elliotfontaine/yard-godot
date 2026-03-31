class_name Armor
extends Item

enum ArmorType { CLOTH, LEATHER, CHAINMAIL, PLATE }
enum ArmorSlot { HEAD, CHEST, HANDS, FEET, LEGS, OFFHAND, ACCESSORY }

@export var defense: int = 0
@export var magic_resistance: float = 0.0
@export var armor_type: ArmorType = ArmorType.CLOTH
@export var armor_slot: ArmorSlot = ArmorSlot.CHEST
@export var required_level: int = 1
@export var is_cursed: bool = false
@export var block_chance: float = 0.0
@export var block_amount: int = 0
