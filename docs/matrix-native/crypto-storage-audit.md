# Crypto Storage Audit (MES-59)

Date: 2024-05-13

## Overview

Messie Messenger currently relies on the Matrix JS SDK (`matrix-js-sdk`) for
crypto and session management. The application layers add their own
`IndexedDB` caches for timeline data and use `localStorage` for session and UI
preferences. This document captures where secrets, keys, and crypto artefacts
live today so the native runtime can import/export them safely.

## Storage Inventory

### 1. Matrix JS SDK IndexedDB (`matrix-js-sdk`)

- **Creation**: `MatrixClientManager.createFromSession` instantiates
  `new matrixSdk.IndexedDBStore({ dbName: 'matrix-js-sdk' })`
  (`frontend/src/viewmodels/matrix/core/MatrixClientManager.ts:19`). The
  Matrix client mounts both the standard sync store and the crypto store in
  the same database.
- **Key tables** (from `indexeddb-crypto-store` implementation shipped with
  `matrix-js-sdk` 28.x):
  - `account` – holds the Olm account pickle containing identity keys and
    one-time keys.
  - `device_data` – device list cache (ed25519/curve25519 keys for the user).
  - `sessions` – Olm session pickles keyed by (device, sessionId).
  - `inbound_group_sessions` / `outbound_group_sessions` – Megolm
    session pickles for encrypted room timelines.
  - `shared_history_users` – per-room history sharing flags.
  - `secret_storage` – encrypted SSSS payloads including
    `m.cross_signing.master`, `m.cross_signing.self`,
    `m.megolm_backup.v1`, and arbitrary application secrets.
  - `key_requests`, `olm_sessions`, `backup` metadata, and sync cursors.
- **Access patterns**:
  - `MatrixCryptoManager.ensureVerificationAndKeys` and
    `.setupEncryptionSession` call SDK crypto APIs that persist verification
    state and backups into these tables (e.g.
    `crypto.checkKeyBackupAndEnable`, `crypto.bootstrapCrossSigning`).
  - Secret storage is accessed via `client.secretStorage` helpers in
    `MatrixCryptoManager.hasSecretStorageAndBackup` and `.restoreFromRecoveryKey`.
- **Implication for migration**: Native runtime must be able to read the
  same pickled Olm/Megolm records and secret-storage payloads to preserve
  login state, cross-signing trust, and backup keys.

### 2. Messie IndexedDB cache (`mx-app-store`)

- **Creation**: `IndexedDbCache` wraps `DbConnection` which opens
  `indexedDB.open('mx-app-store', 8)` with stores `rooms`, `meta`, `users`,
  `media`, `members`, and `timelineEvents`
  (`frontend/src/viewmodels/matrix/core/idb/DbConnection.ts`).
- **Purpose**: timeline caching, avatar/media blobs, unread metadata – no
  crypto secrets.
- **Migration impact**: If the native runtime provides equivalent timeline
  data, the cache can be reused as-is; no secret material needs exporting.

### 3. `localStorage`

- `matrixSession` – `MatrixSessionStore` persists homeserver URL, access
  token, user ID, and device ID in clear text
  (`frontend/src/viewmodels/matrix/core/MatrixSessionStore.ts`).
- `matrixHomeserverUrl`, `matrixUsername`, and
  `matrix:pwdreset:<sid>:client_secret` – password reset helpers in
  `MatrixViewModel` and Svelte login/forgot password views keep temporary
  identifiers to resume the flow (`frontend/src/viewmodels/matrix/MatrixViewModel.ts:366-410`,
  `frontend/src/views/matrix/MatrixLogin.svelte`).
- `matrix_notify_cooldown_ms` – UI preference loaded by `MatrixSettings`
  (`frontend/src/viewmodels/matrix/MatrixSettings.ts`).
- Developer tooling (`frontend/src/viewmodels/settings/DeveloperSettings.ts`) and
  Cloud auth state also store JSON blobs, but they do not contain Matrix
  crypto secrets.
- **Implication**: When migrating to native, we must continue reading the
  `matrixSession` entry to hydrate the native client with homeserver, token,
  and device metadata. Password-reset keys are short-lived and do not need
  migration.

### 4. In-memory / configuration

- `matrixSettings.recoveryKey` holds a user-supplied recovery key in memory
  only; it is not persisted today. Crypto routines use it to unlock backups
  if SSSS is not populated (`MatrixCryptoManager.restoreFromRecoveryKey`).
- Push notification state is stored remotely via Matrix; no local secrets are
  written beyond the ones above.

## Gaps & Risks

1. **Access token at rest** – `matrixSession` stores the access token
   unencrypted. The native runtime must either continue using it (with OS key
   store migration in MES-63) or introduce a secure storage migration path.
2. **Secret storage key material** – SSSS default keys are encrypted and
   stored server-side, but the `secret_storage` table keeps copies of secrets
   encrypted with the SSSS default key. We need the SSSS key (from recovery
   key or bootstrap flow) available during migration to rehydrate native
   stores.
3. **Backup private key** – when present, the JS runtime stores the backup
   key via `crypto.storeSessionBackupPrivateKey`. Migration must export it so
   native crypto can resume incremental backups without re-prompting users.
4. **Device verification cache** – verification state (trust levels) lives in
   `device_data` and `cross_signing_keys`. Losing these would force manual
   re-verification.

## Next Steps for Migration

1. Build import routines (MES-63) that can parse the `matrix-js-sdk`
   IndexedDB tables and emit artifacts consumable by the native Olm machine.
2. Provide an export path so the native runtime can hand back secrets when we
   fall back to JS (e.g. browser environment).
3. Decide where the native runtime will persist the access token and device
   keys (Android Keystore vs. continuing to rely on `localStorage`).

This audit feeds directly into the native bridge migration plan by clarifying
which artefacts the native runtime must accept and produce.
