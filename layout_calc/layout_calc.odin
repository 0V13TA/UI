package layout_calc

import "core:fmt"
import "core:hash"
import "core:mem"
import "core:slice"

Layout_Arena_Block :: struct {
	arena:  mem.Arena,
	buffer: []byte,
	next:   ^Layout_Arena_Block,
}

Layout_Chained_Arena :: struct {
	backing_allocator: mem.Allocator,
	first, current:    ^Layout_Arena_Block,
	block_size:        int,
}

Layout_Context :: struct {
	arenas:           [2]Layout_Chained_Arena,
	active_idx:       u8, // Toggles between 0 and 1
	screen_width:     f32,
	screen_height:    f32,
	text_width_func:  proc(box: ^Box, text: string) -> f32,
	text_height_func: proc(box: ^Box, text: string, max_width: f32) -> f32,
	parent_stack:     [dynamic]^Box,
	draw_buffer:      [dynamic]^Box, // Sorted buffer by depth
	all_boxes:        map[Box_ID]^Box,
	root_boxes:       [dynamic]^Box, // Need this because defer is block scope
	prev_all_boxes:   map[Box_ID]^Box,
	prev_root_boxes:  [dynamic]^Box,
}

Direction :: enum {
	ROW,
	COLUMN,
	ROW_REVERSE,
	COLUMN_REVERSE,
}

Align :: enum {
	START,
	CENTER,
	END,
	STRETCH,
	SPACE_BETWEEN,
}

Side :: enum {
	TOP,
	RIGHT,
	BOTTOM,
	LEFT,
}

Overflow :: enum {
	VISIBLE, // Overflows, does not resize anything and draws over parent
	HIDDEN, // No scrollbar hides content that overflows
	SCROLL, // Scrollbar and whatnot
}

Fixed :: struct {
	value: f32,
}
Percent :: struct {
	value: f32,
}
ViewPercent :: struct {
	value: f32,
}
Grow :: struct {
	factor: f32,
}
Shrink :: struct {
	factor: f32,
}
Fit :: distinct bool

Sizing :: union {
	Fixed,
	Percent,
	ViewPercent,
	Grow,
	Shrink,
	Fit,
}

// Restricted union for min/max bounds (Only Fixed or ViewPercent)
Bound_Sizing :: union {
	Fixed,
	ViewPercent,
}

Rect :: struct {
	x, y, width, height: f32,
}

Position :: enum {
	STATIC,
	STICKY,
	ABSOLUTE,
	RELATIVE,
	FIXED,
}

Box_ID :: distinct u32
Box :: struct {
	id:                    Box_ID,
	user_data:             rawptr,
	warned:                bool,

	// Sizing Intent
	width:                 Sizing,
	height:                Sizing,
	min_width, min_height: Bound_Sizing,
	max_width, max_height: Bound_Sizing,

	// Spacing
	padding:               [4]f32, // [TOP, RIGHT, BOTTOM, LEFT]
	margin:                [4]f32,
	border:                [4]f32,
	gap:                   f32,

	// Flex Alignment
	direction:             Direction,
	justify_content:       Align,
	align_items:           Align,
	basis:                 f32,
	wrap:                  bool,

	// Position
	top:                   Maybe(f32), // Only useful if position != STATIC
	left:                  Maybe(f32),
	right:                 Maybe(f32),
	bottom:                Maybe(f32),
	position:              Position,

	// Depth
	z_index:               i32,

	// Content (Optional)
	text:                  Maybe(string),
	text_height:           f32, // Explicitly track resolved text height
	frozen:                bool, // For the iterative flex redistribution loop

	// Scrolling
	offset_x:              f32,
	offset_y:              f32,
	scroll_width:          f32,
	scroll_height:         f32,
	overflow_x:            Overflow,
	overflow_y:            Overflow,
	clip_rect:             Maybe(Rect), // resolved visible bounds; nil = unclipped, inherit nothing new

	// Hierarchy
	parent:                ^Box,
	children:              [dynamic]^Box,

	// Output Coordinates (Bounding Box)
	x, y:                  f32,
	computed_width:        f32,
	computed_height:       f32,
}

// --- Arena Implementation ---

chained_arena_new_block :: proc(ca: ^Layout_Chained_Arena, min_size: int) -> ^Layout_Arena_Block {
	size := max(min_size, ca.block_size)
	block := new(Layout_Arena_Block, ca.backing_allocator)
	block.buffer = make([]byte, size, ca.backing_allocator)
	mem.arena_init(&block.arena, block.buffer)
	return block
}

chained_arena_init :: proc(
	ca: ^Layout_Chained_Arena,
	block_size := 1024 * 1024,
	backing_allocator := context.allocator,
) {
	ca.backing_allocator = backing_allocator
	ca.block_size = block_size
	ca.first = chained_arena_new_block(ca, block_size)
	ca.current = ca.first
}

