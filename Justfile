sdl2:
  cmake -S SDL -B build/sdl2 -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF
  cmake --build build/sdl2 --parallel

build: sdl2
  odin build . -collection:ffmpeg=ffmpeg-bindings -out:UI -extra-linker-flags:'-Lbuild/sdl2 -Wl,-rpath,$ORIGIN/build/sdl2'

run: debug
  ./UI

run-normal: build
  ./UI

debug: sdl2
  odin build . -collection:ffmpeg=ffmpeg-bindings -debug -out:UI -extra-linker-flags:'-Lbuild/sdl2 -Wl,-rpath,$ORIGIN/build/sdl2'
