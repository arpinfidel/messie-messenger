# Messie Mobile Stack — Phase 1 Progress

## P1-A — Skeleton Verification

- [x] Rust workspace with `messie-matrix` (Matrix SDK wrapper) and
  `messie-ffi` (FFI surface for Flutter).
- [x] Flutter Material 3 shell with Riverpod wiring and a Rust bridge smoke
  test (`ping`).
- [x] Platform scaffolding and hand-written FFI bridge matching the future
  flutter_rust_bridge integration points.

## P1-B — Secure Session & Login

- [x] Rust API for session lifecycle: `init_client`, `restore_or_login`, and
  `logout`, returning structured JSON envelopes for Dart.
- [x] Persistent session storage under the chosen base path with automatic
  restoration through the Matrix SDK.
- [x] Flutter login screen with homeserver / username / password fields,
  secure credential storage (Keychain / Keystore via
  `flutter_secure_storage`), and logout that wipes both the store and Rust
  caches.
- [x] Automatic warm-start restore that rehydrates the session and surfaces the
  logged-in Matrix identity.
