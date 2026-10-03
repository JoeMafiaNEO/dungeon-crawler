class_name ClassData
extends Resource
## Data-driven player class: base stats, sprite frames, starting weapon.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var tint: Color = Color.WHITE
@export var base_health: float = 100.0
@export var base_damage: float = 10.0
@export var base_move_speed: float = 5.0
@export var base_attack_cooldown: float = 0.5
@export var base_attack_range: float = 2.8
@export var starting_weapon: String = ""
@export var frames: Array[Texture2D] = []
