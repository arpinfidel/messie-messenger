# Implementation Plan (Phase 1 — Web + Password Only, add to existing Go server)

**Goal**
Add email to Messie via a thin **HTTP gateway** (implemented in the **existing Golang server**). Web client logs in with **email + app password**, fetches a few recent messages, and prints them to the console.

## Scope

* **Existing Go server**

  * Add endpoints to accept `{host, port, email, appPassword}`.
  * Open IMAP, fetch N newest message **headers** from INBOX.
  * Return JSON over HTTPS. No persistence required.
* **Web client**

  * Minimal login form.
  * POST creds to Go server.
  * Fetch and `console.log` subjects/senders.

## Flow

1. User submits creds → 2) Web POST `/email/login-test` → 3) Go server logs into IMAP → 4) Fetch headers → 5) Respond JSON → 6) Web prints to console.

## Design reasons (why this way)

* **Browsers can’t speak IMAP** (no raw TCP/TLS) → a gateway is required.
* **Fastest MVP**: app passwords validate end-to-end without OAuth plumbing.
* **Low blast radius**: server returns metadata only; no body storage, light compliance.
* **Stable contract**: when we add OAuth later, it’s **server-only**; the web client stays the same.
* **Future-ready**: same Go server can later add background sync, encrypted blob cache, or expose a Matrix-bridge façade—no UI rewrite.

## Out of scope (now)

OAuth, send/drafts/flags/attachments, background sync, caching, desktop/mobile wrappers.

## Expected results (test)

* Submitting valid creds returns JSON list of N headers.
* Console shows subjects/senders; invalid creds return clear error.
* No server persistence beyond the request lifecycle.

**Instruction to AI agent:**
Implement the new **email endpoints inside the existing Golang server** and a minimal web flow to call them. Limit to password-based login and “fetch & print” headers. No OAuth or persistence yet.

## Phase 1 — Status

- Backend: Added `POST /email/login-test` (no auth) to accept `{host, port, email, appPassword}`, connect via IMAP over TLS, select `INBOX`, fetch last N headers, and return `EmailMessagesResponse`.
- OpenAPI: Updated spec with `EmailLoginRequest`, `EmailMessageHeader`, `EmailMessagesResponse`; regenerated server and TS client bindings.
- Server wiring: Registered handler in Chi router under `/api/v1`; route bypasses JWT middleware per spec security.
- Web client: Added Email login tab with a minimal form posting creds to `/api/v1/email/login-test` and `console.log` of returned headers.
- Validation: Happy-path tested locally via fetch; error cases return 401/400/500 with JSON error message.

---

# Implementation Plan (Phase 2 — Web UI integration in sidebar)

**Goal**
Present email **alongside Matrix chats** in the **sidebar timeline** using the same Go gateway and password auth. On click, fetch a few recent messages and log to console.

## Frontend presentation (UI mapping)

* Add three email entries in the sidebar (like rooms):

  * **All Mail**: one item aggregating all non-important emails.
  * **Important**: one item aggregating Gmail “Important” (or IMAP `\Flagged` where “Important” isn’t available).
  * **Thread rooms**: a list where **each email thread** appears as its **own item/room** (can be stubbed: latest subject + unread count).

## Scope

* **Existing Go server**

  * Reuse Phase-1 endpoint.
  * Add simple list endpoints: `/email/inbox`, `/email/important`, `/email/threads` (headers only).
* **Web client**

  * Render three sidebar entries + a simple “Threads” list.
  * Wire clicks to call endpoints and `console.log` results.
  * Show basic unread counts returned by server.

## Flow

1. Sidebar renders three entries after login.
2. Clicking **All Mail/Important/Thread item** → fetch headers for that view → log to console.

## Design reasons

* **UI parity with Matrix** (treat as rooms) with minimal new UI.
* Incremental visibility without building full message reader yet.

## Out of scope

Bodies, attachments, send/drafts, SSE, persistence, OAuth.

## Expected results (test)

* Sidebar shows **All Mail**, **Important**, and a **Threads** list.
* Clicking each fetches data and logs to console.
* Unread counts update from server responses.

**Instruction to AI agent:**
Add minimal filter/list endpoints and render the three sidebar entries. Keep actions to console logging only.

---

# Implementation Plan (Phase 3 — Folders, listing, pagination)

**Goal**
Expose folder list and **paged** message metadata retrieval.

## Scope

* **Existing Go server**

  * `GET /email/accounts/{id}/folders`
  * `GET /email/accounts/{id}/folders/{fid}/messages?cursor=…&limit=…` (headers only)
  * Track `UIDVALIDITY`, `lastUID` cursors.
* **Web client**

  * Simple folder picker; show counts; log paged results.

## Flow

Fetch folders → fetch first page for INBOX → use `cursor` to page older.

## Design reasons

* Scalable browsing without full downloads; sets up cursors for later live sync.

## Out of scope

Events/push, flags, bodies, OAuth.

## Expected results (test)

* Folder list renders; selecting a folder returns a page of headers.
* Requesting next page with `cursor` returns older messages with no duplicates.

**Instruction to AI agent:**
Implement folder listing + paginated metadata endpoints and client calls.

---

# Implementation Plan (Phase 4 — Live updates via SSE)

**Goal**
Provide **near-real-time** updates (new mail/flag changes) via **SSE**.

## Scope

