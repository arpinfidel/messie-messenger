Shared Platform & UX Roadmap (Draft)
====================================

Purpose
-------

Capture cross-cutting initiatives that affect multiple modules—settings, notifications, theming, accessibility, and platform concerns.

Current Gaps
------------

- Accessibility guidelines and audit plan are missing.
- No unified notification center; each module handles alerts ad hoc.
- Settings UI lacks structure (module vs global preferences, account management).
- Theming tokens are not formalized for reuse across web and future desktop shells.

Desired Experience
------------------

- Modular settings panel with tabs per module plus global preferences (notifications, accounts, labs/experiments).
- Notification hub with filters, quick actions, and snooze controls.
- Shared theming/token system with light/dark modes and high-contrast option.
- Accessibility checklist (keyboard navigation, screen reader support, contrast) baked into definition-of-done.

Open Questions / TODOs
----------------------

- How to store per-module preferences (local storage vs synced backend data).
- Multi-account support for Matrix and Email—UX and persistence implications.
- Offline caching boundaries for unified timeline and module data.
- Integrations with OS-level notifications on desktop/mobile wrappers.

Related Docs / Links
--------------------

- Architecture overview: `docs/architecture.md`
- Backend/frontend implementation notes: `docs/backend.md`, `docs/frontend.md`
