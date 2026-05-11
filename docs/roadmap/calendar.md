Calendar Roadmap (Draft)
========================

Purpose
-------

Lay out the next calendar milestone after local `.ics` file import: named calendar sources, remote ICS link sync, and a split-friendly backend boundary that can move into its own service later.

Current State
-------------

- V1 import already exists for uploaded `.ics` files.
- Calendar data already has the right high-level shape for sync work:
  - `CalendarSource` owns `kind`, `import_mode`, `source_url`, `refresh_state`, and `last_synced_at`
  - `CalendarEvent` stores normalized event data plus raw recurrence/blob fields
- FluffyChat already consumes imported events in:
  - a dedicated calendar page
  - the unified workspace list as upcoming timeline rows
- Current import mode is upload-only and read-only.

Design Constraints
------------------

- Calendar stays a separate module with its own entities, repositories, use cases, and handlers.
- No direct joins or ad hoc queries into todo, user, or other modules.
- Cross-module interactions must go through explicit interfaces.
- Timeline composition happens above the module boundary, not inside calendar repositories.
- External calendars remain read-only mirrors in this phase.

Next Step: Named Calendar Sources
---------------------------------

- FluffyChat import flow should let the user confirm or override the source name before upload.
- Backend remains the source of truth for persisted `display_name`.
- If the user does not override the name:
  - use ICS metadata when available (`NAME`, `X-WR-CALNAME`)
  - otherwise fall back to filename without `.ics`
- Follow-up API to consider:
  - `PATCH /calendar/sources/{sourceId}` for renaming a source after import

Next Step: ICS Link Import and Sync
-----------------------------------

User experience target
----------------------

- A user can add a calendar by URL instead of uploading a file.
- The calendar shows up as a named source, just like uploaded calendars.
- The user can manually refresh it.
- The backend can later refresh it on a schedule without client involvement.

API shape
---------

Add endpoints without breaking the current upload path:

- `POST /calendar/sources/link`
  - request: `url`, optional `display_name`
  - behavior: fetch ICS, parse it, create/update a source, import normalized events
- `POST /calendar/sources/{sourceId}/refresh`
  - manual refresh for link-backed calendars
- `PATCH /calendar/sources/{sourceId}`
  - rename source
- optional later:
  - `DELETE /calendar/sources/{sourceId}`
  - unchanged, still deletes source plus imported events

Data model adjustments
----------------------

The current model is close, but link sync needs a little more metadata:

- `CalendarSource`
  - keep existing:
    - `kind`
    - `import_mode`
    - `source_url`
    - `refresh_state`
    - `last_synced_at`
  - add:
    - `last_refresh_attempt_at`
    - `last_refresh_error`
    - `etag`
    - `last_modified`
- `CalendarEvent`
  - current normalized schema is sufficient for read-only sync
  - continue to key imported/upserted events by `(source_id, external_uid)`

Sync behavior
-------------

- For URL-backed sources:
  - fetch ICS over HTTP(S)
  - send `If-None-Match` / `If-Modified-Since` when metadata exists
  - on `304 Not Modified`, update refresh state and timestamps only
  - on `200`, re-parse and upsert events
- Event reconciliation:
  - insert new events
  - update existing events with the same `external_uid`
  - delete events no longer present in the remote feed for that source
- Refresh state values should clearly distinguish:
  - `imported`
  - `synced`
  - `stale`
  - `failed`

Service boundary plan
---------------------

Keep the sync implementation easy to extract later:

- Introduce an interface like `CalendarFeedFetcher` in the calendar module.
- Current implementation can use `net/http` inside the monolith.
- Future extracted calendar service can swap the fetcher and scheduler without changing repository contracts.
- Scheduling should be driven by a calendar-owned refresh coordinator, not by unrelated modules.

FluffyChat follow-up
--------------------

- Add a second creation path next to file upload:
  - `Import .ics file`
  - `Add calendar link`
- Source cards should show:
  - display name
  - source type (`uploaded` vs `link`)
  - last synced / failed state
- Allow rename from the source list once backend patch support exists.
- Keep link refresh UI explicit before adding background sync assumptions.

Open Questions / TODOs
----------------------

- Refresh cadence for linked calendars.
- Allowed URL schemes and SSRF protections.
- Whether private ICS links need secret redaction in logs/UI.
- How much sync status detail should be user-visible.
- Whether to support one-shot import from URL before persistent sync.

Related Docs / Links
--------------------

- Architecture overview: `docs/architecture.md`
- Todo roadmap: `docs/roadmap/todo.md`
