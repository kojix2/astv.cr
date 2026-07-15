# astv

Crystal AST viewer inspired by https://github.com/ko1/astv

## Web (static)

The static UI lives in [web/index.html](web/index.html) and expects a
`web/astv.wasm` module to be available.

Build the WASM module (Linux):

```
make wasm-build
```

Serve:

```
ruby -run -e httpd web -p 8000
```

```
python -m http.server 8000 --directory web
```

> [!NOTE]
> Crystal's `wasm32` target compiles with no GC (`gc/none`), so the WASM
> module never frees memory: each parse/lex call leaks its allocations and
> the module's heap grows monotonically. This is intentionally left as-is —
> it is harmless for typical use, and reloading the page resets everything.

## CLI (Linux)

```
make build
```

Run (reads from stdin):

```
make run
```

Demo:

```
make demo
```
