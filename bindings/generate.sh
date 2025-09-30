#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUST_CRATE_DIR="$PROJECT_ROOT/core/messie-ffi"
DART_OUTPUT="$PROJECT_ROOT/app/lib/bridge/bridge_generated.dart"
RUST_OUTPUT="$PROJECT_ROOT/core/messie-ffi/src/bridge_generated.rs"
CONFIG="$PROJECT_ROOT/bindings/frb_config.yaml"

flutter_rust_bridge_codegen \
  --rust-input "$RUST_CRATE_DIR/src/api.rs" \
  --dart-output "$DART_OUTPUT" \
  --rust-output "$RUST_OUTPUT" \
  --class-name MessieFfi \
  --config "$CONFIG"
