package renderer

import lc "../layout_calc"
import "core:hash"
import "core:math"
import "core:strings"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

Text_Align :: enum {
	LEFT,
	RIGHT,
	CENTER,
}

Color :: distinct [4]f32
Class :: distinct u32


Style :: struct {
	bg_color:        Maybe(Color),

	//
	text_color:      Maybe(Color),
	text_align:      Maybe(Text_Align),

	// Typography
	font_size:       Maybe(f32),
	font_spacing:    Maybe(f32),
	font_name:       Maybe(string),
	font_style:      Maybe(ttf.StyleFlag),

	// Spacing
	gap:             Maybe(f32),
	margin:          Maybe([4]f32),
	padding:         Maybe([4]f32),

	//
	border:          Maybe([4]f32),
	border_color:    Maybe(Color),
	border_radius:   Maybe([4]f32),

	// Flex Alignment
	wrap:            Maybe(bool),
	basis:           Maybe(f32),
	direction:       Maybe(lc.Direction),
	align_items:     Maybe(lc.Align),
	justify_content: Maybe(lc.Align),

	// Position
	top:             Maybe(f32), // Only useful if position != STATIC
	left:            Maybe(f32),
	right:           Maybe(f32),
	bottom:          Maybe(f32),
	position:        Maybe(lc.Position),

	// Scrolling
	overflow_x:      Maybe(lc.Overflow),
	overflow_y:      Maybe(lc.Overflow),

	//
	z_index:         Maybe(i32),

	//
	width:           Maybe(lc.Sizing),
	height:          Maybe(lc.Sizing),
}

Element :: struct {
	using _box:             lc.Box,
	classes:                []Class,
	style:                  Style,

	// Anything not in Box
	// Font
	resolved_font_spacing:  f32,
	resolved_font_size:     f32,
	resolved_font:          ^ttf.Font,
	resolved_font_style:    ttf.StyleFlag,

	// Text
	resolved_text_color:    Color,
	resolved_text_align:    Text_Align,

	// Border
	resolved_border_color:  Color,
	resolved_border_radius: [4]f32,

	// Backgroud
	resolved_bg_color:      Color,
}

UI_Context :: struct {
	layout:     ^lc.Layout_Context,
	fonts:      map[u32]^ttf.Font, // Hash Font name + Cache name
	stylesheet: map[Class]Style,
}


// Utility Functions
Class_Name :: proc(id: string) -> Class {
	return Class(hash.fnv32(transmute([]byte)id))
}

space_1 :: proc(all: f32) -> [4]f32 {
	return {all, all, all, all}
}
space_2 :: proc(vertical, horizontal: f32) -> [4]f32 {
	return {vertical, horizontal, vertical, horizontal}
}
space_3 :: proc(top, horizontal, bottom: f32) -> [4]f32 {
	return {top, horizontal, bottom, horizontal}
}
space_4 :: proc(top, right, bottom, left: f32) -> [4]f32 {
	return {top, right, bottom, left}
}

space :: proc {
	space_1,
	space_2,
	space_3,
	space_4,
}


// --- Color Helpers ---
to_sdl_color :: proc(c: Color) -> (u8, u8, u8, u8) {
	return u8(c[0] * 255), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255)
}

set_render_color :: proc(renderer: ^sdl.Renderer, c: Color) {
	r, g, b, a := to_sdl_color(c)
	sdl.SetRenderDrawColor(renderer, r, g, b, a)
}

// --- Master Box Drawing Proc ---
// border: [Top, Right, Bottom, Left]
// radii:  [TopLeft, TopRight, BottomRight, BottomLeft]
draw_ui_box :: proc(
	renderer: ^sdl.Renderer,
	bounds: sdl.Rect,
	bg_color, border_color: Color,
	border: [4]f32,
	radii: [4]f32,
) {
	// 1. Draw Outer Border (if it has color and thickness)
	has_border := border[0] > 0 || border[1] > 0 || border[2] > 0 || border[3] > 0
	if has_border && border_color[3] > 0 {
		set_render_color(renderer, border_color)
		fill_rounded_rect(renderer, bounds, radii)
	}

	// 2. Draw Inner Background
	if bg_color[3] > 0 {
		inner_bounds := sdl.Rect {
			x = bounds.x + i32(border[3]), // Push in by Left border
			y = bounds.y + i32(border[0]), // Push in by Top border
			w = bounds.w - i32(border[3] + border[1]), // Subtract Left + Right
			h = bounds.h - i32(border[0] + border[2]), // Subtract Top + Bottom
		}

		// Clamp the inner corner radii so they curve cleanly inside the border
		inner_radii: [4]f32
		inner_radii[0] = max(radii[0] - max(border[0], border[3]), 0) // TL
		inner_radii[1] = max(radii[1] - max(border[0], border[1]), 0) // TR
		inner_radii[2] = max(radii[2] - max(border[2], border[1]), 0) // BR
		inner_radii[3] = max(radii[3] - max(border[2], border[3]), 0) // BL

		set_render_color(renderer, bg_color)
		fill_rounded_rect(renderer, inner_bounds, inner_radii)
	}
}

