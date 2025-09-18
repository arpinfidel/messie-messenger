# ADR 0002: Thin Web IMAP Client (Proxy First)

Summary
-------

Ship email in the web app by temporarily proxying IMAP via the backend, while designing a client-heavy interface that can be reused by a future native implementation with direct IMAP.

Context
-------

Browsers cannot open raw TCP sockets to IMAP servers. Until we wrap the app as a native shell (Electron/Tauri/Capacitor) and implement a proper IMAP client, the backend will proxy IMAP calls.

Proposal
--------

- Keep the UI/data model client-centric: the frontend orchestrates sessions, accounts, and threading heuristics.
- Backend exposes minimal, stateless IMAP helper endpoints (login test, list headers, fetch message, etc.).
- The shape of these endpoints mirrors the intended native client APIs so the UI code remains largely unchanged when switching to native IMAP.
- Gate the email feature with a runtime feature flag; disable it on web-only builds if needed.

API Surface (proxy phase)
-------------------------

- POST `/api/v1/email/login-test` — Validate IMAP credentials (host, port, username, app password) over TLS.
- POST `/api/v1/email/inbox` — Return recent inbox headers plus unread counts.
- POST `/api/v1/email/important` — Return flagged/important headers plus unread counts.
- POST `/api/v1/email/headers` — Temporary rich-header proxy (threading hints, references) consumed by the web client. Not yet part of the OpenAPI contract.

Security & Privacy
------------------

- Credentials are used only to perform the requested operation; do not store secrets server-side beyond the request.
- Enforce TLS to upstream IMAP; prefer app passwords where providers support them.
- Rate-limit helper endpoints and redact sensitive fields from logs.

Migration to Native
-------------------

- Replace backend proxy calls with a thin local IMAP client (Node/Tauri runtime APIs) behind a matching interface.
- Keep threading and presentation logic in the frontend to minimize churn.

Feature Flagging
----------------

- Introduce `EMAIL_ENABLED` (and optionally `EMAIL_PROVIDER` mode: `proxy|native`).
- Default to `proxy` for web, `native` for packaged apps when implemented; allow override via config.

Implementation Status
---------------------

- Endpoints and methods: Backend exposes POST endpoints that accept credentials in the JSON body. Generated handlers cover `/api/v1/email/login-test`, `/api/v1/email/inbox`, and `/api/v1/email/important`; a handwritten `/api/v1/email/headers` route returns richer threading metadata for the web client. The OpenAPI spec still omits `/email/headers` and the thread messages endpoint—keep them in sync by extending the spec or deprecating the custom route once a replacement exists.
- Frontend usage: `ProxyEmailAdapter` posts credentials to the `/api/v1/email/*` proxy endpoints, normalises network and parsing errors, and performs client-side grouping/threading. It ignores `/email/threads` (which now responds 410) and fetches bulk headers without pagination.
- Single-message fetch: No `GET /email/message/{id}` (or POST equivalent) is implemented yet.
- Feature flag: `EMAIL_ENABLED` / `EMAIL_PROVIDER` not wired; email is always available in web builds.
- Pagination: Backend supports cursors for thread listings; frontend presently fetches bulk headers and groups locally, not using cursors.
- Security posture: TLS is enforced to IMAP via `DialTLS`; credentials are not persisted. Rate limiting and explicit log redaction policy are not implemented and should be added when exposing these endpoints publicly.

Open Questions
--------------

- Caching strategy for headers and bodies across proxy/native modes.
- Attachment handling and size limits.
- Mapping server-specific flags and folders to a consistent UI model.
