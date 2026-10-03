class_name Decoy
extends Node3D
## Shadow Step decoy (Double Take family trait): a shadowy afterimage that
## draws mob aggro for 3s. Spawned on all peers via dungeon.rpc("spawn_decoy").

var hp := 40.0
var _life := 3.0
var _sprite: Sprite3D


func setup(owner_peer: int) -> void:
	add_to_group("decoys")
	# Visual: dark translucent copy of the owner's current sprite frame.
	var tex: Texture2D = null
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and dungeon.has_method("get_player_node"):
		var p: Node = dungeon.get_player_node(owner_peer)
		if p != null:
			var ps: Node = p.get("_sprite")
			if ps != null and ps.get("frames") != null:
				var frames: SpriteFrames = ps.get("frames")
				if frames.get_frame_count("default") > 0:
					tex = frames.get_frame_texture("default", 0)
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = false
	if tex != null:
		_sprite.texture = tex
		# Pixel-art sprite is large; match roughly the player's on-screen size.
		var h := tex.get_height()
		if h > 0:
			_sprite.pixel_size = 1.8 / h
	_sprite.modulate = Color(0.35, 0.25, 0.6, 0.75)
	_sprite.position = Vector3(0, 0.9, 0)
	add_child(_sprite)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Fade out over the last second.
	if _life < 1.0 and _sprite != null:
		var c: Color = _sprite.modulate
		c.a = 0.75 * _life
		_sprite.modulate = c


## Melee damage from mobs (called directly, server-side only).
func damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	hp -= amount
	if hp <= 0.0:
		Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.35, 0.25, 0.6), 15, 4.0)
		queue_free()