// --- Mathematical Scanline Rasterizer ---
@(private)
fill_rounded_rect :: proc(renderer: ^sdl.Renderer, rect: sdl.Rect, radii: [4]f32) {
	if rect.w <= 0 || rect.h <= 0 do return

	// Ensure corners don't overlap by clamping to half the shortest dimension
	min_dim := f32(min(rect.w, rect.h)) / 2.0
	tl := i32(min(radii[0], min_dim))
	tr := i32(min(radii[1], min_dim))
	br := i32(min(radii[2], min_dim))
	bl := i32(min(radii[3], min_dim))

	// Fast path: if no radius, just draw a native hardware rect
	if tl == 0 && tr == 0 && br == 0 && bl == 0 {
		rect_copy := rect
		sdl.RenderFillRect(renderer, &rect_copy)
		return
	}

	// Scanline pass: draws top-to-bottom preventing alpha-blend overlaps
	for y in 0 ..< rect.h {
		real_y := rect.y + y
		start_x := rect.x
		end_x := rect.x + rect.w - 1

		// Left boundary math
		if y < tl {
			dy := tl - y
			dx := i32(math.sqrt(f32(tl * tl - dy * dy)))
			start_x = rect.x + tl - dx
		} else if y >= rect.h - bl {
			dy := y - (rect.h - bl - 1)
			dx := i32(math.sqrt(f32(bl * bl - dy * dy)))
			start_x = rect.x + bl - dx
		}

		// Right boundary math
		if y < tr {
			dy := tr - y
			dx := i32(math.sqrt(f32(tr * tr - dy * dy)))
			end_x = rect.x + rect.w - 1 - tr + dx
		} else if y >= rect.h - br {
			dy := y - (rect.h - br - 1)
			dx := i32(math.sqrt(f32(br * br - dy * dy)))
			end_x = rect.x + rect.w - 1 - br + dx
		}

		sdl.RenderDrawLine(renderer, start_x, real_y, end_x, real_y)
	}
}


@(private)
ui_text_width :: proc(box: ^lc.Box, text: string) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil || el.resolved_font == nil do return 0

	c_str := strings.clone_to_cstring(text, context.temp_allocator)
	w, h: i32
	ttf.SizeUTF8(el.resolved_font, c_str, &w, &h)

	// Optional: Add custom letter spacing if your UI demands it
	// spacing := f32(max(len(text) - 1, 0)) * el.resolved_font_spacing

	return f32(w)
}

@(private)
ui_text_height :: proc(box: ^lc.Box, text: string, max_width: f32) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil || el.resolved_font == nil do return 0

	// SDL_ttf provides accurate line height directly from the font metrics
	line_height := f32(ttf.FontHeight(el.resolved_font))

	space_w, space_h: i32
	ttf.SizeUTF8(el.resolved_font, " ", &space_w, &space_h)
	space_width := f32(space_w)

	total_lines: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line in explicit_lines {
		total_lines += 1.0
		cursor_x: f32 = 0.0

		words := strings.split(explicit_line, " ", context.temp_allocator)
		for word in words {
			c_word := strings.clone_to_cstring(word, context.temp_allocator)
			w, h: i32
			ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
			word_width := f32(w)

			// Wrap to the next line if the word exceeds constraints
			if box.wrap && cursor_x + word_width > max_width && cursor_x > 0 {
				cursor_x = 0
				total_lines += 1.0
			}
			cursor_x += word_width + space_width
		}
	}

	return max(total_lines, 1.0) * line_height
}


