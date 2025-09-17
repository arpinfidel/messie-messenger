Frontend Guide (Draft)
======================

Purpose
-------

Reference for the Svelte application structure, build pipeline, and data flows. Fill in details as modules mature.

Tech Stack
----------

- Svelte + Vite + TypeScript
- Tailwind CSS for styling
- `matrix-js-sdk` for Matrix connectivity
- Generated `typescript-fetch` client for REST endpoints

Core View Models (to flesh out)
-------------------------------

- `MatrixViewModel`: session restoration, timelines, crypto bootstrap
- `EmailViewModel`: IMAP proxy integration, thread grouping, credential store
- `TodoViewModel`: backend API integration, fractional indexing helper
- `UnifiedTimelineViewModel`: aggregation of module timelines for UI consumption

Build & Tooling
---------------

- `npm run dev -- --host` for local development
- `npm run build` for production bundle
- API client generation via `make gen-fe`

State & Persistence
-------------------

- Local storage keys: `cloud_auth`, `cloud_jwt` (legacy fallback), `matrix_notify_cooldown_ms`
- Svelte stores under `src/viewmodels/**`

Open Questions / TODOs
----------------------

- Document component-level conventions (folder layout, naming)
- Capture testing strategy (unit vs component tests)
- Add guidance for theming and accessibility

