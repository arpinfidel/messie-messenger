RFC 0002: Thin Web IMAP Client (Proxy First)
===========================================

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
------------------------

- POST `/email/login` — Validate IMAP credentials (host, port, username, app password) over TLS.
- GET `/email/headers` — Paginated message headers for a mailbox (e.g., INBOX, Flagged).
- GET `/email/message/{id}` — Fetch specific message parts/metadata as needed.

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

- Endpoints and methods: Current backend exposes POST endpoints that accept credentials in the JSON body. Implemented routes include `/email/headers` and `/email/thread/{threadKey}/messages` (mounted in the router). The OpenAPI spec currently defines `/email/login-test`, `/email/inbox`, `/email/important`, and `/email/threads`, but does not include `/email/headers` or the thread messages route. Align spec and implementation (either add these routes to OpenAPI or switch the frontend to the spec’d endpoints). Given creds in the body, POST is appropriate.
- Frontend usage: The web client calls `/api/v1/email/headers` and performs client-side grouping/threading; it does not call `/email/threads` and currently ignores pagination.
- Single-message fetch: No `GET /email/message/{id}` (or POST equivalent) is implemented yet.
- Feature flag: `EMAIL_ENABLED` / `EMAIL_PROVIDER` not wired; email is always available in web builds.
- Pagination: Backend supports cursors for thread listings; frontend presently fetches bulk headers and groups locally, not using cursors.
- Security posture: TLS is enforced to IMAP via `DialTLS`; credentials are not persisted. Rate limiting and explicit log redaction policy are not implemented and should be added when exposing these endpoints publicly.

Open Questions
--------------

- Caching strategy for headers and bodies across proxy/native modes.
- Attachment handling and size limits.
- Mapping server-specific flags and folders to a consistent UI model.
