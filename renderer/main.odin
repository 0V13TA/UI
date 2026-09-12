package renderer

import anim "../animations"
import "../events"
import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

dashboard := []string{"Overview", "Analytics", "Settings"}
metrics := []string {
	"Total Views\n14,092",
	"Active Users\n1,042",
	"Conversion\n4.2%",
	"Revenue\n$8,430",
}
printed := false


main :: proc() {
	// 1. Initialize SDL & TTF
	sdl.Init({.VIDEO})
	defer sdl.Quit()

	if ttf.Init() != 0 {
		fmt.printfln("TTF Init failed: %s", sdl.GetError())
		return
	}
	defer ttf.Quit()

	window := sdl.CreateWindow(
		"SDL2 UI Engine Test",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		800,
		600,
		{.SHOWN},
	)
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(renderer)

	// 2. Setup the UI Context
	font := ttf.OpenFont("font/Wallpoet-Regular.ttf", 32)
	if font == nil {
		fmt.printfln("Failed to load font: %s", ttf.GetError())
		return
	}
	defer ttf.CloseFont(font)

	anim_ctx := anim.Context {
		states = make(map[lc.Box_ID]^anim.Retained_State),
	}
	defer {
		for _, s in anim_ctx.states do free(s)
		delete(anim_ctx.states)
		delete(anim_ctx.engine.tweens)
	}

	// ADD THIS: Define the target class
	METRIC_CARD_CLASS := Class_Name("metric_card")
	DASHBOARD_ID := lc.ID("dashboard")
	WEEKLY_ANALYTICS := lc.ID("Weekly Analytics")
	SCROLL_CONTAINER_ID := lc.ID("main_scroll_container")

	ui_ctx := ui_context_create(800, 600)
	defer ui_context_destroy(ui_ctx)

	ev_ctx := events.Event_Context {
		layout               = ui_ctx.layout,
		listeners            = make(map[lc.Box_ID]events.Event_Callbacks),
		clicked_this_frame   = make(map[lc.Box_ID]bool),
		scroll_offsets_x     = make(map[lc.Box_ID]f32),
		scroll_offsets_y     = make(map[lc.Box_ID]f32),
		text_cursors         = make(map[lc.Box_ID]int),
		text_selection       = make(map[lc.Box_ID]int),
		cursor_blink_start   = make(map[lc.Box_ID]u64),
		cursor_last_position = make(map[lc.Box_ID]int),
	}
	defer {
		delete(ev_ctx.listeners)
		delete(ev_ctx.clicked_this_frame)
		delete(ev_ctx.scroll_offsets_x)
		delete(ev_ctx.scroll_offsets_y)
		delete(ev_ctx.text_cursors)
		delete(ev_ctx.cursor_blink_start)
		delete(ev_ctx.cursor_last_position)
		delete(ev_ctx.text_selection)
	}

	font_hash := hash.fnv32(transmute([]byte)(string("default_font")))
	ui_ctx.fonts[font_hash] = font

	check_state := false
	radio_state := 1
	slider_val: f32 = 75.0

	// Dynamic arrays require explicit allocation and cleanup
	text_buffer := make([dynamic]u8, 0, 256)
	defer delete(text_buffer)

	running := true
	for running {
		events.begin_frame(&ev_ctx) // Clear the click map

		// Drain OS Event Queue
		event: sdl.Event
		for sdl.PollEvent(&event) {
			events.pump_events(&ev_ctx, &event)
			#partial switch event.type {
			case .QUIT:
				running = false
			}
		}

		// Sync window size with layout core
		win_w, win_h: i32
		sdl.GetWindowSize(window, &win_w, &win_h)

		// Create the timeline
		tl := timeline(ui_ctx, &anim_ctx)
		ui_begin_frame(ui_ctx, renderer, win_w, win_h)

		{
			element_open(
				ui_ctx,
				{
					style = {
						width = lc.ViewPercent{100},
						height = lc.ViewPercent{100},
						direction = .ROW,
						bg_color = Color{0.95, 0.95, 0.97, 1.0},
					},
				},
			)
			defer element_close(ui_ctx)


			{
				scroll_begin(
					ui_ctx,
					&ev_ctx,
					id = SCROLL_CONTAINER_ID,
					user_style = {
						width = lc.Grow{1},
						height = lc.Percent{100},
						direction = .COLUMN,
						padding = space(40),
						gap = 30,
					},
				)
				defer scroll_end(ui_ctx)


				element_open(
					ui_ctx,
					{
						text = "Interactive Controls",
						style = {
							font_size = 24,
							text_color = Color{0.1, 0.1, 0.1, 1.0},
							margin = space_4(20, 0, 15, 0),
						},
					},
				)
				element_close(ui_ctx)

				// Checkbox
				if checkbox(ui_ctx, &ev_ctx, "Enable Hardware Acceleration", &check_state) {
					fmt.printfln("Checkbox toggled: %v", check_state)
				}

				// Radio Group (Wrapped in a row layout)
				element_open(
					ui_ctx,
					{style = {direction = .ROW, gap = 20, margin = space_4(10, 0, 15, 0)}},
				)
				radio(ui_ctx, &ev_ctx, "Low", &radio_state, 1)
				radio(ui_ctx, &ev_ctx, "Medium", &radio_state, 2)
				radio(ui_ctx, &ev_ctx, "High", &radio_state, 3)
				element_close(ui_ctx)

				// Slider (with real-time value text generation)
				slider_text := fmt.tprintf("Master Volume: %.1f%%", slider_val)
				element_open(
					ui_ctx,
					{
						text = slider_text,
						style = {font_size = 18, text_color = Color{0.3, 0.3, 0.3, 1.0}},
					},
				)
				element_close(ui_ctx)

				if slider(ui_ctx, &ev_ctx, &slider_val, 0.0, 100.0) {
					// This block fires continuously as the thumb is dragged
				}

				// Text Input
				element_open(
					ui_ctx,
					{style = {width = lc.Fixed{300}, margin = space_4(15, 0, 20, 0)}},
				)
				text_input(ui_ctx, &ev_ctx, &text_buffer, "Search analytics...")
				element_close(ui_ctx)

			}
		}
		uncomputed_roots := ui_end_frame(ui_ctx)
		tl_play(&tl)

		anim.update(&anim_ctx.engine, 0.016) // Assuming 60fps dt
		anim.process_lifecycles(&anim_ctx, ui_ctx.layout)

		visual :: proc(user_data: rawptr, state: ^anim.Retained_State) {
			el := (^Element)(user_data)
			if el == nil do return
			el.resolved_opacity = state.opacity
		}

		for root in uncomputed_roots {
			anim.apply_structural(&anim_ctx, root)
			anim.apply_visual(&anim_ctx, root, visual)
		}

		sdl.SetRenderDrawColor(renderer, 20, 20, 20, 255)
		sdl.RenderClear(renderer)

		render_tree(ui_ctx, renderer, uncomputed_roots)

		sdl.RenderPresent(renderer)
	}
}
