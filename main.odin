package main

import anim "./animations"
import ev "./events"
import lc "./layout_calc"
import "./renderer"
import "core:hash"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

main :: proc() {
	sdl.Init({.VIDEO})
	defer sdl.Quit()
	ttf.Init()
	defer ttf.Quit()
	img.Init({.PNG, .JPG})
	defer img.Quit()

	window := sdl.CreateWindow(
		"Odin UI Engine - CRUD App",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1184,
		768,
		{.SHOWN},
	)
	defer sdl.DestroyWindow(window)

	sdl_rend := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(sdl_rend)

	sdl.SetRenderDrawBlendMode(sdl_rend, .BLEND)

	font := ttf.OpenFont("assets/font/CaacupeOne-Regular.ttf", 24)
	defer ttf.CloseFont(font)
	font_small := ttf.OpenFont("assets/font/CaacupeOne-Regular.ttf", 16)
	defer ttf.CloseFont(font_small)

	ui_ctx := renderer.ui_context_create(1024, 768)
	defer renderer.ui_context_destroy(ui_ctx)
	ui_ctx.fonts[hash.fnv32(transmute([]byte)string("default_font"))] = font
	ui_ctx.fonts[hash.fnv32(transmute([]byte)string("time_font"))] = font_small

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

	cursor_arrow := sdl.CreateSystemCursor(.ARROW)
	cursor_hand := sdl.CreateSystemCursor(.HAND)
	cursor_ibeam := sdl.CreateSystemCursor(.IBEAM)
	defer sdl.FreeCursor(cursor_arrow)
	defer sdl.FreeCursor(cursor_hand)
	defer sdl.FreeCursor(cursor_ibeam)

	perf_freq := f64(sdl.GetPerformanceFrequency())
	last_time := sdl.GetPerformanceCounter()
	my_popover_open := false

	// Application State (declared outside the loop)
	my_dropdown_open := false
	my_selected_idx := -1
	my_options := []string{"Admin", "Developer", "Designer", "Guest"}

	is_scrubbing: bool = false
	scrub_time: f32 = 0
	slider_val: f32 = 0
	overlay_active: bool = false
	overlay_anim: f32 = 0


	running := true
	for running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last_time) / perf_freq
		last_time = now

		ev.begin_frame(&ev_ctx)

		event: sdl.Event
		for sdl.PollEvent(&event) {
			ev.pump_events(&ev_ctx, &event)
			if event.type == .QUIT do running = false
		}

		target_cursor := cursor_arrow
		if cb, ok := ev_ctx.listeners[ev_ctx.hovered_id]; ok {
			#partial switch cb.cursor {
			case .HAND:
				target_cursor = cursor_hand
			case .IBEAM:
				target_cursor = cursor_ibeam
			}
		}

		if sdl.GetCursor() != target_cursor do sdl.SetCursor(target_cursor)

		win_w, win_h: i32
		sdl.GetWindowSize(window, &win_w, &win_h)

		renderer.ui_begin_frame(ui_ctx, sdl_rend, win_w, win_h)


		{
			renderer.element_open(
				ui_ctx,
				{
					style = {
						width = lc.ViewPercent{100},
						height = lc.ViewPercent{100},
						justify_content = .CENTER,
						align_items = .CENTER,
						bg_color = renderer.Color{0.95, 0.95, 0.97, 1},
					},
				},
			)
			defer renderer.element_close(ui_ctx)


			renderer.dropdown(
				ui_ctx,
				&ev_ctx,
				"life",
				my_options,
				&my_selected_idx,
				&my_dropdown_open,
			)
		}


		roots := renderer.ui_layout_tree(ui_ctx)
		for root in roots {
			anim.apply_structural(&anim_ctx, root)
		}
		renderer.ui_compute(ui_ctx)

		anim.update(&anim_ctx.engine, 0.016)

		visual_cb :: proc(user_data: rawptr, state: ^anim.Retained_State) {
			el := (^renderer.Element)(user_data)
			if el != nil do el.resolved_opacity = state.opacity
		}

		for root in roots {
			anim.apply_visual(&anim_ctx, root, visual_cb)
		}

		sdl.SetRenderDrawColor(sdl_rend, 240, 240, 245, 255)
		sdl.RenderClear(sdl_rend)
		renderer.render_tree(ui_ctx, sdl_rend, roots)
		sdl.RenderPresent(sdl_rend)
	}
}
