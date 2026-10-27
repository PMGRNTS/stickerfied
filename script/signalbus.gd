# This code is set as "global" in the project settings so all scripts can access it.


extends Node

# we DO connect to these signals through script in other nodes,
# so we don't need to see the warning about an "unused" signal
@warning_ignore("unused_signal")
signal dressup_item_signal(signalobject, operation)

# Sent by the color swatches under each item grid.
# hue is a value from 0 to 1, or -1 for "original colors".
@warning_ignore("unused_signal")
signal dressup_color_signal(layer, hue)

# Sent while the player drags a color slider, before letting go.
# The doll shows the color, but the outfit doesn't change yet.
@warning_ignore("unused_signal")
signal dressup_color_preview_signal(layer, hue)

# Sent by the Body menu's sliders with every slider's value (name -> -1..1)
# when the player lets go of a slider, so the doll's new shape can be undone.
@warning_ignore("unused_signal")
signal dressup_body_signal(values)

# Sent while a Body slider is dragged: the doll shows the shape, but the outfit doesn't change yet.
@warning_ignore("unused_signal")
signal dressup_body_preview_signal(values)
