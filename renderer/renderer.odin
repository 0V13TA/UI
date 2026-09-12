package renderer

import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

Text_Align :: enum {
	LEFT,
	RIGHT,
	CENTER,
}
Text_Wrap :: enum {
	NONE,
	WORD,
	LETTER,
}
Cached_Texture :: struct {
	texture: ^sdl.Texture,
	width:   i32,
	height:  i32,
}

Color :: distinct [4]f32
Class :: distinct u32


Style :: struct {
	bg_color:        Maybe(Color),
	opacity:         Maybe(f32),

	//
	text_color:      Maybe(Color),
	text_wrap:       Maybe(Text_Wrap),
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
	min_width:       Maybe(lc.Bound_Sizing),
	max_width:       Maybe(lc.Bound_Sizing),
	min_height:      Maybe(lc.Bound_Sizing),
	max_height:      Maybe(lc.Bound_Sizing),
}


Element :: struct {
	classes:                []Class,
	style:                  Style,
	using _box:             lc.Box,

	// Anything not in Box
	// Font
	resolved_font_spacing:  f32,
	resolved_font_size:     f32,
	resolved_font:          ^ttf.Font,
	resolved_font_style:    ttf.StyleFlag,

	// Text
	resolved_text_wrap:     Text_Wrap,
	resolved_text_color:    Color,
	resolved_text_align:    Text_Align,

	// Border
	resolved_opacity:       f32,
	resolved_border_color:  Color,
	resolved_border_radius: [4]f32,

	// Backgroud
	resolved_bg_color:      Color,
}