chained_arena_destroy :: proc(ca: ^Layout_Chained_Arena) {
	block := ca.first
	for block != nil {
		next := block.next
		delete(block.buffer, ca.backing_allocator)
		free(block, ca.backing_allocator)
		block = next
	}
	ca.first = nil
	ca.current = nil
}

chained_arena_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	ca := (^Layout_Chained_Arena)(allocator_data)

	switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		arena_alloc := mem.arena_allocator(&ca.current.arena)
		data, err := arena_alloc.procedure(
			arena_alloc.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)

		if err == .Out_Of_Memory {
			// Ensure the next block exists AND has enough capacity for this allocation
			if ca.current.next != nil && len(ca.current.next.buffer) < size {
				new_block := chained_arena_new_block(ca, size)
				new_block.next = ca.current.next
				ca.current.next = new_block
			} else if ca.current.next == nil {
				ca.current.next = chained_arena_new_block(ca, size)
			}
			ca.current = ca.current.next

			next_alloc := mem.arena_allocator(&ca.current.arena)

			// If resizing across blocks, allocate fresh memory and copy old data
			if mode == .Resize || mode == .Resize_Non_Zeroed {
				data, err = next_alloc.procedure(
					next_alloc.data,
					.Alloc,
					size,
					alignment,
					nil,
					0,
					loc,
				)
				if err == nil && old_memory != nil {
					mem.copy(raw_data(data), old_memory, min(old_size, size))
				}
			} else {
				data, err = next_alloc.procedure(
					next_alloc.data,
					mode,
					size,
					alignment,
					old_memory,
					old_size,
					loc,
				)
			}
		}
		return data, err

	case .Free_All:
		for block := ca.first; block != nil; block = block.next {
			block.arena.offset = 0
		}
		ca.current = ca.first
		return nil, nil

	case .Free, .Query_Features, .Query_Info:
		return nil, .Mode_Not_Implemented
	}

	return nil, .Mode_Not_Implemented
}

chained_arena_allocator :: proc(ca: ^Layout_Chained_Arena) -> mem.Allocator {
	return mem.Allocator{procedure = chained_arena_proc, data = ca}
}

// --- Helper Functions ---

ID :: proc(id: string) -> Box_ID {
	return Box_ID(hash.fnv32(transmute([]byte)id))
}

rect_intersect :: proc(a, b: Rect) -> Rect {
	x1 := max(a.x, b.x)
	y1 := max(a.y, b.y)
	x2 := min(a.x + a.width, b.x + b.width)
	y2 := min(a.y + a.height, b.y + b.height)
	return Rect{x1, y1, max(x2 - x1, 0), max(y2 - y1, 0)}
}

clamp_value :: proc(min_bound, max_bound: Bound_Sizing, value: f32, viewport_dim: f32) -> f32 {
	result := value

	if min_w := resolve_bound(min_bound, viewport_dim); min_w >= 0 {
		result = max(result, min_w)
	}

	if max_w := resolve_bound(max_bound, viewport_dim); max_w >= 0 {
		result = min(result, max_w)
	}

	return result
}

// Absolute spatial boundaries (Direction agnostic)
get_horizontal :: proc(v: [4]f32) -> f32 {
	return v[Side.LEFT] + v[Side.RIGHT]
}

get_vertical :: proc(v: [4]f32) -> f32 {
	return v[Side.TOP] + v[Side.BOTTOM]
}

resolve_bound :: proc(bound: Bound_Sizing, viewport_dim: f32) -> f32 {
	switch v in bound {
	case Fixed:
		return v.value
	case ViewPercent:
		return (v.value / 100.0) * viewport_dim
	case:
		return -1
	}
	return -1
}

// --- Tree Building ---
new_box_from_config :: proc(
	ctx: ^Layout_Context,
	box_config: Box,
	loc := #caller_location,
) -> ^Box {
	arena_alloc := chained_arena_allocator(&ctx.arenas[ctx.active_idx])
	box, err := new(Box, arena_alloc)
	if err != nil do panic("Failed to allocate memory")

	box^ = box_config
	if box.id == 0 {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		box.id = Box_ID(hash.fnv32a(transmute([]byte)loc_str))
	}

	if prev_box, ok := ctx.prev_all_boxes[box.id]; ok {
		box.offset_x = prev_box.offset_x
		box.offset_y = prev_box.offset_y
	}

	box.children = make([dynamic]^Box, 0, 4, arena_alloc)
	box.computed_width = -1
	box.computed_height = -1
	return box
}

