# Android build

The Android project reuses the SDL 2.32 source in `SDL/`, the pinned SDL2
add-on sources in `third_party/`, and the SDL Android Java activity from
`SDL/android-project`. Native libraries are built with the Android NDK and
packaged by Gradle. The checked-in FFmpeg prebuilt contains only
`arm64-v8a`, so this build intentionally targets that ABI.

Set `ANDROID_SDK_ROOT` and `ANDROID_NDK_HOME`, and ensure the Android SDK has
platform 34 and build-tools 34.0.0 installed. The NDK used for validation is
26.3.11579264. Gradle 8.7 requires a supported JDK; the build recipe defaults
to JDK 17 and accepts JDK 17 or 21. If your JDK 17 installation is elsewhere,
set `ANDROID_JAVA_HOME` to its installation directory.

Build the APK:

```sh
just android-apk
```

Android builds skip relinking `libodin_app.so` when the Odin sources and
FFmpeg inputs are unchanged. To force that native relink:

```sh
just android-native true
```

Install and launch on a connected device with USB debugging enabled:

```sh
just android-install
```

The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`.
Gradle stages project files under the APK's `assets/assets/` directory so
runtime paths such as `assets/pictures/...` resolve through SDL's Android
asset manager.
SDL_image uses its bundled stb decoder on Android; optional AVIF, JPEG XL,
TIFF, and WebP backends are disabled to avoid host-library dependencies.
SDL_ttf builds its local FreeType dependency from source.
The native build targets the same Android API level as `ANDROID_PLATFORM`.
Odin's Android linker requests `-lpthread`, while Android exposes pthread APIs
through libc; CMake creates a build-local linker alias to the NDK libc stub.
This alias is only used during linking and is not packaged in the APK.
