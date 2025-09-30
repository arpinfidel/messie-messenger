#!/usr/bin/env bash
set -euo pipefail

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is required to build the Rust static library" >&2
  exit 1
fi

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CRATE_DIR="$PROJECT_ROOT/core/messie-ffi"
IOS_TARGET_DIR="$PROJECT_ROOT/bindings/ios/rust"

mkdir -p "$IOS_TARGET_DIR"

declare -a TARGETS=(
  "aarch64-apple-ios"
  "x86_64-apple-ios"
)

for TARGET in "${TARGETS[@]}"; do
  cargo build --release --manifest-path "$CRATE_DIR/Cargo.toml" --target "$TARGET"
  TARGET_LIB_DIR="$CRATE_DIR/target/$TARGET/release"
  cp "$TARGET_LIB_DIR/libmessie_ffi.a" "$IOS_TARGET_DIR/libmessie_ffi_${TARGET}.a"
done

lipo -create \
  "$IOS_TARGET_DIR/libmessie_ffi_aarch64-apple-ios.a" \
  "$IOS_TARGET_DIR/libmessie_ffi_x86_64-apple-ios.a" \
  -output "$IOS_TARGET_DIR/libmessie_ffi_universal.a"

rm "$IOS_TARGET_DIR"/libmessie_ffi_*apple-ios.a

mkdir -p "$IOS_TARGET_DIR/MessieFFI.xcframework"
# Placeholder: In a production setup we'd use `xcodebuild -create-xcframework`.
# The skeleton keeps the compiled universal library for debugging purposes.
cp "$IOS_TARGET_DIR/libmessie_ffi_universal.a" "$IOS_TARGET_DIR/MessieFFI.xcframework/libmessie_ffi.a"