UI_Context :: struct {
	layout:     ^lc.Layout_Context,
	fonts:      map[u32]^ttf.Font, // Hash Font name + Cache name
	stylesheet: map[Class]Style,
	word_cache: map[u64]Cached_Texture,
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

clear_texture_cache :: proc(ctx: ^UI_Context) {
	for _, cached in ctx.word_cache {
		sdl.DestroyTexture(cached.texture)
	}
	clear(&ctx.word_cache)
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

get_word_texture :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	word: string,
	font: ^ttf.Font,
	color: Color,
) -> Cached_Texture {
	// Hash the combination of the text, font, and color
	hash_str := fmt.tprintf("%s_%p_%v", word, font, color)
	key := hash.fnv64a(transmute([]byte)hash_str)

	if cached, exists := ctx.word_cache[key]; exists {
		return cached
	}

	// Cache miss: Rasterize on the CPU, upload to the GPU
	r, g, b, a := to_sdl_color(color)
	sdl_color := sdl.Color{r, g, b, a}
	c_word := strings.clone_to_cstring(word, context.temp_allocator)

	surface := ttf.RenderUTF8_Blended(font, c_word, sdl_color)
	if surface == nil do return Cached_Texture{}

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	cached := Cached_Texture{texture, surface.w, surface.h}

	sdl.FreeSurface(surface)
	ctx.word_cache[key] = cached
	return cached
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

	max_w: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for line in explicit_lines {
		if len(line) == 0 do continue
		c_str := fmt.ctprintf("%s", line)
		w, h: i32
		ttf.SizeUTF8(el.resolved_font, c_str, &w, &h)

		if f32(w) > max_w do max_w = f32(w)
	}

	return max_w
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

		if el.resolved_text_wrap == .LETTER {
			runes := utf8.string_to_runes(explicit_line, context.temp_allocator)
			for r in runes {
				buf: [5]u8
				bytes, n := utf8.encode_rune(r)
				for j in 0 ..< n do buf[j] = bytes[j]
				buf[n] = 0

				w, h: i32
				ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)
				rune_width := f32(w)

				if cursor_x + rune_width > max_width && cursor_x > 0 {
					cursor_x = 0
					total_lines += 1.0
				}
				cursor_x += rune_width
			}
		} else {
			words := strings.split(explicit_line, " ", context.temp_allocator)
			for word in words {
				word_width: f32 = 0.0
				if len(word) > 0 {
					c_word := fmt.ctprintf("%s", word)
					w, h: i32
					ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
					word_width = f32(w)

					if el.resolved_text_wrap == .WORD &&
					   cursor_x + word_width > max_width &&
					   cursor_x > 0 {
						cursor_x = 0
						total_lines += 1.0
					}
				}
				cursor_x += word_width + space_width
			}
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

		el.resolved_text_wrap = parent.resolved_text_wrap
		el.resolved_opacity = parent.resolved_opacity

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

		el.resolved_text_wrap = .WORD
		el.resolved_opacity = 1.0

		DEFAULT_FONT_HASH := hash.fnv32(transmute([]byte)string("default_font"))
		el.resolved_font = ctx.fonts[DEFAULT_FONT_HASH]
	}
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

	if v, ok := s.opacity.?; ok {
		el.resolved_opacity = v
	}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	if v, ok := s.text_wrap.?; ok {
		el.resolved_text_wrap = v
	}

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

	if v, ok := s.min_width.?; ok {
		el._box.min_width = v
	}

	if v, ok := s.max_width.?; ok {
		el._box.max_width = v
	}

	if v, ok := s.min_height.?; ok {
		el._box.min_height = v
	}

	if v, ok := s.max_height.?; ok {
		el._box.max_height = v
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

@(private)
set_clip :: proc(renderer: ^sdl.Renderer, current: ^Maybe(lc.Rect), target: Maybe(lc.Rect)) {
	if current^ == target do return

	if t, ok := target.?; ok {
		clip_rect := sdl.Rect{i32(t.x), i32(t.y), i32(t.width), i32(t.height)}
		sdl.RenderSetClipRect(renderer, &clip_rect)
	} else {
		sdl.RenderSetClipRect(renderer, nil) // Removes the clip
	}
	current^ = target
}

render_box :: proc(
	ui_ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	box: ^lc.Box,
	current_clip: ^Maybe(lc.Rect),
) {
	previous_clip := current_clip^

	set_clip(renderer, current_clip, box.clip_rect)

	if box.user_data == nil do return
	el := (^Element)(box.user_data)

	bg_color := el.resolved_bg_color
	bg_color[3] *= el.resolved_opacity

	border_color := el.resolved_border_color
	border_color[3] *= el.resolved_opacity

	bounds := sdl.Rect{i32(box.x), i32(box.y), i32(box.computed_width), i32(box.computed_height)}
	sdl.SetRenderDrawBlendMode(renderer, .BLEND) // Ensure alpha blending is active

	draw_ui_box(renderer, bounds, bg_color, border_color, box.border, el.resolved_border_radius)

	// 4. Draw Cached Text
	if text, ok := box.text.?; ok {
		if el.resolved_font != nil { 	// Prevent Segfault if font is missing!

			text_x := box.x + box.padding[lc.Side.LEFT] + box.border[lc.Side.LEFT]
			text_y := box.y + box.padding[lc.Side.TOP] + box.border[lc.Side.TOP]

			inner_width := max(
				box.computed_width -
				lc.get_horizontal(box.padding) -
				lc.get_horizontal(box.border),
				0.0,
			)

			space_w, space_h: i32
			ttf.SizeUTF8(el.resolved_font, " ", &space_w, &space_h)
			space_width := f32(space_w)
			line_height := f32(ttf.FontHeight(el.resolved_font))

			cursor_y := text_y
			explicit_lines := strings.split(text, "\n", context.temp_allocator)

			for explicit_line in explicit_lines {
				if el.resolved_text_wrap == .LETTER {
					runes := utf8.string_to_runes(explicit_line, context.temp_allocator)
					start_idx := 0
					for start_idx < len(runes) {
						end_idx := start_idx
						line_width: f32 = 0.0

						// 1. Measure how many runes fit on this line
						for end_idx < len(runes) {
							buf: [5]u8
							bytes, n := utf8.encode_rune(runes[end_idx])
							for j in 0 ..< n do buf[j] = bytes[j]
							buf[n] = 0

							w, h: i32
							ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)
							rune_width := f32(w)

							if line_width + rune_width > inner_width && end_idx > start_idx {
								break
							}
							line_width += rune_width
							end_idx += 1
						}

						// 2. Align the line horizontally
						start_x := text_x
						if el.resolved_text_align == .CENTER {
							start_x += max((inner_width - line_width) / 2.0, 0.0)
						} else if el.resolved_text_align == .RIGHT {
							start_x += max(inner_width - line_width, 0.0)
						}
						cursor_x := start_x

						// 3. Draw the cached runes
						for i in start_idx ..< end_idx {
							buf: [5]u8
							bytes, n := utf8.encode_rune(runes[i])
							for j in 0 ..< n do buf[j] = bytes[j]
							buf[n] = 0
							rune_str := string(buf[:n])

							cached := get_word_texture(
								ui_ctx,
								renderer,
								rune_str,
								el.resolved_font,
								el.resolved_text_color,
							)
							if cached.texture != nil {
								dest := sdl.Rect {
									i32(cursor_x),
									i32(cursor_y),
									cached.width,
									cached.height,
								}
								sdl.SetTextureAlphaMod(
									cached.texture,
									u8(el.resolved_opacity * 255.0),
								)
								sdl.RenderCopy(renderer, cached.texture, nil, &dest)
								cursor_x += f32(cached.width)
							}
						}
						cursor_y += line_height
						start_idx = end_idx
					}
				} else {
					words := strings.split(explicit_line, " ", context.temp_allocator)
					start_idx := 0
					for start_idx < len(words) {
						end_idx := start_idx
						line_width: f32 = 0.0

						// Measure how many words fit on this line
						for end_idx < len(words) {
							word_width: f32 = 0.0
							if len(words[end_idx]) > 0 {
								c_word := fmt.ctprintf("%s", words[end_idx])
								w, h: i32
								ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
								word_width = f32(w)
							}
							if el.resolved_text_wrap == .WORD &&
							   end_idx > start_idx &&
							   line_width + word_width > inner_width {
								break
							}
							line_width += word_width + space_width
							end_idx += 1
						}

						if end_idx > start_idx do line_width -= space_width

						// Align the line horizontally
						start_x := text_x
						if el.resolved_text_align == .CENTER {
							start_x += max((inner_width - line_width) / 2.0, 0.0)
						} else if el.resolved_text_align == .RIGHT {
							start_x += max(inner_width - line_width, 0.0)
						}
						cursor_x := start_x

						// Draw the cached words
						for i in start_idx ..< end_idx {
							if len(words[i]) > 0 {
								cached := get_word_texture(
									ui_ctx,
									renderer,
									words[i],
									el.resolved_font,
									el.resolved_text_color,
								)
								if cached.texture != nil {
									dest := sdl.Rect {
										i32(cursor_x),
										i32(cursor_y),
										cached.width,
										cached.height,
									}
									sdl.SetTextureAlphaMod(
										cached.texture,
										u8(el.resolved_opacity * 255.0),
									)
									sdl.RenderCopy(renderer, cached.texture, nil, &dest)
									cursor_x += f32(cached.width)
								}
							}
							cursor_x += space_width
						}
						cursor_y += line_height
						start_idx = end_idx
					}
				}
			}
		}
	}

	for child in box.children {
		render_box(ui_ctx, renderer, child, current_clip)
	}

	// 5. RESTORE the caller's clip state before returning
	set_clip(renderer, current_clip, previous_clip)
}

render_tree :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, root_boxes: []^lc.Box) {
	lc.end_layout(ctx.layout)


	current_clip: Maybe(lc.Rect) = nil
	for root_box in root_boxes {
		render_box(ctx, renderer, root_box, &current_clip)
	}

	if current_clip != nil {
		sdl.RenderSetClipRect(renderer, nil)
	}
}


