# Generic Crystal+WASM runtime helper for wasm32-wasi targets.
#
# This file has no app-specific logic and can be copied to new projects as-is.
#
# Usage in your WASM entry point (e.g. wsm/your_app_wasm.cr):
#
#   require "./wasm_helper"
#
#   fun your_app_alloc(size : Int32) : UInt8*
#     WasmRuntime.alloc(size)
#   end
#
#   fun your_app_free(ptr : UInt8*, size : Int32)
#     WasmRuntime.free(ptr)
#   end
#
#   fun your_app_last_len : Int32
#     WasmRuntime.last_len
#   end
#
#   fun your_app_hello(ptr : UInt8*, len : Int32) : Int32
#     source = WasmRuntime.safe_string(ptr, len)
#     WasmRuntime.set_output(%({"result":"hello, #{source}"}))
#   end

lib LibC
  fun malloc(size : SizeT) : Void*
  fun free(ptr : Void*)
end

# Provides WASM linear-memory I/O helpers shared across all exported functions.
#
# - `safe_string`  converts a (ptr, len) pair from WASM memory into a Crystal String.
# - `set_output`   stores a result String and returns its address as Int32 for JS.
# - `last_len`     returns the byte length of the last stored output (call from JS after each export).
# - `alloc`/`free` delegate to libc malloc/free for JS-managed input buffers.
module WasmRuntime
  extend self

  @@last_string = ""
  @@last_bytes = Bytes.empty
  @@last_len = 0

  # Returns the byte length of the string last written by `set_output`.
  # JS must call the exported wrapper of this function immediately after each
  # WASM call to retrieve how many bytes to read from the returned pointer.
  def last_len : Int32
    @@last_len
  end

  # Safely converts a pointer+length from WASM linear memory into a Crystal String.
  # Returns an empty string for null pointers or non-positive lengths.
  def safe_string(ptr : UInt8*, len : Int32) : String
    return "" if ptr.null? || len <= 0
    String.new(ptr, len)
  end

  # Stores *output* as the current result and returns its memory address as Int32.
  # JS reads `last_len` bytes starting at the returned address to decode the JSON.
  def set_output(output : String) : Int32
    @@last_string = output
    @@last_bytes = output.to_slice
    @@last_len = @@last_bytes.size
    @@last_bytes.to_unsafe.address.to_i32
  end

  # Allocates *size* bytes in WASM linear memory via libc malloc.
  # JS uses the returned pointer to write input data before calling an export.
  def alloc(size : Int32) : UInt8*
    return Pointer(UInt8).null if size <= 0
    LibC.malloc(size).as(UInt8*)
  end

  # Frees a pointer previously allocated with `alloc`.
  def free(ptr : UInt8*)
    return if ptr.null?
    LibC.free(ptr.as(Void*))
  end
end
