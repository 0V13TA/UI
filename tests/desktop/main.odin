package main

import "core:fmt"
import ui "../.."
import net "../../vendor/sdl2/net"

main :: proc() {
	app := ui.ui_begin_app("Odin UI desktop smoke test", 800, 600)
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
			"Odin UI + SDL2_net",
			user_style = {font_size = 28, text_color = ui.hex_rgb(0xF4F1E9)},
		)
		ui.app_end_frame(app)
	}
}
