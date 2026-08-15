/*
Raylib example file.
This is an example main file for a simple raylib project.
Use this as a starting point or replace it with your code.

by Jeffery Myers is marked with CC0 1.0. To view a copy of this license, visit https://creativecommons.org/publicdomain/zero/1.0/

Odin port: the original C quickstart (src/main.c) converted to Odin.

Raygui integration: the raygui bindings ship with the Odin toolchain inside the
`vendor:raylib` package directory (vendor/raylib/raygui.odin), so its symbols
are exposed on the same `rl` import and link the prebuilt libraygui static lib.
Controls used here: GuiButton() and GuiMessageBox().
*/

package main

import rl "vendor:raylib"

main :: proc() {
	// Tell the window to use vsync, work on high DPI displays, and allow resizing
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})

	// Create the window and OpenGL context
	rl.InitWindow(800, 600, "Hello Raylib")

	// Maximize the window to fill the monitor (not fullscreen mode).
	// Requires the WINDOW_RESIZABLE flag set above.
	rl.MaximizeWindow()

	// Utility function to find the resources folder and set it as the current
	// working directory so we can load from it
	search_and_set_resource_dir("resources")

	// Load a texture from the resources directory
	wabbit := rl.LoadTexture("wabbit_alpha.png")
	defer rl.UnloadTexture(wabbit)

	// Raygui: the button opens a message box modal
	show_message_box := false
	message_box_bounds := rl.Rectangle{200, 150, 400, 180}

	// game loop: run until the user presses ESCAPE or presses the Close button on the window
	for !rl.WindowShouldClose() {
		// drawing
		rl.BeginDrawing()

		// Setup the back buffer for drawing (clear color and depth buffers)
		rl.ClearBackground(rl.BLACK)

		// draw some text using the default font
		rl.DrawText("Hello Raylib", 200, 200, 20, rl.WHITE)

		// draw our texture to the screen
		rl.DrawTexture(wabbit, 400, 200, rl.WHITE)

		// Raygui: while the message box is open it is the only gui drawn, so
		// the trigger button underneath is not clickable (modal behaviour)
		if show_message_box {
			// Dim the background behind the modal
			rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{0, 0, 0, 100})

			// GuiMessageBox() draws the modal window and returns:
			//   -1 while it is still open,
			//    0 when closed via the window X button,
			//    1, 2, ... when the Nth button in the string is pressed
			if rl.GuiMessageBox(message_box_bounds, "Message Box", "Raygui says hello!", "OK;Cancel") >= 0 {
				show_message_box = false
			}
		} else {
			// Raygui button, returns true on the frame it is clicked
			if rl.GuiButton({300, 520, 200, 30}, "Show Message Box") {
				show_message_box = true
			}
		}

		// end the frame and get ready for the next one (display frame, poll input, etc...)
		rl.EndDrawing()
	}

	// destroy the window and cleanup the OpenGL context
	rl.CloseWindow()
}

// search_and_set_resource_dir looks for the specified resource dir in several common
// locations: the working dir, the app dir, and up to 3 levels above the app dir.
// When found the dir is set as the working dir so that assets can be loaded relative to it.
// Returns true if a dir with the name was found, false if no change was made to the working dir.
search_and_set_resource_dir :: proc(folder_name: cstring) -> bool {
	// check the working dir
	if rl.DirectoryExists(folder_name) {
		rl.ChangeDirectory(rl.TextFormat("%s/%s", rl.GetWorkingDirectory(), folder_name))
		return true
	}

	app_dir := rl.GetApplicationDirectory()

	// check the applicationDir
	dir := rl.TextFormat("%s%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) {
		rl.ChangeDirectory(dir)
		return true
	}

	// check one up from the app dir
	dir = rl.TextFormat("%s../%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) {
		rl.ChangeDirectory(dir)
		return true
	}

	// check two up from the app dir
	dir = rl.TextFormat("%s../../%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) {
		rl.ChangeDirectory(dir)
		return true
	}

	// check three up from the app dir
	dir = rl.TextFormat("%s../../../%s", app_dir, folder_name)
	if rl.DirectoryExists(dir) {
		rl.ChangeDirectory(dir)
		return true
	}

	return false
}
