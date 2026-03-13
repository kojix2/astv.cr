// ── App-specific WASM bindings ────────────────────────────────────────────────
//
// To create a new Crystal+WASM app from this template:
//   1. Change the wasmUrl to point to your .wasm file.
//   2. Replace the `astv_` prefix on all export names with your app name.
//   3. Replace the postJson routing logic with your own API calls.
//
// The generic WASM loader lives in wasm-loader.js — no changes needed there.

import { initWasm, makeStringIO } from "./wasm-loader.js";

const wasmUrl = new URL("./astv.wasm", import.meta.url);
window.astvWasmReady = initAstvWasm();

async function initAstvWasm() {
  const { exports, memory } = await initWasm(wasmUrl);

  const { astv_alloc, astv_free, astv_parse, astv_lex, astv_last_len, astv_version } =
    exports;
  if (!astv_alloc || !astv_parse || !astv_lex || !astv_last_len) {
    throw new Error("Required WASM exports are missing.");
  }

  const { call, callNoInput } = makeStringIO(memory, astv_alloc, astv_free, astv_last_len);

  let crystalVersion = null;
  if (astv_version) {
    try {
      const versionInfo = callNoInput(astv_version);
      if (versionInfo && typeof versionInfo.crystal_version === "string") {
        crystalVersion = versionInfo.crystal_version;
      }
    } catch (_) {
      crystalVersion = null;
    }
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

  return { postJson, crystalVersion };
}
