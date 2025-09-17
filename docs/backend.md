Backend Guide (Draft)
=====================

Purpose
-------

Working notes for the Go backend service. Flesh out details as implementation stabilizes.

Service Overview
----------------

- Entrypoint: `backend/main.go`
- Runtime: Go + Chi router, GORM for persistence, JWT auth middleware
- Dependencies: PostgreSQL, external IMAP servers, Matrix federation for OpenID verification

Key Modules (to document)
------------------------

- `internal/user`: Registration, Matrix OpenID bridge, JWT issuance
- `internal/todo`: Todo list/item use cases and repositories
- `internal/email`: IMAP proxy handlers (login test, headers, threads)
- `pkg/middleware`: Auth middleware and context keys

Operational Notes
-----------------

- Environment vars: `DATABASE_URL`, `JWT_SECRET`, `PORT`
- Initialization: auto-migrates GORM models on startup (no SQL migrations checked in)
- Generated code: `api/generated/todo_api.go` from `docs/openapi.yaml`

Testing & Tooling
-----------------

- TODO: Document go test suites, linting, and test data strategy.

Future Additions
----------------

- Document SSE/email streaming implementation once built
- Capture observability stack (metrics, structured logging)
- Add deployment guidance (Docker images, Compose targets, CI/CD)