resolve_fixed_width :: proc(
	box: ^Box,
	ctx: ^Layout_Context,
	viewport_dim: f32,
	parent_is_fit: bool,
) {
	if box.computed_width != -1 do return
	is_row := box.direction == .ROW || box.direction == .ROW_REVERSE

	switch v in box.width {
	case Fixed:
		box.computed_width = v.value
	case ViewPercent:
		box.computed_width = max(
			((v.value / 100.0) * viewport_dim) - get_horizontal(box.margin),
			0.0,
		)
	case Percent:
		if parent_is_fit || box.parent == nil {
			box.computed_width = 0.0
			if !box.warned {
				parent_id := box.parent != nil ? box.parent.id : 0
				fmt.printfln(
					"Box: %d is dependent on parent: %d, which is Fit-sized",
					box.id,
					parent_id,
				)
				box.warned = true
			}
		} else {
			parent_inner_width := max(
				box.parent.computed_width -
				get_horizontal(box.parent.padding) -
				get_horizontal(box.parent.border),
				0.0,
			)
			box.computed_width = max(
				((v.value / 100.0) * parent_inner_width) - get_horizontal(box.margin),
				0.0,
			)
		}
	case Grow:
		box.computed_width = 0.0
	case Shrink:
		// Fix 1: Shrink starts at box.basis rather than 0
		box.computed_width = box.basis
	case Fit:
		sum: f32 = 0.0
		if val, ok := box.text.?; ok do sum = ctx.text_width_func(box, val)
		for child in box.children {
			resolve_fixed_width(child, ctx, viewport_dim, true)
			child_total := child.computed_width + get_horizontal(child.margin)
			if is_row {sum += child_total} else {sum = max(sum, child_total)}
		}
		gap_count := max(len(box.children) - 1, 0)
		if is_row do sum += f32(gap_count) * box.gap
		box.computed_width = sum + get_horizontal(box.padding) + get_horizontal(box.border)

	case:
		// If width is unset, default to text width (if it exists) or 0
		if text, ok := box.text.?; ok {
			box.computed_width =
				ctx.text_width_func(box, text) +
				get_horizontal(box.padding) +
				get_horizontal(box.border)
		} else do box.computed_width = 0

	}

	if min_w := resolve_bound(box.min_width, viewport_dim); min_w >= 0 do box.computed_width = max(box.computed_width, min_w)
	if max_w := resolve_bound(box.max_width, viewport_dim); max_w >= 0 do box.computed_width = min(box.computed_width, max_w)

	#partial switch _ in box.width {
	case Fit, Grow, Shrink:
	// Skip recursion here; children will be sized in grow_shrink_width
	case:
		for child in box.children {
			resolve_fixed_width(child, ctx, viewport_dim, false)
		}
	}
}

