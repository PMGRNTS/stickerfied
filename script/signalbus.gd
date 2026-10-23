# This code is set as "global" in the project settings so all scripts can access it.


extends Node

# we DO connect to this signal through script in other nodes,
# so we don't need to see the warning about an "unused" signal
@warning_ignore("unused_signal") 
signal dressup_item_signal(signalobject, operation)