* **Existing Go server**

  * `GET /email/accounts/{id}/events` (SSE).
  * Use IMAP `IDLE` (fallback to polling).
  * Emit deltas: `{folder, uid, type: new|flags|deleted}`.
* **Web client**

  * Open SSE stream; log deltas; trigger narrow refetches.

## Flow

Client subscribes to SSE → server pushes deltas → client refetches affected items.

## Design reasons

* Instant feel without complex state sync; fits gateway model.

## Out of scope

Bodies, send, drafts, OAuth.

## Expected results (test)

* New email arriving triggers an SSE event within seconds.
* Flag change (e.g., star) emits an event; client refetch prints updated header.

**Instruction to AI agent:**
Add SSE endpoint wired to IMAP IDLE; minimal client listener to log events and refetch.

---

# Implementation Plan (Phase 5 — Bodies, attachments, read/star)

**Goal**
Fetch **message bodies/attachments on demand**; set `\Seen` / `\Flagged`.

## Scope

* **Existing Go server**

  * `GET /email/accounts/{id}/messages/{uid}/body` (stream)
  * `GET /email/accounts/{id}/messages/{uid}/attachments/{partId}` (stream)
  * `POST /email/accounts/{id}/messages/{uid}/flags` (seen/flagged)
* **Web client**

  * Console-log first KB of body; test star/unstar; reflect via SSE.

## Flow

Click message → fetch body; toggle star → server updates IMAP → SSE confirms.

## Design reasons

* On-demand fetch keeps bandwidth low; flags enable basic triage.

## Out of scope

Send, drafts, move/delete, OAuth.

## Expected results (test)

* Body endpoint returns text/html; attachments stream with correct MIME/size.
* Toggling `\Flagged` updates IMAP and emits SSE; read state updates with `\Seen`.

**Instruction to AI agent:**
Implement body/attachment streaming and flags API; wire minimal client calls.

---

# Implementation Plan (Phase 6 — Drafts & send)

**Goal**
Create/update **drafts** and **send** messages (new/reply) via SMTP.

## Scope

* **Existing Go server**

  * `POST /email/accounts/{id}/drafts` (create/update in “Drafts” with `\Draft`)
  * `POST /email/accounts/{id}/send` (SMTP app password; later XOAUTH2)
  * Add `In-Reply-To/References` for replies.
* **Web client**

  * Minimal compose form; log send result.

## Flow

Compose → optional save draft → send → server returns success.

## Design reasons

* Completes core mail loop with minimal UI changes.

## Out of scope

Scheduling, templates, rich editor, OAuth.

## Expected results (test)

* Creating/updating draft reflects in Drafts folder.
* Sending succeeds and appears in Sent folder (server confirms ID).

**Instruction to AI agent:**
Add draft/save and send endpoints; simple client compose + console result.

---

# Implementation Plan (Phase 7 — Move & delete)

**Goal**
Support moving messages between folders and deletion.

## Scope

* **Existing Go server**

  * `POST /email/accounts/{id}/messages/{uid}/move` (IMAP MOVE or COPY+EXPUNGE)
  * `DELETE /email/accounts/{id}/messages/{uid}`
* **Web client**

  * Trigger moves/deletes; log confirmations; observe SSE deltas.

## Flow

Action → server applies → SSE announces delta → client refetches.

## Design reasons

* Basic mailbox management; parity with common clients.

## Out of scope

Undo/Trash restore beyond server defaults.

## Expected results (test)

* Move moves the UID to target folder; source no longer lists it.
* Delete removes message; SSE `deleted` event fires.

**Instruction to AI agent:**
Implement move/delete endpoints and SSE announcements; minimal client triggers.

---

# Implementation Plan (Phase 8 — Minimal persistence & privacy controls)

**Goal**
Introduce **metadata persistence** and optional **encrypted blob cache**; add wipe controls.

## Scope

* **Existing Go server**

  * Persist accounts, folders, cursors, message metadata.
  * Optional: cache bodies as **encrypted blobs** (envelope encryption).
  * “Disconnect & Wipe” endpoint to purge tokens + cached data.
* **Web client**

  * Add “disconnect & wipe” button; log outcome.

## Flow

Normal usage persists metadata; user can wipe anytime.

## Design reasons

* Faster cold start without storing plaintext; clear privacy posture.

## Out of scope

Search/indexing, OAuth.

## Expected results (test)

* Restarting app still lists folders and recent headers quickly.
* “Wipe” clears stored metadata/blobs; next open requires fresh fetch.

**Instruction to AI agent:**
Add metadata persistence and optional encrypted blob cache; implement wipe.

---

# Implementation Plan (Phase 9 — Search v1: metadata filters)

**Goal**
Enable **basic search** using server-side metadata filters; fetch bodies on demand.

## Scope

* **Existing Go server**

  * `GET /email/search?folder=…&from=…&subject=…&dateAfter=…` (metadata only)
* **Web client**

  * Call search; log IDs; fetch bodies on click.

## Flow

Search → server returns candidate UIDs → client fetches bodies as needed.

## Design reasons

* Adds value without storing plaintext or embeddings yet.

## Out of scope

Semantic/vector search, OAuth.

## Expected results (test)

* Searching by from/subject/date returns matching headers.
* Clicking a result fetches body successfully.

**Instruction to AI agent:**
Implement metadata search endpoint; client consumes and fetches bodies on demand.
