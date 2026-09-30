SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:

UI_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SDL_CMAKE_ARGS ?=
APP_ROOT ?= $(UI_DIR)/tests/android
override APP_ROOT := $(abspath $(APP_ROOT))
APP_ASSETS_DIR ?= $(APP_ROOT)/assets
override APP_ASSETS_DIR := $(abspath $(APP_ASSETS_DIR))
APP_ASSET_DIR ?= assets
DESKTOP_APP_ROOT ?= $(UI_DIR)/tests/desktop
override DESKTOP_APP_ROOT := $(abspath $(DESKTOP_APP_ROOT))
DESKTOP_BINARY ?= $(UI_DIR)/build/desktop/OdinUI
override DESKTOP_BINARY := $(abspath $(DESKTOP_BINARY))

ANDROID_SDK_ROOT ?= $(ANDROID_HOME)
ANDROID_NDK_HOME ?= $(if $(ANDROID_NDK_ROOT),$(ANDROID_NDK_ROOT),$(if $(ANDROID_SDK_ROOT),$(ANDROID_SDK_ROOT)/ndk/26.3.11579264))
ANDROID_JAVA_HOME ?= /usr/lib/jvm/java-17-openjdk
ANDROID_FFMPEG_ROOT ?= $(UI_DIR)/Android-FFmpeg-Prebuilt/ffmpeg-9.0
override ANDROID_FFMPEG_ROOT := $(abspath $(ANDROID_FFMPEG_ROOT))

