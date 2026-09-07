package main

import "core:strings"
import lc "layout_calc"
import rl "vendor:raylib" // Adjust import path as needed

// Global font for WYSIWYG typography
app_font: rl.Font

// --- Text Measurement Bridges ---

ui_text_width :: proc(text: string) -> f32 {
	c_str := strings.clone_to_cstring(text, context.temp_allocator)
	size := rl.MeasureTextEx(app_font, c_str, 20.0, 1.0)
	return size.x
}

ui_text_height :: proc(text: string, max_width: f32) -> f32 {
	c_str := strings.clone_to_cstring(text, context.temp_allocator)
	size := rl.MeasureTextEx(app_font, c_str, 20.0, 1.0)
	return size.y
}

// --- Recursive Render Pass ---

render_box :: proc(box: ^lc.Box) {
	// 1. Apply baked clipping rect
	if clip, ok := box.clip_rect.?; ok do rl.BeginScissorMode(i32(clip.x), i32(clip.y), i32(clip.width), i32(clip.height))
	else do rl.EndScissorMode()


	// 2. Draw Box Background & Border (Styling placeholders)
	box_rect := rl.Rectangle{box.x, box.y, box.computed_width, box.computed_height}
	rl.DrawRectangleRec(box_rect, rl.Fade(rl.SKYBLUE, 0.2))
	rl.DrawRectangleLinesEx(box_rect, 1.0, rl.DARKBLUE)

	// 3. Draw Text Content
	if text, ok := box.text.?; ok {
		c_str := strings.clone_to_cstring(text, context.temp_allocator)
		// Offset slightly by padding if desired, currently using raw X/Y
		rl.DrawTextEx(app_font, c_str, {box.x + 5, box.y + 5}, 20.0, 1.0, rl.BLACK)
	}

	// 4. Recurse into children (Z-order preserved by layout core)
	for child in box.children {
		render_box(child)
	}

	// 5. Restore this box's clip state for subsequent siblings
	// Raylib's scissor is global; children may have overwritten it
	if clip, ok := box.clip_rect.?; ok do rl.BeginScissorMode(i32(clip.x), i32(clip.y), i32(clip.width), i32(clip.height))
	else do rl.EndScissorMode()
}

// --- Editor Loop ---

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(600, 500, "WYSIWYG Layout Core")
	defer rl.CloseWindow()

	app_font = rl.GetFontDefault()

	layout_ctx := lc.layout_context_create(ui_text_width, ui_text_height, 1280, 720)
	defer lc.layout_context_destroy(layout_ctx)

	for !rl.WindowShouldClose() {
    lc.begin_layout(layout_ctx)
    layout_ctx.screen_width = f32(rl.GetScreenWidth())
    layout_ctx.screen_height = f32(rl.GetScreenWidth())

    lc.begin_layout(layout_ctx)

    {
      lc.box_open(layout_ctx,{
        width = lc.ViewPercent{100},
        height = lc.ViewPercent{100},
        direction = .COLUMN,
        align_items = .CENTER,
        justify_content = .CENTER,
        gap = 20.0
      })
      defer lc.box_close(layout_ctx)

      {
        lc.box_open(layout_ctx, {
          width = lc.Fit(true),
          text = "WYSIWYG Engine",
          padding = {10, 20, 10, 20},
          border = {0,0,0,0},
        })
        defer lc.box_close(layout_ctx)
      }
    }

    lc.end_layout(layout_ctx)

    rl.BeginDrawing()
    rl.ClearBackground(rl.RAYWHITE)

    for root_box in layout_ctx.root_boxes do render_box(root_box)

    rl.EndDrawing()
  }
}
