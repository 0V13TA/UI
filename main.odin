package UI

import sdl "vendor:sdl2"

App_State :: struct {
	carousel_index:     int,
	video_scrubbing:   bool,
	video_scrub_time:  f32,
	video_slider_value: f32,
	video_overlay:     bool,
	video_overlay_anim: f32,
}

main :: proc() {
	app := app_init(
		"Odin — Media",
		960,
		800,
		sdl.WINDOW_SHOWN | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_RESIZABLE,
	)
	if app == nil do return
	defer app_destroy(app)

	state := new(App_State)
	defer free(state)

	defer {
		for _, player in app.ui.videos {
			if player != nil do video_player_destroy(player)
		}
	}

	for !app.quit {
		app_begin_frame(app)
		media_screen(app, state)
		app_end_frame(app)
	}
}

media_screen :: proc(app: ^App, state: ^App_State) {
	{
		element_open(
			app,
			Element {
				style = {
					direction    = .COLUMN,
					align_items  = .CENTER,
					gap          = 24,
					width        = ViewPercent{100},
					height       = ViewPercent{100},
					padding      = space(20, 16),
					bg_color     = hex_rgb(0x101820),
					overflow_y   = .SCROLL,
				},
			},
		)
		defer element_close(app)

		{
			element_open(
				app,
				Element {
					style = {
						direction       = .ROW,
						align_items     = .CENTER,
						justify_content = .SPACE_BETWEEN,
						width           = Percent{100},
						max_width       = Fixed{820},
						padding         = space(4, 0),
					},
				},
			)
			defer element_close(app)

			text(
				app,
				"ODIN / FIELD NOTES",
				user_style = {
					font_size  = 14,
					text_color = hex_rgb(0x9FB5C4),
					text_wrap  = .NONE,
				},
			)
			text(
				app,
				"01  —  MEDIA",
				user_style = {
					font_size  = 12,
					text_color = hex_rgb(0x718797),
					text_wrap  = .NONE,
				},
			)
		}

		{
			element_open(
				app,
				Element {
					style = {
						direction   = .COLUMN,
						align_items = .START,
						gap         = 8,
						width       = Percent{100},
						max_width   = Fixed{820},
						padding     = space(8, 0, 0, 0),
					},
				},
			)
			defer element_close(app)

			text(
				app,
				"Small moments.\nWide open.",
				user_style = {
					font_size  = 36,
					text_color = hex_rgb(0xF4F1E9),
				},
			)
			text(
				app,
				"A simple collection of images and moving pictures.",
				user_style = {
					font_size  = 15,
					text_color = hex_rgb(0x9FB0BA),
				},
			)
		}

		{
			element_open(
				app,
				Element {
					style = {
						direction     = .COLUMN,
						gap           = 14,
						width         = Percent{100},
						max_width     = Fixed{820},
						padding       = space(16),
						bg_color      = hex_rgb(0x1B2934),
						border        = space(1),
						border_color  = hex_rgb(0x2B3D49),
						border_radius = space(16),
					},
				},
			)
			defer element_close(app)

			text(
				app,
				"Collected light",
				user_style = {
					font_size  = 20,
					text_color = hex_rgb(0xF4F1E9),
				},
			)
			text(
				app,
				"Three scenes, one slow scroll.",
				user_style = {font_size = 13, text_color = hex_rgb(0x9FB0BA)},
			)
			carousel_paths(
				app,
				[]string {
					"assets/pictures/carousel/slide1.png",
					"assets/pictures/carousel/slide2.png",
					"assets/pictures/carousel/slide3.png",
				},
				&state.carousel_index,
				wrapper_style = {width = Percent{100}},
				viewport_style = {
					width         = Percent{100},
					height        = Fixed{240},
					overflow_x    = .HIDDEN,
					overflow_y    = .HIDDEN,
					border_radius = space(12),
				},
				arrow_style = {
					width         = Fixed{44},
					height        = Fixed{44},
					border_radius = space(22),
				},
				salt = "gallery",
			)
		}

		{
			element_open(
				app,
				Element {
					style = {
						direction     = .COLUMN,
						gap           = 14,
						width         = Percent{100},
						max_width     = Fixed{820},
						padding       = space(16),
						bg_color      = hex_rgb(0x1B2934),
						border        = space(1),
						border_color  = hex_rgb(0x2B3D49),
						border_radius = space(16),
					},
				},
			)
			defer element_close(app)

			text(
				app,
				"Take a pause",
				user_style = {
					font_size  = 20,
					text_color = hex_rgb(0xF4F1E9),
				},
			)
			text(
				app,
				"A short film for a quieter minute.",
				user_style = {font_size = 13, text_color = hex_rgb(0x9FB0BA)},
			)
			video(
				app,
				"assets/Two 2-minute Rules to Beat Procrastination (in 2 minutes).mp4",
				f64(app.time.delta),
				&state.video_scrubbing,
				&state.video_scrub_time,
				&state.video_slider_value,
				&state.video_overlay,
				&state.video_overlay_anim,
				wrapper_style = {
					width         = Percent{100},
					height        = Fixed{300},
					border_radius = space(12),
				},
				frame_style = {object_fit = .CONTAIN, bg_color = hex_rgb(0x0A1117)},
				salt = "feature_video",
			)
		}

		{
			element_open(
				app,
				Element {
					style = {
						width       = Percent{100},
						max_width   = Fixed{820},
						padding     = space(4, 0, 12, 0),
					},
				},
			)
			defer element_close(app)
			text(
				app,
				"Made for the space between things.",
				user_style = {font_size = 12, text_color = hex_rgb(0x718797)},
			)
		}
	}
}
