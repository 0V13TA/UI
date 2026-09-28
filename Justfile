sdl2:
  cmake -S SDL -B build/sdl2 -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF {{env_var_or_default("SDL_CMAKE_ARGS", "")}}
  cmake --build build/sdl2 --parallel
  cmake --install build/sdl2 --prefix "$PWD/build/sdl2-install"

sdl2-sources:
  mkdir -p build/sources/SDL_image build/sources/SDL_ttf
  git -C SDL_image archive release-2.8.8 | tar -x -C build/sources/SDL_image
  git -C SDL_ttf archive release-2.24.0 | tar -x -C build/sources/SDL_ttf

sdl2-image: sdl2 sdl2-sources
  cmake -S build/sources/SDL_image -B build/sdl2-image -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$PWD/build/sdl2-install" -DSDL2_DIR="$PWD/build/sdl2-install/lib/cmake/SDL2" -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF -DSDL2IMAGE_INSTALL=OFF {{env_var_or_default("SDL_CMAKE_ARGS", "")}}
  cmake --build build/sdl2-image --parallel

sdl2-ttf: sdl2 sdl2-sources
  cmake -S build/sources/SDL_ttf -B build/sdl2-ttf -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$PWD/build/sdl2-install" -DSDL2_DIR="$PWD/build/sdl2-install/lib/cmake/SDL2" -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_INSTALL=OFF {{env_var_or_default("SDL_CMAKE_ARGS", "")}}
  cmake --build build/sdl2-ttf --parallel

build: sdl2-image sdl2-ttf
  odin build . -collection:ffmpeg=ffmpeg-bindings -out:UI -extra-linker-flags:'-Lbuild/sdl2-install/lib -Lbuild/sdl2-image -Lbuild/sdl2-ttf -Wl,-rpath,$ORIGIN/build/sdl2-install/lib:$ORIGIN/build/sdl2-image:$ORIGIN/build/sdl2-ttf'

run: debug
  ./UI

run-normal: build
  ./UI

debug: sdl2-image sdl2-ttf
  odin build . -collection:ffmpeg=ffmpeg-bindings -debug -out:UI -extra-linker-flags:'-Lbuild/sdl2-install/lib -Lbuild/sdl2-image -Lbuild/sdl2-ttf -Wl,-rpath,$ORIGIN/build/sdl2-install/lib:$ORIGIN/build/sdl2-image:$ORIGIN/build/sdl2-ttf'
