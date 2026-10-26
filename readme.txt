This example project was first published on: https://mx176.itch.io/
It was created in Godot 4.6.1. 
It may be used as a base for creating dress-up games in Godot.

Features:
	Create a simple dress-up game from your own art- coding not required
	Replace sample GUI images to customize the look of the user interface
	Use as many layers as you want- scroll bars will appear to accomodate more buttons
	Publish your dress-up game like any other Godot game

	Players can recolor items, place stickers, undo/redo, randomize, save outfits, take photos,
	share outfit codes, play dress-up challenges, make new backgrounds and stickers with AI,
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
- AI Create makes a new background or sticker from a description (see below)
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
- Drag a box over empty space to select several stickers (Shift + drag adds to the selection).
  Shift + click adds or removes one sticker, Ctrl+A (Cmd+A on Mac) selects them all and
  Escape lets go. Selected stickers move, resize, turn, copy, mirror and delete together.
- Add your own sticker art to the "stickers" folder (transparent png or svg, any size).
  An icon.png in that folder replaces the star category button.
- Stickers are saved with outfits and included in share codes.

Saved outfits, photos and AI pictures are stored in the player's user:// folder
(in the browser's storage for web games), never in the game files.

AI backgrounds and stickers:
The AI Create window (also opened by the sparkle button in the background and
sticker menus) uses OpenRouter ( https://openrouter.ai ), which offers
many image models with one account. Each player pastes their own OpenRouter API key
(from https://openrouter.ai/keys); it is only stored on their device.
New backgrounds are added to the first background folder's menu, new stickers to the
sticker menu, and both are kept for next time. They have a small "x" button for deleting them.
- Stickers need a picture without a background. Models marked "(transparent)" in the list
  can make one (the default is openai/gpt-image-1-mini). With other models the game asks
  for a plain white background and removes it, which works best for items with an outline.
- Change the default models and the text added to every prompt by selecting
  Popups/AICreateDialog in dress_up.tscn and editing it in the Inspector.
- Styles are listed at the top of script/ai_create_dialog.gd.
- Don't put your own API key into the game files: anyone can read it from an
  exported game. To pay for players' images yourself, run a small proxy server
  that holds the key, and set "Base Url" on the OpenRouterClient node
  (inside GUI/ai_create_dialog.tscn) to the proxy's address.

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
