# Native Matrix Crypto Integration Notes

## 1. Upstream artifacts

- **Web**: `@matrix-org/matrix-sdk-crypto-wasm` – the same WASM bindings that `matrix-js-sdk` already uses.
- **Android**: Maven artifacts published under `org.matrix.rustcomponents`, notably `crypto-android:0.11.0` (crypto-only) and `sdk-android` if we ever need more of the stack.
- **iOS**: Swift package `matrix-rust-components-swift`, which bundles the XCFramework for the same Rust engine.

## 2. Android onboarding steps

1. Add the dependency in `frontend/android/app/build.gradle`:
   ```gradle
   dependencies {
       implementation 'org.matrix.rustcomponents:crypto-android:0.11.0'
   }
   ```
   `crypto-android` already ships the JNI libraries, Kotlin bindings, and their JNA helper classes.

2. At runtime the `MatrixCryptoPlugin` now:
   - loads `libmatrix_sdk_crypto_ffi.so` from the AAR,
   - initialises an `OlmMachine` backed by an app-specific directory under `filesDir/matrix_rust_crypto/<userId>_<deviceId>`,
   - exposes `initCrypto` and `decryptEvent` via Capacitor. `decryptEvent` returns the decrypted JSON plus the metadata the JS SDK can use for shields.

3. The plugin still needs additional wiring for outbound requests (key uploads/claims, etc.). Once those are exposed we can replace the fallback `client.initRustCrypto()` call.

## 3. TypeScript bridge

- `frontend/src/native/MatrixCryptoPlugin.ts` registers the Capacitor plugin and defines the shared interface. It exposes a web fallback (`MatrixCryptoWeb`) so desktop/web builds keep working with WASM.
- `MatrixClientManager.initCryptoIfNeeded()` prefers the Capacitor plugin on native and falls back to `client.initRustCrypto()` otherwise.

## 4. Next steps

- Extend the Android bridge to surface the full set of crypto APIs the JS SDK expects (outgoing requests, key backup, verification, etc.).
- Mirror the approach on iOS via `matrix-rust-components-swift` and a Swift Capacitor plugin.
- Swap the JS SDK over to the native bridge once feature parity is reached, keeping WASM as the browser fallback.

## 5. Useful references

- Maven Central: [org.matrix.rustcomponents:crypto-android](https://search.maven.org/artifact/org.matrix.rustcomponents/crypto-android/0.11.0/aar)
- Swift package: [matrix-rust-components-swift](https://github.com/matrix-org/matrix-rust-components-swift)
- WASM bindings: [@matrix-org/matrix-sdk-crypto-wasm](https://www.npmjs.com/package/@matrix-org/matrix-sdk-crypto-wasm)
