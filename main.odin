package main

import anim "./animations"
import ev "./events"
import lc "./layout_calc"
import "./renderer"
import "core:fmt"
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
		600,
		600,
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

	// --- Component States ---
	my_options := []string{"Admin", "Developer", "Designer", "Guest"}
	my_dropdown_open := false
	my_selected_idx := -1

	my_switch_val := false

	my_multi_open := false
	// Stack allocated array to prevent memory leaks
	my_multi_array := [4]bool{false, false, false, false}
	my_multi_states := my_multi_array[:]

	my_combo_open := false
	my_combo_idx := -1
	my_combo_buf := make([dynamic]u8)
	defer delete(my_combo_buf)

	my_modal_open := false
	my_context_open := false
	my_context_x: f32 = 0
	my_context_y: f32 = 0

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

			if event.type == .MOUSEBUTTONDOWN && event.button.button == sdl.BUTTON_RIGHT {
				my_context_open = true
				my_context_x = f32(event.button.x)
				my_context_y = f32(event.button.y)
			}
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
						gap = 20,
						direction = .COLUMN,
						align_items = .CENTER,
						justify_content = .CENTER,
						width = lc.ViewPercent{100},
						height = lc.ViewPercent{100},
						bg_color = renderer.Color{0.95, 0.95, 0.97, 1},
					},
				},
			)
			defer renderer.element_close(ui_ctx)


			renderer.dropdown(
				ui_ctx,
				&ev_ctx,
				"Select a role...",
				my_options,
				&my_selected_idx,
				&my_dropdown_open,
				wrapper_style = {
					width = lc.Fixed{250},
					border = renderer.space(1),
					padding = renderer.space(12, 16),
					bg_color = renderer.Color{1, 1, 1, 1},
					text_color = renderer.Color{0, 0, 0, 1},
					border_color = renderer.Color{0, 0, 0, 1},
				},
			)

			renderer.switch_toggle(ui_ctx, &ev_ctx, "Dark Mode", &my_switch_val)

			renderer.multi_select(
				ui_ctx,
				&ev_ctx,
				"Permissions",
				my_options,
				my_multi_states,
				&my_multi_open,
				wrapper_style = {
					width = lc.Fixed{250},
					border = renderer.space(1),
					padding = renderer.space(12, 16),
					border_radius = renderer.space(6),
					bg_color = renderer.Color{1, 1, 1, 1},
					text_color = renderer.Color{0, 0, 0, 1},
					border_color = renderer.Color{0, 0, 0, 1},
				},
			)

			renderer.combobox(
				ui_ctx,
				&ev_ctx,
				"Search roles...",
				my_options,
				&my_combo_buf,
				&my_combo_idx,
				&my_combo_open,
				wrapper_style = {
					width = lc.Fixed{250},
					height = lc.Fixed{50},
					border = renderer.space(2),
					padding = renderer.space(8),
					border_radius = renderer.space(6),
					bg_color = renderer.Color{1, 1, 1, 1},
				},
			)

			if renderer.button(ui_ctx, &ev_ctx, "Open Modal") do my_modal_open = true

			if renderer.modal_begin(ui_ctx, &ev_ctx, &my_modal_open) {
				defer renderer.modal_end(ui_ctx, my_modal_open)

				renderer.text(
					ui_ctx,
					&ev_ctx,
					"Are you sure you want to delete this?",
					user_style = {font_size = 24},
				)

				{
					renderer.element_open(
						ui_ctx,
						{
							style = {
								gap = 12,
								direction = .ROW,
								justify_content = .END,
								width = lc.Percent{100},
							},
						},
					)
					defer renderer.element_close(ui_ctx)

					if renderer.button(ui_ctx, &ev_ctx, "Cancle") do my_modal_open = false
					if renderer.button(
						ui_ctx,
						&ev_ctx,
						"delete",
						user_style = {bg_color = renderer.Color{0.9, 0.2, 0.2, 1}},
					) {
						fmt.println("Something Deleted")
						my_modal_open = false
					}
				}
			}

			if renderer.context_menu_begin(
				ui_ctx,
				&ev_ctx,
				my_context_x,
				my_context_y,
				&my_context_open,
			) {
				defer renderer.context_menu_end(ui_ctx, true)

				if renderer.button(ui_ctx, &ev_ctx, "Edit", user_style = {text_align = .LEFT}) do my_context_open = false
				if renderer.button(ui_ctx, &ev_ctx, "Duplicate", user_style = {text_align = .LEFT}) do my_context_open = false
				if renderer.button(ui_ctx, &ev_ctx, "Delete", user_style = {text_align = .LEFT, text_color = renderer.Color{0.9, 0.2, 0.2, 1}}) do my_context_open = false

			}
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
