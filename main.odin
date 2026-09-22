package UI
import sdl "vendor:sdl2"

main :: proc() {
	app := app_init("My UI Toolkit", 500, 500, sdl.WINDOW_SHOWN | sdl.WINDOW_ALLOW_HIGHDPI)
	defer app_destroy(app)
	buffer: Gap_Buffer
	gap_buffer_init(&buffer)
	defer gap_buffer_destroy(&buffer)

	for !app.quit {
		{
			app_begin_frame(app)
			defer app_end_frame(app)

			{
				element_open(
					app.ui,
					{
						style = {
							width = ViewPercent{100},
							height = ViewPercent{100},
							bg_color = COLOR_WHITE,
							justify_content = .CENTER,
							align_items = .CENTER,
							direction = .COLUMN,
						},
					},
				)
				defer element_close(app.ui)


				text(app.ui, app.ev, "Text Area ☺️", user_style = {font_size = 60})
				textarea(
					app.ui,
					app.ev,
					&buffer,
					placeholder = "Type your multi-line message here...\nPress Enter for new lines.",
					wrapper_style = {
						border = space(2),
						padding = space(10),
						width = Percent{50},
						height = Percent{50},
						bg_color = COLOR_WHITE,
						border_color = COLOR_BLACK,
					},
					salt = "my_main_textarea",
				)
			}
		}
	}
}
