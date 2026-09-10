package renderer

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
	font := ttf.OpenFont("../font/CaacupeOne-Regular.ttf", 32)
	if font == nil {
		fmt.printfln("Failed to load font: %s", ttf.GetError())
		return
	}
	defer ttf.CloseFont(font)

	ui_ctx := ui_context_create(800, 600)
	defer ui_context_destroy(ui_ctx)

	// FIX 1: Explicitly cast the untyped string literal to 'string' before transmuting
	font_hash := hash.fnv32(transmute([]byte)(string("default_font")))
	ui_ctx.fonts[font_hash] = font

	running := true
	for running {
		free_all(context.temp_allocator)

		// Drain OS Event Queue
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			}
		}

		// Sync window size with layout core
		win_w, win_h: i32
		sdl.GetWindowSize(window, &win_w, &win_h)

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
				element_open(
					ui_ctx,
					{
						style = {
							width = lc.Fixed{260},
							height = lc.Percent{100},
							direction = .COLUMN,
							padding = space(20),
							gap = 15,
							bg_color = Color{0.1, 0.12, 0.15, 1.0},
							text_color = Color{0.8, 0.8, 0.8, 1.0},
						},
					},
				)
				defer element_close(ui_ctx)

				{
					element_open(
						ui_ctx,
						{
							text = "DASHBOARD",
							style = {
								font_size = 24,
								text_color = Color{1, 1, 1, 1},
								margin = space(0, 0, 30, 0),
							},
						},
					)
					defer element_close(ui_ctx)
				}

				for dash in dashboard {
					element_open(ui_ctx, {text = dash})
					element_close(ui_ctx)
				}
			}

			{
				element_open(
					ui_ctx,
					{
						style = {
							width = lc.Grow{1},
							height = lc.Percent{100},
							direction = .COLUMN,
							padding = space(40),
							gap = 30,
						},
					},
				)
				defer element_close(ui_ctx)

				{
					element_open(
						ui_ctx,
						{
							text = "Weekly Analytics",
							style = {font_size = 32, text_color = Color{0.1, 0.1, 0.1, 1.0}},
						},
					)
					defer element_close(ui_ctx)
				}

				{
					element_open(
						ui_ctx,
						{
							style = {
								width = lc.Percent{100},
								height = lc.Fit(true),
								direction = .ROW,
								wrap = true,
								gap = 20,
							},
						},
					)
					defer element_close(ui_ctx)

					for metric in metrics {
						element_open(
							ui_ctx,
							{
								text = metric,
								style = {
									width         = lc.Grow{1}, // Stretch to fill row
									min_width     = lc.Fixed{200}, // Force wrap if squeezed
									height        = lc.Fixed{120},
									padding       = space(25),
									bg_color      = Color{1, 1, 1, 1},
									border_radius = space(12),
									border        = space(1),
									border_color  = Color{0.85, 0.85, 0.85, 1.0},
									text_color    = Color{0.2, 0.2, 0.2, 1.0},
									font_size     = 20,
								},
							},
						)
						element_close(ui_ctx)
					}

				}
			}
		}

		ui_end_frame(ui_ctx, renderer)

		sdl.RenderPresent(renderer)
	}
}