grow_shrink_width :: proc(box: ^Box, ctx: ^Layout_Context, viewport_dim: f32) {
	#partial switch _ in box.width {
	case Grow, Shrink:
		for child in box.children {
			resolve_fixed_width(child, ctx, viewport_dim, false)
		}
	}


	switch box.direction {
	case .ROW, .ROW_REVERSE:
		parent_inner_width :=
			box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border)
		start := 0

		for start < len(box.children) {
			end := start
			line_sum: f32 = 0.0

			// 1. Find the end index of the current line
			for end < len(box.children) {
				child := box.children[end]
				child_outer := child.computed_width + get_horizontal(child.margin)

				if box.wrap && end > start {
					if line_sum + box.gap + child_outer > parent_inner_width {
						break
					}
				}

				if end > start do line_sum += box.gap
				line_sum += child_outer
				end += 1
			}

			// 2. Process this specific line
			line_children := box.children[start:end]
			remaining_space := parent_inner_width - line_sum

			if remaining_space > 0 {
				for child in line_children do child.frozen = false
				iteration := 0
				for {
					iteration += 1
					if iteration > 100 {
						if !box.warned {
							fmt.printfln(
								"WARNING: Infinite flex-grow (height) loop on Box %d. Breaking.",
								box.id,
							)
							box.warned = true
						}
						break
					}

					total_grow_factor: f32 = 0
					for child in line_children {
						if !child.frozen {
							#partial switch v in child.width {case Grow:
								total_grow_factor += v.factor}
						}
					}
					if total_grow_factor <= 0 do break

					newly_frozen := false
					round_space := remaining_space // SNAPSHOT

					for child in line_children {
						if child.frozen do continue
						#partial switch v in child.width {
						case Grow:
							extra := round_space * (v.factor / total_grow_factor) // USE SNAPSHOT
							target := child.computed_width + extra
							clamped := clamp_value(
								child.min_width,
								child.max_width,
								target,
								viewport_dim,
							)

							if clamped != target {
								child.frozen = true
								newly_frozen = true
								remaining_space -= (clamped - child.computed_width)
								child.computed_width = clamped
							}
						}
					}

					if !newly_frozen {
						for child in line_children {
							if !child.frozen {
								#partial switch v in child.width {
								case Grow:
									child.computed_width +=
										remaining_space * (v.factor / total_grow_factor)
								}
							}
						}
						break
					}
				}
			} else if remaining_space < 0 {
				for child in line_children do child.frozen = false
				iteration := 0
				for {
					iteration += 1
					if iteration > 100 {
						if !box.warned {
							fmt.printfln(
								"WARNING: Infinite flex-shrink (height) loop on Box %d. Breaking.",
								box.id,
							)
							box.warned = true
						}
						break
					}

					total_shrink_factor: f32 = 0
					for child in line_children {
						if !child.frozen {
							#partial switch v in child.width {case Shrink:
								total_shrink_factor += v.factor * child.computed_width}
						}
					}
					if total_shrink_factor <= 0 do break

					newly_frozen := false
					round_space := remaining_space // SNAPSHOT

					for child in line_children {
						if child.frozen do continue
						#partial switch v in child.width {
						case Shrink:
							extra :=
								round_space *
								((v.factor * child.computed_width) / total_shrink_factor) // USE SNAPSHOT
							target := child.computed_width + extra
							clamped := clamp_value(
								child.min_width,
								child.max_width,
								target,
								viewport_dim,
							)

							if clamped != target {
								child.frozen = true
								newly_frozen = true
								remaining_space -= (clamped - child.computed_width)
								child.computed_width = clamped
							}
						}
					}

					if !newly_frozen {
						for child in line_children {
							if !child.frozen {
								#partial switch v in child.width {
								case Shrink:
									child.computed_width +=
										remaining_space *
										((v.factor * child.computed_width) / total_shrink_factor)
								}
							}
						}
						break
					}
				}
			}

			// 3. Advance to next line
			start = end
		}

	case .COLUMN, .COLUMN_REVERSE:
		parent_inner_width :=
			box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border)
		for child in box.children {
			should_stretch := false
			#partial switch _ in child.width {
			case Grow, Shrink:
				should_stretch = true
			case Fit:
				should_stretch = box.align_items == .STRETCH
			case:
				if child.width == nil {
					should_stretch = box.align_items == .STRETCH
				}
			}

			if should_stretch {
				child.computed_width = parent_inner_width - get_horizontal(child.margin)
				child.computed_width = clamp_value(
					child.min_width,
					child.max_width,
					child.computed_width,
					viewport_dim,
				)
			}
		}
	}

	for child in box.children {
		grow_shrink_width(child, ctx, viewport_dim)
	}
}

wrap_text :: proc(box: ^Box, ctx: ^Layout_Context) {
	// If text exists and text_height_func is provided
	if text, ok := box.text.?; ok && len(text) > 0 && ctx.text_height_func != nil {
		inner_width := max(
			box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border),
			0.0,
		)
		box.text_height = ctx.text_height_func(box, text, inner_width)
	}

	for child in box.children {
		wrap_text(child, ctx)
	}
}

resolve_fixed_height :: proc(box: ^Box, viewport_dim: f32, parent_is_fit: bool) {
	if box.computed_height != -1 do return

	is_column := box.direction == .COLUMN || box.direction == .COLUMN_REVERSE

	switch v in box.height {
	case Fixed:
		box.computed_height = v.value
	case ViewPercent:
		box.computed_height = max(
			((v.value / 100.0) * viewport_dim) - get_vertical(box.margin),
			0.0,
		)
	case Percent:
		if parent_is_fit || box.parent == nil {
			box.computed_height = 0.0
			if !box.warned {
				parent_id := box.parent != nil ? box.parent.id : 0
				fmt.printfln(
					"Box: %d is dependent on parent: %d, which is Fit-sized",
					box.id,
					parent_id,
				)
				box.warned = true
			}
		} else {
			parent_inner_height := max(
				box.parent.computed_height -
				get_vertical(box.parent.padding) -
				get_vertical(box.parent.border),
				0.0,
			)
			box.computed_height = max(
				((v.value / 100.0) * parent_inner_height) - get_vertical(box.margin),
				0.0,
			)
		}
	case Grow:
		box.computed_height = 0.0
	case Shrink:
		box.computed_height = box.basis
	case Fit:
		content_height: f32 = 0.0

		if is_column {
			// Columns just sum all child heights
			for child in box.children {
				resolve_fixed_height(child, viewport_dim, true)
				content_height += child.computed_height + get_vertical(child.margin)
			}
			gap_count := max(len(box.children) - 1, 0)
			content_height += f32(gap_count) * box.gap
		} else {
			// Rows must calculate line by line to support wrapping
			parent_inner_width := max(
				box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border),
				0.0,
			)

			start := 0
			line_count := 0
			for start < len(box.children) {
				end := start
				line_width: f32 = 0.0
				line_max_height: f32 = 0.0

				for end < len(box.children) {
					child := box.children[end]
					resolve_fixed_height(child, viewport_dim, true)

					child_w := child.computed_width + get_horizontal(child.margin)
					child_h := child.computed_height + get_vertical(child.margin)

					if box.wrap && end > start {
						if line_width + box.gap + child_w > parent_inner_width do break
					}

					if end > start do line_width += box.gap
					line_width += child_w
					line_max_height = max(line_max_height, child_h)
					end += 1
				}

				if line_count > 0 do content_height += box.gap // Cross-axis gap between lines
				content_height += line_max_height

				line_count += 1
				start = end
			}
		}

		// Preserve text height if this node wraps text
		if text, ok := box.text.?; ok && len(text) > 0 {
			// Read safely from the explicit state!
			content_height = max(content_height, box.text_height)
		}

		box.computed_height = content_height + get_vertical(box.padding) + get_vertical(box.border)
	case:
		// If height is unset, default to text_height (if it exists) or 0
		if box.computed_height < 0 {
			if box.text_height > 0 {
				box.computed_height =
					box.text_height + get_vertical(box.padding) + get_vertical(box.border)
			} else {
				box.computed_height = 0
			}
		}
	}


	if min_h := resolve_bound(box.min_height, viewport_dim); min_h >= 0 do box.computed_height = max(box.computed_height, min_h)
	if max_h := resolve_bound(box.max_height, viewport_dim); max_h >= 0 do box.computed_height = min(box.computed_height, max_h)

	#partial switch _ in box.height {
	case Fit, Grow, Shrink:
	// Children visited during Fit loop or deferred to grow_shrink_height
	case:
		for child in box.children {
			resolve_fixed_height(child, viewport_dim, false)
		}
	}
}

