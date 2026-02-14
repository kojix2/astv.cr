const wasmUrl = new URL("./astv.wasm", import.meta.url);
window.astvWasmReady = initAstvWasm();

async function initAstvWasm() {
  const res = await fetch(wasmUrl);
  if (!res.ok) {
    throw new Error(`Failed to load astv.wasm: ${res.status}`);
  }

  const bytes = await res.arrayBuffer();
  const module = await WebAssembly.compile(bytes);
  const { imports, memory: importedMemory } = buildImports(module);
  const instance = await WebAssembly.instantiate(module, imports);
  const exports = instance.exports;
  const memory = exports.memory || importedMemory;

  if (!memory) {
    throw new Error("WASM memory not found.");
  }

  const { astv_alloc, astv_free, astv_parse, astv_lex, astv_last_len } =
    exports;
  if (!astv_alloc || !astv_parse || !astv_lex || !astv_last_len) {
    throw new Error("Required WASM exports are missing.");
  }

  initializeRuntime(exports);

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function call(fn, source) {
    const input = encoder.encode(source ?? "");
    const size = input.length;
    const ptr = size > 0 ? astv_alloc(size) : 0;
    if (size > 0) {
      new Uint8Array(memory.buffer, ptr, size).set(input);
    }

    const outPtr = fn(ptr, size);
    const outLen = astv_last_len();
    const outBytes = new Uint8Array(memory.buffer, outPtr, outLen);
    const text = decoder.decode(outBytes);

    if (size > 0 && astv_free) {
      astv_free(ptr, size);
    }

    return JSON.parse(text);
  }

  function postJson(url, payload) {
    const source =
      payload && typeof payload.code === "string" ? payload.code : "";
    if (url.includes("/api/parse")) {
      return call(astv_parse, source);
    }
    if (url.includes("/api/lex")) {
      return call(astv_lex, source);
    }
    throw new Error(`Unknown endpoint: ${url}`);
  }

  return { postJson };
}

function initializeRuntime(exports) {
  if (exports.__main_argc_argv) {
    exports.__main_argc_argv(0, 0);
    return;
  }
  if (exports._start) exports._start();
}

function buildImports(module) {
  const imports = {};
  let memory = null;
  const wasi = createWasi(() => memory);

  for (const { module: mod, name, kind } of WebAssembly.Module.imports(
    module,
  )) {
    const target = (imports[mod] ??= {});
    if (kind === "function") {
      if (mod === "wasi_snapshot_preview1") {
        target[name] = wasi[name] ?? (() => 58);
      } else {
        target[name] = () => 0;
      }
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

function createWasi(getMemory) {
  const ok = 0;
  const badf = 8;
  const notsup = 58;
  const noent = 44;
  const filetypeChar = 2;
  const filetypeDir = 3;
  const prestatDirTag = 1;

  function memoryView() {
    const mem = getMemory && getMemory();
    return mem ? new DataView(mem.buffer) : null;
  }

  function writeU32(ptr, value) {
    const view = memoryView();
    if (!view) return;
    view.setUint32(ptr, value >>> 0, true);
  }

  function writeU64(ptr, value) {
    const view = memoryView();
    if (!view) return;
    const low = value >>> 0;
    view.setUint32(ptr, low, true);
    view.setUint32(ptr + 4, 0, true);
  }

  function fill(ptr, len, value = 0) {
    const mem = getMemory && getMemory();
    if (!mem) return;
    new Uint8Array(mem.buffer, ptr, len).fill(value);
  }

  function writeFdstat(ptr, filetype) {
    const view = memoryView();
    if (!view) return;
    view.setUint8(ptr, filetype);
    view.setUint16(ptr + 2, 0, true);
    view.setBigUint64(ptr + 8, 0n, true);
    view.setBigUint64(ptr + 16, 0n, true);
  }

  function writePrestatDir(ptr, nameLen) {
    const view = memoryView();
    if (!view) return;
    view.setUint8(ptr, prestatDirTag);
    view.setUint32(ptr + 4, nameLen >>> 0, true);
  }

  function writeFilestatDir(ptr) {
    const view = memoryView();
    if (!view) return;
    fill(ptr, 64, 0);
    view.setUint8(ptr + 16, filetypeDir);
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
    clock_time_get: (clockId, precision, timePtr) => {
      writeU64(timePtr, 0);
      return ok;
    },
    random_get: (bufPtr, bufLen) => {
      fill(bufPtr, bufLen, 0);
      return ok;
    },
    fd_fdstat_get: (fd, bufPtr) => {
      if (fd === 0 || fd === 1 || fd === 2) {
        writeFdstat(bufPtr, filetypeChar);
        return ok;
      }
      if (fd === 3) {
        writeFdstat(bufPtr, filetypeDir);
        return ok;
      }
      return badf;
    },
    fd_fdstat_set_flags: (fd, flags) => {
      if (fd !== 0 && fd !== 1 && fd !== 2) return badf;
      return ok;
    },
    fd_seek: (fd, offsetLow, offsetHigh, whence, newOffsetPtr) => {
      writeU64(newOffsetPtr, 0);
      return ok;
    },
    fd_write: (fd, iovs, iovsLen, writtenPtr) => {
      const view = memoryView();
      if (!view) {
        writeU32(writtenPtr, 0);
        return ok;
      }
      let written = 0;
      for (let i = 0; i < iovsLen; i += 1) {
        const base = iovs + i * 8;
        const len = view.getUint32(base + 4, true);
        written += len;
      }
      writeU32(writtenPtr, written);
      return ok;
    },
    path_filestat_get: (fd, flags, pathPtr, pathLen, bufPtr) => {
      if (fd === 3) {
        writeFilestatDir(bufPtr);
        return ok;
      }
      return noent;
    },
    fd_prestat_get: (fd, prestatPtr) => {
      if (fd !== 3) return badf;
      writePrestatDir(prestatPtr, 1);
      return ok;
    },
    fd_prestat_dir_name: (fd, pathPtr, pathLen) => {
      if (fd !== 3) return badf;
      if (pathLen < 1) return notsup;
      const mem = getMemory && getMemory();
      if (!mem) return notsup;
      new Uint8Array(mem.buffer, pathPtr, 1)[0] = 46;
      return ok;
    },
    proc_exit: () => ok,
  };
}
