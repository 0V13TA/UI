SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:

SDL_CMAKE_ARGS ?=
ANDROID_SDK_ROOT ?= $(ANDROID_HOME)
ANDROID_NDK_HOME ?= $(if $(ANDROID_NDK_ROOT),$(ANDROID_NDK_ROOT),$(if $(ANDROID_SDK_ROOT),$(ANDROID_SDK_ROOT)/ndk/26.3.11579264))
ANDROID_JAVA_HOME ?= /usr/lib/jvm/java-17-openjdk
ANDROID_FFMPEG_ROOT ?= Android-FFmpeg-Prebuilt/ffmpeg-9.0

ANDROID_NDK := $(ANDROID_NDK_HOME)
ANDROID_FFMPEG := $(abspath $(ANDROID_FFMPEG_ROOT))
ANDROID_NDK_BIN := $(ANDROID_NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin
ANDROID_JNI_LIBS := $(CURDIR)/build/android/jniLibs/arm64-v8a
ANDROID_FFMPEG_LINK := $(CURDIR)/build/android/ffmpeg-link
ANDROID_DUMMY_C := build/android/tmp/dummy.c
ANDROID_CLANG_WRAPPER := build/android/tmp/clang
ANDROID_ODIN_APP := $(ANDROID_JNI_LIBS)/libodin_app.so
ANDROID_FFMPEG_SO := $(ANDROID_FFMPEG)/libffmpeg.so

ODIN_SOURCES := $(shell find . -path ./build -prune -o -type f -name '*.odin' -print)

.PHONY: all sdl2-sources sdl2 sdl2-image sdl2-ttf build debug run run-normal
.PHONY: android-native android-apk android-install clean

all: build

sdl2-sources:
	test -f third_party/SDL2_image-2.8.8/CMakeLists.txt
	test -f third_party/SDL2_ttf-2.24.0/CMakeLists.txt
	test -f third_party/SDL2_ttf-2.24.0/external/freetype/CMakeLists.txt

sdl2: sdl2-sources
	cmake -S SDL -B build/desktop/sdl2 -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF $(SDL_CMAKE_ARGS)
	find build/desktop/sdl2 -type f -name '*.o' -size 0 -delete
	cmake --build build/desktop/sdl2 --parallel
	cmake --install build/desktop/sdl2 --prefix "$(CURDIR)/build/desktop/sdl2-install"

sdl2-image: sdl2 sdl2-sources
	cmake -S third_party/SDL2_image-2.8.8 -B build/desktop/sdl2-image -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$(CURDIR)/build/desktop/sdl2-install" -DSDL2_DIR="$(CURDIR)/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF -DSDL2IMAGE_INSTALL=OFF $(SDL_CMAKE_ARGS)
	cmake --build build/desktop/sdl2-image --parallel

sdl2-ttf: sdl2 sdl2-sources
	cmake -S third_party/SDL2_ttf-2.24.0 -B build/desktop/sdl2-ttf -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$(CURDIR)/build/desktop/sdl2-install" -DSDL2_DIR="$(CURDIR)/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_INSTALL=OFF $(SDL_CMAKE_ARGS)
	cmake --build build/desktop/sdl2-ttf --parallel

build: sdl2-image sdl2-ttf
	odin build . -collection:ffmpeg=ffmpeg-bindings -out:UI -extra-linker-flags:'-Lbuild/desktop/sdl2-install/lib -Lbuild/desktop/sdl2-image -Lbuild/desktop/sdl2-ttf -Wl,-rpath,$$ORIGIN/build/desktop/sdl2-install/lib:$$ORIGIN/build/desktop/sdl2-image:$$ORIGIN/build/desktop/sdl2-ttf'

debug: sdl2-image sdl2-ttf
	odin build . -collection:ffmpeg=ffmpeg-bindings -debug -out:UI -extra-linker-flags:'-Lbuild/desktop/sdl2-install/lib -Lbuild/desktop/sdl2-image -Lbuild/desktop/sdl2-ttf -Wl,-rpath,$$ORIGIN/build/desktop/sdl2-install/lib:$$ORIGIN/build/desktop/sdl2-image:$$ORIGIN/build/desktop/sdl2-ttf'

run: debug
	./UI

run-normal: build
	./UI

$(ANDROID_DUMMY_C): Makefile
	mkdir -p $(@D)
	printf '%s\n' 'void dummy(){}' > $@

$(ANDROID_CLANG_WRAPPER): Makefile $(ANDROID_NDK_BIN)/clang
	mkdir -p $(@D)
	printf '%s\n' '#!/bin/sh' 'exec "$(ANDROID_NDK_BIN)/clang" "$$@" --target=aarch64-linux-android21 --sysroot="$(ANDROID_NDK)/toolchains/llvm/prebuilt/linux-x86_64/sysroot"' > $@
	chmod +x $@

$(ANDROID_FFMPEG_LINK)/libSDL2.so $(ANDROID_FFMPEG_LINK)/libSDL2_image.so $(ANDROID_FFMPEG_LINK)/libSDL2_ttf.so: $(ANDROID_DUMMY_C) $(ANDROID_NDK_BIN)/aarch64-linux-android21-clang Makefile
	mkdir -p $(@D)
	"$(ANDROID_NDK_BIN)/aarch64-linux-android21-clang" -shared $< -o $@

$(ANDROID_FFMPEG_LINK)/libavcodec.so $(ANDROID_FFMPEG_LINK)/libavformat.so $(ANDROID_FFMPEG_LINK)/libavutil.so $(ANDROID_FFMPEG_LINK)/libswresample.so: $(ANDROID_FFMPEG_SO)
	mkdir -p $(@D)
	ln -sf "$(ANDROID_FFMPEG_SO)" $@

$(ANDROID_FFMPEG_LINK)/libpthread.so $(ANDROID_FFMPEG_LINK)/librt.so: Makefile
	mkdir -p $(@D)
	printf '%s\n' 'INPUT(-lc)' > $@

$(ANDROID_ODIN_APP): $(ODIN_SOURCES) $(ANDROID_CLANG_WRAPPER) $(ANDROID_FFMPEG_LINK)/libSDL2.so $(ANDROID_FFMPEG_LINK)/libSDL2_image.so $(ANDROID_FFMPEG_LINK)/libSDL2_ttf.so $(ANDROID_FFMPEG_LINK)/libavcodec.so $(ANDROID_FFMPEG_LINK)/libavformat.so $(ANDROID_FFMPEG_LINK)/libavutil.so $(ANDROID_FFMPEG_LINK)/libswresample.so $(ANDROID_FFMPEG_LINK)/libpthread.so $(ANDROID_FFMPEG_LINK)/librt.so $(ANDROID_FFMPEG_SO) Makefile
	mkdir -p "$(@D)"
	PATH="$(CURDIR)/build/android/tmp:$$PATH" odin build . -target:linux_arm64 -subtarget=android -build-mode:shared -collection:ffmpeg=ffmpeg-bindings -out:"$@" -extra-linker-flags:"-L$(ANDROID_FFMPEG_LINK) -Wl,-soname,libodin_app.so -Wl,--allow-shlib-undefined"

ifeq ($(FORCE),1)
.PHONY: force-android-odin
force-android-odin:
$(ANDROID_ODIN_APP): force-android-odin
endif

android-native: sdl2-sources
	test -f "$(ANDROID_NDK)/build/cmake/android.toolchain.cmake" || { echo "Set ANDROID_NDK_HOME to the installed Android NDK." >&2; exit 1; }
	test -f "$(ANDROID_FFMPEG_SO)" || { echo "Set ANDROID_FFMPEG_ROOT to the Android arm64 FFmpeg directory." >&2; exit 1; }
	$(MAKE) "$(ANDROID_ODIN_APP)"
	cmake -S android/native -B build/android/native -DCMAKE_TOOLCHAIN_FILE="$(ANDROID_NDK)/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 -DFFMPEG_ROOT="$(ANDROID_FFMPEG)" -DANDROID_JNI_LIBS_DIR="$(ANDROID_JNI_LIBS)" -DFFMPEG_LINK_DIR="$(ANDROID_FFMPEG_LINK)"
	cmake --build build/android/native --parallel

android-apk: android-native
	test -x "$(ANDROID_JAVA_HOME)/bin/java" || { echo "Set ANDROID_JAVA_HOME to an installed JDK 17 or 21; Gradle 8.7 cannot run with Java 27." >&2; exit 1; }
	"$(ANDROID_JAVA_HOME)/bin/java" -version 2>&1 | grep -Eq 'version "(17|21)([."]|$$)' || { echo "ANDROID_JAVA_HOME must point to JDK 17 or 21; Gradle 8.7 cannot run with Java 27." >&2; exit 1; }
	JAVA_HOME="$(ANDROID_JAVA_HOME)" PATH="$(ANDROID_JAVA_HOME)/bin:$$PATH" ANDROID_HOME="$(ANDROID_SDK_ROOT)" ANDROID_SDK_ROOT="$(ANDROID_SDK_ROOT)" SDL_ANDROID_HOME="$(CURDIR)/SDL/android-project" SDL_ANDROID_APP="$(CURDIR)/android" SDL_ANDROID_FFMPEG="$(ANDROID_FFMPEG)" SDL_ANDROID_NDK="$(ANDROID_NDK)" ./SDL/android-project/gradlew -p android assembleDebug

android-install: android-apk
	adb install -r android/app/build/outputs/apk/debug/app-debug.apk
	adb shell am start -n org.odin.ui/org.libsdl.app.SDLActivity

clean:
	rm -rf build/ UI android/app/build/ android/.gradle/
