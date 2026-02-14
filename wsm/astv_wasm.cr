require "../src/astv/core"

module AstvWasm
  extend self

  MAX_INPUT_BYTES = 1_000_000

  @@last_string = ""
  @@last_bytes = Bytes.empty
  @@last_len = 0

  def last_len : Int32
    @@last_len
  end

  def parse(ptr : UInt8*, len : Int32) : Int32
    source = ""
    begin
      source = safe_string(ptr, len)
      if len > MAX_INPUT_BYTES
        return set_output(Astv::Core.error_response(RuntimeError.new("payload too large"), ""))
      end

      set_output(Astv::Core.parse_response(source))
    rescue ex
      set_output(Astv::Core.error_response(ex, source))
    end
  end

  def lex(ptr : UInt8*, len : Int32) : Int32
    source = ""
    begin
      source = safe_string(ptr, len)
      if len > MAX_INPUT_BYTES
        return set_output(Astv::Core.error_response(RuntimeError.new("payload too large"), ""))
      end

      set_output(Astv::Core.lex_response(source))
    rescue ex
      set_output(Astv::Core.error_response(ex, source))
    end
  end

  private def safe_string(ptr : UInt8*, len : Int32) : String
    return "" if ptr.null? || len <= 0

    String.new(ptr, len)
  end

  private def set_output(output : String) : Int32
    @@last_string = output
    @@last_bytes = output.to_slice
    @@last_len = @@last_bytes.size
    @@last_bytes.to_unsafe.address.to_i32
  end
end

lib LibC
  fun malloc(size : SizeT) : Void*
  fun free(ptr : Void*)
end

fun astv_alloc(size : Int32) : UInt8*
  return Pointer(UInt8).null if size <= 0

  LibC.malloc(size).as(UInt8*)
end

fun astv_free(ptr : UInt8*, size : Int32)
  return if ptr.null?

  LibC.free(ptr.as(Void*))
end

fun astv_parse(ptr : UInt8*, len : Int32) : Int32
  AstvWasm.parse(ptr, len)
end

fun astv_lex(ptr : UInt8*, len : Int32) : Int32
  AstvWasm.lex(ptr, len)
end

fun astv_last_len : Int32
  AstvWasm.last_len
end
