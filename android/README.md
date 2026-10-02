# Android build

This Gradle/NDK project packages a consumer Odin application's source with the
UI library. The SDL 2.32 source, the pinned SDL2 add-ons including SDL2_net,
and Android SDL activity are kept in the library folder. The bundled FFmpeg
prebuilt targets
`arm64-v8a`, so Android support currently targets that ABI.

## Requirements

- Android SDK platform 34 and build-tools 34.0.0
- Android NDK 26.3.11579264
- JDK 17 or 21 (the Makefile defaults to JDK 17)
- Odin, CMake, and GNU Make

Set `ANDROID_SDK_ROOT` and `ANDROID_NDK_HOME` if the SDK/NDK are not at the
default locations. `ANDROID_JAVA_HOME` can select a non-default supported JDK.
These are build-machine prerequisites; no Odin global collection or project
configuration is needed.

## Build the included smoke-test app

```sh
make android-apk
```

## Build a consuming project

For a consumer with `MyProject/main.odin`, `MyProject/assets/`, and
`MyProject/UI/`, run:

```sh
make -C UI android-apk APP_ROOT=.. APP_ASSETS_DIR=../assets
```

`APP_ROOT` points to the Odin package containing the application's `main`.
The application source must export `odin_app_start` as the SDL Android entry
point. `APP_ASSETS_DIR` selects the on-disk application assets to package, and
`APP_ASSET_DIR` selects the virtual path used by `ui_begin_app` and resource
loading; both default to `assets`. If using a different resource path, pass the
same value to the application and build:

```sh
make -C UI android-apk APP_ROOT=.. APP_ASSETS_DIR=../resources APP_ASSET_DIR=resources
```

Declare additional Android permissions in a UTF-8 `permissions` file at the
root of `APP_ROOT`, with one permission per line. Blank lines and lines
beginning with `#` are ignored. Short platform permission names are expanded
to `android.permission.*`; fully qualified custom permission names are kept as
written. Duplicate or malformed entries stop the build with the file and line
number in the error.

```text
# Required for network access
INTERNET
ACCESS_NETWORK_STATE
VIBRATE
```

The Gradle build regenerates the manifest from the SDL template and this file,
so changes are picked up on the next Android build. No generated manifest
editing is needed.

The included smoke app has an example configuration at
`tests/android/permissions`. To begin with the Android SDK 34 permission list,
copy `tests/android/permissions.template` to your project's `permissions` file
and uncomment only the permissions the application needs.

Application assets are staged under the selected packaged path. Images, fonts,
and videos load through SDL `RWops`, so Android's asset manager is used
internally rather than expecting files in the library or application working
directory. Odin UI's default font and component icons are embedded in the
library and need no Android asset staging.

On Android, the UI automatically uses density-independent coordinates based on
the device's display density. This scales typography and other UI geometry
together while desktop coordinates remain unchanged.

The FFmpeg prebuilt is under `Android-FFmpeg-Prebuilt/ffmpeg-9.0`. The generated
APK is `android/app/build/outputs/apk/debug/app-debug.apk`. Install and launch
it on a connected device with USB debugging enabled:

```sh
make android-install
```

Android builds skip relinking the Odin shared library when application/library
sources and embedded resources are unchanged. Force that relink with:

```sh
make android-native FORCE=1
```
