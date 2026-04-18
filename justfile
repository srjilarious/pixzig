alias t := test
alias b := build
alias bwin := build_win
alias bweb := build_web
alias rweb := run_web
alias d := docs

docs :
	zig build docs

test *OPTS:
	zig build tests -- {{OPTS}}

build EX *OPTS:
	zig build {{EX}} {{OPTS}}

build_win EX *OPTS:
	zig build -Dtarget=x86_64-windows {{EX}} {{OPTS}}

build_web *EX:
	zig build {{EX}} -Dtarget=wasm32-emscripten --sysroot /home/jeffdw/.cache/emscripten/sysroot

run_web EX:
	cd zig-out/web/{{EX}} && /usr/lib/emscripten/emrun ./index.html