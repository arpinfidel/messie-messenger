<p align="center">
  <img src="frontend/public/messie-logo.svg" alt="Messie Messenger logo" width="160">
</p>

<h1 align="center">Messie Messenger</h1>

Messie Messenger is a multi-channel productivity hub that combines Matrix chat, IMAP email, and collaborative todos inside a single workspace.

## Contents

- [Contents](#contents)
- [Overview](#overview)
  - [Vision](#vision)
  - [Focus Areas](#focus-areas)
  - [Core Capabilities](#core-capabilities)
- [Architecture](#architecture)
- [Development Setup](#development-setup)
  - [Prerequisites](#prerequisites)
  - [Project Bootstrap](#project-bootstrap)
  - [Docker Compose Workflow](#docker-compose-workflow)
  - [Manual Service Runs](#manual-service-runs)
  - [GitHub Codespaces](#github-codespaces)
  - [Flutter + Rust Mobile Stack](#flutter--rust-mobile-stack)
- [Testing \& QA](#testing--qa)
  - [Playwright End-to-End Suite](#playwright-end-to-end-suite)
  - [Local Matrix Homeserver](#local-matrix-homeserver)
- [Operations \& Tooling](#operations--tooling)
  - [Environment Configuration](#environment-configuration)
  - [Common Commands](#common-commands)
  - [Day-to-Day Development Flow](#day-to-day-development-flow)
- [Jira Task Sync Utility](#jira-task-sync-utility)
  - [Configuration](#configuration)
  - [Usage](#usage)
- [API and Code Generation](#api-and-code-generation)
- [Project Layout](#project-layout)
- [Further Reading](#further-reading)

## Overview

### Vision

Use Matrix bridges as the backbone to connect commonly used messengers, and complement it with email, collaborative notes/todos, and calendar for daily work. Unifying those channels gives future Messie AI assistants a trusted knowledge source, since they can reference the full history of chats, emails, and todo context when offering guidance.

### Focus Areas

Bridge connections should feel invisible to teammates. We invest in polished authentication flows, consistent room metadata, and shared settings so bridged services behave like first-class citizens across chat, email, and timeline surfaces.

### Core Capabilities

- Messaging via Matrix
- Email viewing via IMAP
- Collaborative todo lists

This section intentionally stays non-technical. Detailed UI behavior and timeline/cloud auth notes live in the frontend README and future docs.

## Architecture

Messie Messenger spans a web frontend, a Go backend, a Flutter mobile/desktop client, and containerized infrastructure.

- **Frontend**: Svelte + Vite + Tailwind, with Matrix connectivity via `matrix-js-sdk`. See `frontend/README.md` for implementation notes.
- **Backend**: Go (Chi) with PostgreSQL and OpenAPI-defined endpoints. See `backend/README.md`.
- **API Gateway**: nginx proxy for `/api` and the SPA.
- **Mobile/Desktop**: Flutter application backed by a shared Rust core exposed through `flutter_rust_bridge`.
- **Orchestration**: Docker Compose templates for development and production topologies.

## Development Setup

### Prerequisites

Install these before you begin local development:

- **Docker Desktop + Compose v2** — required for the default `make up` workflow.
- **Go 1.24.6 toolchain** — install from go.dev or your OS package manager so local builds match the Docker images.
- **Node.js 20.x + npm** — aligns with the `node:20-alpine` images and Vite dev server.
- **Java 11+** — needed by `openapi-generator-cli` when regenerating API clients.
- **Matrix account** — any homeserver works; required to exercise the Matrix module once the app is running.

### Project Bootstrap

1. Clone the repository and move into the project root.
2. Copy environment defaults: `cp .env.example .env`, then edit values as needed for your machine.
3. Install frontend dependencies (outside Docker) if you intend to run Vite locally:

   ```bash
   cd frontend
   npm install
   ```

4. Ensure your Go environment uses the 1.24.6 toolchain and download modules:

   ```bash
   cd backend
   go mod download
   ```

   If you manage multiple Go versions, confirm `go version` reports 1.24.6 before running the command.

### Docker Compose Workflow

1. Install Docker and Docker Compose (v2).
2. Start the full stack (Postgres, backend, frontend, nginx) with:

   ```bash
   make up
   ```

   Use `STACK=prod make up` for the production topology.
3. Visit `http://localhost:8080` to access the app through nginx. The backend API lives at `/api/v1`.
4. Stop services with `make down`.

Helpful commands: `make logs`, `make ps`, `make sh backend`.

### Manual Service Runs

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

### GitHub Codespaces

- Open the repo in Codespaces; the workspace attaches to the `devcontainer` service defined in `.devcontainer/devcontainer.json`.
- The devcontainer uses `docker-compose.dev.yml` and automatically launches Postgres, backend, frontend, and nginx.
- Port forwarding for `8080`, `5173`, and `5432` is preconfigured; Codespaces prompts you to open the web UI when the stack is ready.
- The first boot runs `go mod download` and `npm install`. To rebuild later, use `docker compose -f docker-compose.dev.yml up --build` from `/workspace`.

### Flutter + Rust Mobile Stack

The native client lives under `app/` with its shared Rust core inside `core/`.

1. Install the Flutter SDK (3.16+) and the stable Rust toolchain. If you need
   the platform scaffolds (Android, iOS, desktop), run
   `flutter create --platforms=android,ios,macos,windows,linux .` from the `app/`
   directory once to let Flutter materialize them.
2. Generate flutter_rust_bridge bindings:

   ```bash
   # script
   ./bindings/generate.sh
   # or Make target
   make bridge-generate
   ```

3. Build the Rust crates for your platform as needed:
   - Host (for headless tests): `make flutter-bridge-build-lib`
   - Android: `./bindings/android/build.sh` or `make bridge-build-android`
   - iOS/macOS: `./bindings/ios/build.sh` or `make bridge-build-ios`

4. Run the Flutter app:

   ```bash
   cd app
   flutter pub get
   flutter run
   ```

The initial screen calls the Rust `ping()` function and renders the returned string to verify the bridge.

## Testing & QA

### Playwright End-to-End Suite

The Playwright suite lives in `frontend/tests/e2e`. Start the SPA first (`make up` or `cd frontend && npm run dev -- --host 127.0.0.1 --port 4173`) so the tests and recorder can hit a live UI.

- Run the headless smoke suite: `cd frontend && npm run test:e2e` (pass `--project` to narrow browsers).
- Launch the recorder from the repo root with `make test-e2e-codegen`, which opens Playwright Codegen against `http://127.0.0.1:4173/`.
- Override the target URL by appending it: `npm run test:e2e:codegen -- http://localhost:5173/`.

Multi-user storage guidance and recorder workflows live in `frontend/README.md`.

### Local Matrix Homeserver

An opt-in Synapse service (profile `matrix`) exposes the unstable Simplified Sliding Sync endpoint without any proxy. Quick start:

- `make matrix-init` generates config and pins the shared secret.
- `make matrix-up matrix` boots Synapse `v1.114.0`.
- `make matrix-seed` (or `make matrix-setup` / `./scripts/matrix/setup.sh`) seeds 400 encrypted rooms/messages.
- `make matrix-cleanup` (or `./scripts/matrix/cleanup.sh`) stops containers and clears the Matrix data/state.

Full walkthrough—including Flutter bridge tests—is in `docs/local-matrix.md`.

### Headless bridge integration test

Run the Flutter <-> Rust bridge test without an emulator. A Make target builds
the Rust FFI for your host and runs the headless test in `app/`.

Quick start (after seeding Synapse):

```bash
make flutter-bridge-test
```

The Make target:
- Builds `core` in release if needed.
- Sets `MESSIE_FFI_LIB_PATH` to the built library.
- Runs `flutter test test/bridge/sliding_sync_bridge_test.dart` in `app/`.

Environment overrides (optional):
- `MESSIE_MATRIX_HOMESERVER` (default `http://127.0.0.1:8008`)
- `MESSIE_MATRIX_USERNAME` / `MESSIE_MATRIX_PASSWORD`
- `MESSIE_BRIDGE_STORE_PATH` (where the test stores state)
- `MESSIE_MATRIX_RECOVERY_KEY` or `MESSIE_MATRIX_RECOVERY_FILE`
  - The test auto-detects `scripts/matrix/.state/recovery_key.json` produced by `make matrix-seed`. You only need to set this if you keep state elsewhere.
- `MESSIE_SEEDED_ROOM_COUNT` or `MESSIE_SEED_STATE_FILE` (optional)
  - By default, the test reads `scripts/matrix/.state/seed_state.json` and asserts the exact number of seeded rooms. Set these to override in custom setups.

Example with overrides:

```bash
MESSIE_MATRIX_HOMESERVER=http://localhost:8008 \
MESSIE_BRIDGE_STORE_PATH=$PWD/app/build/matrix-store \
make flutter-bridge-test
```

## Operations & Tooling

### Environment Configuration

Compose supports a root `.env` for configuration. To get started:

```bash
cp .env.example .env
# edit .env to adjust ports, DB credentials, secrets
```

Key variables: `NGINX_PORT`, `FRONTEND_PORT`, `BACKEND_PORT`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `JWT_SECRET`, `VITE_API_BASE_URL`.

Mobile wrappers reuse the same values and fall back to `.env.mobile` (tracked) for deterministic build metadata such as `MATRIX_RUST_SDK_ANDROID_VERSION`.

The frontend runs inside Docker in dev; in prod the SPA is built and served by nginx.

### Common Commands

```bash
make up           # start stack
make down         # stop stack
make logs         # tail all logs (add service name to scope)
make sh backend   # shell into a service container
make gen          # regenerate API stubs/clients
```

### Day-to-Day Development Flow

- Use `make up`/`make down` to manage the full stack in Docker, or run the backend and frontend manually as shown above.
- Regenerate OpenAPI clients whenever you touch `docs/openapi.yaml` (see **API and Code Generation**) so both the Go server and TypeScript client stay in sync.
- Aside from the Playwright smoke tests, there are no automated regression suites yet—plan on manual verification for feature work.
- Capacitor build and packaging instructions live in `frontend/README.md#mobile-wrapper`.

## Jira Task Sync Utility

The repository ships with a small Go program that mirrors Jira issues into a local YAML file so you can iterate offline and push results back to Jira.

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

Each YAML issue supports optional fields such as `labels`, `priority` (matching Jira priority names), `parent` (linking sub-tasks to an existing issue key—Jira only accepts parents for sub-task issue types), and `delete: true` to remove an existing Jira issue on the next push. If you need to change an issue's type during an update, set `forceIssueType: true`; otherwise the sync preserves the existing Jira type to avoid API validation errors.

### Usage

Run the helper from within the backend module:

```bash
cd backend
go run ./cmd/jira-sync pull   # fetch issues into the YAML file (written at repo root)
# edit ../jira-tasks.yaml locally, add or tweak issues
go run ./cmd/jira-sync push   # push updates/new issues back to Jira
```

Pushes run concurrently (default 4 workers) so large batches finish faster; adjust `JIRA_PUSH_WORKERS` if you need to throttle or speed up the sync. After a push completes, the tool refreshes the YAML file from Jira so newly created issues pick up their generated keys and status.

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
app/            Flutter application scaffold
core/           Rust workspace shared by the Flutter app
bindings/       flutter_rust_bridge tooling and build scripts
api-gateway/    nginx configurations and Dockerfiles for dev/prod proxies
docs/           Shared OpenAPI specification and supporting documentation
```

Additional assets such as the implementation roadmap (`plan.md`) and supporting docs live alongside the source tree.

## Further Reading

- Architecture: `docs/architecture.md`
- ADR 0001 – Fractional Indexing for Todos: `docs/adrs/0001-fractional-indexing.md`
- ADR 0002 – Thin Web IMAP Client (backend proxy first): `docs/adrs/0002-thin-web-imap-client.md`
- ADR 0003 – Matrix OpenID → Backend JWT Bridge: `docs/adrs/0003-matrix-cloud-auth.md`
- Backend implementation notes (draft): `docs/backend.md`
- Frontend implementation notes (draft): `docs/frontend.md`
- Local Matrix setup: `docs/local-matrix.md`
- Roadmap index: `docs/roadmap/README.md`
