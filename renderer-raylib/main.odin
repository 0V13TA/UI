package renderer

import lc "../layout_calc"
import "core:fmt"
import rl "vendor:raylib"

TITLE :: "This is a hero card showcasing dynamic word wrapping."
CONTENT :: "The layout core automatically calculates the height of this text block based on the parent's width constraints. Because this card uses `lc.ViewPercent{100}`, resizing the window will seamlessly reflow this text and expand or contract the card's height."

metrics := []string{"Total Views\n\n14,092", "Active Users\n\n1,042", "Conversion\n\n4.2%"}


main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(1024, 768, "WYSIWYG Layout Engine - Complex UI")
	defer rl.CloseWindow()

	// The UI Context now completely encapsulates the layout math, text measuring, and rendering
	ui_ctx := ui_context_create(1024, 768)
	defer ui_context_destroy(ui_ctx)

	// 1. Load high-res, smoothed fonts
	font_bold := load_sdf_font("font/CaacupeOne-Regular.ttf")
	font_italic := load_sdf_font("font/SankofaDisplay-Regular.ttf")

	// Pick fonts that actually contain English letters!
	font_mono := load_sdf_font("font/CaacupeOne-Regular.ttf")
	font_serif := load_sdf_font("font/Kablammo-Regular-VariableFont_MORF.ttf")

	// Clean up Raylib resources on exit
	defer {
		rl.UnloadFont(font_bold)
		rl.UnloadFont(font_italic)
		rl.UnloadFont(font_mono)
		rl.UnloadFont(font_serif)
	}

	// 2. Register them into your UI Engine
	ui_ctx.fonts["bold"] = font_bold
	ui_ctx.fonts["italic"] = font_italic
	ui_ctx.fonts["mono"] = font_mono
	ui_ctx.fonts["serif"] = font_serif

	// Inside your main file, before the loop:
	counter := 0
	bg_color := rl.RAYWHITE

	// Inside your main loop:
	for !rl.WindowShouldClose() {
		ui_begin_frame(ui_ctx, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
		defer ui_end_frame(ui_ctx)

		{
			element_open(
				ui_ctx,
				{
					direction = .COLUMN,
					justify_content = .CENTER,
					align_items = .CENTER,
					width = lc.ViewPercent{100},
					height = lc.ViewPercent{100},
					border = {10, 10, 10, 10},
					style = {bg_color = rl.BLACK, border_color = rl.WHITE},
				},
			)
			defer element_close(ui_ctx)

			ui_text(ui_ctx, fmt.tprint(counter), style = {text_color = rl.WHITE})

			{
				element_open(
					ui_ctx,
					{
						direction = .ROW,
						width = lc.Fit(true),
						height = lc.Fit(true),
						border = {2, 2, 2, 2},
						gap = 10,
						style = {border_color = rl.WHITE},
					},
				)
				defer element_close(ui_ctx)

				if ui_button(ui_ctx, "Increment") do counter += 1
				if ui_button(ui_ctx, "Decrement") do counter -= 1
			}
		}
	}
}
