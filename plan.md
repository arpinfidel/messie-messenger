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

* Backend: Added `POST /email/login-test` (no auth) to accept `{host, port, email, appPassword}`, connect via IMAP over TLS, select `INBOX`, fetch last N headers, and return `EmailMessagesResponse`.
* OpenAPI: Updated spec with `EmailLoginRequest`, `EmailMessageHeader`, `EmailMessagesResponse`; regenerated server and TS client bindings.
* Server wiring: Registered handler in Chi router under `/api/v1`; route bypasses JWT middleware per spec security.
* Web client: Added Email login tab with a minimal form posting creds to `/api/v1/email/login-test` and `console.log` of returned headers.
* Validation: Happy-path tested locally via fetch; error cases return 401/400/500 with JSON error message.

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

## Phase 2 — Status

* Backend: Implemented `POST /email/inbox`, `POST /email/important`, and `POST /email/threads` using a shared IMAP header fetcher, returning `EmailMessagesResponse` with `unreadCount`.
* OpenAPI: Added email list endpoints to `docs/openapi.yaml`; regenerated Go server bindings and TS client. Endpoints are unauthenticated per spec.
* Server wiring: Registered new routes under `/api/v1` via `oapi-codegen` router; they bypass JWT middleware automatically (no security on ops).
* Web client: Sidebar now shows All Mail, Important, and stubbed Threads. Clicks POST the saved credentials to the corresponding endpoints and log results.
* Unread counts: After fetch, the sidebar badge updates via a singleton `EmailViewModel` that tracks per-item `unreadCount`.

---

# Implementation Plan (Phase 3 — Thread identity & pagination in 3-view model)

**Goal**
Add proper **thread grouping** and **pagination** for the three main views (All Mail, Important, Threads). Each thread appears as a **room-like item** in the sidebar.

## Scope

* **Existing Go server**

  * Compute a stable `threadKey` (e.g. SHA1 of root `Message-ID` + `References` chain).
  * Endpoints:

    * `/email/inbox` → returns newest headers with `threadKey` and `cursor`.
    * `/email/important` → same, filtered by Important/`\,Flagged`.
    * `/email/threads` → returns **one row per threadKey** with latest message + unread count, paginated.
  * Return `threadKey`, `latestSubject`, `from`, `date`, `unreadCount`.
* **Web client**

  * Update sidebar:

    * All Mail → one entry, shows unread total.
    * Important → one entry, shows unread total.
    * Threads → **list of thread rooms**, each with latest subject, unread badge, timestamp.
  * Clicking a thread logs the full header list for that thread.

## Flow

1. Client requests `/email/threads?cursor=…` → server groups by `threadKey` → returns list of thread previews.
2. Sidebar shows each thread as a “room.”
3. Clicking a thread calls `/email/thread/{threadKey}/messages` → logs headers.

## Design reasons

* Forces UI to treat threads as rooms, not folders.
* Pagination ensures large mailboxes load progressively.
* Stable `threadKey` guarantees consistent grouping across syncs.

## Out of scope

Bodies, attachments, flags, drafts, SSE, OAuth.

## Expected results (test)

* Sidebar shows All Mail, Important, and a **dynamic list of thread rooms**.
* Each thread room shows subject, unread count, and last date.
* Clicking a thread logs that thread’s messages.
* Paging `/email/threads` loads older threads without duplicates.

**Instruction to AI agent:**
Implement `threadKey` grouping server-side and render per-thread rooms in sidebar. Client must show thread list as clickable rooms, not just log all headers.

## Phase 3 — Status

* Backend: Implemented thread grouping with stable `threadKey` based on `In-Reply-To` (fallback `Message-ID`) hashed via SHA1. Added pagination with `?cursor=<unix_ts>` to request older threads.
* Endpoints:
  * `POST /api/v1/email/threads` → returns `{ threads: [{ threadKey, latestSubject, from, date, unreadCount }], cursor }`.
  * `POST /api/v1/email/thread/{threadKey}/messages` → returns `EmailMessagesResponse` for that thread (headers + per-thread `unreadCount`).
* Web client: Sidebar shows a dynamic list of thread rooms from `/email/threads`. Each thread displays latest subject, from, timestamp, and unread badge.
* Click behavior: Clicking a thread posts credentials to `/api/v1/email/thread/{threadKey}/messages`, logs headers, and updates the thread’s unread badge.
* Notes: OpenAPI and generated TS client remain unchanged; the web uses `fetch` for these email endpoints. The `threadKey` uses `In-Reply-To`/`Message-ID` (no full References chain yet).

---

# Implementation Plan (Phase 4 — Live updates via SSE for 3-view model)

**Goal**
Add **real-time updates** (new messages, flag changes, deletions) so sidebar items and thread rooms stay current.

## Scope

* **Existing Go server**

  * `GET /email/events` (SSE).
  * Use IMAP `IDLE` (fallback to polling).
  * Emit events:

    * `inbox:new`, `important:new`, `thread:update`, `thread:new`, `message:deleted`.
  * Include `threadKey`, `uid`, `unreadCount`, `latestSubject`, `date`.
* **Web client**

  * Subscribe once; update:

    * All Mail/Important unread counts.
    * Thread rooms: update preview subject, bump unread, or add new thread.

## Flow

1. New mail → server emits `inbox:new` + `thread:update`.
2. Client updates All Mail count, and thread room preview/unread badge.
3. Starring/unstarring updates Important view.
4. Deletions remove or update a thread room.

## Design reasons

* Keeps sidebar in sync, same as Matrix live timeline.
* Users see thread rooms update instantly without refresh.

## Out of scope

