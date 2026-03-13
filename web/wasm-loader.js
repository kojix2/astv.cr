/**
 * Generic Crystal+WASM loader for wasm32-wasi targets.
 *
 * This file has no app-specific logic and can be copied to new projects as-is.
 *
 * Typical usage in your app's main.js:
 *
 *   import { initWasm, makeStringIO } from "./wasm-loader.js";
 *
 *   const { exports, memory } = await initWasm(new URL("./app.wasm", import.meta.url));
 *   const { call, callNoInput } = makeStringIO(
 *     memory, exports.app_alloc, exports.app_free, exports.app_last_len
 *   );
 *
 *   const result = call(exports.app_hello, "world");  // → parsed JSON
 */

/**
 * Fetch, compile and instantiate a WASM module built with --target wasm32-wasi.
 *
 * @param {URL|string} wasmUrl - URL of the .wasm file (use `new URL("./app.wasm", import.meta.url)`)
 * @returns {{ exports: WebAssembly.Exports, memory: WebAssembly.Memory }}
 */
export async function initWasm(wasmUrl) {
  const res = await fetch(wasmUrl);
  if (!res.ok) {
    throw new Error(`Failed to load WASM: ${res.status} ${wasmUrl}`);
  }

  const bytes = await res.arrayBuffer();
  const module = await WebAssembly.compile(bytes);
  const { imports, memory: importedMemory } = _buildImports(module);
  const instance = await WebAssembly.instantiate(module, imports);
  const exports = instance.exports;
  const memory = exports.memory || importedMemory;

  if (!memory) {
    throw new Error("WASM memory not found.");
  }

  _initializeRuntime(exports);

  return { exports, memory };
}

/**
 * Creates a string I/O helper bound to the WASM module's memory management exports.
 *
 * The Crystal side must expose three functions (here shown with an `app_` prefix):
 *   - `app_alloc(size: i32) → i32`    allocate *size* bytes, return pointer
 *   - `app_free(ptr: i32, size: i32)` free a previously allocated buffer
 *   - `app_last_len() → i32`          return byte length of last JSON output
 *
 * @param {WebAssembly.Memory} memory    - The WASM linear memory instance
 * @param {Function}           allocFn   - Exported alloc function
 * @param {Function}           freeFn    - Exported free function
 * @param {Function}           lastLenFn - Exported last_len function
 * @returns {{ call: Function, callNoInput: Function }}
 */
export function makeStringIO(memory, allocFn, freeFn, lastLenFn) {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  /**
   * Call a WASM export that takes (ptr: i32, len: i32) and returns ptr to JSON.
   * Encodes *source* as UTF-8, copies it into WASM memory, calls *fn*, then
   * decodes and parses the JSON output.
   *
   * @param {Function} fn     - Exported WASM function
   * @param {string}   source - Input string
   * @returns {any} Parsed JSON value
   */
  function call(fn, source) {
    const input = encoder.encode(source ?? "");
    const size = input.length;
    const ptr = size > 0 ? allocFn(size) : 0;
    if (size > 0) {
      new Uint8Array(memory.buffer, ptr, size).set(input);
    }

    const outPtr = fn(ptr, size);
    const outLen = lastLenFn();
    const text = decoder.decode(new Uint8Array(memory.buffer, outPtr, outLen));

    if (size > 0 && freeFn) freeFn(ptr, size);

    return JSON.parse(text);
  }

  /**
   * Call a WASM export that takes no input and returns ptr to JSON.
   *
   * @param {Function} fn - Exported WASM function
   * @returns {any} Parsed JSON value
   */
  function callNoInput(fn) {
    const outPtr = fn();
    const outLen = lastLenFn();
    const text = decoder.decode(new Uint8Array(memory.buffer, outPtr, outLen));
    return JSON.parse(text);
  }

  return { call, callNoInput };
}

// ── Internal helpers (not exported) ──────────────────────────────────────────

function _initializeRuntime(exports) {
  if (exports.__main_argc_argv) {
    exports.__main_argc_argv(0, 0);
    return;
  }
  if (exports._start) exports._start();
}

