This example project was first published on: https://mx176.itch.io/
It was created in Godot 4.6.1. 
It may be used as a base for creating dress-up games in Godot.

Features:
	Create a simple dress-up game from your own art- coding not required
	Replace sample GUI images to customize the look of the user interface
	Use as many layers as you want- scroll bars will appear to accomodate more buttons
	Publish your dress-up game like any other Godot game

	Players can recolor items, reshape the doll, place stickers, undo/redo, randomize, save outfits, take photos,
	share outfit codes, play dress-up challenges, make new backgrounds, stickers and doll items with AI,
	add their own drawings and photos to any menu,
	and let an AI stylist dress the doll or judge the look (see "Extra features" below)

Every layer (except backgrounds) has a row of color swatches that recolor the
item: colorful parts take on the new hue, while black, white and gray parts
(outlines, eye whites) stay as they are. To offer items that recolor nicely,
draw them in one color with dark outlines. You can still add separate images
for each color if you prefer.

Example:
	The alien has 2 skin color options, 2 face options and multiple hair options.
	The background will be shown behind the alien, so background folder is named 00Background.
	The skin is the lowest layer to display, so the folder is named 01Skin.
	The alien has 2 skin color options, so it has 2 separate images in the 01Skin folder.
	All of the skin, face and hair options have separate png files. The dimensions of these files are the same.
	The background images can be jpg or png files.
	There is also an image called "icon.png" in each folder; this represents the folder in the menus.
	So for the alien's hair, there is a folder called "03Hair", and inside that folder
	an icon.png that looks like an alien with a hair tuft.


####################################
#### How it works
####################################
1. Create your dress-up art in the program of your choice, and export as transparent PNG files.
2. Add the images to "images" folder, where each layer has its own folder (see the examples in folders)
3. Open the project in Godot editor and make any changes you want
4. Run and play the game!
5. Share the game (export)

Look below for more info on each of these steps.


####################################
#### How it works ... slightly more technical explanation
####################################
The game starts from the dress_up.tscn file. This is a Godot specific scene file, 
which can be edited and previewed in 2D view (see top center of the editor to switch between 2d, 3d, Script and Game windows).
dress_up.gd is a code file that reads through the "images" folder. 
Each subfolder becomes a category, such as 01skin, 03hair.
Folders with names starting 00 are treated as background images and are displayed from
the top left corner of the screen. All the rest of the folders will be drawn in the same
position as the "SpritePlaceHolder" object in dress_up.tscn. This way repositioning SpritePlaceholder item
in the Godot editor allows the user to move and scale the doll in the Godot editor without 
having to touch any code.
The buttons are generated through code and are set up to send "signals" when pressed. 
"signalbus.gd" is set as global (Project > Project settings > Globals), so that 
all generated buttons can easily be connected to the same signal through code.
When a button is pressed (button_base.gd), it emits a signal to "signalbus";
other elements (interactivity.gd) can then "listen" to signalbus and react to the signals.




####################################
#### 1. Create your dress-up art
####################################
I made the example images in Krita, which is free and open source.
Create a new folder for each of the layers you wish to show, and number the folders.
In the examples, I used 00Backgrounds, 01Skin, 02Face and 03Hair as folder names.
You can use whatever names you like, but FOLDERS STARTING WITH TWO ZERO 00 WILL BE TREATED AS BACKGROUND.

Whatever program you use, keep in mind:
- Export the files as transparent PNG files. Krita has a tool for this: Tools > Scripts > Export Layers
- Exported parts must all be the same size in pixels, or they may not show up correctly.
- Background images can be a different size, but their folder name must START with two zeroes 00.


####################################
#### 2. Add the images to "images" folder
####################################

Each folder in the "images" folder represents a layer of your doll.
The folders show up in alphabetical order, so the easiest way to keep them in order is numbering them.
Folders beginning with 00 will be displayed below folders beginning with 01, and so on.
Only background images should be placed in folders beginning with 00.