grow_shrink_height :: proc(box: ^Box, viewport_dim: f32) {
	#partial switch _ in box.height {
	case Grow, Shrink:
		for child in box.children {
			resolve_fixed_height(child, viewport_dim, false)
		}
	}


	switch box.direction {
	case .COLUMN, .COLUMN_REVERSE:
		sum := f32(max((len(box.children) - 1), 0)) * box.gap
		for child in box.children do sum += child.computed_height + get_vertical(child.margin)

		parent_inner_height :=
			box.computed_height - get_vertical(box.padding) - get_vertical(box.border)
		remaining_space := parent_inner_height - sum

		if remaining_space > 0 {
			for child in box.children do child.frozen = false
			for {
				total_grow_factor: f32 = 0
				for child in box.children {
					if !child.frozen {
						#partial switch v in child.height {case Grow:
							total_grow_factor += v.factor}
					}
				}
				if total_grow_factor <= 0 do break

				newly_frozen := false
				round_space := remaining_space // SNAPSHOT

				for child in box.children {
					if child.frozen do continue
					#partial switch v in child.height {
					case Grow:
						extra := round_space * (v.factor / total_grow_factor) // USE SNAPSHOT
						target := child.computed_height + extra
						clamped := clamp_value(
							child.min_height,
							child.max_height,
							target,
							viewport_dim,
						)

						if clamped != target {
							child.frozen = true
							newly_frozen = true
							remaining_space -= (clamped - child.computed_height)
							child.computed_height = clamped
						}
					}
				}

				if !newly_frozen {
					for child in box.children {
						if !child.frozen {
							#partial switch v in child.height {
							case Grow:
								child.computed_height +=
									remaining_space * (v.factor / total_grow_factor)
							}
						}
					}
					break
				}
			}
		} else if remaining_space < 0 {
			for child in box.children do child.frozen = false
			for {
				total_shrink_factor: f32 = 0
				for child in box.children {
					if !child.frozen {
						#partial switch v in child.height {case Shrink:
							total_shrink_factor += v.factor * child.computed_height}
					}
				}
				if total_shrink_factor <= 0 do break

				newly_frozen := false
				round_space := remaining_space // SNAPSHOT

				for child in box.children {
					if child.frozen do continue
					#partial switch v in child.height {
					case Shrink:
						extra :=
							round_space *
							((v.factor * child.computed_height) / total_shrink_factor) // USE SNAPSHOT
						target := child.computed_height + extra
						clamped := clamp_value(
							child.min_height,
							child.max_height,
							target,
							viewport_dim,
						)

						if clamped != target {
							child.frozen = true
							newly_frozen = true
							remaining_space -= (clamped - child.computed_height)
							child.computed_height = clamped
						}
					}
				}

				if !newly_frozen {
					for child in box.children {
						if !child.frozen {
							#partial switch v in child.height {
							case Shrink:
								child.computed_height +=
									remaining_space *
									((v.factor * child.computed_height) / total_shrink_factor)
							}
						}
					}
					break
				}
			}
		}

	case .ROW, .ROW_REVERSE:
		parent_inner_width := max(
			box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border),
			0.0,
		)
		start := 0

		for start < len(box.children) {
			end := start
			line_width: f32 = 0.0
			line_max_height: f32 = 0.0
			flow_count := 0

			// 1. Identify the current line and its maximum cross-axis height
			for end < len(box.children) {
				child := box.children[end]

				if child.position == .ABSOLUTE || child.position == .FIXED {
					end += 1
					continue
				}

				child_w := child.computed_width + get_horizontal(child.margin)
				child_h := child.computed_height + get_vertical(child.margin)

				if box.wrap && flow_count > 0 {
					if line_width + box.gap + child_w > parent_inner_width do break
				}

				if flow_count > 0 do line_width += box.gap
				line_width += child_w
				line_max_height = max(line_max_height, child_h)
				flow_count += 1
				end += 1
			}

			// 2. Stretch children vertically against the LINE'S max height
			for i := start; i < end; i += 1 {
				child := box.children[i]
				if child.position == .ABSOLUTE || child.position == .FIXED do continue

				should_stretch := false
				#partial switch _ in child.height {
				case Grow, Shrink:
					should_stretch = true
				case Fit:
					should_stretch = box.align_items == .STRETCH
				case:
					if child.height == nil {
						should_stretch = box.align_items == .STRETCH
					}
				}

				if should_stretch {
					child.computed_height = line_max_height - get_vertical(child.margin)
					child.computed_height = clamp_value(
						child.min_height,
						child.max_height,
						child.computed_height,
						viewport_dim,
					)
				}
			}

			// 3. Advance to the next line
			start = end
		}
	}

	for child in box.children {
		grow_shrink_height(child, viewport_dim)
	}
}

