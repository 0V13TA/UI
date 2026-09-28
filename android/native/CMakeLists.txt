cmake_minimum_required(VERSION 3.22)
project(OdinUI_Android LANGUAGES C)

if(NOT ANDROID OR NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "This build currently supports Android arm64-v8a only.")
endif()

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(FFMPEG_ROOT "${REPO_ROOT}/Android-FFmpeg-Prebuilt/ffmpeg-9.0" CACHE PATH "Android FFmpeg prebuilt root")
set(FFMPEG_LINK_DIR "${CMAKE_BINARY_DIR}/ffmpeg-link" CACHE PATH "FFmpeg link aliases")
set(ANDROID_JNI_LIBS_DIR "${CMAKE_BINARY_DIR}/jniLibs/${ANDROID_ABI}" CACHE PATH "Packaged Android native libraries")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${ANDROID_JNI_LIBS_DIR}")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

if(NOT EXISTS "${FFMPEG_ROOT}/libffmpeg.so")
    message(FATAL_ERROR "Missing libffmpeg.so under FFMPEG_ROOT=${FFMPEG_ROOT}")
endif()
if(NOT EXISTS "${FFMPEG_ROOT}/include/libavformat/avformat.h")
    message(FATAL_ERROR "Missing FFmpeg headers under FFMPEG_ROOT=${FFMPEG_ROOT}")
endif()

set(SDL_SHARED ON CACHE BOOL "Build SDL2 shared library" FORCE)
set(SDL_STATIC OFF CACHE BOOL "Do not build SDL2 static library" FORCE)
set(SDL_TEST OFF CACHE BOOL "Do not build SDL2 tests" FORCE)
set(SDL_TESTS OFF CACHE BOOL "Do not build SDL2 tests" FORCE)
set(SDL2IMAGE_SAMPLES OFF CACHE BOOL "Do not build SDL2_image samples" FORCE)
set(SDL2IMAGE_TESTS OFF CACHE BOOL "Do not build SDL2_image tests" FORCE)
set(SDL2IMAGE_INSTALL OFF CACHE BOOL "Do not install SDL2_image" FORCE)
set(SDL2IMAGE_BACKEND_STB ON CACHE BOOL "Use bundled stb image decoder" FORCE)
set(SDL2IMAGE_AVIF OFF CACHE BOOL "Disable AVIF dependency" FORCE)
set(SDL2IMAGE_JXL OFF CACHE BOOL "Disable JPEG XL dependency" FORCE)
set(SDL2IMAGE_TIF OFF CACHE BOOL "Disable TIFF dependency" FORCE)
set(SDL2IMAGE_WEBP OFF CACHE BOOL "Disable WebP dependency" FORCE)
set(SDL2TTF_SAMPLES OFF CACHE BOOL "Do not build SDL2_ttf samples" FORCE)
set(SDL2TTF_INSTALL OFF CACHE BOOL "Do not install SDL2_ttf" FORCE)
set(SDL2TTF_VENDORED ON CACHE BOOL "Build FreeType from the local source tree" FORCE)
set(SDL2TTF_HARFBUZZ OFF CACHE BOOL "Disable optional HarfBuzz dependency" FORCE)

add_subdirectory("${REPO_ROOT}/SDL" SDL2)
add_subdirectory("${REPO_ROOT}/third_party/SDL2_image-2.8.8" SDL2_image)
add_subdirectory("${REPO_ROOT}/third_party/SDL2_ttf-2.24.0" SDL2_ttf)

file(MAKE_DIRECTORY "${ANDROID_JNI_LIBS_DIR}")
configure_file("${FFMPEG_ROOT}/libffmpeg.so" "${ANDROID_JNI_LIBS_DIR}/libffmpeg.so" COPYONLY)
configure_file(
    "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-android/libc++_shared.so"
    "${ANDROID_JNI_LIBS_DIR}/libc++_shared.so"
    COPYONLY
)

find_program(ODIN_EXECUTABLE odin REQUIRED)
set(ODIN_APP_LIBRARY "${ANDROID_JNI_LIBS_DIR}/libodin_app.so")
set(ODIN_LINK_FLAGS "-L${ANDROID_JNI_LIBS_DIR} -L${FFMPEG_LINK_DIR}")

add_custom_command(
    OUTPUT "${ODIN_APP_LIBRARY}"
    COMMAND "${CMAKE_COMMAND}" -E env "ODIN_ANDROID_NDK=${CMAKE_ANDROID_NDK}"
        "${ODIN_EXECUTABLE}" build "${REPO_ROOT}"
            -target:linux_arm64
            -subtarget:android
            -build-mode:shared
            -collection:ffmpeg=${REPO_ROOT}/ffmpeg-bindings
            -out:${ODIN_APP_LIBRARY}
            -extra-linker-flags:${ODIN_LINK_FLAGS}
    WORKING_DIRECTORY "${REPO_ROOT}"
    DEPENDS
        "${REPO_ROOT}/app.odin"
        "${REPO_ROOT}/main.odin"
        "${REPO_ROOT}/video.odin"
    VERBATIM
)
add_custom_target(odin_app_build DEPENDS "${ODIN_APP_LIBRARY}")

add_library(odin_app SHARED IMPORTED GLOBAL)
set_target_properties(odin_app PROPERTIES IMPORTED_LOCATION "${ODIN_APP_LIBRARY}")

add_library(main SHARED android_entry.c)
target_link_libraries(main PRIVATE SDL2 SDL2_image SDL2_ttf odin_app)
add_dependencies(main odin_app_build)
