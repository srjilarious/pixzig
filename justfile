alias t := test
alias b := build
alias bwin := build_win
alias bweb := build_web
alias band := build_android
alias rand := run_android
alias emu := emulator
alias rweb := run_web
alias d := docs
alias pyi := py_install
alias boot := bootstrap

EMSCRIPTEN_SYSROOT := env_var_or_default("EMSCRIPTEN_SYSROOT", "")
# Android CPU: aarch64 for phones and tablets, x86_64 for the emulator
ANDROID_ABI := env_var_or_default("ANDROID_ABI", "aarch64")
ANDROID_SDK := env_var_or_default("ANDROID_HOME", home_directory() / "Android/Sdk")
# The SDK's adb, the one the build installs with; a second adb version keeps restarting the server
ADB := ANDROID_SDK / "platform-tools/adb"



docs :
	zig build docs

test *OPTS:
	zig build tests -- {{OPTS}}

build EX *OPTS:
	zig build {{EX}} {{OPTS}}

# Repeatable Linux build: verify the pinned Zig, prime the cache, then `zig build {{ARGS}}`
bootstrap *ARGS:
	./scripts/bootstrap-linux.sh {{ARGS}}

build_win EX *OPTS:
	zig build -Dtarget=x86_64-windows {{EX}} {{OPTS}}

build_web *EX:
	@if [ -z "{{EMSCRIPTEN_SYSROOT}}" ]; then \
		echo "Error: set EMSCRIPTEN_SYSROOT, e.g. /home/you/.cache/emscripten/sysroot"; \
		exit 1; \
	fi
	zig build {{EX}} -Dtarget=wasm32-emscripten --sysroot {{EMSCRIPTEN_SYSROOT}}

run_web EX:
	cd zig-out/web/{{EX}} && emrun ./index.html

# Build the named examples' APKs into zig-out/android/, or every example's with no names
build_android *EX:
	@if [ -z "{{EX}}" ]; then \
		zig build install -Dtarget={{ANDROID_ABI}}-linux-android; \
	else \
		for ex in {{EX}}; do zig build "${ex}_apk" -Dtarget={{ANDROID_ABI}}-linux-android || exit 1; done; \
	fi

# Build one example's APK, install it on the connected device (booting the emulator if there's none), and launch it
run_android EX *OPTS: emulator
	#!/usr/bin/env bash
	set -euo pipefail
	# Build for the device's CPU unless ANDROID_ABI says otherwise
	abi="${ANDROID_ABI:-}"
	if [ -z "$abi" ]; then
		case "$("{{ADB}}" shell getprop ro.product.cpu.abi | tr -d '\r')" in
			x86_64) abi=x86_64 ;;
			*) abi=aarch64 ;;
		esac
	fi
	zig build {{EX}} -Dtarget="$abi"-linux-android {{OPTS}}

# Boot the emulator (ANDROID_AVD, or the first image) and wait for it, unless a device is connected or one is running
emulator:
	#!/usr/bin/env bash
	set -euo pipefail
	adb="{{ADB}}"
	if "$adb" devices | sed 1d | grep -qw device; then exit 0; fi
	if ! pgrep -f 'qemu-system.*-avd' >/dev/null; then
		emulator="{{ANDROID_SDK}}/emulator/emulator"
		avd="${ANDROID_AVD:-$("$emulator" -list-avds | head -n 1)}"
		if [ -z "$avd" ]; then
			echo "No emulator images; create one in Android Studio's Device Manager" >&2
			exit 1
		fi
		log="${TMPDIR:-/tmp}/pixzig-emulator.log"
		echo "Booting $avd (log: $log)"
		setsid "$emulator" -avd "$avd" -no-snapshot-save >"$log" 2>&1 < /dev/null &
	fi
	echo "Waiting for the emulator to finish booting..."
	"$adb" wait-for-device
	until [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 1; done

# Follow the running game's log
logcat:
	{{ADB}} logcat -s pixzig SDL AndroidRuntime DEBUG

# Build the Linux and Windows Python wheels into python/dist/
wheels:
	python3 python/build_wheels.py

# Build the wheels, then install the Linux one into VENV (created with uv if missing)
py_install VENV=".venv": wheels
	@[ -d "{{VENV}}" ] || uv venv "{{VENV}}"
	uv pip install --python "{{VENV}}" --reinstall "python/dist/pixzig-$(cat python/VERSION)-py3-none-linux_x86_64.whl"

# Run a Python example against the installed wheel, e.g. `just py hello_pixzig`
py EX VENV=".venv":
	"{{VENV}}/bin/python" python/examples/{{EX}}.py