layout_position_pass :: proc(
	box: ^Box,
	ctx: ^Layout_Context,
	parent_x: f32 = 0.0,
	parent_y: f32 = 0.0,
	inherited_clip: Maybe(Rect) = nil,
) {
	// 1. Calculate box's own top-left origin (including margins)
	box.x = parent_x + box.margin[Side.LEFT]
	box.y = parent_y + box.margin[Side.TOP]

	// Inner content origin for children (after padding and border)
	content_x := box.x + box.padding[Side.LEFT] + box.border[Side.LEFT] - box.offset_x
	content_y := box.y + box.padding[Side.TOP] + box.border[Side.TOP] - box.offset_y

	inner_width := max(
		box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border),
		0.0,
	)
	inner_height := max(
		box.computed_height - get_vertical(box.padding) - get_vertical(box.border),
		0.0,
	)

	is_row := box.direction == .ROW || box.direction == .ROW_REVERSE
	is_reverse := box.direction == .ROW_REVERSE || box.direction == .COLUMN_REVERSE
	parent_main_dim := is_row ? inner_width : inner_height

	current_cross: f32 = 0.0
	start := 0

	own_rect := Rect{box.x, box.y, box.computed_width, box.computed_height}
	clips_children := box.overflow_x != .VISIBLE || box.overflow_y != .VISIBLE
	effective_rect := own_rect
	if box.overflow_x == .VISIBLE {
		effective_rect.x = -1e9
		effective_rect.width = 2e9
	}
	if box.overflow_y == .VISIBLE {
		effective_rect.y = -1e9
		effective_rect.height = 2e9
	}

	child_clip := inherited_clip
	if clips_children {
		if inherited, ok := inherited_clip.?; ok {
			r := rect_intersect(inherited, effective_rect)
			child_clip = r
		} else {
			child_clip = effective_rect
		}
	}
	box.clip_rect = inherited_clip // what THIS box is drawn within


	for start < len(box.children) {
		end := start
		line_main_size: f32 = 0.0
		line_cross_size: f32 = 0.0
		flow_count := 0

		// 2. Measure the current line
		for end < len(box.children) {
			child := box.children[end]

			// Out of flow elements don't break lines or take space in flex calculation
			if child.position == .ABSOLUTE || child.position == .FIXED {
				end += 1
				continue
			}

			child_main :=
				is_row ? (child.computed_width + get_horizontal(child.margin)) : (child.computed_height + get_vertical(child.margin))
			child_cross :=
				is_row ? (child.computed_height + get_vertical(child.margin)) : (child.computed_width + get_horizontal(child.margin))

			if box.wrap && flow_count > 0 {
				if line_main_size + box.gap + child_main > parent_main_dim do break
			}

			if flow_count > 0 do line_main_size += box.gap
			line_main_size += child_main
			line_cross_size = max(line_cross_size, child_cross)

			flow_count += 1
			end += 1
		}

		if !box.wrap {
			parent_cross_dim := is_row ? inner_height : inner_width
			line_cross_size = max(line_cross_size, parent_cross_dim)
		}

		// 3. Determine main-axis cursor and gap step for the line based on justify_content
		free_space := parent_main_dim - line_main_size
		main_cursor: f32 = 0.0
		space_between_gap: f32 = box.gap

		switch box.justify_content {
		case .START, .STRETCH:
			main_cursor = 0.0
		case .CENTER:
			main_cursor = free_space * 0.5
		case .END:
			main_cursor = free_space
		case .SPACE_BETWEEN:
			if flow_count > 1 {
				space_between_gap = box.gap + (free_space / f32(flow_count - 1))
			}
			main_cursor = 0.0
		}

		current_main := is_reverse ? (parent_main_dim - main_cursor) : main_cursor

		// 4. Lay out children along the current line
		for i := start; i < end; i += 1 {
			child := box.children[i]

			// --- Out of Flow: ABSOLUTE / FIXED Positioning ---
			if child.position == .ABSOLUTE || child.position == .FIXED {
				anchor_x := (child.position == .FIXED) ? 0.0 : content_x
				anchor_y := (child.position == .FIXED) ? 0.0 : content_y
				bounds_w := (child.position == .FIXED) ? ctx.screen_width : inner_width
				bounds_h := (child.position == .FIXED) ? ctx.screen_height : inner_height

				child_x := anchor_x
				child_y := anchor_y

				if left, ok := child.left.?; ok {
					child_x = anchor_x + left
				} else if right, ok := child.right.?; ok {
					child_x = anchor_x + bounds_w - child.computed_width - right
				}

				if top, ok := child.top.?; ok {
					child_y = anchor_y + top
				} else if bottom, ok := child.bottom.?; ok {
					child_y = anchor_y + bounds_h - child.computed_height - bottom
				}

				layout_position_pass(child, ctx, child_x, child_y, child_clip)
				continue
			}

			// --- In Flow: Flex Layout Positioning ---
			child_main :=
				is_row ? (child.computed_width + get_horizontal(child.margin)) : (child.computed_height + get_vertical(child.margin))
			child_cross :=
				is_row ? (child.computed_height + get_vertical(child.margin)) : (child.computed_width + get_horizontal(child.margin))

			if is_reverse do current_main -= child_main

			// Calculate cross-axis offset against the LINE's cross size, not the parent's
			cross_offset: f32 = 0.0
			switch box.align_items {
			case .START, .STRETCH, .SPACE_BETWEEN:
				cross_offset = 0.0
			case .CENTER:
				cross_offset = (line_cross_size - child_cross) * 0.5
			case .END:
				cross_offset = line_cross_size - child_cross
			}

			child_x, child_y: f32
			if is_row {
				child_x = content_x + current_main
				child_y = content_y + current_cross + cross_offset
			} else {
				child_x = content_x + current_cross + cross_offset
				child_y = content_y + current_main
			}

			if child.position == .RELATIVE {
				if left, ok := child.left.?; ok do child_x += left
				if top, ok := child.top.?; ok do child_y += top
			}

			layout_position_pass(child, ctx, child_x, child_y, child_clip)

			if !is_reverse {
				current_main += child_main + space_between_gap
			} else {
				current_main -= space_between_gap
			}
		}

		// 5. Advance cross-axis cursor for the next line
		if flow_count > 0 {
			current_cross += line_cross_size + box.gap
		}

		start = end
	}

	// --- Replace the bottom of layout_position_pass with this: ---

	// 1. Define the inner origin (top-left of usable content area, UNSCROLLED)
	inner_origin_x := box.x + box.padding[Side.LEFT] + box.border[Side.LEFT]
	inner_origin_y := box.y + box.padding[Side.TOP] + box.border[Side.TOP]

	furthest_content_x := inner_origin_x
	furthest_content_y := inner_origin_y

	for child in box.children {
		// Out-of-flow elements don't stretch the scroll canvas
		if child.position == .ABSOLUTE || child.position == .FIXED do continue

		// 2. Bring the child's bounding box back to UNSCROLLED container space
		unscrolled_child_x := child.x + box.offset_x
		unscrolled_child_y := child.y + box.offset_y

		child_right := unscrolled_child_x + child.computed_width + child.margin[Side.RIGHT]
		child_bottom := unscrolled_child_y + child.computed_height + child.margin[Side.BOTTOM]

		if child_right > furthest_content_x do furthest_content_x = child_right
		if child_bottom > furthest_content_y do furthest_content_y = child_bottom
	}

	// 3. Find the raw span of the inner content
	inner_content_w := furthest_content_x - inner_origin_x
	inner_content_h := furthest_content_y - inner_origin_y

	// 4. Add the container's trailing padding & border
	total_inner_w := inner_content_w + box.padding[Side.RIGHT] + box.border[Side.RIGHT]
	total_inner_h := inner_content_h + box.padding[Side.BOTTOM] + box.border[Side.BOTTOM]

	// 5. Final dimensions live in the outer box's coordinate space (add leading padding & border)
	box.scroll_width = max(
		total_inner_w + box.padding[Side.LEFT] + box.border[Side.LEFT],
		box.computed_width,
	)
	box.scroll_height = max(
		total_inner_h + box.padding[Side.TOP] + box.border[Side.TOP],
		box.computed_height,
	)
}

