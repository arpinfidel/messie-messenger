# Messie Messenger

Messie Messenger is a multi-channel productivity hub that combines Matrix chat, IMAP email, and collaborative todos inside a single workspace.

## Vision

Use Matrix as the backbone to connect commonly used messengers, and complement it with email, collaborative notes/todos, and calendar for daily work.

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

### Quick start with Docker Compose

1. Install Docker and Docker Compose (v2).
2. Start the full stack (Postgres, backend, frontend, nginx):

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

### Running services manually

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