ANDROID_NDK := $(ANDROID_NDK_HOME)
ANDROID_FFMPEG := $(ANDROID_FFMPEG_ROOT)
ANDROID_NDK_BIN := $(ANDROID_NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin
ANDROID_JNI_LIBS := $(UI_DIR)/build/android/jniLibs/arm64-v8a
ANDROID_FFMPEG_LINK := $(UI_DIR)/build/android/ffmpeg-link
ANDROID_DUMMY_C := $(UI_DIR)/build/android/tmp/dummy.c
ANDROID_CLANG_WRAPPER := $(UI_DIR)/build/android/tmp/clang
ANDROID_ODIN_APP := $(ANDROID_JNI_LIBS)/libodin_app.so
ANDROID_FFMPEG_SO := $(ANDROID_FFMPEG)/libffmpeg.so

ODIN_SOURCES := $(shell find "$(UI_DIR)" -path "$(UI_DIR)/build" -prune -o -type f -name '*.odin' -print)
APP_SOURCES := $(shell find "$(APP_ROOT)" -type f -name '*.odin' -print)
UI_RESOURCES := $(shell find "$(UI_DIR)/resources" -type f -print)

cmake-fresh-flag = $(shell \
	if test -f "$(1)/CMakeCache.txt" && \
	   { ! grep -Fqx 'CMAKE_CACHEFILE_DIR:INTERNAL=$(1)' "$(1)/CMakeCache.txt" || \
	     ! grep -Fqx 'CMAKE_HOME_DIRECTORY:INTERNAL=$(2)' "$(1)/CMakeCache.txt"; }; then \
		printf '%s' '--fresh'; \
	fi)

.PHONY: all sdl2-sources sdl2 sdl2-image sdl2-ttf sdl2-net desktop-libs build
.PHONY: desktop-build desktop-run
.PHONY: android-native android-apk android-install clean

all: build

sdl2-sources:
	test -f "$(UI_DIR)/third_party/SDL2_image-2.8.8/CMakeLists.txt"
	test -f "$(UI_DIR)/third_party/SDL2_ttf-2.24.0/CMakeLists.txt"
	test -f "$(UI_DIR)/third_party/SDL2_ttf-2.24.0/external/freetype/CMakeLists.txt"
	test -f "$(UI_DIR)/third_party/SDL2_net-2.2.0/CMakeLists.txt"

sdl2: sdl2-sources
	cmake $(call cmake-fresh-flag,$(UI_DIR)/build/desktop/sdl2,$(UI_DIR)/SDL) -S "$(UI_DIR)/SDL" -B "$(UI_DIR)/build/desktop/sdl2" -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF $(SDL_CMAKE_ARGS)
	find "$(UI_DIR)/build/desktop/sdl2" -type f -name '*.o' -size 0 -delete
	cmake --build "$(UI_DIR)/build/desktop/sdl2" --parallel
	cmake --install "$(UI_DIR)/build/desktop/sdl2" --prefix "$(UI_DIR)/build/desktop/sdl2-install"

sdl2-image: sdl2 sdl2-sources
	cmake $(call cmake-fresh-flag,$(UI_DIR)/build/desktop/sdl2-image,$(UI_DIR)/third_party/SDL2_image-2.8.8) -S "$(UI_DIR)/third_party/SDL2_image-2.8.8" -B "$(UI_DIR)/build/desktop/sdl2-image" -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$(UI_DIR)/build/desktop/sdl2-install" -DSDL2_DIR="$(UI_DIR)/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF -DSDL2IMAGE_INSTALL=OFF $(SDL_CMAKE_ARGS)
	cmake --build "$(UI_DIR)/build/desktop/sdl2-image" --parallel

sdl2-ttf: sdl2 sdl2-sources
	cmake $(call cmake-fresh-flag,$(UI_DIR)/build/desktop/sdl2-ttf,$(UI_DIR)/third_party/SDL2_ttf-2.24.0) -S "$(UI_DIR)/third_party/SDL2_ttf-2.24.0" -B "$(UI_DIR)/build/desktop/sdl2-ttf" -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$(UI_DIR)/build/desktop/sdl2-install" -DSDL2_DIR="$(UI_DIR)/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_INSTALL=OFF $(SDL_CMAKE_ARGS)
	cmake --build "$(UI_DIR)/build/desktop/sdl2-ttf" --parallel

sdl2-net: sdl2 sdl2-sources
	cmake $(call cmake-fresh-flag,$(UI_DIR)/build/desktop/sdl2-net,$(UI_DIR)/third_party/SDL2_net-2.2.0) -S "$(UI_DIR)/third_party/SDL2_net-2.2.0" -B "$(UI_DIR)/build/desktop/sdl2-net" -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$$ORIGIN/../sdl2-install/lib' -DCMAKE_PREFIX_PATH="$(UI_DIR)/build/desktop/sdl2-install" -DSDL2_DIR="$(UI_DIR)/build/desktop/sdl2-install/lib/cmake/SDL2" -DSDL2NET_SAMPLES=OFF -DSDL2NET_INSTALL=OFF $(SDL_CMAKE_ARGS)
	cmake --build "$(UI_DIR)/build/desktop/sdl2-net" --parallel

desktop-libs: sdl2-image sdl2-ttf sdl2-net

build: desktop-libs
	odin test "$(UI_DIR)"

desktop-build: desktop-libs
	test -f "$(DESKTOP_APP_ROOT)/main.odin" || { echo "Set DESKTOP_APP_ROOT to an Odin desktop app directory containing main.odin." >&2; exit 1; }
	mkdir -p "$(dir $(DESKTOP_BINARY))"
	odin build "$(DESKTOP_APP_ROOT)" -out:"$(DESKTOP_BINARY)" -extra-linker-flags:"-L$(UI_DIR)/build/desktop/sdl2-net -Wl,-rpath,\$$ORIGIN/sdl2-install/lib:\$$ORIGIN/sdl2-image:\$$ORIGIN/sdl2-ttf:\$$ORIGIN/sdl2-net"

desktop-run: desktop-build
	"$(DESKTOP_BINARY)"

$(ANDROID_DUMMY_C): $(UI_DIR)/Makefile
	mkdir -p "$(@D)"
	printf '%s\n' 'void dummy(){}' > "$@"

$(ANDROID_CLANG_WRAPPER): $(UI_DIR)/Makefile $(ANDROID_NDK_BIN)/clang
	mkdir -p "$(@D)"
	printf '%s\n' '#!/bin/sh' 'exec "$(ANDROID_NDK_BIN)/clang" "$$@" --target=aarch64-linux-android21 --sysroot="$(ANDROID_NDK)/toolchains/llvm/prebuilt/linux-x86_64/sysroot"' > "$@"
	chmod +x "$@"

$(ANDROID_FFMPEG_LINK)/libSDL2.so $(ANDROID_FFMPEG_LINK)/libSDL2_image.so $(ANDROID_FFMPEG_LINK)/libSDL2_ttf.so $(ANDROID_FFMPEG_LINK)/libSDL2_net.so: $(ANDROID_DUMMY_C) $(ANDROID_NDK_BIN)/aarch64-linux-android21-clang $(UI_DIR)/Makefile
	mkdir -p "$(@D)"
	"$(ANDROID_NDK_BIN)/aarch64-linux-android21-clang" -shared "$<" -o "$@"

$(ANDROID_FFMPEG_LINK)/libavcodec.so $(ANDROID_FFMPEG_LINK)/libavformat.so $(ANDROID_FFMPEG_LINK)/libavutil.so $(ANDROID_FFMPEG_LINK)/libswresample.so: $(ANDROID_FFMPEG_SO)
	mkdir -p "$(@D)"
	ln -sf "$(ANDROID_FFMPEG_SO)" "$@"

$(ANDROID_FFMPEG_LINK)/libpthread.so $(ANDROID_FFMPEG_LINK)/librt.so: $(UI_DIR)/Makefile
	mkdir -p "$(@D)"
	printf '%s\n' 'INPUT(-lc)' > "$@"

$(ANDROID_ODIN_APP): $(ODIN_SOURCES) $(APP_SOURCES) $(UI_RESOURCES) $(ANDROID_CLANG_WRAPPER) $(ANDROID_FFMPEG_LINK)/libSDL2.so $(ANDROID_FFMPEG_LINK)/libSDL2_image.so $(ANDROID_FFMPEG_LINK)/libSDL2_ttf.so $(ANDROID_FFMPEG_LINK)/libSDL2_net.so $(ANDROID_FFMPEG_LINK)/libavcodec.so $(ANDROID_FFMPEG_LINK)/libavformat.so $(ANDROID_FFMPEG_LINK)/libavutil.so $(ANDROID_FFMPEG_LINK)/libswresample.so $(ANDROID_FFMPEG_LINK)/libpthread.so $(ANDROID_FFMPEG_LINK)/librt.so $(ANDROID_FFMPEG_SO) $(UI_DIR)/Makefile
	test -f "$(APP_ROOT)/main.odin" || { echo "Set APP_ROOT to an Odin app directory containing main.odin." >&2; exit 1; }
	mkdir -p "$(@D)"
	PATH="$(UI_DIR)/build/android/tmp:$$PATH" ODIN_ANDROID_NDK="$(ANDROID_NDK)" odin build "$(APP_ROOT)" -target:linux_arm64 -subtarget:android -build-mode:shared -out:"$@" -extra-linker-flags:"-L$(ANDROID_FFMPEG_LINK) -Wl,-soname,libodin_app.so -Wl,--allow-shlib-undefined"

ifeq ($(FORCE),1)
.PHONY: force-android-odin
force-android-odin:
$(ANDROID_ODIN_APP): force-android-odin
endif

android-native: sdl2-sources
	test -d "$(APP_ROOT)" || { echo "Set APP_ROOT to the consuming Odin application directory." >&2; exit 1; }
	test -f "$(ANDROID_NDK)/build/cmake/android.toolchain.cmake" || { echo "Set ANDROID_NDK_HOME to the installed Android NDK." >&2; exit 1; }
	test -f "$(ANDROID_FFMPEG_SO)" || { echo "Set ANDROID_FFMPEG_ROOT to the Android arm64 FFmpeg directory." >&2; exit 1; }
	$(MAKE) "$(ANDROID_ODIN_APP)"
	cmake -S "$(UI_DIR)/android/native" -B "$(UI_DIR)/build/android/native" -DCMAKE_TOOLCHAIN_FILE="$(ANDROID_NDK)/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 -DFFMPEG_ROOT="$(ANDROID_FFMPEG)" -DANDROID_JNI_LIBS_DIR="$(ANDROID_JNI_LIBS)" -DFFMPEG_LINK_DIR="$(ANDROID_FFMPEG_LINK)" -DAPP_ROOT="$(APP_ROOT)"
	cmake --build "$(UI_DIR)/build/android/native" --parallel

android-apk: android-native
	test -x "$(ANDROID_JAVA_HOME)/bin/java" || { echo "Set ANDROID_JAVA_HOME to an installed JDK 17 or 21; Gradle 8.7 cannot run with Java 27." >&2; exit 1; }
	"$(ANDROID_JAVA_HOME)/bin/java" -version 2>&1 | grep -Eq 'version "(17|21)([."]|$$)' || { echo "ANDROID_JAVA_HOME must point to JDK 17 or 21; Gradle 8.7 cannot run with Java 27." >&2; exit 1; }
	JAVA_HOME="$(ANDROID_JAVA_HOME)" PATH="$(ANDROID_JAVA_HOME)/bin:$$PATH" ANDROID_HOME="$(ANDROID_SDK_ROOT)" ANDROID_SDK_ROOT="$(ANDROID_SDK_ROOT)" SDL_ANDROID_HOME="$(UI_DIR)/SDL/android-project" SDL_ANDROID_APP="$(UI_DIR)/android" SDL_ANDROID_FFMPEG="$(ANDROID_FFMPEG)" SDL_ANDROID_NDK="$(ANDROID_NDK)" "$(UI_DIR)/SDL/android-project/gradlew" -p "$(UI_DIR)/android" assembleDebug -PuiAssetsDir="$(APP_ASSETS_DIR)" -PuiAssetDir="$(APP_ASSET_DIR)"

android-install: android-apk
	adb install -r "$(UI_DIR)/android/app/build/outputs/apk/debug/app-debug.apk"
	adb shell am start -n org.odin.ui/org.libsdl.app.SDLActivity

clean:
	rm -rf "$(UI_DIR)/build" "$(UI_DIR)/android/app/build" "$(UI_DIR)/android/.gradle"
