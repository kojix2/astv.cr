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
