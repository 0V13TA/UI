package renderer

import avcodec "../ffmpeg-bindings/avcodec"
import avformat "../ffmpeg-bindings/avformat"
import avutil "../ffmpeg-bindings/avutil"
import types "../ffmpeg-bindings/types"
import "core:c"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import sdl "vendor:sdl2"

Video_Frame :: struct {
	y_plane, u_plane, v_plane: []u8,
	y_pitch, u_pitch, v_pitch: i32,
	pts:                       f64,
}

Video_Player :: struct {
	texture:          ^sdl.Texture,
	width:            i32,
	height:           i32,
	is_playing:       bool,
	playback_time:    f64,

	// --- FFmpeg State ---
	file_path:        string,
	fmt_ctx:          ^types.Format_Context,
	codec_ctx:        ^types.Codec_Context,
	video_stream_idx: i32,

	// --- Threading ---
	decoder_thread:   ^thread.Thread,
	frame_queue:      [dynamic]Video_Frame,
	queue_mutex:      sync.Mutex,
	quit_flag:        bool,
}

video_player_init :: proc(renderer: ^sdl.Renderer, path: string) -> ^Video_Player {
	player := new(Video_Player)
	player.file_path = path
	player.is_playing = true
	player.frame_queue = make([dynamic]Video_Frame)

	c_path := strings.clone_to_cstring(path)
	defer delete(c_path)

	if avformat.open_input(&player.fmt_ctx, c_path, nil, nil) < 0 {
		fmt.printfln("FFMPEG ERROR: Could not open file: %s", path)
		return nil
	}

	if avformat.find_stream_info(player.fmt_ctx, nil) < 0 {
		fmt.println("FFMPEG ERROR: Could not find stream info")
		return nil
	}

	player.video_stream_idx = -1
	codec: ^types.Codec = nil
	streams := slice.from_ptr(player.fmt_ctx.streams, int(player.fmt_ctx.nb_streams))

	for stream, i in streams {
		if stream.codecpar.codec_type == .Video {
			player.video_stream_idx = i32(i)
			codec = avcodec.find_decoder(stream.codecpar.codec_id)
			break
		}
	}

	if player.video_stream_idx == -1 || codec == nil {
		fmt.println("FFMPEG ERROR: No video stream or unsupported codec found")
		return nil
	}

	player.codec_ctx = avcodec.alloc_context3(codec)
	avcodec.parameters_to_context(player.codec_ctx, streams[player.video_stream_idx].codecpar)

	if avcodec.open2(player.codec_ctx, codec, nil) < 0 {
		fmt.println("FFMPEG ERROR: Could not open codec")
		return nil
	}

	// BRUTE FORCE FIX: FFmpeg's AV_PIX_FMT_YUV420P is exactly 0 in C.
	// We cast it to the Odin enum to completely bypass the broken binding mapping.
	FORCE_YUV420P := cast(types.Pixel_Format)c.int(0)


	player.width = player.codec_ctx.width
	player.height = player.codec_ctx.height

	// Create an IYUV texture for hardware color conversion
	player.texture = sdl.CreateTexture(
		renderer,
		sdl.PixelFormatEnum.IYUV,
		sdl.TextureAccess.STREAMING,
		player.width,
		player.height,
	)

	player.decoder_thread = thread.create_and_start_with_data(player, ffmpeg_worker_thread)
	return player
}

video_player_update :: proc(player: ^Video_Player, dt: f64) {
	if !player.is_playing do return

	player.playback_time += dt

	sync.lock(&player.queue_mutex)
	defer sync.unlock(&player.queue_mutex)

	if len(player.frame_queue) > 0 {
		next_frame := player.frame_queue[0]

		if player.playback_time >= next_frame.pts {
			// Pass all 3 planar components directly to the GPU shader
			sdl.UpdateYUVTexture(
				player.texture,
				nil,
				raw_data(next_frame.y_plane),
				next_frame.y_pitch,
				raw_data(next_frame.u_plane),
				next_frame.u_pitch,
				raw_data(next_frame.v_plane),
				next_frame.v_pitch,
			)

			delete(next_frame.y_plane)
			delete(next_frame.u_plane)
			delete(next_frame.v_plane)
			ordered_remove(&player.frame_queue, 0)
		}
	}
}

