# Flutter Rust Bridge Bindings

This directory hosts tooling to generate the Flutter Rust Bridge glue code and
platform-specific build scripts. The default workflow is:

1. Run `./bindings/generate.sh` after editing any Rust APIs in
   `core/messie-ffi/src/api.rs`.
2. Build the platform artefacts:
   - Android: `./bindings/android/build.sh`
   - iOS: `./bindings/ios/build.sh`

Generated Dart files are written to `app/lib/bridge/bridge_generated.dart` while
Rust glue lives in `core/messie-ffi/src/bridge_generated.rs`. The repository
includes a hand-written minimal bridge so the project compiles before the
codegen step is wired into CI.
