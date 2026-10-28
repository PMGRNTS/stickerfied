# A sticker's picture, drawn on a grid of points bent along with the doll (see sticker_stage.gd),
# so a sticker on the waist gets wider with the waist and one on the chest breathes with it.
# It is a child of the sticker's Sprite2D, which isn't drawn itself: the sprite is the
# sticker's straight frame, for clicking it, its handles and erasing it.

extends "res://script/doll_layer.gd"

var still := PackedVector2Array() # the grid's points with the doll standing still
var inhaled := PackedVector2Array() # the same with the doll breathed in, or empty when breathing doesn't move them

# Shows the grid breathed in by amount (0 to 1)
func breathe(amount:float) -> void:
	if inhaled.is_empty():
		return
	var moved := PackedVector2Array()
	moved.resize(len(still))
	for k in len(still):
		moved[k] = still[k].lerp(inhaled[k], amount)
	set_points(moved)
