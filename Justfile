sdl2-sources:
  test -f third_party/SDL2_image-2.8.8/CMakeLists.txt
  test -f third_party/SDL2_ttf-2.24.0/CMakeLists.txt
  test -f third_party/SDL2_ttf-2.24.0/external/freetype/CMakeLists.txt

sdl2:
  cmake -S SDL -B build/desktop/sdl2 -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF {{env_var_or_default("SDL_CMAKE_ARGS", "")}}
  cmake --build build/desktop/sdl2 --parallel
  cmake --install build/desktop/sdl2 --prefix "$PWD/build/desktop/sdl2-install"

sdl2-image: sdl2 sdl2-sources
  cmake -S third_party/SDL2_image-2.8.8 -B build/desktop/sdl2-image -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$PWD/build/desktop/sdl2-install" -DSDL2_DIR="$PWD/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF -DSDL2IMAGE_INSTALL=OFF {{env_var_or_default("SDL_CMAKE_ARGS", "")}}
  cmake --build build/desktop/sdl2-image --parallel

sdl2-ttf: sdl2 sdl2-sources
  cmake -S third_party/SDL2_ttf-2.24.0 -B build/desktop/sdl2-ttf -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$PWD/build/desktop/sdl2-install" -DSDL2_DIR="$PWD/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_INSTALL=OFF {{env_var_or_default("SDL_CMAKE_ARGS", "")}}
  cmake --build build/desktop/sdl2-ttf --parallel

build: sdl2-image sdl2-ttf
  odin build . -collection:ffmpeg=ffmpeg-bindings -out:UI -extra-linker-flags:'-Lbuild/desktop/sdl2-install/lib -Lbuild/desktop/sdl2-image -Lbuild/desktop/sdl2-ttf -Wl,-rpath,$ORIGIN/build/desktop/sdl2-install/lib:$ORIGIN/build/desktop/sdl2-image:$ORIGIN/build/desktop/sdl2-ttf'

run: debug
  ./UI

run-normal: build
  ./UI

debug: sdl2-image sdl2-ttf
  odin build . -collection:ffmpeg=ffmpeg-bindings -debug -out:UI -extra-linker-flags:'-Lbuild/desktop/sdl2-install/lib -Lbuild/desktop/sdl2-image -Lbuild/desktop/sdl2-ttf -Wl,-rpath,$ORIGIN/build/desktop/sdl2-install/lib:$ORIGIN/build/desktop/sdl2-image:$ORIGIN/build/desktop/sdl2-ttf'

android-sdk := env_var_or_default("ANDROID_SDK_ROOT", env_var_or_default("ANDROID_HOME", ""))
android-ndk := env_var_or_default("ANDROID_NDK_HOME", env_var_or_default("ANDROID_NDK_ROOT", android-sdk + "/ndk/26.3.11579264"))
android-java-home := env_var_or_default("ANDROID_JAVA_HOME", "/usr/lib/jvm/java-17-openjdk")
android-ffmpeg := env_var_or_default("ANDROID_FFMPEG_ROOT", "Android-FFmpeg-Prebuilt/ffmpeg-9.0")
android-jni-libs := "$PWD/build/android/jniLibs/arm64-v8a"
android-ffmpeg-link := "$PWD/build/android/ffmpeg-link"

