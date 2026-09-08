package renderer

import lc "../layout_calc"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Text_Align :: enum {
	LEFT,
	CENTER,
	RIGHT,
}

Style :: struct {
	bg_color:     Maybe(rl.Color),
	border_color: Maybe(rl.Color),
	text_color:   Maybe(rl.Color),
	text_align:   Maybe(Text_Align),

	// Typography
	font_name:    Maybe(string),
	font_size:    Maybe(f32),
	font_spacing: Maybe(f32),
	padding:      Maybe([4]f32),
	margin:       Maybe([4]f32),
	gap:          Maybe(f32),
	width:        Maybe(lc.Sizing),
	height:       Maybe(lc.Sizing),
}

Class :: struct {
	name:  string,
	style: Style,
}

Element :: struct {
	using box:           lc.Box,
	classes:             []string,
	style:               Style,

	// Resolved Visuals
	resolved_bg:         rl.Color,
	resolved_text:       rl.Color,
	resolved_border:     rl.Color,
	resolved_text_align: Text_Align,
	resolved_font:       rl.Font,
}

UI_Context :: struct {
	layout:       ^lc.Layout_Context,
	stylesheet:   map[string]Class,
	fonts:        map[string]rl.Font,
	default_font: rl.Font,
}

// --- Internal Text Measurement ---

@(private)
ui_text_width :: proc(box: ^lc.Box, text: string) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil do return 0
	c_str := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(el.resolved_font, c_str, box.font_size, box.font_spacing).x
}

@(private)
ui_text_height :: proc(box: ^lc.Box, text: string, max_width: f32) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil do return 0
	space_width := rl.MeasureTextEx(el.resolved_font, " ", box.font_size, box.font_spacing).x
	line_height := rl.MeasureTextEx(el.resolved_font, "Wy", box.font_size, box.font_spacing).y

	total_lines: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line in explicit_lines {
		total_lines += 1.0
		cursor_x: f32 = 0.0
		words := strings.split(explicit_line, " ", context.temp_allocator)

		for word in words {
			c_word := strings.clone_to_cstring(word, context.temp_allocator)
			word_width :=
				rl.MeasureTextEx(el.resolved_font, c_word, box.font_size, box.font_spacing).x

			if cursor_x + word_width > max_width && cursor_x > 0 {
				cursor_x = 0
				total_lines += 1.0
			}
			cursor_x += word_width + space_width
		}
	}
	return max(total_lines, 1.0) * line_height
}

@(private)
set_clip :: proc(current: ^Maybe(lc.Rect), target: Maybe(lc.Rect)) {
	if current^ == target do return // Skip redundant batch flushes!

	if t, ok := target.?; ok {
		rl.BeginScissorMode(i32(t.x), i32(t.y), i32(t.width), i32(t.height))
	} else {
		rl.EndScissorMode()
	}
	current^ = target
}

// --- Public API ---

ui_context_create :: proc(screen_width, screen_height: f32) -> ^UI_Context {
	ctx := new(UI_Context)
	ctx.layout = lc.layout_context_create(
		ui_text_width,
		ui_text_height,
		screen_width,
		screen_height,
	)
	ctx.stylesheet = make(map[string]Class)
	ctx.fonts = make(map[string]rl.Font)
	ctx.default_font = rl.GetFontDefault()
	return ctx
}

ui_context_destroy :: proc(ctx: ^UI_Context) {
	lc.layout_context_destroy(ctx.layout)
	delete(ctx.stylesheet)
	delete(ctx.fonts)
	free(ctx)
}

ui_begin_frame :: proc(ctx: ^UI_Context, screen_width, screen_height: f32) {
	lc.layout_reset(ctx.layout)
	ctx.layout.screen_width = screen_width
	ctx.layout.screen_height = screen_height
	lc.begin_layout(ctx.layout)
}

ui_end_frame :: proc(ctx: ^UI_Context) {
	lc.end_layout(ctx.layout)

	rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	// Initialize the explicit state tracker
	current_clip: Maybe(lc.Rect) = nil

	for root_box in ctx.layout.root_boxes {
		render_box(ctx, root_box, &current_clip)
	}

	// Failsafe cleanup (though it should naturally unwind to nil)
	if current_clip != nil {
		rl.EndScissorMode()
	}

	rl.EndDrawing()
}

apply_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	// 1. Set base defaults
	el.resolved_bg = rl.BLANK
	el.resolved_text = rl.BLACK
	el.resolved_border = rl.BLANK
	el.resolved_text_align = .LEFT
	el.resolved_font = ctx.default_font
	el.box.font_size = 20.0
	el.box.font_spacing = 1.0

	merge_style :: proc(el: ^Element, s: Style, ctx: ^UI_Context) {
		if c, ok := s.bg_color.?; ok do el.resolved_bg = c
		if c, ok := s.text_color.?; ok do el.resolved_text = c
		if c, ok := s.border_color.?; ok do el.resolved_border = c
		if ta, ok := s.text_align.?; ok do el.resolved_text_align = ta

		if fn, ok := s.font_name.?; ok {
			if f, exists := ctx.fonts[fn]; exists do el.resolved_font = f
		}
		if fs, ok := s.font_size.?; ok do el.box.font_size = fs
		if fsp, ok := s.font_spacing.?; ok do el.box.font_spacing = fsp

		if p, ok := s.padding.?; ok do el.padding = p
		if m, ok := s.margin.?; ok do el.margin = m
		if g, ok := s.gap.?; ok do el.gap = g
		if w, ok := s.width.?; ok do el.width = w
		if h, ok := s.height.?; ok do el.height = h
	}

	for class_name in el.classes {
		if c, ok := ctx.stylesheet[class_name]; ok do merge_style(el, c.style, ctx)
	}
	merge_style(el, el.style, ctx)
}

