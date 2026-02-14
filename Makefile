CRYSTAL ?= crystal
SRC ?= src/astv.cr
BIN_DIR ?= bin
BIN ?= $(BIN_DIR)/astv
RELEASE_FLAGS ?= --release

WASM_SRC ?= wsm/astv_wasm.cr
WASM_OUT ?= web/astv.wasm
WASI_CACHE_DIR ?= .cache/wasm
WASI_SYSROOT_DIR ?= $(WASI_CACHE_DIR)/wasm32-wasi-sysroot
WASI_SYSROOT_URL ?= https://github.com/kojix2/wasm-libs/releases/download/v0.0.4/wasm32-wasi-sysroot.tar.gz

.PHONY: all build run demo wasm-deps wasm-build wasm-serve clean

all: wasm-build

build:
	mkdir -p $(BIN_DIR)
	$(CRYSTAL) build $(SRC) -o $(BIN) $(RELEASE_FLAGS)

run:
	$(CRYSTAL) run $(SRC)

demo:
	printf 'class User; def initialize(@name : String); end; end\n' | $(CRYSTAL) run $(SRC)

wasm-deps:
	@if [ ! -d "$(WASI_SYSROOT_DIR)" ]; then \
		mkdir -p "$(WASI_CACHE_DIR)"; \
		curl -fsSL "$(WASI_SYSROOT_URL)" -o /tmp/wasm32-wasi-sysroot.tar.gz; \
		tar -xzf /tmp/wasm32-wasi-sysroot.tar.gz -C "$(WASI_CACHE_DIR)"; \
	fi

wasm-build: wasm-deps
	mkdir -p web
	WASI_SYSROOT="$(PWD)/$(WASI_SYSROOT_DIR)" \
	CRYSTAL_LIBRARY_PATH="$(PWD)/$(WASI_SYSROOT_DIR)/lib/wasm32-wasi" \
	$(CRYSTAL) build $(WASM_SRC) -o $(WASM_OUT) --target wasm32-wasi $(RELEASE_FLAGS)

wasm-serve:
	python -m http.server 8000 --directory web

clean:
	rm -rf $(BIN_DIR)
	rm -rf $(WASI_CACHE_DIR)
	rm -f $(WASM_OUT)
