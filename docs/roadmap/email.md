Email Roadmap (Draft)
=====================

Purpose
-------

Plan the path from the current IMAP-proxy MVP to a full-featured email experience that coexists with Matrix and Todo timelines.

Current Gaps
------------

- The three entry points (All Mail, Important, Threads) exist in code but lack a published contract and UX spec.
- Thread detail view does not define HTML sanitization rules, inline image treatment, or quoting behavior.
- No composer for replies/forwards; no strategy for sending email (SMTP bridge, Matrix bridge, etc.).
- Attachment handling, pagination, and caching are undefined.

Desired Experience
------------------

- Sidebar always exposes:
  - **All Mail**: unified, minus flagged threads.
  - **Important**: IMAP `\\Flagged`/Gmail Important filter.
  - **Threads**: deduped conversations sorted by latest activity.
- Detail pane renders HTML safely (sanitization + reveal controls) with plaintext fallback.
- Composer supports reply/reply-all/forward, quoting, formatting primitives, and attaches files once upload pipeline exists.
- Pagination + caching allow fast scrolling through large mailboxes; unread counts stay in sync via SSE.

Open Questions / TODOs
----------------------

- Define attachment download policy (size limits, caching, storage path).
- Decide on send architecture (backend SMTP proxy vs native client) and auth requirements.
- Map out pagination API between frontend and backend (cursor semantics, caching strategy).
- Determine approach for HTML sanitization library and configuration.
- Plan migration when native IMAP clients replace proxy endpoints.

Related Docs / Links
--------------------

- ADR 0002 – Thin Web IMAP Client: `docs/adrs/0002-thin-web-imap-client.md`
- Architecture overview: `docs/architecture.md`

