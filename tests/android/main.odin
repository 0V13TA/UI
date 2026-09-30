package main

import "base:runtime"
import ui "../.."

main :: proc() {
	app := ui.ui_begin_app("Odin UI Android smoke test", 640, 480)
	if app == nil do return
	defer ui.app_destroy(app)

	for !app.quit {
		ui.app_begin_frame(app)
		ui.text(app, "Odin UI Android package smoke test")
		ui.app_end_frame(app)
	}
}

@(export)
odin_app_start :: proc "c" () -> i32 {
	context = runtime.default_context()
	main()
	return 0
}
