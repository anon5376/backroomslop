class_name LoreScrap
extends StaticBody3D
## A margin note on a floor stand. E to read; feeds the field journal.
## Local-only collectible: the journal is personal, progress stays shared.

var scrap_id: int = 0


func _init() -> void:
	# Ray-hit only, like pickups: actors walk through the stand.
	collision_layer = 2
	collision_mask = 0


func prompt_text() -> String:
	return "[E] READ / margin note"


func interact() -> void:
	var camp: Node = get_tree().get_first_node_in_group("campaign")
	if camp != null and camp.has_method("collect_scrap"):
		camp.collect_scrap(scrap_id)
