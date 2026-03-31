class_name Item
extends Resource

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum MagicSchool { NONE, FIRE, WATER, EARTH, AIR, ARCANE, DIVINE, DARK }

@export var texture: Texture2D
@export var name: String = ""
@export_multiline var description: String = ""
@export var base_price: int = 0
@export var weight: float = 0.5
@export var max_stack_count: int = 1
@export var in_inventory_width: int = 1
@export var in_inventory_height: int = 1
@export var rarity: Rarity = Rarity.COMMON