// Sorts children locally by z_index
sort_siblings_by_z :: proc(box: ^Box) {
	if len(box.children) > 1 {
		slice.stable_sort_by(box.children[:], proc(a, b: ^Box) -> bool {
			return a.z_index < b.z_index
		})
	}

	for child in box.children {
		sort_siblings_by_z(child)
	}
}

box_open :: proc(ctx: ^Layout_Context, box_config: Box, loc := #caller_location) -> ^Box {
	box := new_box_from_config(ctx, box_config, loc)

	if len(ctx.parent_stack) > 0 {
		parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
		append(&parent.children, box)
		box.parent = parent
	} else {
		append(&ctx.root_boxes, box)
	}

	ctx.all_boxes[box.id] = box
	append(&ctx.parent_stack, box)

	return box
}

box_close :: proc(ctx: ^Layout_Context) {
	if len(ctx.parent_stack) > 0 {
		pop(&ctx.parent_stack)
	}
}

layout_context_create :: proc(
	text_width: proc(box: ^Box, text: string) -> f32,
	text_height: proc(box: ^Box, text: string, max_width: f32) -> f32,
	scr_width, scr_height: f32,
	allocator := context.allocator,
) -> ^Layout_Context {
	ctx := new(Layout_Context, allocator)
	ctx.text_width_func = text_width
	ctx.text_height_func = text_height
	ctx.screen_width = scr_width
	ctx.screen_height = scr_height

	for i in 0 ..< 2 {
		chained_arena_init(&ctx.arenas[i], 4096 * 4096, allocator)
	}

	ctx.all_boxes = make(map[Box_ID]^Box, allocator)
	ctx.prev_all_boxes = make(map[Box_ID]^Box, allocator)
	ctx.root_boxes = make([dynamic]^Box, allocator)
	ctx.prev_root_boxes = make([dynamic]^Box, allocator)

	ctx.parent_stack = make([dynamic]^Box, allocator)
	ctx.draw_buffer = make([dynamic]^Box, allocator)
	return ctx
}

