# Android build

The Android project reuses the SDL 2.32 source in `SDL/`, the pinned SDL2
add-on sources in `third_party/`, and the SDL Android Java activity from
`SDL/android-project`. Native libraries are built with the Android NDK and
packaged by Gradle. The checked-in FFmpeg prebuilt contains only
`arm64-v8a`, so this build intentionally targets that ABI.

Set `ANDROID_SDK_ROOT` and `ANDROID_NDK_HOME`, and ensure the Android SDK has
platform 34 and build-tools 34.0.0 installed. The NDK used for validation is
26.3.11579264. A JDK supported by Gradle 8.7 is also required.

Build the APK:

```sh
just android-apk
```

Install and launch on a connected device with USB debugging enabled:

```sh
just android-install
```

The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`.
The project assets are packaged with their existing `assets/` path intact.
SDL_image uses its bundled stb decoder on Android; optional AVIF, JPEG XL,
TIFF, and WebP backends are disabled to avoid host-library dependencies.
SDL_ttf builds its local FreeType dependency from source.
