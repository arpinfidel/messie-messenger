# Context

We are building a **custom lightweight Matrix client** to replace `matrix-js-sdk`.
The MVP must cover:

- Login/logout
- Room list
- Messages (fetch, paginate, send)
- Room members
- E2EE (via **recovery key + key backup**, no SAS, no cross-signing)
- Media (upload/download)

Everything else (typing, receipts, presence, push, SAS, cross-signing) is mocked.
The old SDK remains in the repo until the end for reference and parity checks.

**Maintainability rules:**

- Place code in `src/matrix-lite/` with clear submodules (`http/`, `api/`, `crypto/`, `compat/`, `types/`, `runtime/`).
- Define interfaces in `client.ts`, keep internals swappable.
- Use **TypeScript strict mode**, strong types, minimal `any`.
- Allowed libraries: lightweight helpers + `olm` or `matrix-sdk-crypto-wasm`. Avoid heavy runtime deps.
- Write clear JSDoc, modular clean code.

---

# Phases (each testable in the UI)

## Phase 0 — Mocks

- Implement the full public API with fake rooms/messages/members.
- Print `[compat-mock]` warnings.
- Add flag `USE_MATRIX_LITE`.
- App still works with fake data.

**Visible result:** App loads with fake rooms/messages.

---

## Phase 1 — Login (real)

- Implement real `/_matrix/client/v3/login` and logout.
- Store session (token, user_id, device_id).
- Rooms/messages still mocked.

**Visible result:** Real login works, sidebar still fake.

---

## Phase 2 — Rooms (real)

- Implement `joined_rooms` + room state.
- Replace sidebar mock.

**Visible result:** Sidebar shows real joined rooms.

---

## Phase 3 — Messages (plaintext)

- Implement `/rooms/{roomId}/messages` with pagination.
- Implement plaintext `sendMessage`.
- Keep memory window small (\~120 events per room).

**Visible result:** Room timelines show real messages; plaintext send works.

---

## Phase 4 — Members

- Implement `/rooms/{roomId}/members`.

**Visible result:** Sender names and avatars resolve correctly.

---

## Phase 5 — Mini-sync (to-device only)

- Implement `/sync` loop (only `to_device` + `device_lists`).
- Expose via `onToDevice`.

**Visible result:** HUD shows sync active, console logs to-device events.

---

## Phase 6 — E2EE Init

- Integrate `matrix-sdk-crypto-wasm` (or `olm`).
- `initCrypto()` → create machine with user_id/device_id.
- Hook `to_device` events into crypto engine.

**Visible result:** Crypto engine reports initialized.

---

## Phase 7 — Device Keys

- Implement device key upload/query/claim.
- Fulfill crypto engine requests.
- Explain to user how to test.

**Visible result:** Other clients can see this device in their list.

---

## Phase 8 — Secure Secret Storage (SSSS) + Key Backup Restore

### Goal

Allow the user to enter their **recovery key** after login.
Use it to decrypt their Megolm session key backup and import those sessions into the crypto engine.
This makes **old encrypted messages decrypt automatically**.

---

### Recovery key format

- Recovery keys are **Base58-encoded** (not Base64).
- They usually start with `base58` characters like `EsTc5...`.
- Decode with a Base58 library (e.g. [`bs58`](https://www.npmjs.com/package/bs58)).

Example:

```ts
import bs58 from 'bs58';

function decodeRecoveryKey(input: string): Uint8Array {
  return bs58.decode(input.trim());
}
```

---

### Decryption process

1. **Fetch backup info**
   - `GET /_matrix/client/v3/room_keys/version`
   - `GET /_matrix/client/v3/room_keys/keys`

2. **Obtain recovery key**
   - User pastes their Base58 recovery key.
   - Decode to raw bytes: `Uint8Array`.

3. **Derive AES key**
   - Use HKDF-SHA256 with the recovery key as input key material.
   - Context string is `"backup"` (per Matrix spec).
   - Derive 32 bytes.

   Example (Node crypto):

   ```ts
   import { hkdfSync } from 'crypto';

   function deriveBackupKey(rawKey: Uint8Array): Buffer {
     return hkdfSync('sha256', Buffer.alloc(0), rawKey, Buffer.from('backup'), 32);
   }
   ```

4. **Decrypt sessions**
   - Backup entries are encrypted JSON payloads.
   - Use AES-CTR or AES-GCM depending on the backup algorithm reported by the server.
   - Decrypt with the derived backup key.
   - Each decrypted entry is a Megolm session key.

5. **Import into crypto engine**
   - For each decrypted session:
     - Call `OlmMachine.importRoomKeys()` (if using matrix-sdk-crypto-wasm).

   - This seeds the crypto engine with the old Megolm sessions.

---

### API shape

```ts
export async function restoreBackupWithRecoveryKey(recoveryKey: string): Promise<number> {
  const raw = decodeRecoveryKey(recoveryKey); // Base58 decode
  const aesKey = deriveBackupKey(raw); // HKDF → 32-byte AES key

  const backupVersion = await httpGet('/room_keys/version');
  const backupData = await httpGet(`/room_keys/keys?version=${backupVersion.version}`);

  let importedCount = 0;
  for (const key of backupData.rooms) {
    const decrypted = decryptBackupEntry(key, aesKey); // AES-CTR/GCM
    if (decrypted) {
      await crypto.importRoomKey(decrypted);
      importedCount++;
    }
  }

  return importedCount;
}
```

- Return value = number of sessions imported.
- Print `[backup-restore] Imported ${count} sessions` to console.

---

### Visible result

- User enters recovery key → backup sessions imported.
- Old encrypted history decrypts automatically.
- HUD/console shows “Backup restored, N sessions imported”.

---

⚠️ **Reminder for AI implementer**:

- The recovery key is **Base58**.
- Use `bs58.decode()`, not atob/base64.
- Matrix spec: [MSC1219](https://spec.matrix.org/latest/client-server-api/#key-backup) for key backup, [MSC1946](https://github.com/matrix-org/matrix-spec-proposals/pull/1946) for recovery key derivation.

---

## Phase 9 — Decrypt Events

- Implement `decryptEvent`.
- Hook into message fetch + sync:
  - Old encrypted messages now decrypt automatically if keys exist.
  - New incoming messages decrypt live.

**Visible result:** Encrypted room history is readable right after restore.

---

## Phase 10 — Encrypt + Send

- Implement `encryptEvent` using Olm/Megolm.
- Update `sendMessage` to auto-encrypt if room is encrypted.

**Visible result:** Messages sent are encrypted, readable in Element/Hydrogen.

---

## Phase 11 — Media

- Implement media upload (`/_matrix/media/v3/upload`).
- Implement `mxcToHttp`.
- Ensure blob URLs revoked after render.

**Visible result:** Images/files send and display correctly.

---

## Final Cutover — Remove old SDK

- Delete `matrix-js-sdk` from repo.
- Default to `USE_MATRIX_LITE=true`.
- Keep dev switch optional for a while.

**Visible result:** App fully runs on new client only.

---

✅ With this plan, your MVP achieves the exact flow you want:
**Login → Recovery key → Old encrypted messages decrypt automatically → New messages encrypted/decrypted seamlessly.**
