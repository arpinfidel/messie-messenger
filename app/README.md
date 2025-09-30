# Messie Flutter App

This is the Flutter front-end for the Messie messenger project. It uses
Material 3 styling and Riverpod for state management. The skeleton wires a
`ping()` call to the Rust core via flutter_rust_bridge to verify the toolchain.

## Development

1. Ensure the Rust toolchain and Flutter SDK are installed.
2. Generate FRB bindings with `../bindings/generate.sh`.
3. Run the Flutter app:

```bash
flutter pub get
flutter run
```
