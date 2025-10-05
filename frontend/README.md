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

## Mobile

The Capacitor-based mobile wrappers are deprecated. Use the native Flutter app in `app/`:

```bash
# One-time (if codegen needed)
make bridge-generate

# Build Rust FFI for your platform as needed
make bridge-build-android   # Android .so into app/android
make bridge-build-ios       # iOS/macOS libraries

# Run the Flutter app
cd app
flutter pub get
flutter run                 # or: flutter run -d android / -d ios
```

The web frontend continues to run via Vite/Node or Docker as documented above.
3. Build an archive and export an IPA (requires signing assets and an `exportOptions.plist`):

   ```bash
   xcodebuild -scheme App -configuration Release -sdk iphoneos -archivePath build/App.xcarchive archive
   xcodebuild -exportArchive -archivePath build/App.xcarchive \
     -exportOptionsPlist exportOptions.plist -exportPath build/export
   ```

   The IPA lands in `frontend/ios/App/build/export/`.