Remember to add a "icon.png" file to each folder!
It will be used as a button for that category.




####################################
#### 3. Open the project in Godot and make any changes you want
####################################

You need to open the project in Godot. I recommend getting the latest version.
Godot game engine's official site: https://godotengine.org/

Here are some easy changes to try in the editor:
- Change the size of the game window:
	 Project > Project settings > General > Display > Window > Size: Viewport width & height
- Reposition / scale the "SpritePlaceholder" node. Your own doll will show up in that spot when you run the game!
- Reposition the "ButtonTray" node to move the menu to a different spot on the screen

Note that to change the background images/color of the menu or buttons, you
can either edit the game's theme (look up tutorials on editing Godot themes)
or replace the images button_BG.png and menu_BG.png in the GUI folder.
Don't be afraid to experiment! Godot has plenty of options to fiddle with even without coding knowledge.


####################################
#### 4. Run and play the game
####################################

When you press the "play" button in Godot's top right corner, your new dress-up game should start!
Hover over the buttons next to the "play" button to see what the other icons mean.
Find "Remote deploy > Run in browser" near the "play" button to see what the game would 
look like after exporting.


####################################
#### 5. Share the game (export)
####################################

When you're finished making your dress-up game, you can export it from Godot ( Project > Export... ).
Select "Web" as the export preset if you want to publish it on itch.io, and name the file "index.html".
I like to Export... > Export project... to an empty folder. 
Then just zip those files, and upload the zip to itch.io as a playable html file.


####################################
#### Extra features
####################################

Layers:
- Backgrounds (folders starting with 00) and the doll's body (the first folder
  after the backgrounds, 01Skin in the example) always show something.
  The game starts with the first image of each of these.
- Every other layer gets a "nothing" button, so items can be taken off.
- Under the color swatches, the rainbow slider picks any color, and "Keep"
  makes Random leave that layer as it is.
- The game remembers the outfit the player was wearing and starts with it next time.
  To always start fresh, select Interactivity in dress_up.tscn and untick
  "Remember Last Outfit" in the Inspector.
- Images can be png, jpg, jpeg, webp or svg. A file named icon.png is the
  category button, not an item.
- Item buttons zoom in on the drawn part of each image, so small items
  are easy to see. The doll still uses the whole image.

Tool buttons (move or restyle them in GUI/toolbar.tscn; their look is the
"ToolButton" style in theme.tres):
- Undo / Redo (also Ctrl+Z and Ctrl+Shift+Z), Random, Reset
- The speaker button turns sound on and off (remembered for next time)
- Save keeps the outfit with a small picture; Outfits lists saved outfits
- Share gives a code (starting with DU1-) that a friend can paste to wear the same outfit
- Photo saves a picture without the menus (a download in the browser)
- AI Create makes a new background, sticker or doll item from a description (see below)
- AI Stylist dresses the doll for an occasion, or judges the outfit (see below)
- Challenge (bottom left) gives a theme to dress up for before the time runs out.
  Press Judge for an AI score, or take a Photo. Change the themes and the time
  by selecting ChallengeBar in GUI/toolbar.tscn ("Seconds" 0 means no time limit).

Stickers:
The star category button (the last one) holds stickers: accessories that can be
placed anywhere on the doll, unlike layers.
- Click a sticker in the menu to put it on the doll. Drag it to move it.
- Drag the round handle at its corner to resize and turn it.
  The mouse wheel also resizes it, and Shift + mouse wheel turns it.
- The red handle (or the Delete key) takes it off. Clicking a sticker brings it to the front.
- The green handle (or the D key) makes a copy. The handle at the bottom left (or the F key)
  mirrors it.
- The eraser handle at the top (or the E key) rubs out parts of a sticker, such as the inside
  of a collar or hem. Paint over what should go (scroll or use the slider to change the eraser's
  size), then press Done. Every copy of that sticker changes. The game's own stickers stay as
  they are: the erased one is added to the menu as a new sticker.
