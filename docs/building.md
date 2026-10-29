# Building and Shipping

Pixzig builds with the Zig build system, for Linux, Windows and the browser. [Getting Started](../index.html) covers `buildGame`; this page covers what happens after that.

## Zig Version

Pixzig tracks a pinned Zig version, recorded as `minimum_zig_version` in pixzig's `build.zig.zon`. Use exactly that version; Zig changes enough between builds that a newer or older one usually won't compile it. On Linux, `./scripts/bootstrap-linux.sh` checks the version and the system prerequisites, then builds:

```sh
./scripts/bootstrap-linux.sh          # zig build
./scripts/bootstrap-linux.sh tests    # any arguments go to zig build
```

## Dev Builds and Packaged Builds

A plain `zig build` makes a dev build. The executable reads assets straight from your source tree, so hot reload picks up edits to the real files:

```sh
zig build my_game                        # build and run
zig build my_game -Doptimize=ReleaseFast # optimized
```

When you're ready to hand the game to someone, build a package. It copies your `assets/` folder next to the executable and reads from there:

```sh
zig build -Dpackage=true -Doptimize=ReleaseSafe
```

The result is `zig-out/bin/my_game/`: the executable plus its `assets/`. Zip that folder up and it runs from anywhere. Hot reload is only active in debug builds, so a release package never watches files.

## Windows

Zig cross-compiles, so you can build the Windows version from Linux:

```sh
zig build -Dtarget=x86_64-windows -Dpackage=true -Doptimize=ReleaseSafe
```

## The Web

Web builds go through Emscripten. Install the Emscripten SDK, activate it so `em++` is on your `PATH`, then build with the `wasm32-emscripten` target and Emscripten's sysroot:

```sh
zig build my_game -Dtarget=wasm32-emscripten --sysroot ~/.cache/emscripten/sysroot
```

The output is `zig-out/web/my_game/index.html` plus its `.wasm` and `.data` files. Serve that folder over HTTP, for instance with `emrun`:

```sh
cd zig-out/web/my_game && emrun index.html
```

A few things are different on the web:

- Assets are preloaded into Emscripten's virtual file system. With an inline manifest, only the files it lists are packed in; otherwise the whole `assets/` folder is.
- The page comes from an HTML shell file, `src/shell.html`, which the build reads from your project. Copy pixzig's `src/shell.html` into your game to start with, and change it as you like.
- Rendering uses WebGL 2. Custom shaders need to be GLSL ES 3.00 (see [Low-Level Rendering](page:low-level-rendering)).
- There's no hot reload, and the window icon is left to the page's favicon.

`AppRunner` hides the different main loop the browser needs, so the same game code runs on both.

In the pixzig repo itself, the `justfile` wraps these: `just bweb render_ex` builds an example for the web (set `EMSCRIPTEN_SYSROOT` first) and `just rweb render_ex` runs it.

## Android

Android builds need the Android SDK (with build-tools and a platform) and NDK, as Android Studio installs them, plus a JDK 17 or newer for `javac`, `jar` and the SDK's Java tools. Then:

```sh
zig build my_game -Dtarget=aarch64-linux-android
```

builds `zig-out/android/my_game.apk`, installs it on the connected phone or tablet with `adb`, and launches it. `zig build my_game_apk` with the same target only builds the APK, and `zig build install` builds all of them. Use `-Dtarget=x86_64-linux-android` for the emulator. There's no Gradle project: the build compiles SDL3 and the game for Android, makes the APK with the SDK's own tools, and signs it with the debug key (`~/.android/debug.keystore`, which Android Studio creates).

| Option | Default |
|---|---|
| `-Dandroid_sdk=<dir>` | `$ANDROID_HOME`, then `~/Android/Sdk` |
| `-Dandroid_ndk=<dir>` | `$ANDROID_NDK_HOME`, then the newest under the SDK's `ndk/` |
| `-Dandroid_api=<n>` | 26 (Android 8.0, the first with AAudio), or the level a triple names, e.g. `aarch64-linux-android.28` |
| `-Dandroid_target_sdk=<n>` | 35 |
| `-Dandroid_keystore=<file>` | `~/.android/debug.keystore` |

The log goes to logcat: `adb logcat -s pixzig` shows the game's own lines, and `adb logcat -s pixzig SDL AndroidRuntime DEBUG` adds SDL's and any crash.

On Android:

- The `assets/` folder is packed into the APK, and relative asset paths read from there, so the game's code doesn't change. Everything the engine loads (textures, fonts, maps, sounds, Lua scripts) reads through SDL, which knows where to look. Saves go to `platform.prefPath`, the app's private storage.
- The window always fills the screen. `EngineInitOptions.orientation` picks the way up: the default, `.auto`, is landscape for a `windowSize` wider than tall and portrait otherwise; `.landscape`, `.portrait` and `.any` say so outright.
- Rendering uses OpenGL ES 3.0. The engine's shaders are GLSL ES 3.00 everywhere, so custom shaders written for the web work here too.
- Touch drives the [virtual pad](page:input), and the back button closes the game.
- There's no hot reload, and the launcher icon is pixzig's for now.

In the pixzig repo, `just band render_ex` builds an example's APK (`just band` alone builds them all), `just rand render_ex` builds, installs and launches it, and `just logcat` follows the log. `band` targets `aarch64`; set `ANDROID_ABI=x86_64` to build for the emulator. `rand` builds for whichever device is connected, and with none it boots the emulator first (`just emu` does only that; `ANDROID_AVD` picks the image). With a phone and the emulator both connected, set `ANDROID_SERIAL` to the one `adb devices` lists that you want.

## Tests and Docs

In the pixzig repo:

```sh
zig build tests          # run the unit tests
zig build tests -- -v    # arguments after -- go to the test runner
zig build docs           # build these docs into docs-out/
```

The tests use [testz](https://github.com/srjilarious/testz) and open a hidden window for the ones that need OpenGL. The docs are built with [zkdocs](https://github.com/srjilarious/zkdocs) from the pages in `docs/` and the doc comments in the source.

## Screenshots

`tools/doc_screenshots.py` regenerates the example screenshots in `docs/assets/screenshots/`. It needs Pillow:

```sh
tools/doc_screenshots.py              # build, then capture every shot
tools/doc_screenshots.py actor tiles  # just these
tools/doc_screenshots.py --list       # which shot goes on which page
```

Each shot runs an example under SDL's offscreen driver, so no windows open, and the script crops and scales the frame. The shots, their timing, input and crops are a table at the top of the script.

It works through a hook in `AppRunner` that an app opts into with `EngineOptions.screenshotHook`. It's off by default, so a shipped game can't be driven by environment variables. With it on, setting `PIXZIG_SCREENSHOT` makes the runner do one update per frame, capture the frame at a set game time and exit:

| Variable | What it does |
|---|---|
| `PIXZIG_SCREENSHOT` | The PNG to write. Nothing changes unless this is set. |
| `PIXZIG_SCREENSHOT_MS` | Game time to capture at, default 1000. |
| `PIXZIG_SCREENSHOT_SIZE` | Window size as `WxH`. |
| `PIXZIG_SCREENSHOT_SEED` | Seed for `eng.rng`, default 1. |
| `PIXZIG_SCREENSHOT_INPUT` | Scripted input, like `300 tap F1; 500 text print(1); 600 tap enter`. |

Because game time counts ticks rather than wall time, a capture lands on the same tick every run. The input verbs are `tap`, `down` and `up` for keys, `text` to type, `move` for the cursor, and `click`, `mdown` and `mup` for mouse buttons. `src/pixzig/screenshot.zig` has the details.
