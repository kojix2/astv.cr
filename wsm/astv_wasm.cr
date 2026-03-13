require "../src/astv/core"
require "./wasm_helper"

# ── App-specific WASM bindings ────────────────────────────────────────────────
#
# To create a new Crystal+WASM app from this template:
#   1. Replace the `astv_` prefix throughout this file with your app name.
#   2. Replace the contents of the AstvWasm module with your own logic.
#   3. Add or remove `fun` exports to match what main.js expects.
#
# The WasmRuntime helpers (safe_string, set_output, alloc, free, last_len)
# come from wasm_helper.cr and need no changes.

module AstvWasm
  extend self

  MAX_INPUT_BYTES = 1_000_000

  def parse(ptr : UInt8*, len : Int32) : Int32
    source = ""
    begin
      if len > MAX_INPUT_BYTES
        return WasmRuntime.set_output(Astv::Core.error_response(RuntimeError.new("payload too large"), ""))
      end

      source = WasmRuntime.safe_string(ptr, len)
      WasmRuntime.set_output(Astv::Core.parse_response(source))
    rescue ex
      WasmRuntime.set_output(Astv::Core.error_response(ex, source))
    end
  end

  def lex(ptr : UInt8*, len : Int32) : Int32
    source = ""
    begin
      if len > MAX_INPUT_BYTES
        return WasmRuntime.set_output(Astv::Core.error_response(RuntimeError.new("payload too large"), ""))
      end

      source = WasmRuntime.safe_string(ptr, len)
      WasmRuntime.set_output(Astv::Core.lex_response(source))
    rescue ex
      WasmRuntime.set_output(Astv::Core.error_response(ex, source))
    end
  end

  def version : Int32
    WasmRuntime.set_output(%({"crystal_version":"#{Crystal::VERSION}"}))
  end
end

# ── Exported C functions ──────────────────────────────────────────────────────
# Rename the `astv_` prefix to match your app name.
# alloc / free / last_len are required by the JS loader (wasm-loader.js).

fun astv_alloc(size : Int32) : UInt8*
  WasmRuntime.alloc(size)
end

fun astv_free(ptr : UInt8*, size : Int32)
  WasmRuntime.free(ptr)
end

fun astv_last_len : Int32
  WasmRuntime.last_len
end

# App-specific exports — add/remove/rename to match your app's API.

fun astv_parse(ptr : UInt8*, len : Int32) : Int32
  AstvWasm.parse(ptr, len)
end

fun astv_lex(ptr : UInt8*, len : Int32) : Int32
  AstvWasm.lex(ptr, len)
end

fun astv_version : Int32
  AstvWasm.version
end
