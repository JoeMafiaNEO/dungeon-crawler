class_name TransferTrigger
extends Area3D
## The transfer trigger on every playable building's door
## (issue #204 shipped the component + record + doorstep;
## issue #205 S1 wires it): using the door is the party
## transfer INTO the building — party-together (F0), the
## whole party gathers to the ground floor. A second
## building's door cannot be used while the party is inside
## one: the party is in the floor scene then, not the street
## (emergent from the transfer shape, no separate lock).

var building_key := ""
var doorstep := Vector3.ZERO
var record: Dictionary = {}


func prompt_text() -> String:
	return "Enter building"


func interact(player: Node) -> void:
	activate(player)


func activate(_player: Node) -> void:
	if building_key == "":
		return
	if Dungeon.floor_active():
		return # the party is already inside a building
	NetworkManager.rpc("load_floor", building_key, 0, true)