element_open :: proc(ctx: ^UI_Context, el_val: Element, loc := #caller_location) {
	el := new(Element, context.temp_allocator)
	el^ = el_val

	if el.box.id == "" {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		el.box.id = lc.Box_ID(strings.clone(loc_str, context.temp_allocator))
	}

	apply_styles(el, ctx)
	el.box.user_data = el
	lc.box_open(ctx.layout, el.box, loc)
}

element_close :: proc(ctx: ^UI_Context) {
	lc.box_close(ctx.layout)
}

// --- Recursive Render Pass ---


// Update the signature to take the tracked state
render_box :: proc(ui_ctx: ^UI_Context, box: ^lc.Box, current_clip: ^Maybe(lc.Rect)) {
	// 1. Snapshot the state we inherited from the caller
	previous_clip := current_clip^

	// 2. Apply this box's required clip (only hits OpenGL if it differs)
	set_clip(current_clip, box.clip_rect)

	if box.user_data == nil do return
	el := (^Element)(box.user_data)

	box_rect := rl.Rectangle{box.x, box.y, box.computed_width, box.computed_height}
	if el.resolved_bg != rl.BLANK {
		rl.DrawRectangleRec(box_rect, el.resolved_bg)
	}

	if el.resolved_border != rl.BLANK {
		if box.border[lc.Side.TOP] > 0.0 do rl.DrawRectangleRec({box.x, box.y, box.computed_width, box.border[lc.Side.TOP]}, el.resolved_border)
		if box.border[lc.Side.BOTTOM] > 0.0 do rl.DrawRectangleRec({box.x, box.y + box.computed_height - box.border[lc.Side.BOTTOM], box.computed_width, box.border[lc.Side.BOTTOM]}, el.resolved_border)
		if box.border[lc.Side.LEFT] > 0.0 do rl.DrawRectangleRec({box.x, box.y, box.border[lc.Side.LEFT], box.computed_height}, el.resolved_border)
		if box.border[lc.Side.RIGHT] > 0.0 do rl.DrawRectangleRec({box.x + box.computed_width - box.border[lc.Side.RIGHT], box.y, box.border[lc.Side.RIGHT], box.computed_height}, el.resolved_border)
	}

	if text, ok := box.text.?; ok {
		text_x := box.x + box.padding[lc.Side.LEFT] + box.border[lc.Side.LEFT]
		text_y := box.y + box.padding[lc.Side.TOP] + box.border[lc.Side.TOP]
		inner_width := max(
			box.computed_width - lc.get_horizontal(box.padding) - lc.get_horizontal(box.border),
			0.0,
		)

		space_width := rl.MeasureTextEx(el.resolved_font, " ", box.font_size, box.font_spacing).x
		line_height := rl.MeasureTextEx(el.resolved_font, "Wy", box.font_size, box.font_spacing).y
		cursor_y := text_y

		explicit_lines := strings.split(text, "\n", context.temp_allocator)
		for explicit_line in explicit_lines {
			words := strings.split(explicit_line, " ", context.temp_allocator)
			start_idx := 0

			for start_idx < len(words) {
				end_idx := start_idx
				line_width: f32 = 0.0

				for end_idx < len(words) {
					c_word := strings.clone_to_cstring(words[end_idx], context.temp_allocator)
					word_width :=
						rl.MeasureTextEx(el.resolved_font, c_word, box.font_size, box.font_spacing).x
					if end_idx > start_idx && line_width + word_width > inner_width do break
					line_width += word_width + space_width
					end_idx += 1
				}
				if end_idx > start_idx do line_width -= space_width

				start_x := text_x
				if el.resolved_text_align == .CENTER {
					start_x += max((inner_width - line_width) / 2.0, 0.0)
				} else if el.resolved_text_align == .RIGHT {
					start_x += max(inner_width - line_width, 0.0)
				}

				cursor_x := start_x
				for i in start_idx ..< end_idx {
					c_word := strings.clone_to_cstring(words[i], context.temp_allocator)
					rl.DrawTextEx(
						el.resolved_font,
						c_word,
						{cursor_x, cursor_y},
						box.font_size,
						box.font_spacing,
						el.resolved_text,
					)
					cursor_x +=
						rl.MeasureTextEx(el.resolved_font, c_word, box.font_size, box.font_spacing).x +
						space_width
				}
				cursor_y += line_height
				start_idx = end_idx
			}
		}
	}

	for child in box.children {
		render_box(ui_ctx, child, current_clip)
	}

	// 3. RESTORE the caller's clip state before returning!
	set_clip(current_clip, previous_clip)
}
