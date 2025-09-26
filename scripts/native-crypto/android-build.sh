#!/bin/bash
set -euo pipefail

cd /work/rust/messie-crypto-ffi
mkdir -p include
cargo ndk -t aarch64-linux-android -t x86_64-linux-android build --release
uniffi-bindgen generate src/native_crypto.udl --language kotlin --out-dir /work/plugins/native-crypto/android/nativecrypto/src/main/kotlin/com/messie/nativecrypto/ffi
uniffi-bindgen generate src/native_crypto.udl --language swift --out-dir /work/plugins/native-crypto/ios/Sources/NativeCrypto/Generated
uniffi-bindgen generate src/native_crypto.udl --language c --out-dir include
mkdir -p /work/out/android/jni
find target -path '*android*/release' -name 'libmessie_crypto_ffi.so' -exec cp {} /work/out/android/jni/ \;

cd /work/plugins/native-crypto/android
./gradlew :nativecrypto:assembleRelease
mkdir -p /work/out/android
find nativecrypto/build/outputs/aar -name '*.aar' -exec cp {} /work/out/android/ \;
