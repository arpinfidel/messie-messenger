#!/usr/bin/env bash
set -euo pipefail

# Ensure cargo-ndk exists
if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "Install cargo-ndk: cargo install cargo-ndk" >&2
  exit 1
fi

# Make sure SDK/NDK envs point to a *real* Android SDK, not just commandlinetools
: "${ANDROID_SDK_ROOT:=$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE_DIR="$ROOT/core/messie-ffi"
OUT_DIR="$ROOT/app/android/app/src/main/jniLibs"

mkdir -p "$OUT_DIR"

pushd "$CRATE_DIR" >/dev/null

# Ensure Rust targets exist (run once; harmless if already installed)
rustup target add aarch64-linux-android x86_64-linux-android

# Don’t leak host OpenSSL into the Android cross build
unset OPENSSL_DIR LDFLAGS CPPFLAGS

# Build for ABIs you need (arm64-v8a is enough for your gphone64 arm64 emulator)
cargo ndk \
  --platform 21 \
  --target arm64-v8a \
  --target x86_64 \
  -o "$OUT_DIR" \
  build --release

popd >/dev/null
echo "✔ .so copied under: $OUT_DIR"
