# Context

We are building a minimal Matrix client **without `matrix-js-sdk`**.
The app must remain testable at every step.
We will begin with mocks for all functionality, remove the SDK, and then progressively replace mocks with real implementations.
Final MVP must support:

* Login
* Room list
* Messages with pagination
* Room members
* E2EE (send/receive)
* Media (upload/download)

All other features (typing, receipts, presence, push, devices, etc.) remain mocked.

---

# Instructions

## Phase 0 — Mocks

* Create `src/matrix-lite/`.
* Add `client.ts` exporting the following functions (all mocked initially):

```ts
export async function loginWithPassword(username:string, password:string) { /* mock */ }
export async function logout() { /* mock */ }
export function setSession(session:{access_token:string; user_id:string; device_id:string}) { /* mock */ }

export async function listJoinedRooms() { /* mock */ }
export async function getRoomState(roomId:string) { /* mock */ }
export async function getRoomMembers(roomId:string) { /* mock */ }

export async function getMessages(roomId:string, from?:string, dir:'b'|'f'='b', limit=20) { /* mock */ }
export async function sendMessage(roomId:string, content:any) { /* mock */ }

export async function uploadMedia(data:Blob|ArrayBuffer, contentType:string) { /* mock */ }
export function mxcToHttp(mxcUrl:string) { /* mock */ }

export function startMiniSync() { /* mock */ }
export function stopMiniSync() { /* mock */ }
export function onToDevice(handler:(evts:any[])=>void) { /* mock */ }

export async function initCrypto() { /* mock */ }
export async function decryptEvent(evt:any) { /* mock */ }
export async function encryptEvent(roomId:string, type:string, plain:any) { /* mock */ }
```

* All mocks should:

  * Return hardcoded fake rooms, events, and members.
  * Print `[compat-mock]` warnings in console.
* Add `USE_MATRIX_LITE` flag to toggle between old SDK and new client.

**Visible result:**

* With flag enabled, app runs end-to-end with fake data.

---

## Phase 1 — Remove SDK

* Delete `matrix-js-sdk` from `package.json` and all imports.
* Ensure app only calls into `matrix-lite/client.ts`.
* App still works (on mocks).

**Visible result:**

* Build passes with no SDK present.
* UI runs with fake rooms/messages.

---

## Phase 2 — Login (real)

* Replace `loginWithPassword`, `logout`, and `setSession` with real REST calls.
* Leave all other functions mocked.

**Visible result:**

* Logging in with real credentials works.
* UI still shows fake rooms/messages.

---

## Phase 3 — Rooms (real)

* Replace `listJoinedRooms` with `GET /_matrix/client/v3/joined_rooms`.
* Replace `getRoomState` with `GET /rooms/{roomId}/state`.
* Summaries derive from `m.room.name`, `m.room.avatar`, `m.room.topic`.
* Leave messages mocked.

**Visible result:**

* Sidebar shows real joined rooms.
* Opening a room still shows fake messages.

---

## Phase 4 — Messages (real)

* Replace `getMessages` with `GET /rooms/{roomId}/messages`.
* Implement pagination with `from` token.
* Clamp memory to ≤120 in-memory events per room.
* Replace `sendMessage` with `PUT /rooms/{roomId}/send/m.room.message/{txnId}`.

**Visible result:**

* Rooms display real messages.
* Sending plaintext messages works.

---

## Phase 5 — Members (real)

* Replace `getRoomMembers` with `GET /rooms/{roomId}/members`.
* Provide `{user_id, displayname, avatar_url}`.

**Visible result:**

* Messages show real displaynames and avatars.

---

## Phase 6 — E2EE

* Integrate `matrix-sdk-crypto-wasm`.
* Implement `initCrypto()`:

  * Initialize `OlmMachine(userId, deviceId)`.
  * Upload device keys and one-time keys.
* Implement `startMiniSync` to call `/sync` with `to_device` only.
* Wire `onToDevice` to pass events into crypto.
* Replace `decryptEvent`:

  * For `m.room.encrypted`, call `OlmMachine.decryptRoomEvent`.
* Replace `encryptEvent`:

  * Create outbound session if needed.
  * Use `OlmMachine.encrypt` before sending.
* Update `sendMessage` to call `encryptEvent` when room is encrypted.

**Visible result:**

* Encrypted rooms decrypt correctly.
* Sending encrypted messages works and other clients can read them.

---

## Phase 7 — Media

* Replace `uploadMedia` with `POST /_matrix/media/v3/upload`.
* Replace `mxcToHttp` with resolver to `/_matrix/media/v3/download/...` or `thumbnail`.
* Ensure app revokes blob URLs on unmount.

**Visible result:**

* Image/file messages send and display.
* Memory stays stable after leaving rooms.

---

# Completion Criteria (MVP)

* SDK fully removed.
* App can:

  * Log in with real credentials.
  * List joined rooms.
  * Fetch and paginate messages.
  * Show real members.
  * Encrypt/decrypt messages in E2EE rooms.
  * Upload and display media.
* Everything else (typing, receipts, presence, push, devices) remains mocked but non-breaking.
