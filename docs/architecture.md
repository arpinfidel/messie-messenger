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
- Email: Web uses backend IMAP proxy for now (see ADR 0002: `docs/adrs/0002-thin-web-imap-client.md`). Native will speak IMAP directly.

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

Unified Timeline Composition
----------------------------

The UI stitches multiple domains (Matrix, Email, Todos) into a single timeline to avoid context switching. Each module exposes a Svelte store of timeline entries and implements `IModuleViewModel`.

- `UnifiedTimelineViewModel` instantiates the Matrix, Email, and Todo view models and aggregates their stores (frontend/src/viewmodels/shared/UnifiedTimelineViewModel.ts).
- Modules push their own `TimelineItem` representations (timestamped, typed records). The aggregator sorts these items on demand for the UI and relays loading-state updates.
- Matrix items stream directly from the SDK timeline services. Email items are client-generated summaries derived from proxy endpoints. Todo items represent lists and items returned by the REST API.

Matrix ↔ Backend Auth Bridge
-----------------------------

Matrix remains the primary identity. To access backend-protected features the client performs the OpenID bridge defined in ADR 0003 (`docs/adrs/0003-matrix-cloud-auth.md`):

1. Restore or prompt for a Matrix session via `matrix-js-sdk`.
2. Request an OpenID token (`matrixClient.getOpenIdToken()`).
3. POST the token to `/api/v1/auth/matrix/openid` where the backend verifies it against the homeserver and issues a JWT.
4. Persist `{ token, mxid, userId }` in local storage (`cloud_auth`) for subsequent REST calls.

The backend provisions users on demand by MXID, allowing non-Matrix features to share the same auth domain without password management.

Email Proxy Topology
--------------------

Until native shells can speak IMAP directly, the backend exposes helper endpoints that sign in with app passwords. The frontend currently uses `/api/v1/email/headers` (custom) for grouping and `/api/v1/email/thread/{threadKey}/messages` for detail views. Additional endpoints generated from OpenAPI (e.g. `/email/inbox`, `/email/important`) remain available for future UI integrations.

Future Roadmap (High Level)
---------------------------

- **Realtime updates**: Replace polling with SSE/Matrix bridging so todos and email badges update live.
- **Thread-aware spec alignment**: Update OpenAPI to reflect thread previews and custom endpoints, then regenerate clients.
- **Native clients**: Share Matrix auth bridge and email threading logic with desktop/mobile shells.
- **Feature flags**: Gate email modules behind config (e.g. `EMAIL_ENABLED`, `EMAIL_PROVIDER`) to support environments without IMAP access.
- **Token refresh UX**: Surface JWT expiry in the UI and automate re-authentication using the Matrix bridge.
- Detailed module plans live in `docs/roadmap/README.md`; keep roadmap bullets in sync.