ui_context_create :: proc(screen_width, screen_height: f32) -> ^UI_Context {
	ctx := new(UI_Context)

	// Pass the new SDL text measurement functions to the layout core
	ctx.layout = lc.layout_context_create(
		ui_text_width,
		ui_text_height,
		screen_width,
		screen_height,
	)

	ctx.stylesheet = make(map[Class]Style)
	ctx.fonts = make(map[u32]^ttf.Font)
	ctx.word_cache = make(map[u64]Cached_Texture) // Your new VRAM cache

	return ctx
}

ui_context_destroy :: proc(ctx: ^UI_Context) {
	lc.layout_context_destroy(ctx.layout)

	// Purge GPU textures before destroying the map
	clear_texture_cache(ctx)
	delete(ctx.word_cache)

	delete(ctx.stylesheet)
	delete(ctx.fonts)
	free(ctx)
}

ui_begin_frame :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, screen_w, screen_h: i32) {
	// Note: Event processing and pointer state updates will go here next

	lc.layout_reset(ctx.layout)
	ctx.layout.screen_width = f32(screen_w)
	ctx.layout.screen_height = f32(screen_h)
	lc.begin_layout(ctx.layout)
}

ui_end_frame :: proc(ctx: ^UI_Context) -> []^lc.Box {
	return ctx.layout.root_boxes[:] // Return the built tree for animations to use
}


element_open :: proc(ctx: ^UI_Context, el_val: Element, loc := #caller_location) {
	// Allocate the element for this frame
	el := new(Element, context.temp_allocator)
	el^ = el_val

	// Auto-generate an ID based on the call site if one wasn't provided
	if el._box.id == 0 {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		el._box.id = lc.Box_ID(hash.fnv32(transmute([]byte)loc_str))
	}

	// Resolve cascading styles
	apply_styles(el, ctx)

	// Bind the styled element to the layout box
	el._box.user_data = el

	lc.box_open(ctx.layout, el._box, loc)
}

element_close :: proc(ctx: ^UI_Context) {
	lc.box_close(ctx.layout)
}