@(private)
default_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	// ------------------------------------------------------------
	// Non-inherited visual defaults
	// ------------------------------------------------------------

	el.resolved_bg_color = {0, 0, 0, 0}
	el.resolved_border_color = {0, 0, 0, 0}
	el.resolved_border_radius = {0, 0, 0, 0}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	// Typography is inherited from the parent.
	if el._box.parent != nil && el._box.parent.user_data != nil {
		parent := (^Element)(el._box.parent.user_data)

		el.resolved_text_color = parent.resolved_text_color
		el.resolved_text_align = parent.resolved_text_align

		el.resolved_font_size = parent.resolved_font_size
		el.resolved_font_spacing = parent.resolved_font_spacing
		el.resolved_font = parent.resolved_font
		el.resolved_font_style = parent.resolved_font_style
	} else {
		// Root defaults.
		el.resolved_text_color = {0, 0, 0, 1}
		el.resolved_text_align = .LEFT

		el.resolved_font_size = 16.0
		el.resolved_font_spacing = 1.0
		el.resolved_font_style = {}

		// If you have a designated default font in ctx.fonts,
		// resolve it here. Otherwise leave the zero font and let
		// your font setup provide the default.
		//
		// el.resolved_font = ctx.fonts[DEFAULT_FONT_HASH]
	}

	// ------------------------------------------------------------
	// Box/layout defaults
	// ------------------------------------------------------------

	// These should only be assigned here if Box itself doesn't
	// already establish sensible defaults.
	el._box.gap = 0
	el._box.padding = {0, 0, 0, 0}
	el._box.margin = {0, 0, 0, 0}
	el._box.border = {0, 0, 0, 0}

	el._box.direction = .ROW
	el._box.align_items = .START
	el._box.justify_content = .START

	el._box.wrap = false

	el._box.position = .STATIC

	el._box.overflow_x = .VISIBLE
	el._box.overflow_y = .VISIBLE

	el._box.z_index = 0
}

@(private)
apply_style_block :: proc(el: ^Element, s: Style, ctx: ^UI_Context) {
	// ------------------------------------------------------------
	// Visuals
	// ------------------------------------------------------------

	if v, ok := s.bg_color.?; ok {
		el.resolved_bg_color = v
	}

	if v, ok := s.border_color.?; ok {
		el.resolved_border_color = v
	}

	if v, ok := s.border_radius.?; ok {
		el.resolved_border_radius = v
	}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	if v, ok := s.text_color.?; ok {
		el.resolved_text_color = v
	}

	if v, ok := s.text_align.?; ok {
		el.resolved_text_align = v
	}

	if v, ok := s.font_size.?; ok {
		el.resolved_font_size = v
	}

	if v, ok := s.font_spacing.?; ok {
		el.resolved_font_spacing = v
	}

	if v, ok := s.font_style.?; ok {
		el.resolved_font_style = v
	}

	if v, ok := s.font_name.?; ok {
		font_hash := hash.fnv32(transmute([]byte)v)

		if font, exists := ctx.fonts[font_hash]; exists {
			el.resolved_font = font
		}
	}

	// ------------------------------------------------------------
	// Spacing / layout
	// ------------------------------------------------------------

	if v, ok := s.gap.?; ok {
		el._box.gap = v
	}

	if v, ok := s.margin.?; ok {
		el._box.margin = v
	}

	if v, ok := s.padding.?; ok {
		el._box.padding = v
	}

	if v, ok := s.border.?; ok {
		el._box.border = v
	}

	// ------------------------------------------------------------
	// Flex
	// ------------------------------------------------------------

	if v, ok := s.wrap.?; ok {
		el._box.wrap = v
	}

	if v, ok := s.basis.?; ok {
		el._box.basis = v
	}

	if v, ok := s.direction.?; ok {
		el._box.direction = v
	}

	if v, ok := s.align_items.?; ok {
		el._box.align_items = v
	}

	if v, ok := s.justify_content.?; ok {
		el._box.justify_content = v
	}

	// ------------------------------------------------------------
	// Position
	// ------------------------------------------------------------

	if v, ok := s.position.?; ok {
		el._box.position = v
	}

	if v, ok := s.top.?; ok {
		el._box.top = v
	}

	if v, ok := s.left.?; ok {
		el._box.left = v
	}

	if v, ok := s.right.?; ok {
		el._box.right = v
	}

	if v, ok := s.bottom.?; ok {
		el._box.bottom = v
	}

	// ------------------------------------------------------------
	// Scrolling
	// ------------------------------------------------------------

	if v, ok := s.overflow_x.?; ok {
		el._box.overflow_x = v
	}

	if v, ok := s.overflow_y.?; ok {
		el._box.overflow_y = v
	}

	// ------------------------------------------------------------
	// Size
	// ------------------------------------------------------------

	if v, ok := s.width.?; ok {
		el._box.width = v
	}

	if v, ok := s.height.?; ok {
		el._box.height = v
	}

	// ------------------------------------------------------------
	// Stacking
	// ------------------------------------------------------------

	if v, ok := s.z_index.?; ok {
		el._box.z_index = v
	}
}

@(private)
apply_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	default_styles(el, ctx)

	for cls in el.classes {
		if class_style, exists := ctx.stylesheet[cls]; exists {
			apply_style_block(el, class_style, ctx)
		}
	}

	apply_style_block(el, el.style, ctx)
}
