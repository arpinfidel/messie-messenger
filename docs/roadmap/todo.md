Todo Roadmap (Draft)
====================

Purpose
-------

Lay out planned enhancements for collaborative todos, including cross-surface UX and deeper integrations with the timeline and calendar.

Current Gaps
------------

- Mobile interaction patterns (swipe gestures, long-press actions, shortcuts) are undefined.
- Calendar integration is only aspirational—no spec for how due dates appear alongside other modules.
- Realtime collaboration (presence, live updates) is rudimentary.

Desired Experience
------------------

- Mobile: swipe left/right for complete/delete, long-press to reorder, quick edit inline.
- Timeline cards show due badges, status chips, and collaborator avatars; calendar view highlights tasks by due date.
- Realtime updates via SSE or WebSocket keep lists and timeline entries current.
- Editable checklist items with attachment support and comments in future iterations.

Open Questions / TODOs
----------------------

- Offline/optimistic updates for mobile clients and conflict resolution.
- Synchronizing fractional positions with multi-user edits.
- Notification strategy (email/push) when tasks change state.
- Calendar API contract (iCal export? Matrix calendar integration?).

Related Docs / Links
--------------------

- Fractional indexing ADR: `docs/adrs/0001-fractional-indexing.md`
- Architecture overview: `docs/architecture.md`

