Matrix Roadmap (Draft)
======================

Purpose
-------

Track improvements for the Matrix chat module, including bridged network ergonomics and authentication considerations.

Current Gaps
------------

- **Baseline chat ergonomics**: Reply, reactions, message editing, pinning, mute per room, and richer read receipts are missing.
- **Bridge awareness**: Need badges for bridged rooms, explicit bridge-bot grouping, and origin indicators on messages.
- **Encryption UX**: No documented plan for verification flows or device management.

Desired Experience
------------------

- Reply/reaction affordances mirror Element’s shortcuts but fit our two-pane layout (modal vs inline composer TBD).
- Room settings expose mute/snooze and pin controls; pinned messages surface with timeline chips.
- Member panel separates humans vs bridge bots; bridged messages carry network badges.
- Verification assist flows (emoji SAS, QR) align with Matrix best practices once crypto is stable.

Open Questions / TODOs
----------------------

- Define notification batching across Matrix + bridged events.
- Specify how bridged threads appear in the unified timeline alongside native Matrix rooms.
- Decide on minimum encryption support for MVP (timeline hints, verification prompts, fallback for unverified devices).
- Document retention and redaction behavior for bridged content.

Related Docs / Links
--------------------

- Auth bridge ADR: `docs/adrs/0003-matrix-cloud-auth.md`
- Architecture overview: `docs/architecture.md`

