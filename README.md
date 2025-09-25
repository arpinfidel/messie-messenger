<p align="center">
  <img src="frontend/public/messie-logo.svg" alt="Messie Messenger logo" width="160">
</p>

<h1 align="center">Messie Messenger</h1>

Messie Messenger is a multi-channel productivity hub that combines Matrix chat, IMAP email, and collaborative todos inside a single workspace.

## Vision

Use Matrix bridges as the backbone to connect commonly used messengers, and complement it with email, collaborative notes/todos, and calendar for daily work.

Unifying those channels gives future Messie AI assistants a trusted knowledge source, since they can reference the full history of chats, emails, and todo context when offering guidance.

## Seamless Bridge Integrations

Bridge connections should feel invisible to teammates. We are investing in polished authentication flows, consistent room metadata, and shared settings so bridged services behave like first-class citizens across chat, email, and timeline surfaces.

## Stack Overview

- Frontend: Svelte + Vite + Tailwind, with Matrix via `matrix-js-sdk`. See `frontend/README.md`.
- Backend: Go (Chi) with PostgreSQL and OpenAPI-defined endpoints. See `backend/README.md`.
- API Gateway: nginx proxy for `/api` and SPA.
- Orchestration: Docker Compose for dev and prod topologies.

## Core Features

- Messaging via Matrix
- Email viewing via IMAP
- Collaborative todo lists

Note: This section intentionally stays non-technical. Detailed UI behavior and timeline/cloud auth notes live in the frontend README and future docs.

## Getting Started

### Prerequisites for Development

- **Docker Desktop + Compose v2** – required for the default `make up` workflow.
- **Go 1.24.6 toolchain** – install the official release from go.dev or your OS package manager so local builds match our Docker images.
- **Node.js 20.x + npm** – aligns with the `node:20-alpine` images and Vite dev server.
- **Java 11+** – needed by `openapi-generator-cli` when regenerating API clients.
- **Matrix account** – any homeserver works; needed to exercise the Matrix module once the app is running.

### Initial Setup

1. Clone the repository and move into the project root.
2. Copy environment defaults: `cp .env.example .env`, then edit values as needed for your machine.
3. Install frontend dependencies (outside Docker) if you intend to run Vite locally:

   ```bash
   cd frontend
   npm install
   ```

4. Ensure your Go environment is using the 1.24.6 toolchain and download modules:

   ```bash
   cd backend
   go mod download
   ```

   If you manage multiple Go versions, make sure `go version` reports 1.24.6 before running the command.

### Quick start with Docker Compose (Recommended)

1. Install Docker and Docker Compose (v2).
2. Start the full stack (Postgres, backend, frontend, nginx) using `make up`. This is the preferred way to develop—containers keep dependencies aligned across machines:

   ```bash
   make up
   ```

   Use `STACK=prod` for the production topology, for example: `STACK=prod make up`.
3. Visit `http://localhost:8080` to access the app through nginx. The backend API is at `/api/v1`.
4. Stop services:

   ```bash
   make down
   ```

Useful helpers: `make logs`, `make ps`, `make sh backend`.

### GitHub Codespaces

- Open the repo in Codespaces; the workspace attaches to the `devcontainer` service defined in `.devcontainer/devcontainer.json`.
- The devcontainer uses `docker-compose.dev.yml` and automatically launches Postgres, backend, frontend, and nginx via Docker Compose.
- Port forwarding for `8080`, `5173`, and `5432` is preconfigured; Codespaces will prompt you to open the web UI when the stack is ready.
- The first boot runs `go mod download` and `npm install` inside the container. To rebuild later, use `docker compose -f docker-compose.dev.yml up --build` from `/workspace`.

### Running services manually (optional)

Backend (Go):

```bash
export DATABASE_URL="postgres://user:password@localhost:5432/todo_db?sslmode=disable"
export JWT_SECRET="your-secret"
export PORT=8080
cd backend
go run .
```

Frontend (Svelte):

```bash
cd frontend
npm install
npm run dev -- --host
```

### Mobile wrapper (Capacitor)

The Svelte frontend ships with a Capacitor configuration so you can build native wrappers for Android and iOS. Install the fro
ntend dependencies if you have not already (`cd frontend && npm install`), then run the add command for each platform you care
 about (requires the Android SDK command-line tools or Xcode command-line tools):

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

Run the native project directly from the CLI (Capacitor will prompt you to pick a connected device or emulator):

```bash
make mobile-run-android
make mobile-run-ios
```

Open the native project in its IDE once assets are synced if you still want an editor experience:

```bash
make mobile-open-android
make mobile-open-ios
```

`make mobile-sync` wraps `npm run mobile:sync`, which performs `vite build` followed by `npx cap sync`. You can also call the N
PM scripts directly from the `frontend` directory if you prefer.

#### Build Android APK via CLI

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

