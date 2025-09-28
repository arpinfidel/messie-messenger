# Native Runtime Smoke Tests

The Android native runtime currently exposes a lightweight smoke test flow to
catch build/regression issues before shipping.

## Prerequisites

- Android SDK + emulator image (API 33+) installed locally.
- `MATRIX_RUST_SDK_ANDROID_VERSION` set in `.env.mobile` if you want to pin a
  specific SDK build.
- Run from the `frontend/` directory so Capacitor paths resolve correctly.

## Emulator Setup via Makefile

Run the helper targets from the repository root so the Android SDK and AVD stay in sync. These guards are idempotent, so you can re-run them when you reinstall SDK bits or wipe the image.

```bash
make android-emulator-install   # installs emulator, platform-tools, and API 34 image into $ANDROID_SDK_ROOT
make android-emulator-avd       # creates the MessiePixel6Api34 virtual device
make android-emulator-run       # boots the emulator and starts the adb daemon
```

For a one-liner, `make android-emulator` chains the three targets above. Export `ANDROID_SDK_ROOT` and `JAVA_HOME` (see repository README) before invoking the commands so Gradle and the CLI tools resolve the correct SDK.

## Commands

```bash
# Sync web assets and build the debug APK
npm run test:native-smoke

# (Optional) Launch the emulator smoke loop once instrumentation lands
# ./android/gradlew app:connectedDebugAndroidTest
```

The smoke script performs a Capacitor sync and runs `./gradlew
app:assembleDebug`, exercising the Kotlin plugin wiring (`MatrixNativePlugin`),
Coroutines usage, and the Rust SDK dependency graph. Failures here typically
point to missing native bindings or Gradle configuration regressions.

## Release Checklist Additions

1. Run `npm run test:native-smoke` from `frontend/` and ensure the build
   completes without errors.
2. Deploy the generated APK to an emulator/device and manually verify login,
   timeline sync, and message send while observing logcat for native runtime
   errors.
3. Capture the active runtime telemetry (console logs show the selected
   flavor) so we can confirm the native path is active.
4. If fallbacks occur, rerun the JS path (`npm run dev`) to ensure web remains
   healthy before release.

Document any native-specific issues in the release notes so QA understands the
coverage delta between native and web paths.
