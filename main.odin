package main

import anim "./animations"
import ev "./events"
import lc "./layout_calc"
import "./renderer"
import "core:fmt"
import "core:hash"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

main :: proc() {
	sdl.Init({.VIDEO})
	defer sdl.Quit()
	ttf.Init()
	defer ttf.Quit()

	window := sdl.CreateWindow(
		"Odin UI Engine",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1024,
		768,
		{.SHOWN},
	)
	defer sdl.DestroyWindow(window)
	sdl_rend := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(sdl_rend)

	font := ttf.OpenFont("font/CaacupeOne-Regular.ttf", 24)
	defer ttf.CloseFont(font)

	ui_ctx := renderer.ui_context_create(1024, 768)
	defer renderer.ui_context_destroy(ui_ctx)
	ui_ctx.fonts[hash.fnv32(transmute([]byte)string("default_font"))] = font

	ev_ctx := ev.Event_Context {
		layout               = ui_ctx.layout,
		listeners            = make(map[lc.Box_ID]ev.Event_Callbacks),
		clicked_this_frame   = make(map[lc.Box_ID]bool),
		scroll_offsets_x     = make(map[lc.Box_ID]f32),
		scroll_offsets_y     = make(map[lc.Box_ID]f32),
		text_cursors         = make(map[lc.Box_ID]int),
		text_selection       = make(map[lc.Box_ID]int),
		cursor_blink_start   = make(map[lc.Box_ID]u64),
		cursor_last_position = make(map[lc.Box_ID]int),
	}

	anim_ctx := anim.Context {
		states = make(map[lc.Box_ID]^anim.Retained_State),
	}

	// Component State
	check_state := true
	radio_state := 2
	slider_val: f32 = 45.0
	text_buffer := make([dynamic]u8)
	defer delete(text_buffer)

	sample_text := "This is a selectable text block. Drag your mouse across these words to see the global highlight rendering in action alongside the text kerning and word wrapping."

	running := true
	for running {
		ev.begin_frame(&ev_ctx)

		event: sdl.Event
		for sdl.PollEvent(&event) {
			ev.pump_events(&ev_ctx, &event)
			if event.type == .QUIT do running = false
		}

		win_w, win_h: i32
		sdl.GetWindowSize(window, &win_w, &win_h)

		renderer.ui_begin_frame(ui_ctx, sdl_rend, win_w, win_h)
		tl := renderer.timeline(ui_ctx, &anim_ctx)

		{
			renderer.element_open(
				ui_ctx,
				{
					style = {
						width = lc.ViewPercent{100},
						height = lc.ViewPercent{100},
						direction = .ROW,
						bg_color = renderer.Color{0.95, 0.95, 0.97, 1},
					},
				},
			)
			defer renderer.element_close(ui_ctx)

			{
				renderer.element_open(
					ui_ctx,
					{
						style = {
							gap = 20,
							direction = .COLUMN,
							width = lc.Fixed{300},
							height = lc.Percent{100},
							padding = renderer.space(20),
							bg_color = renderer.Color{1, 1, 1, 1},
							border = renderer.space(0, 2, 0, 0),
							border_color = renderer.Color{0.8, 0.8, 0.8, 1},
						},
					},
				)
				defer renderer.element_close(ui_ctx)

				renderer.selectable_text(
					ui_ctx,
					&ev_ctx,
					"Settings",
					{font_size = 18, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
				)

				renderer.checkbox(ui_ctx, &ev_ctx, "Enable VSync", &check_state)

				{
					renderer.element_open(ui_ctx, {style = {direction = .ROW, gap = 15}})
					defer renderer.element_close(ui_ctx)

					renderer.radio(ui_ctx, &ev_ctx, "Low", &radio_state, 1)
					renderer.radio(ui_ctx, &ev_ctx, "High", &radio_state, 2)
				}

				text := fmt.tprintf("Volume: %.0f%%", slider_val)
				renderer.selectable_text(
					ui_ctx,
					&ev_ctx,
					text,
					{margin = renderer.space(20, 0, 0, 0)},
				)
				renderer.slider(ui_ctx, &ev_ctx, &anim_ctx, &slider_val, 0, 100)
			}

			{
				renderer.scroll_begin(
					ui_ctx,
					&ev_ctx,
					lc.ID("main_scroll"),
					user_style = {
						gap = 30,
						width = lc.Grow{1},
						height = lc.Percent{100},
						padding = renderer.space(10),
						bg_color = renderer.Color{0, 1, 0.3, 1},
					},
				)
				defer renderer.scroll_end(ui_ctx)

				renderer.text_input(ui_ctx, &ev_ctx, &text_buffer, "Search query...")

				{
					// Fine Elements
					renderer.element_open(
						ui_ctx,
						{
							style = {
								width = lc.Percent{100},
								height = lc.Fixed{100},
								padding = renderer.space(20),
								bg_color = renderer.Color{1, 1, 1, 1},
								border_radius = renderer.space(8),
								border = renderer.space(2),
								border_color = renderer.Color{0.3, 0.8, 0.8, 1},
							},
						},
					)
					defer renderer.element_close(ui_ctx)

					renderer.selectable_text(
						ui_ctx,
						&ev_ctx,
						sample_text,
						{
							text_wrap = .WORD,
							font_size = 20,
							text_color = renderer.Color{0.3, 0.3, 0.3, 0.1},
						},
					)

					for i in 0 ..< 5 {
						renderer.element_open(
							ui_ctx,
							{
								style = {
									width = lc.Percent{100},
									height = lc.Fixed{150},
									bg_color = renderer.Color{0.9, 0.9, 0.9, 1},
									border_radius = renderer.space(8),
								},
							},
						); renderer.element_close(ui_ctx)
					}
				}
			}
		}

		uncomputed_roots := renderer.ui_end_frame(ui_ctx)
		renderer.tl_play(&tl)
		anim.update(&anim_ctx.engine, 0.016)

		sdl.SetRenderDrawColor(sdl_rend, 240, 240, 245, 255)
		sdl.RenderClear(sdl_rend)
		renderer.render_tree(ui_ctx, sdl_rend, uncomputed_roots)
		sdl.RenderPresent(sdl_rend)
	}
}
