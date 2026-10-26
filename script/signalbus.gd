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
