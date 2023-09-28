FROM scratch
COPY /target/wasm32-wasi/release/dockercon.wasm .
COPY spin.toml .
