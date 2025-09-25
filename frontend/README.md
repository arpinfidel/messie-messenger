# Messie Messenger Frontend

## Frontend Features (moved from root README)

- Matrix-first messaging – A dedicated Matrix view model handles session restoration, client bootstrapping, crypto, notifications, room timelines, and read receipts, exposing data as timeline items consumed by the UI.
- Email aggregation without OAuth – Users provide IMAP host, port, and app password from the Email settings tab to fetch headers; the backend signs in via TLS and exposes aggregate thread listings and detailed headers.
- Todo lists and items – Authenticated users can create, read, update, and delete lists and items; fractional indexing keeps ordering stable and todos surface in the shared timeline.
- Unified timeline & detail panes – Items from Matrix, Email, and Todo modules appear in a unified timeline with a responsive two-pane layout and contextual settings.
- Cloud-auth bridge for JWT issuance – Exchanges a Matrix OpenID token for a backend JWT and persists it for authenticated API calls.

For architectural context on how these modules collaborate, see `docs/architecture.md` and the module breakdown in `docs/frontend.md`.

## Generating the API Client

To interact with the backend API, you need to generate the TypeScript client code. This client is generated using `openapi-generator-cli` from the OpenAPI specification.

### Prerequisites

- **Java Development Kit (JDK)**: `openapi-generator-cli` requires Java to run. Ensure you have a JDK installed (version 8 or higher is recommended). You can download it from [Oracle](https://www.oracle.com/java/technologies/downloads/) or use OpenJDK.

### Installation

If you don't have `openapi-generator-cli` installed globally, you can install it using npm:

```bash
npm install -g @openapitools/openapi-generator-cli
```

### Generating the Client

Once `openapi-generator-cli` is installed, navigate to the `frontend` directory and run the following command to generate the client:

```bash
openapi-generator-cli generate -i ../docs/openapi.yaml -g typescript-fetch -o src/api/generated
```

This command will:

- Read the OpenAPI specification from `../docs/openapi.yaml`.
- Generate a TypeScript client using the `typescript-fetch` generator.
- Output the generated code into the `src/api/generated` directory.

Alternatively, from the repository root you can use the Makefile targets:

```bash
make gen-fe   # regenerate frontend client
make gen      # backend + frontend
```

## End-to-end testing

The frontend uses [Playwright](https://playwright.dev/) for browser-based end-to-end tests. To run the suite locally:

1. Install the project dependencies (`npm install`).
2. Install the Playwright browsers once per machine: `npx playwright install --with-deps`.
3. Execute the tests with `npm run test:e2e`.

Additional scripts are available for headed runs (`npm run test:e2e:headed`) and the Playwright UI mode (`npm run test:e2e:ui`).

### Multi-user flows

Record signed-in states for each Matrix account you want to exercise by saving storage per user:

```bash
cd frontend
npm run test:e2e:codegen -- --save-storage=tests/e2e/.auth/user-a.json
npm run test:e2e:codegen -- --save-storage=tests/e2e/.auth/user-b.json
```

Playwright launches a fresh browser context each run, so you can authenticate as separate users and close the window once the script writes the storage file. Use those fixtures inside tests to orchestrate parallel sessions:

```ts
test('DM handoff', async ({ browser }) => {
  const userA = await browser.newContext({ storageState: 'tests/e2e/.auth/user-a.json' });
  const userB = await browser.newContext({ storageState: 'tests/e2e/.auth/user-b.json' });
  // ...exercise the conversation across both pages...
});
```

For live debugging, run two recorder sessions in separate terminals—each launches an isolated incognito context.

## Mobile wrapper

The Svelte frontend ships with a Capacitor configuration so you can build native wrappers for Android and iOS. Install the frontend dependencies if you have not already (`cd frontend && npm install`), then run the add command for each platform you care about (requires the Android SDK or Xcode command-line tools):

```bash
cd frontend
npm run mobile:add:android   # one-time platform scaffold
npm run mobile:add:ios       # optional iOS scaffold
```

After adding a platform, rebuild the web assets and sync them into the native project anytime the Svelte app changes:

```bash
make mobile-sync
```

Generate native launcher icons and splash assets from the shared logo (`frontend/public/messie-logo.svg`) whenever the artwork changes:

```bash
make mobile-assets
```

The script copies the shared SVG into a temporary `frontend/assets/` directory so the Capacitor Assets CLI can transform it for Android and iOS, then cleans up after it finishes.

Run the native project directly from the CLI (Capacitor prompts you to pick a connected device or emulator):

```bash
make mobile-run-android
make mobile-run-ios
```

Open the native project in its IDE once assets are synced if you still want an editor experience:

```bash
make mobile-open-android
make mobile-open-ios
```

`make mobile-sync` wraps `npm run mobile:sync`, which performs `vite build` followed by `npx cap sync`. You can also call the npm scripts directly from the `frontend` directory if you prefer.

### Build Android APK via CLI

Prerequisites (macOS example):

```bash
brew install --cask android-commandlinetools
mkdir -p "$HOME/Library/Android/sdk/cmdline-tools/latest"
cp -R /opt/homebrew/share/android-commandlinetools/* \
  "$HOME/Library/Android/sdk/cmdline-tools/latest/"

echo 'export ANDROID_HOME="$HOME/Library/Android/sdk"' >> ~/.zshrc
echo 'export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"' >> ~/.zshrc
echo 'export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"' >> ~/.zshrc
brew install --cask temurin@17
echo 'export JAVA_HOME=$(/usr/libexec/java_home -v 17)' >> ~/.zshrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Adjust the paths if you are on Intel Homebrew or unpacked Google’s ZIP manually. Confirm `sdkmanager` works (`sdkmanager --list`) before continuing. If `echo $ANDROID_SDK_ROOT` prints nothing after reloading your shell, export it manually in the current session:

```bash
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
```

1. Install the Android SDK command-line tools, ensure `sdkmanager` is on your `PATH`, and accept licenses (the app currently targets `compileSdkVersion = 34`, see `frontend/android/variables.gradle`). Run each command individually so environment changes take effect:

   ```bash
   sdkmanager --install "platforms;android-34" "build-tools;34.0.0"
   # optional: pre-install newer APIs you plan to use
   sdkmanager --install "platforms;android-35" "build-tools;35.0.0"
   yes | sdkmanager --licenses --sdk_root="$ANDROID_SDK_ROOT"
   ls "$ANDROID_SDK_ROOT/licenses"
   ```

   Make sure `JAVA_HOME` points to Java 17 or newer.
2. Install frontend dependencies and add the Android platform if you have not already (the Capacitor CLI is installed here; skipping `npm install` triggers `npm error could not determine executable to run` when you add the platform):

   ```bash
   cd frontend
   npm install
   npm run mobile:add:android
   ```

3. Build web assets and sync them into the native project:

   ```bash
   npm run mobile:sync
   ```

### Build iOS App via CLI

1. Add the iOS platform (if you did not earlier) and sync assets:

   ```bash
   cd frontend
   npm install
   npm run mobile:add:ios
   cd ..
   make mobile-sync
   ```

2. Build for the simulator (no signing required):

   ```bash
   cd frontend/ios/App
   xcodebuild -scheme App -configuration Debug -sdk iphonesimulator build
   ```

   The `.app` bundle lands in `frontend/ios/App/build/Build/Products/Debug-iphonesimulator/App.app` and can be installed with `xcrun simctl`.
3. Build an archive and export an IPA (requires signing assets and an `exportOptions.plist`):

   ```bash
   xcodebuild -scheme App -configuration Release -sdk iphoneos -archivePath build/App.xcarchive archive
   xcodebuild -exportArchive -archivePath build/App.xcarchive \
     -exportOptionsPlist exportOptions.plist -exportPath build/export
   ```

   The IPA lands in `frontend/ios/App/build/export/`.