layout_context_destroy :: proc(ctx: ^Layout_Context) {
	if ctx == nil do return
	backing_alloc := ctx.arenas[0].backing_allocator

	chained_arena_destroy(&ctx.arenas[0])
	chained_arena_destroy(&ctx.arenas[1])
	delete(ctx.all_boxes)
	delete(ctx.prev_all_boxes)
	delete(ctx.root_boxes)
	delete(ctx.prev_root_boxes)
	delete(ctx.parent_stack)
	delete(ctx.draw_buffer)
	free(ctx, backing_alloc)
}

layout_reset :: proc(ctx: ^Layout_Context) {
	// 1. Swap Arenas
	ctx.active_idx = 1 - ctx.active_idx
	arena_alloc := chained_arena_allocator(&ctx.arenas[ctx.active_idx])
	free_all(arena_alloc)

	// 2. Swap Maps & Arrays
	tmp_map := ctx.all_boxes
	ctx.all_boxes = ctx.prev_all_boxes
	ctx.prev_all_boxes = tmp_map
	clear(&ctx.all_boxes)

	tmp_roots := ctx.root_boxes
	ctx.root_boxes = ctx.prev_root_boxes
	ctx.prev_root_boxes = tmp_roots
	clear(&ctx.root_boxes)

	// 3. Clear Transient State
	clear(&ctx.parent_stack)
	clear(&ctx.draw_buffer)
}

begin_layout :: proc(ctx: ^Layout_Context) {
	// NOTE: This is the beginning of the tree
	layout_reset(ctx)
}

end_layout :: proc(ctx: ^Layout_Context) {
	for root in ctx.root_boxes {
		// --- Horizontal Width Passes ---
		resolve_fixed_width(root, ctx, ctx.screen_width, false)
		grow_shrink_width(root, ctx, ctx.screen_width)

		// --- Text Wrapping Pass ---
		wrap_text(root, ctx)

		// --- Vertical Height Passes ---
		resolve_fixed_height(root, ctx.screen_height, false)
		grow_shrink_height(root, ctx.screen_height)

		// Pass 6: Calculate final absolute (X, Y) coordinates
		layout_position_pass(root, ctx, 0.0, 0.0)
		sort_siblings_by_z(root)
	}
}
