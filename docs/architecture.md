Architecture Overview
=====================

Components
----------

- Frontend: Svelte + Vite + Tailwind, Matrix via `matrix-js-sdk`, generated OpenAPI client.
- Backend: Go (Chi), PostgreSQL, OpenAPI-defined endpoints for auth, todos, and IMAP helpers.
- API Gateway: nginx proxy for `/api` and static SPA in prod; proxies Vite in dev.
- External services: Matrix homeserver (user-provided); IMAP servers (user accounts).

Data Flow
---------

- UI calls REST endpoints via the gateway: `/api/v1/*` → backend.
- Matrix flows directly from client to homeserver using `matrix-js-sdk`.
- Email: Web uses backend IMAP proxy for now (see RFC 0002). Native will speak IMAP directly.

Auth Model
----------

- Users log in to Matrix in the client.
- Client can exchange Matrix OpenID for a backend JWT to call protected endpoints.
- Backend uses JWT for todo APIs and email helper access control.

Environments
------------

- Dev: `docker-compose.dev.yml` runs postgres, backend, frontend, nginx; Vite serves the SPA.
- Prod: `docker-compose.prod.yml` runs postgres, backend, nginx; nginx serves built SPA.
- Configuration: root `.env` drives ports, DB, and secrets.