Adjust the paths if you are on Intel Homebrew or you unpacked Google’s ZIP manually. Confirm `sdkmanager` works (`sdkmanager --list`) before continuing. If `echo $ANDROID_SDK_ROOT` prints nothing after reloading your shell, export it manually in the current session:

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
   cd ..
   make mobile-sync
   ```

4. Build a debug APK with Gradle:

   ```bash
   cd frontend/android
   ./gradlew assembleDebug
   ```

   The package appears at `frontend/android/app/build/outputs/apk/debug/app-debug.apk`. If Gradle reports missing SDK components or licenses, install the requested versions with `sdkmanager` (then rerun `sdkmanager --licenses`). For a release build, configure signing in `android/app/build.gradle` and run `./gradlew assembleRelease`.

#### Build iOS Archive/IPA via CLI

1. Install the Xcode Command Line Tools (`xcode-select --install`) and ensure you have a signing identity plus provisioning profile for device or release builds.
2. Prepare the Capacitor project (run `npm install` first so the local Capacitor CLI is available):

   ```bash
   cd frontend
   npm install
   npm run mobile:add:ios
   cd ..
   make mobile-sync
   ```

3. Build for the simulator (no signing required):

   ```bash
   cd frontend/ios/App
   xcodebuild -scheme App -configuration Debug -sdk iphonesimulator build
   ```

   The `.app` bundle lives at `frontend/ios/App/build/Build/Products/Debug-iphonesimulator/App.app` and can be installed with `xcrun simctl`.
4. Build an archive and export an IPA (requires signing assets and an `exportOptions.plist`):

   ```bash
   xcodebuild -scheme App -configuration Release -sdk iphoneos -archivePath build/App.xcarchive archive
   xcodebuild -exportArchive -archivePath build/App.xcarchive \
     -exportOptionsPlist exportOptions.plist -exportPath build/export
   ```

   The IPA lands in `frontend/ios/App/build/export/`.

### Matrix Account

You need a Matrix account to sign in for messaging. Register on any homeserver (e.g., your own or a public one), then log in from the Matrix settings screen inside the app.

### Day-to-Day Development Flow

- Use `make up`/`make down` to manage the full stack in Docker, or run the backend and frontend manually as shown above.
- Regenerate OpenAPI clients whenever you touch `docs/openapi.yaml` (see **API and Code Generation** below) so both the Go server and TypeScript client stay in sync.
- The repo does not ship automated tests yet; plan on manual verification for now.

## Operations

### .env and Compose

Compose now supports a root `.env` for configuration. To get started:

```bash
cp .env.example .env
# edit .env to adjust ports, DB credentials, secrets
```

Key variables: `NGINX_PORT`, `FRONTEND_PORT`, `BACKEND_PORT`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `JWT_SECRET`, `VITE_API_BASE_URL`.

Frontend is dockerized in dev; in prod the SPA is built and served by nginx.

### Common commands

```bash
make up           # start stack
make down         # stop stack
make logs         # tail all logs (add service name to scope)
make sh backend   # shell into a service container
make gen          # regenerate API stubs/clients
```

## Jira task sync utility

The repository ships with a small Go program that mirrors Jira issues into a local YAML file so you can iterate on them offline (for example with Codex) and then push the results back to Jira.

### Configuration

1. Copy `.env.example` to `.env` if you have not already done so.
2. Populate the Jira-related variables:

   ```bash
   JIRA_BASE_URL=https://your-domain.atlassian.net
   JIRA_EMAIL=your-email@example.com
   JIRA_API_TOKEN=your-api-token
   JIRA_PROJECT_KEY=PROJ
   JIRA_DEFAULT_ISSUE_TYPE=Task
   # Optional overrides:
   # JIRA_JQL=project = PROJ ORDER BY created DESC
   # JIRA_YAML_PATH=jira-tasks.yaml   # relative paths resolve from the repo root
   # JIRA_MAX_RESULTS=50
   # JIRA_PUSH_WORKERS=4              # number of concurrent push workers
   ```

The YAML file defaults to `jira-tasks.yaml` at the repo root and is ignored by Git.

Each YAML issue supports optional fields such as `labels`, `priority` (matching Jira priority names), `parent` (linking sub-tasks to an existing issue key—Jira only accepts parents for sub-task issue types), and `delete: true` to permanently remove an existing Jira issue on the next push. If you explicitly need to change an issue's type during an update, set `forceIssueType: true`; otherwise the sync preserves the existing Jira type to avoid API validation errors.

### Usage

Run the helper from within the backend module:

```bash
cd backend
go run ./cmd/jira-sync pull   # fetch issues into the YAML file (written at repo root)
# edit ../jira-tasks.yaml locally, add or tweak issues
go run ./cmd/jira-sync push   # push updates/new issues back to Jira
```

Pushes run concurrently (default 4 workers) so large batches finish faster; adjust `JIRA_PUSH_WORKERS` if you need to throttle or speed up the sync. After a push completes, the tool automatically refreshes the YAML file from Jira so that newly created issues pick up their generated keys and status.

You can also strike issues by setting `delete: true` on a YAML entry (with a valid `key`). During the next push the tool deletes the issue in Jira and drops it from the YAML file before re-syncing.

Convenience targets are available from the repo root:

```bash
make jira-pull
make jira-push
```

## API and Code Generation

Regenerate server and client stubs with:

```bash
make gen          # runs both targets
make gen-be       # Go chi server stubs
make gen-fe       # TypeScript fetch client (prettified)
```

See `frontend/README.md` for standalone client generation notes.

## Project Layout

```txt
backend/        Go service and generated API handlers
frontend/       Svelte application with view models and generated client
api-gateway/    nginx configurations and Dockerfiles for dev/prod proxies
docs/           Shared OpenAPI specification and supporting documentation
```

Additional assets such as the implementation roadmap (`plan.md`) and supporting docs can be found alongside the source tree.

## Further Reading

- Architecture: `docs/architecture.md`
- ADR 0001 – Fractional Indexing for Todos: `docs/adrs/0001-fractional-indexing.md`
- ADR 0002 – Thin Web IMAP Client (backend proxy first): `docs/adrs/0002-thin-web-imap-client.md`
- ADR 0003 – Matrix OpenID → Backend JWT Bridge: `docs/adrs/0003-matrix-cloud-auth.md`
- Backend implementation notes (draft): `docs/backend.md`
- Frontend implementation notes (draft): `docs/frontend.md`
- Roadmap index: `docs/roadmap/README.md`
