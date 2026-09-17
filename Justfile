run:
  odin run . -collection:ffmpeg=ffmpeg-bindings -debug

run-normal:
  odin run . -collection:ffmpeg=ffmpeg-bindings

debug:
  odin build . -collection:ffmpeg=ffmpeg-bindings -debug