- Drag a box over empty space to select several stickers (Shift + drag adds to the selection).
  Shift + click adds or removes one sticker, Ctrl+A (Cmd+A on Mac) selects them all and
  Escape lets go. Selected stickers move, resize, turn, copy, mirror and delete together.
- Add your own sticker art to the "stickers" folder (transparent png or svg, any size).
  An icon.png in that folder replaces the star category button.
- Stickers are saved with outfits and included in share codes.

Body shaping:
The Body menu (the last category button) has sliders that reshape the doll:
head size, shoulders, waist, hips, legs and height, eye size, eye spacing,
mouth size, mouth height, cheeks, squint and smile, and a head tilt and lean to pose it.
The doll blinks and breathes, and long hair swings when the doll moves.
Every layer bends the same way, so the hair, face and clothes still fit, and
stickers move, turn and grow with the part of the doll they are on.
Dragging a slider shows the change; letting go puts it on, so it can be undone.
Double-click a slider to put it back; "As drawn" puts everything back, sculpting too.
The shape is saved with outfits and included in share codes, and Random leaves it alone.
- Fit points (in the Body menu) lets players move the sliders' points onto their own doll,
  for bodies that aren't shaped like the one the points were placed on, such as a body
  made with AI or uploaded. The doll is shown as drawn, and one point is worked on at a
  time: its areas are shown and the other points are small dots (points in the same spot,
  like everything on one eye, share a dot). Tap a dot, or step with Prev and Next (Tab and
  Shift+Tab), to work on another; hovering over a dot shows what it is. Drag the point's
  circle, or anywhere inside its area, onto the matching part of the doll (arrow keys nudge
  it), and drag its small square (or turn the mouse wheel) to make its area bigger or smaller.
  Find parts puts the points on the doll by itself: it follows the body's outline (the neck
  is the narrowest place under the head, the legs part at the crotch, the waist is the
  narrowest place above them) and looks for the eyes and mouth on the face, in the face
  layer or drawn on the body. Standard puts them where they usually are on a doll standing
  straight and facing forward, sized to the doll. Both work best on such a doll; fix up
  whatever they get wrong by hand. Done keeps the fit, Reset puts the points back where
  they were placed in the scene, Cancel (or Escape) forgets the changes.
  Each body picture keeps its own fit, on the player's device only.
- Sculpt (in the Body menu) is a brush for pushing the doll into any shape: drag on the
  doll to push it, and size the brush with the slider or the mouse wheel. With Restore on,
  the brush eases pushed parts back to how they were drawn. Undo takes back a stroke and
  Clear all of them. Done puts the sculpting on (it can be undone like any change, and is
  saved with outfits and share codes); Cancel (or Escape) forgets it. The sliders still
  work on the sculpted doll, and every layer and sticker follows it.
- The sliders come from the "controls" under the BodyShaper node in dress_up.tscn.
  Each one is drawn as an oval or lines over the doll in the editor; move
  them over the matching part of your own doll, or add more. Select one to set it
  up in the Inspector (the top of script/body_control.gd explains each setting):
  - Slider: the slider's name. Controls with the same name move together (both eyes).
  - Group: the heading it is listed under, such as Body, Face or Pose.
  - Shape: an Area changes the part of the doll inside its oval (Reach is the oval's
    half width and height); a Strip changes everything between its two lines, such as
    the legs, and moves what is beyond them out of the way. Anchor is the strip's edge
    that stays put (the feet stay on the ground with Bottom Or Right). A Turn turns
    everything above it, like the head on the neck: put it where the turn happens.
  - Stretch makes the part wider or taller (0.2 is 20% bigger with the slider all the
    way right, 20% smaller all the way left), Move shifts it (in pixels),
    Bend lifts its left and right ends more than its middle (in pixels, like the
    corners of a smile), and Turn turns it (in degrees).
  - Landmark: the part of the doll the control sits on (Head, Left Eye, Waist...). Find parts
    and Standard put it on that part of the player's doll; controls on the same landmark go
    to the same spot and keep their sizes compared to each other. None leaves it where it is.
  - Soft Edge: how much of an Area's oval fades out. Lower it to move a whole part,
    such as the mouth, without bending it. For a Turn, it fades the turn out towards
    the sides (Reach.x), so arms sticking out don't swing as far as the head.
  - Swing (an Area with no Slider): the layers named in Swing Layers ("Hair", or several
    words separated by commas) hang loose inside the oval, from its top edge. They move
    with what is above them, so long hair follows the head as it tilts, then lag behind
    and swing back. The example's HairSwing covers the long hair.
