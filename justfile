alias t := test
alias b := build
alias bwin := build_win
alias bweb := build_web
alias rweb := run_web
alias d := docs

EMSCRIPTEN_SYSROOT := env_var_or_default("EMSCRIPTEN_SYSROOT", "")



docs :
	zig build docs

test *OPTS:
	zig build tests -- {{OPTS}}

build EX *OPTS:
	zig build {{EX}} {{OPTS}}

build_win EX *OPTS:
	zig build -Dtarget=x86_64-windows {{EX}} {{OPTS}}

build_web *EX:
	@if [ -z "{{EMSCRIPTEN_SYSROOT}}" ]; then \
		echo "Error: set EMSCRIPTEN_SYSROOT, e.g. /home/you/.cache/emscripten/sysroot"; \
		exit 1; \
	fi
	zig build {{EX}} -Dtarget=wasm32-emscripten --sysroot {{EMSCRIPTEN_SYSROOT}}

run_web EX:
	cd zig-out/web/{{EX}} && /usr/lib/emscripten/emrun ./index.html