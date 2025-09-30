#!/usr/bin/env bash
set -euo pipefail

if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "cargo-ndk is required. Install with 'cargo install cargo-ndk'." >&2
  exit 1
fi

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CRATE_DIR="$PROJECT_ROOT/core/messie-ffi"
OUTPUT_DIR="$PROJECT_ROOT/app/android/app/src/main/jniLibs"

mkdir -p "$OUTPUT_DIR"

cargo ndk \
  -t armeabi-v7a \
  -t arm64-v8a \
  -t x86_64 \
  -o "$OUTPUT_DIR" \
  -p 21 \
  build --release --manifest-path "$CRATE_DIR/Cargo.toml"
