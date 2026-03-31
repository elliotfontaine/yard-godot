class_name Consumable
extends Item

enum ConsumableType { POTION, FOOD, SCROLL, INGREDIENT }
enum Effect { NONE, HEALTH, MANA, STRENGTH, SPEED, INVISIBILITY, ANTIDOTE, FIRE_RESIST, COLD_RESIST }

@export var consumable_type: ConsumableType = ConsumableType.INGREDIENT
@export var is_single_use: bool = true
@export var use_description: String = ""
@export_range(0.0, 10.0, 0.1, "or_greater") var cooldown_seconds: float = 0.0
@export var effect: Effect = Effect.NONE
@export var potency: int = 0
@export var duration_seconds: float = 0.0
@export var liquid_color: Color = Color.WHITE