function _buildImports(module) {
  const imports = {};
  let memory = null;
  const wasi = _createWasi(() => memory);

  for (const { module: mod, name, kind } of WebAssembly.Module.imports(module)) {
    const target = (imports[mod] ??= {});
    if (kind === "function") {
      target[name] = mod === "wasi_snapshot_preview1"
        ? (wasi[name] ?? (() => 58))
        : () => 0;
    } else if (kind === "memory") {
      memory = new WebAssembly.Memory({ initial: 256 });
      target[name] = memory;
    } else if (kind === "table") {
      target[name] = new WebAssembly.Table({ initial: 0, element: "funcref" });
    } else {
      target[name] = 0;
    }
  }

  return { imports, memory };
}

function _createWasi(getMemory) {
  const ok = 0;
  const badf = 8;
  const notsup = 58;
  const noent = 44;
  const filetypeChar = 2;
  const filetypeDir = 3;
  const prestatDirTag = 1;

  function dv() {
    const m = getMemory ? getMemory() : null;
    return m ? new DataView(m.buffer) : null;
  }

  function mem() {
    return getMemory ? getMemory() : null;
  }

  function writeU32(ptr, v) {
    const d = dv();
    if (!d) return;
    d.setUint32(ptr, v >>> 0, true);
  }

  function writeU64(ptr, v) {
    const d = dv();
    if (!d) return;
    d.setUint32(ptr, v >>> 0, true);
    d.setUint32(ptr + 4, 0, true);
  }

  function fill(ptr, len, v = 0) {
    const m = mem();
    if (m) new Uint8Array(m.buffer, ptr, len).fill(v);
  }

  function writeFdstat(ptr, filetype) {
    const d = dv();
    if (!d) return;
    d.setUint8(ptr, filetype);
    d.setUint16(ptr + 2, 0, true);
    d.setBigUint64(ptr + 8, 0n, true);
    d.setBigUint64(ptr + 16, 0n, true);
  }

  function writePrestatDir(ptr, nameLen) {
    const d = dv();
    if (!d) return;
    d.setUint8(ptr, prestatDirTag);
    d.setUint32(ptr + 4, nameLen >>> 0, true);
  }

  function writeFilestatDir(ptr) {
    const d = dv();
    if (!d) return;
    fill(ptr, 64, 0);
    d.setUint8(ptr + 16, filetypeDir);
  }

  return {
    args_get: () => ok,
    args_sizes_get: (argc, argvBufSize) => {
      writeU32(argc, 0);
      writeU32(argvBufSize, 0);
      return ok;
    },
    environ_get: () => ok,
    environ_sizes_get: (count, bufSize) => {
      writeU32(count, 0);
      writeU32(bufSize, 0);
      return ok;
    },
    clock_time_get: (_id, _prec, ptr) => {
      writeU64(ptr, 0);
      return ok;
    },
    random_get: (ptr, len) => {
      fill(ptr, len, 0);
      return ok;
    },
    fd_fdstat_get: (fd, ptr) => {
      if (fd === 0 || fd === 1 || fd === 2) { writeFdstat(ptr, filetypeChar); return ok; }
      if (fd === 3) { writeFdstat(ptr, filetypeDir); return ok; }
      return badf;
    },
    fd_fdstat_set_flags: (fd) => (fd <= 2 ? ok : badf),
    fd_seek: (_fd, _lo, _hi, _w, ptr) => {
      writeU64(ptr, 0);
      return ok;
    },
    fd_write: (_fd, iovs, iovsLen, writtenPtr) => {
      const d = dv();
      if (!d) { writeU32(writtenPtr, 0); return ok; }
      let written = 0;
      for (let i = 0; i < iovsLen; i++) {
        written += d.getUint32(iovs + i * 8 + 4, true);
      }
      writeU32(writtenPtr, written);
      return ok;
    },
    path_filestat_get: (fd, _flags, _pathPtr, _pathLen, ptr) => {
      if (fd === 3) { writeFilestatDir(ptr); return ok; }
      return noent;
    },
    fd_prestat_get: (fd, ptr) => {
      if (fd !== 3) return badf;
      writePrestatDir(ptr, 1);
      return ok;
    },
    fd_prestat_dir_name: (fd, pathPtr, pathLen) => {
      if (fd !== 3) return badf;
      if (pathLen < 1) return notsup;
      const m = mem();
      if (!m) return notsup;
      new Uint8Array(m.buffer, pathPtr, 1)[0] = 46; // "."
      return ok;
    },
    proc_exit: () => ok,
  };
}
