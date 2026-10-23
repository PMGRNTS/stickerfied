This example project was first published on: https://mx176.itch.io/
It was created in Godot 4.6.1. 
It may be used as a base for creating dress-up games in Godot.

Features:
	Create a simple dress-up game from your own art- coding not required
	Replace sample GUI images to customize the look of the user interface
	Use as many layers as you want- scroll bars will appear to accomodate more buttons
	Publish your dress-up game like any other Godot game

This project does not support color grouping of items, but you can add as many 
options to each layer as you'd like. So to offer a red and a green shirt, you 
can simply add both as separate shirt images!

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
Note that there may be duplicate items in the menus when the game is run inside the editor.
Hover over the buttons next to the "play" button to see what the other icons mean.
Find "Remote deploy > Run in browser" near the "play" button to see what the game would 
look like after exporting. When you run the game in browser, the duplicate menu items 
should not be visible anymore.


####################################
#### 5. Share the game (export)
####################################

When you're finished making your dress-up game, you can export it from Godot ( Project > Export... ).
Select "Web" as the export preset if you want to publish it on itch.io, and name the file "index.html".
I like to Export... > Export project... to an empty folder. 
Then just zip those files, and upload the zip to itch.io as a playable html file.
