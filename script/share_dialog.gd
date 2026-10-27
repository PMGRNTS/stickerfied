# Pop-up for share codes: copy a code for the current outfit,
# or paste a friend's code to wear their outfit.

extends OverlayDialog

@export var interactivity: Node

func _ready() -> void:
	super()
	%CopyButton.pressed.connect(copy_code)
	%LoadButton.pressed.connect(load_code)
	%PasteEdit.text_submitted.connect(func(_text): load_code())
	%CloseButton.pressed.connect(close)

func _on_open() -> void:
	%CodeEdit.text = OutfitStore.to_share_code(interactivity.outfit)
	%PasteEdit.text = ""
	%StatusLabel.text = ""

func copy_code() -> void:
	DisplayServer.clipboard_set(%CodeEdit.text)
	%StatusLabel.text = "Copied! Send it to a friend."

func load_code() -> void:
	var outfit = OutfitStore.from_share_code(%PasteEdit.text)
	if outfit.is_empty():
		%StatusLabel.text = "That code doesn't look right. Codes start with " + OutfitStore.SHARE_CODE_PREFIX
		return
	interactivity.set_outfit(outfit)
	# Items that aren't in this game (or AI items made on another device) are skipped
	var worn = interactivity.cleaned_outfit(outfit)
	var missing = 0
	for layer in outfit:
		if layer == interactivity.STICKERS:
			missing += len(outfit[layer]) - len(worn[layer])
		elif layer == interactivity.BODY:
			continue
		elif outfit[layer].item != "" and worn.get(layer, {}).get("item", "") != outfit[layer].item:
			missing += 1
	%StatusLabel.text = "Outfit loaded!" if missing == 0 else \
		"Outfit loaded, but %d item(s) aren't in this game and were skipped." % missing
	%CodeEdit.text = OutfitStore.to_share_code(interactivity.outfit)
