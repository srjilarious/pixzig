alias t := test
alias b := build
alias bwin := build_win
alias bweb := build_web
alias rweb := run_web
alias d := docs
alias pyi := py_install
alias boot := bootstrap

EMSCRIPTEN_SYSROOT := env_var_or_default("EMSCRIPTEN_SYSROOT", "")



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
