# Messie Messenger

Messie Messenger is a multi-channel productivity hub that combines Matrix chat, IMAP email, and collaborative todos inside a single workspace.

## Vision

Use Matrix bridges as the backbone to connect commonly used messengers, and complement it with email, collaborative notes/todos, and calendar for daily work.

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
   ```

The YAML file defaults to `jira-tasks.yaml` at the repo root and is ignored by Git.

Each YAML issue supports optional fields such as `labels`, `priority` (matching Jira priority names), `parent` (linking sub-tasks to an existing issue key—Jira only accepts parents for sub-task issue types), and `delete: true` to permanently remove an existing Jira issue on the next push.

### Usage

Run the helper from within the backend module:

```bash
cd backend
go run ./cmd/jira-sync pull   # fetch issues into the YAML file (written at repo root)
# edit ../jira-tasks.yaml locally, add or tweak issues
go run ./cmd/jira-sync push   # push updates/new issues back to Jira
```

After a push completes, the tool automatically refreshes the YAML file from Jira so that newly created issues pick up their generated keys and status.

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
