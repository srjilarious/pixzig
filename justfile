alias t := test
alias b := build
alias bw := build_web
alias rw := run_web
alias d := docs

docs :
	zig build docs

test *OPTS:
	zig build tests -- {{OPTS}}

build EX *OPTS:
	zig build {{EX}} {{OPTS}}

build_web *EX:
	zig build {{EX}} -Dtarget=wasm32-emscripten --sysroot /home/jeffdw/.cache/emscripten/sysroot

run_web EX:
	cd zig-out/web/{{EX}} && /usr/lib/emscripten/emrun ./index.html