video_player_destroy :: proc(player: ^Video_Player) {
	player.quit_flag = true
	thread.join(player.decoder_thread)
	thread.destroy(player.decoder_thread)

	sdl.DestroyTexture(player.texture)

	// Clean up any remaining unplayed frames
	for f in player.frame_queue {
		delete(f.y_plane)
		delete(f.u_plane)
		delete(f.v_plane)
	}
	delete(player.frame_queue)
}

@(private)
ffmpeg_worker_thread :: proc(data: rawptr) {
	player := cast(^Video_Player)data

	pkt: ^types.Packet = avcodec.packet_alloc()
	frame: ^types.Frame = avutil.frame_alloc()
	defer {
		avcodec.packet_free(&pkt)
		avutil.frame_free(&frame)
	}

	MAX_BUFFERED_FRAMES :: 30
	stream := player.fmt_ctx.streams[player.video_stream_idx]
	time_base := f64(stream.time_base.numerator) / f64(stream.time_base.denominator)

	for !player.quit_flag {
		sync.lock(&player.queue_mutex)
		queue_len := len(player.frame_queue)
		sync.unlock(&player.queue_mutex)

		if queue_len >= MAX_BUFFERED_FRAMES {
			time.sleep(time.Millisecond * 5)
			continue
		}

		if avformat.read_frame(player.fmt_ctx, pkt) < 0 do break
		defer avcodec.packet_unref(pkt)

		if pkt.stream_index != player.video_stream_idx do continue

		if avcodec.send_packet(player.codec_ctx, pkt) == 0 {
			for avcodec.receive_frame(player.codec_ctx, frame) == 0 {
				pts_seconds := f64(frame.best_effort_timestamp) * time_base

				// YUV420P Math: U and V planes are half the resolution of Y
				y_pitch := player.width
				u_pitch := player.width / 2
				v_pitch := player.width / 2

				new_frame := Video_Frame {
					y_plane = make([]u8, y_pitch * player.height),
					u_plane = make([]u8, u_pitch * (player.height / 2)),
					v_plane = make([]u8, v_pitch * (player.height / 2)),
					y_pitch = y_pitch,
					u_pitch = u_pitch,
					v_pitch = v_pitch,
					pts     = pts_seconds,
				}

				// Safely cast FFmpeg's raw C-pointers to Odin multi-pointers for slicing
				src_y := cast([^]u8)frame.data[0]
				src_u := cast([^]u8)frame.data[1]
				src_v := cast([^]u8)frame.data[2]

				// 1. Copy Y Plane (Luma - Full Resolution)
				for y: i32 = 0; y < player.height; y += 1 {
					src_idx := y * frame.linesize[0]
					dst_idx := y * new_frame.y_pitch

					copy(
						new_frame.y_plane[dst_idx:dst_idx + player.width],
						src_y[src_idx:src_idx + player.width],
					)
				}

				// 2. Copy U and V Planes (Chroma - Half Resolution for 4:2:0)
				half_w := player.width / 2
				half_h := player.height / 2

				for y: i32 = 0; y < half_h; y += 1 {
					src_idx_u := y * frame.linesize[1]
					src_idx_v := y * frame.linesize[2]

					dst_idx_u := y * new_frame.u_pitch
					dst_idx_v := y * new_frame.v_pitch

					copy(
						new_frame.u_plane[dst_idx_u:dst_idx_u + half_w],
						src_u[src_idx_u:src_idx_u + half_w],
					)
					copy(
						new_frame.v_plane[dst_idx_v:dst_idx_v + half_w],
						src_v[src_idx_v:src_idx_v + half_w],
					)
				}

				sync.lock(&player.queue_mutex)
				append(&player.frame_queue, new_frame)
				sync.unlock(&player.queue_mutex)

				avutil.frame_unref(frame)
			}
		}
	}
}
