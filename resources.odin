package UI

import "core:fmt"
import "core:hash"
import "core:strings"
import sdl "./vendor/sdl2"
import img "./vendor/sdl2/image"

@(rodata)
DEFAULT_FONT_BYTES := #load("resources/CaacupeOne-Regular.ttf", []u8)

@(rodata)
ICON_DOWN_BYTES := #load("resources/icons/down.png", []u8)

@(rodata)
ICON_LEFT_BYTES := #load("resources/icons/left_button.png", []u8)

@(rodata)
ICON_PAUSE_BYTES := #load("resources/icons/pause.png", []u8)

@(rodata)
ICON_PLAY_BUTTON_BYTES := #load("resources/icons/play-button.png", []u8)

@(rodata)
ICON_PLAY_BYTES := #load("resources/icons/play.png", []u8)

@(rodata)
ICON_RIGHT_BYTES := #load("resources/icons/right_button.png", []u8)

@(private)
builtin_resource :: proc(path: string) -> ([]u8, bool) {
	switch path {
	case "ui://font/default":
		return DEFAULT_FONT_BYTES, true
	case "ui://icons/down":
		return ICON_DOWN_BYTES, true
	case "ui://icons/left":
		return ICON_LEFT_BYTES, true
	case "ui://icons/pause":
		return ICON_PAUSE_BYTES, true
	case "ui://icons/play-button":
		return ICON_PLAY_BUTTON_BYTES, true
	case "ui://icons/play":
		return ICON_PLAY_BYTES, true
	case "ui://icons/right":
		return ICON_RIGHT_BYTES, true
	}
	return nil, false
}

@(private)
path_is_absolute :: proc(path: string) -> bool {
	if len(path) == 0 do return false
	return path[0] == '/' || path[0] == '\\' || (len(path) > 2 && path[1] == ':')
}

@(private)
resource_path_join :: proc(root, path: string) -> string {
	if len(root) == 0 do return path
	if len(path) == 0 do return root
	return fmt.tprintf("%s/%s", root, path)
}

@(private)
resource_open :: proc(asset_dir, path: string) -> ^sdl.RWops {
	if bytes, ok := builtin_resource(path); ok {
		return sdl.RWFromConstMem(raw_data(bytes), i32(len(bytes)))
	}

	resolved_path := path
	if !path_is_absolute(path) {
		when ODIN_PLATFORM_SUBTARGET == .Android {
			resolved_path = resource_path_join(asset_dir, path)
		} else {
			resource_root := asset_dir
			if !path_is_absolute(resource_root) {
				base_path := sdl.GetBasePath()
				if base_path == nil {
					fmt.printfln("ERROR: Could not locate application resources: %s", sdl.GetError())
					return nil
				}
				base_dir := strings.clone(string(base_path), context.temp_allocator)
				sdl.free(cast(rawptr)base_path)
				resource_root = resource_path_join(base_dir, asset_dir)
			}
			resolved_path = resource_path_join(resource_root, path)
		}
	}

	c_path := strings.clone_to_cstring(resolved_path, context.temp_allocator)
	rw := sdl.RWFromFile(c_path, "rb")
	if rw == nil {
		fmt.printfln("ERROR: Failed to open resource '%s': %s", path, sdl.GetError())
	}
	return rw
}

@(private)
get_image_texture :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	path: string,
) -> ^sdl.Texture {
	path_hash := hash.fnv32(transmute([]byte)path)
	if texture, exists := ctx.image_cache[path_hash]; exists {
		return texture
	}

	rw := resource_open(ctx.asset_dir, path)
	texture: ^sdl.Texture
	if rw != nil {
		texture = img.LoadTexture_RW(renderer, rw, true)
		if texture == nil {
			fmt.printfln("ERROR: Failed to load image '%s': %s", path, sdl.GetError())
		}
	}
	ctx.image_cache[path_hash] = texture
	return texture
}