android-native force="false": sdl2-sources
  test -f "{{android-ndk}}/build/cmake/android.toolchain.cmake" || (echo "Set ANDROID_NDK_HOME to the installed Android NDK." >&2; exit 1)
  test -f "{{android-ffmpeg}}/libffmpeg.so" || (echo "Set ANDROID_FFMPEG_ROOT to the Android arm64 FFmpeg directory." >&2; exit 1)
  mkdir -p {{android-jni-libs}} {{android-ffmpeg-link}} build/android/tmp

  # 1. Setup FFmpeg symlinks so the Odin linker can locate them
  ln -sf "$PWD/{{android-ffmpeg}}/libffmpeg.so" {{android-ffmpeg-link}}/libavcodec.so
  ln -sf "$PWD/{{android-ffmpeg}}/libffmpeg.so" {{android-ffmpeg-link}}/libavformat.so
  ln -sf "$PWD/{{android-ffmpeg}}/libffmpeg.so" {{android-ffmpeg-link}}/libavutil.so
  ln -sf "$PWD/{{android-ffmpeg}}/libffmpeg.so" {{android-ffmpeg-link}}/libswresample.so

  # 2. Create dummy shared libraries to satisfy Odin's Linux linker requirements for Android
  if [ ! -f build/android/tmp/dummy.c ] || [ Justfile -nt build/android/tmp/dummy.c ]; then echo "void dummy(){}" > build/android/tmp/dummy.c; fi
  echo "INPUT(-lc)" > {{android-ffmpeg-link}}/libpthread.so
  echo "INPUT(-lc)" > {{android-ffmpeg-link}}/librt.so
  if [ ! -f {{android-ffmpeg-link}}/libSDL2.so ] || [ build/android/tmp/dummy.c -nt {{android-ffmpeg-link}}/libSDL2.so ] || [ "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang" -nt {{android-ffmpeg-link}}/libSDL2.so ] || [ Justfile -nt {{android-ffmpeg-link}}/libSDL2.so ]; then "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang" -shared build/android/tmp/dummy.c -o {{android-ffmpeg-link}}/libSDL2.so; fi
  if [ ! -f {{android-ffmpeg-link}}/libSDL2_image.so ] || [ build/android/tmp/dummy.c -nt {{android-ffmpeg-link}}/libSDL2_image.so ] || [ "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang" -nt {{android-ffmpeg-link}}/libSDL2_image.so ] || [ Justfile -nt {{android-ffmpeg-link}}/libSDL2_image.so ]; then "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang" -shared build/android/tmp/dummy.c -o {{android-ffmpeg-link}}/libSDL2_image.so; fi
  if [ ! -f {{android-ffmpeg-link}}/libSDL2_ttf.so ] || [ build/android/tmp/dummy.c -nt {{android-ffmpeg-link}}/libSDL2_ttf.so ] || [ "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang" -nt {{android-ffmpeg-link}}/libSDL2_ttf.so ] || [ Justfile -nt {{android-ffmpeg-link}}/libSDL2_ttf.so ]; then "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang" -shared build/android/tmp/dummy.c -o {{android-ffmpeg-link}}/libSDL2_ttf.so; fi

  # 3. Create a Clang wrapper to force Odin to use the NDK compiler and override the target triplet
  if [ ! -f build/android/tmp/clang ] || [ Justfile -nt build/android/tmp/clang ] || [ "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" -nt build/android/tmp/clang ]; then \
    echo '#!/bin/sh' > build/android/tmp/clang; \
    echo 'exec "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" "$@" --target=aarch64-linux-android21 --sysroot="{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"' >> build/android/tmp/clang; \
    chmod +x build/android/tmp/clang; \
  fi

  # 4. Rebuild Odin only when an input changed (or explicitly forced)
  if [ "{{force}}" = "true" ] || [ ! -f {{android-jni-libs}}/libodin_app.so ] || [ Justfile -nt {{android-jni-libs}}/libodin_app.so ] || [ "{{android-ndk}}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" -nt {{android-jni-libs}}/libodin_app.so ] || [ "{{android-ffmpeg}}/libffmpeg.so" -nt {{android-jni-libs}}/libodin_app.so ] || find . -path ./build -prune -o -type f -name '*.odin' -newer {{android-jni-libs}}/libodin_app.so -print -quit | grep -q . || find . -path ./build -prune -o -type d -newer {{android-jni-libs}}/libodin_app.so -print -quit | grep -q . || find "{{android-ffmpeg}}" -type f -newer {{android-jni-libs}}/libodin_app.so -print -quit | grep -q .; then \
    PATH="$PWD/build/android/tmp:$PATH" \
    odin build . -target:linux_arm64 -subtarget=android -build-mode:shared -collection:ffmpeg=ffmpeg-bindings \
    -out:{{android-jni-libs}}/libodin_app.so \
    -extra-linker-flags:"-L{{android-ffmpeg-link}} -Wl,-soname,libodin_app.so -Wl,--allow-shlib-undefined"; \
  fi

  # 5. Build the native Android SDL wrapper
  cmake -S android/native -B build/android/native -DCMAKE_TOOLCHAIN_FILE="{{android-ndk}}/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 -DFFMPEG_ROOT="$PWD/{{android-ffmpeg}}" -DANDROID_JNI_LIBS_DIR={{android-jni-libs}} -DFFMPEG_LINK_DIR={{android-ffmpeg-link}}
  cmake --build build/android/native --parallel

android-apk: android-native
  test -x "{{android-java-home}}/bin/java" || (echo "Set ANDROID_JAVA_HOME to an installed JDK 17 or 21; Gradle 8.7 cannot run with Java 27." >&2; exit 1)
  "{{android-java-home}}/bin/java" -version 2>&1 | grep -Eq 'version "(17|21)([."]|$)' || (echo "ANDROID_JAVA_HOME must point to JDK 17 or 21; Gradle 8.7 cannot run with Java 27." >&2; exit 1)
  JAVA_HOME="{{android-java-home}}" PATH="{{android-java-home}}/bin:$PATH" ANDROID_HOME="{{android-sdk}}" ANDROID_SDK_ROOT="{{android-sdk}}" SDL_ANDROID_HOME="$PWD/SDL/android-project" SDL_ANDROID_APP="$PWD/android" SDL_ANDROID_FFMPEG="$PWD/{{android-ffmpeg}}" SDL_ANDROID_NDK="{{android-ndk}}" ./SDL/android-project/gradlew -p android assembleDebug

android-install: android-apk
  adb install -r android/app/build/outputs/apk/debug/app-debug.apk
  adb shell am start -n org.odin.ui/org.libsdl.app.SDLActivity

clean:
  rm -rf build/ UI android/app/build/ android/.gradle/