- A Turn's Reach.y is the band around it where the turn fades in.
- Controls are applied from the top of the list down (all Areas, then Turns, then Strips),
  and each one moves along with what the ones above it moved. List bigger parts first:
  the head's size before the eyes on it, and the head's turn before the whole body leaning.
- Blinking: select BodyShaper and set "Blink Slider" to the slider that closes the eyes
  (Squint in the example: its Stretch.y of -0.9 squashes the eyes nearly shut). Blinking
  moves it all the way right for a moment, then back. Leave it empty for no blinking.
  "Blink Every" is the shortest and longest wait between blinks, in seconds.
- Breathing works the same way with "Breathe Slider" (Breathing in the example) and
  "Breath Time": its controls go from the middle to all the way right and back again.
  Leave its controls' Group empty, so it isn't listed in the Body menu.
- Areas fade out towards their edge, so keep each oval clear of parts it shouldn't change
  (the eyes' ovals stop above the mouth). If your faces or clothes differ a lot,
  make the ovals big enough for all of them.
- Height and Legs make the doll taller, so leave some room above it on the screen.
- With no controls under BodyShaper, there is no Body menu.
- Pictures players add to the doll are lined up with the doll as drawn: the doll goes
  back to its drawn shape while one is placed, then reshapes with the new item on.

Players' own pictures:
The first button in every menu (a picture with an arrow) adds a picture from the
player's computer or phone: png, jpg, webp or svg. Dropping a picture file on the
game window adds it to the menu that is open.
- Backgrounds are scaled to cover the screen.
- Stickers are trimmed and placed on the doll.
- Doll items (hair, faces, clothes...) are put in place by the player: the menus hide,
  the picture appears on the doll, and the player drags it into place, resizes it with the
  mouse wheel or the corner handle, and presses Done (or Enter; Escape cancels).
  Erase rubs out parts of it right on the doll, such as the inside of a collar that shows
  above the neck.
  A picture that is exactly the size of the doll's images skips this step and lines up
  by itself, so art drawn over the doll's template fits straight away.
- A plain background, such as white paper, is removed from stickers and doll items.
  A drawing on clean white paper with a dark outline works best; a photo of paper
  with shadows may keep some of the paper.
- They can be recolored like the game's own items, and have a small "x" for deleting them.
- The file name becomes the item's name ("red_beret.png" is "red beret"), which the
  AI Stylist reads.
- Like AI pictures, they only exist on the player's device: a share code that uses one
  shows the outfit without it on another device.

Saved outfits, photos, AI pictures and players' own pictures are stored in the player's user:// folder
(in the browser's storage for web games), never in the game files.

AI backgrounds, stickers and doll items:
The AI Create window (also opened by the sparkle button in the menus) uses OpenRouter ( https://openrouter.ai ), which offers
many image models with one account. Each player pastes their own OpenRouter API key
(from https://openrouter.ai/keys); it is only stored on their device.
Under "AI settings", Provider can instead be fal ( https://fal.ai ), Replicate ( https://replicate.com )
or RunPod ( https://runpod.io ), which run any model you name, including ones you trained yourself.
Each has its own API key ("Get a key" opens the right page). Type the model instead of picking it:
- fal: the model's id from its page, such as fal-ai/flux/dev or fal-ai/flux-lora.
- Replicate: owner/model (its latest version), or owner/model:version for one exact version.
- RunPod: the ID of your serverless endpoint (Endpoint).
The game sends the prompt and the picture's size with the names most image models use (prompt,
image_size on fal; aspect_ratio, width and height on Replicate; width and height on RunPod).
Anything else your model needs goes in Extra, written as JSON. It's added to what the game
sends and replaces anything with the same name, for example a LoRA on fal-ai/flux-lora:
  {"loras": [{"path": "https://.../my_style.safetensors", "scale": 0.9}]}
The game finds the picture in the model's answer by itself, whether it's a link or base64 data.
Each kind of picture (background, sticker, doll item) remembers its own model and Extra.
These providers can't make see-through pictures, so the game asks for a plain white
background and removes it, as with OpenRouter models that aren't marked "(transparent)".
New backgrounds are added to the first background folder's menu, new stickers to the
sticker menu, and all of them are kept for next time. They have a small "x" button for deleting them.
- Doll items: pick "Doll item" and a layer (the sparkle button in a layer's menu picks it
  for you), and describe it. The new item is put on the doll to be moved into place and
  resized, the same way as players' own pictures (see above); Done adds it to that
  layer's menu. It can be recolored like any other item. AI models don't know your
  doll's exact shape, so the player lines it up by hand.
- Stickers and doll items are asked to be drawn flat, like paper doll cutouts, so clothes
  don't show their inside through the neck or hem ("Flat Prompt" in the Inspector, see below).
  The Shiny 3D and Photo styles keep their depth and use "Depth Prompt" instead, which still
  asks for closed openings.
  Models still get this wrong sometimes: the eraser (see Stickers and Players' own pictures)
  cleans up what's left.
- Stickers and doll items need a picture without a background. Models marked "(transparent)" in the list
  can make one (the default is openai/gpt-image-1-mini). With other models the game asks
  for a plain white background and removes it, which works best for items with an outline.
- Change the default models and the text added to every prompt by selecting
  Popups/AICreateDialog in dress_up.tscn and editing it in the Inspector.
- Styles are listed at the top of script/ai_create_dialog.gd. Sticker styles that shouldn't be
  drawn flat go in DEPTH_STYLES there too.
- Don't put your own API key into the game files: anyone can read it from an
  exported game. To pay for players' images yourself, run a small proxy server
  that holds the key, and set "Base Url" on the OpenRouterClient node
  (inside GUI/ai_create_dialog.tscn) to the proxy's address. For fal, Replicate and RunPod, set
  "Fal Url", "Replicate Url" or "Runpod Url" on the CustomImageClient node next to it.
- Replicate doesn't accept requests from web pages, so in the web version it only works through
  such a proxy (it works in downloaded games). If another provider can't be reached from the web
  version, a proxy fixes that too.

AI Stylist:
Uses the same OpenRouter key as AI Create, and a text model that can look at pictures
(the default is anthropic/claude-haiku-5.5; change "Text Model" by selecting
Popups/AIStylistDialog in dress_up.tscn).
- Dress me: the player says where the doll is going ("a picnic in the park"), and the
  stylist picks items and colors from the game's own menus. It reads the file names, so
  name your art files clearly (red_beret.png, not item7.png). AI backgrounds and stickers
  are described by the prompt they were made from. The change can be undone like any other.
- Judge me: a picture of the doll (without the menus) is sent to the model, which gives
  a score out of 10, a name for the look and a friendly tip. During a challenge it
  judges how well the outfit fits the theme.
- The instructions given to the model can be edited in the Inspector too.

Sounds:
The game makes its own small sound effects (pop, click, shutter, sparkle) with code
( script/sound_effects.gd ), so no audio files are needed. To use your own, make a
"sounds" folder and add files with those names, for example sounds/pop.ogg or
sounds/click.wav. They are used instead of the built-in sounds automatically.
