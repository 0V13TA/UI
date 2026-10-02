# Odin UI

Odin UI is a reusable immediate-mode UI package distributed as a self-contained
folder. Copy the complete `UI/` directory into an Odin project and import it
locally:

```odin
package main

import ui "./UI"

main :: proc() {
	app := ui.ui_begin_app()
	if app == nil do return
	defer ui.app_destroy(app)

	for !app.quit {
		ui.app_begin_frame(app)
		ui.text(app, "Hello from Odin UI")
		ui.app_end_frame(app)
	}
}
```

## Application resources

Keep application assets outside the library. By default, paths passed to
`image_path`, `video`, and font styles are relative to the application's
`assets/` directory. On desktop, that directory is resolved beside the
executable, not relative to the current working directory. For example:

```odin
ui.image_path(app, "images/logo.png")
ui.text(app, "Custom font", user_style = {font_name = "fonts/body.ttf"})
```

The directory can be changed per application:

```odin
app := ui.ui_begin_app(asset_dir = "resources")
```

The same `asset_dir` is used on Android. The Android packaging task copies the
application's asset directory into the matching packaged asset path; set
`APP_ASSET_DIR` when building if it differs from `assets`.

Odin UI embeds its Caacupe One default font and built-in component icons in the
package. They need no runtime files and are not copied into the application's
asset directory.

## Desktop build

The package includes its Odin SDL2/SDL2_net bindings and SDL2, SDL2_image,
SDL2_ttf, SDL2_net, and FreeType source dependencies. Build those native
dependencies locally inside the copied library folder:

```sh
make -C UI desktop-libs
```

Build and launch the included desktop smoke app with:

```sh
make -C UI desktop-run
```

For consumer applications, locally built shared libraries are under
`UI/build/desktop/`. The Odin SDL2_net binding imports `system:SDL2_net`, so
consumers that use networking should add the SDL2_net build output to their
linker search path and runtime library path, and import the bundled binding:

```sh
odin build . -extra-linker-flags:'-LUI/build/desktop/sdl2-install/lib -LUI/build/desktop/sdl2-image -LUI/build/desktop/sdl2-ttf -LUI/build/desktop/sdl2-net -Wl,-rpath,$ORIGIN/UI/build/desktop/sdl2-install/lib:$ORIGIN/UI/build/desktop/sdl2-image:$ORIGIN/UI/build/desktop/sdl2-ttf:$ORIGIN/UI/build/desktop/sdl2-net'
```

```odin
import net "./UI/vendor/sdl2/net"
```

The compiler's Odin standard library is still required, but no Odin collection
or global library configuration is needed. Video playback uses FFmpeg; the
Android build uses the bundled Android arm64 prebuilt. Desktop applications
that use video must provide compatible FFmpeg libraries at link/runtime.

Run the library tests from the library directory with:

```sh
odin test .
```

## Android build

The Android project under `android/` is a build host for an application that
imports this package. It uses the consuming app's Odin source directory and
asset directory, while keeping the SDL/FFmpeg native build and Gradle project
inside `UI/`.

For the included Android smoke-test app:

```sh
make -C UI android-apk
```

For a project laid out as `MyProject/main.odin`, `MyProject/assets/`, and
`MyProject/UI/`:

```sh
make -C UI android-apk APP_ROOT=.. APP_ASSETS_DIR=../assets
```

The consumer's Android entry source must export `odin_app_start` for SDL's
native activity to invoke its `main` procedure. `APP_ASSET_DIR` defaults to
`assets`; override it when the app uses a different virtual asset path.
Declare Android permissions in a `permissions` file in `APP_ROOT`, one name per
line; blank lines and `#` comments are ignored. For example:

```text
INTERNET
ACCESS_NETWORK_STATE
```

The included Android smoke app declares its required permissions in
[`tests/android/permissions`](tests/android/permissions). To start a project
configuration from the available Android SDK 34 permissions, copy
[`tests/android/permissions.template`](tests/android/permissions.template) to
your project's `permissions` file and uncomment only the permissions your app
needs.

The Android build validates the entries and regenerates the manifest whenever
the file changes. See [android/README.md](android/README.md) for details.
Android builds require the Android SDK/NDK and a supported JDK; see
[android/README.md](android/README.md).

## Licensing

Third-party license notices are retained beside the bundled dependencies,
including SDL2_net 2.2.0 under `third_party/SDL2_net-2.2.0/LICENSE.txt`.
The repository does not currently specify a license for Odin UI's original
code; choose and add one before redistributing the library.