Bodies, drafts, OAuth.

## Expected results (test)

* Sending self a test mail creates a new thread room in sidebar.
* Marking a message seen decreases unread badge.
* Star toggles add/remove thread from Important view in real time.

**Instruction to AI agent:**
Wire SSE events to update sidebar counts and per-thread rooms. Don’t just log; UI must update live.

---

# Implementation Plan (Phase 5 — Bodies, attachments, read/star inside thread rooms)

**Goal**
Open threads, fetch **message bodies/attachments**, and allow marking read/star.

## Scope

* **Existing Go server**

  * `GET /email/thread/{threadKey}/messages` → headers for all messages in thread.
  * `GET /email/messages/{uid}/body` → stream body.
  * `GET /email/messages/{uid}/attachments/{partId}` → stream attachment.
  * `POST /email/messages/{uid}/flags` → set `\Seen`, `\Flagged`.
* **Web client**

  * Clicking a thread room loads message list → console.log messages.
  * Clicking a message fetches body/attachment → console.log.
  * Star/unstar updates Important view + thread preview unread badge.

## Flow

Open thread → fetch all messages → click message → fetch body → toggle flags → SSE updates Important & All Mail.

## Design reasons

* Adds depth to thread rooms without leaving 3-view model.
* Flags integrate naturally into Important.

## Out of scope

Drafts, send, move, OAuth.

## Expected results (test)

* Opening thread logs all messages in it.
* Clicking message prints body text.
* Starring moves it to Important and updates thread room immediately.

**Instruction to AI agent:**
Implement thread detail + message body/flag endpoints. Client must load thread room content, not just log global headers.

---

# Implementation Plan (Phase 6 — Drafts & send in thread context)

**Goal**
Enable composing replies or new mails inside thread rooms.

## Scope

* **Existing Go server**

  * `POST /email/drafts` → save to Drafts with `\Draft`, keyed by `threadKey` if replying.
  * `POST /email/send` → send via SMTP, set `In-Reply-To` for replies.
  * Emit SSE to update thread preview + All Mail.
* **Web client**

  * Compose box in thread room (minimal).
  * Log send result, update preview via SSE.

## Flow

Compose reply → send → new message appears in same thread room.

## Design reasons

* Completes mail loop while keeping thread as main unit.
* Matches Matrix chat experience.

## Out of scope

Rich editor, scheduling, OAuth.

## Expected results (test)

* Replying adds new message to thread room in real time.
* Draft saving logs confirmation; draft visible in thread when fetched again.

**Instruction to AI agent:**
Implement send/draft endpoints; client adds compose box inside thread rooms.

---

# Implementation Plan (Phase 7 — Delete & archive in 3-view model)

**Goal**
Support delete/archive actions while preserving 3-view sidebar model.

## Scope

* **Existing Go server**

  * `DELETE /email/messages/{uid}` → Trash per server default.
  * `POST /email/messages/{uid}/archive` → move to Archive (if supported).
  * Emit SSE to remove/update thread room + counts.
* **Web client**

  * Delete/archive buttons in thread rooms.
  * Log action + observe sidebar updates.

## Flow

Delete → removes message/thread from All Mail + Important.
Archive → removes from All Mail but thread remains accessible.

## Design reasons

* Simple mailbox management in thread UI.
* Fits 3-view abstraction without showing folder tree.

## Out of scope

Restore, move to arbitrary folders, OAuth.

## Expected results (test)

* Deleting last message in thread removes thread room from sidebar.
* Archiving hides thread from All Mail but doesn’t break Important/Thread view.

**Instruction to AI agent:**
Implement delete/archive with SSE events to keep 3-view model consistent.

---

# Implementation Plan (Phase 8 — Persistence & wipe for 3-view model)

**Goal**
Persist minimal metadata for All Mail, Important, and Threads for faster cold starts; add wipe control.

## Scope

* **Existing Go server**

  * Store per-account thread index (threadKey → latest header, unread count).
  * Optional encrypted blob cache for bodies.
  * `POST /email/wipe` → clear all tokens + caches.
* **Web client**

  * On restart, immediately render cached sidebar with counts.
  * “Disconnect & Wipe” button clears data.

## Flow

Restart → preload All Mail/Important counts + thread previews → background sync updates.
Wipe → sidebar empties, login required again.

## Design reasons

* Faster UX without losing privacy.
* Minimal persistence avoids full folder tree complexity.

## Out of scope

Vector search, OAuth.

## Expected results (test)

* Restart shows sidebar populated before IMAP sync completes.
* Wipe clears sidebar and requires login.

**Instruction to AI agent:**
Persist only metadata for 3-view model; implement wipe endpoint and client action.

---

# Implementation Plan (Phase 9 — Search v1: metadata filters in 3-view model)

**Goal**
Add metadata search scoped to All Mail, Important, or Threads.

## Scope

* **Existing Go server**

  * `GET /email/search?view=inbox|important|threads&from=…&subject=…&dateAfter=…`
  * Returns headers + `threadKey` matches.
* **Web client**

  * Search bar scoped to current view.
  * Log results; clicking fetches body.

## Flow

Search query → server filters messages/threads → client shows results.
Clicking a result fetches body.

## Design reasons

* Provides search without needing folder UI.
* Keeps consistent with 3-view sidebar model.

## Out of scope

Semantic search, OAuth.

## Expected results (test)

* Searching “from\:me” in All Mail returns matching messages.
* Searching in Threads shows matching thread rooms.
* Clicking opens thread, logs body.

**Instruction to AI agent:**
Implement search endpoints scoped to 3-view model; client consumes results with body fetch on click.
