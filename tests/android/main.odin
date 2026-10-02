package main

import "base:runtime"
import "core:fmt"
import ui "../.."
import net "../../vendor/sdl2/net"

main :: proc() {
	app := ui.ui_begin_app("Odin UI Android smoke test", 640, 480)
	if app == nil do return
	defer ui.app_destroy(app)

	if net.Init() != 0 {
		fmt.printfln("SDL2_net initialization failed: %s", net.GetError())
		return
	}
	defer net.Quit()

	for !app.quit {
		ui.app_begin_frame(app)
		ui.text(
			app,
			"Android permissions",
			user_style = {font_size = 28, text_color = ui.hex_rgb(0xF4F1E9)},
		)
		ui.text(app, "This screen is packaged with permissions from the project permissions file.")
		ui.app_end_frame(app)
	}
}

@(export)
odin_app_start :: proc "c" () -> i32 {
	context = runtime.default_context()
	main()
	return 0
}
