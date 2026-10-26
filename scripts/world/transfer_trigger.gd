class_name TransferTrigger
extends Area3D
## Issue #204 (P4): the transfer-trigger component stub on
## every playable building's doorstep — the whole of the P5
## interface that ships in P4, alongside the building record
## and the doorstep point. P4 places the component and fills
## its fields; P5 S1 wires activate() to the floor transfer.
## Deliberately inert until then: the door is present and
## honest, the promise it makes is P5's to keep.

var building_key := ""
var doorstep := Vector3.ZERO
var record: Dictionary = {}


func activate(_player: Node) -> void:
	pass # P5 S1 wires the building transfer here.
