# Local Matrix Homeserver (native Simplified Sliding Sync)

Messie Messenger ships with an opt-in [Synapse](https://github.com/matrix-org/synapse) container that now enables the **native Simplified Sliding Sync (MSC4186)** endpoints. The same Postgres instance defined in `docker-compose.dev.yml` is reused; no additional proxy containers are required.

## Prerequisites

- Docker + Docker Compose v2
- `.env` populated with any non-default ports or credentials you plan to use

## First-time setup

1. Generate configuration and secrets (writes to the `matrix_data` volume):

   ```bash
   make matrix-init
   ```

   Override the shared registration secret by exporting `MATRIX_REGISTRATION_SHARED_SECRET=your-secret` before running the command.
2. Bring the homeserver online with the sliding-sync profile enabled:

   ```bash
   make matrix-up matrix
   ```

   The service listens on `http://localhost:8008` by default. Change the external port via `MATRIX_PORT` in `.env` if needed. The container mounts `infra/matrix/conf.d/simplified-sliding-sync.yaml` and runs Synapse `v1.114.0` so the unstable simplified sliding-sync endpoint is exposed at `/_matrix/client/unstable/org.matrix.simplified_msc3575/sync`.

## Seeding a bridge-friendly dataset

The repo contains a small Node-based seeder (`scripts/matrix/src/seed_synapse.ts`) that provisions a deterministic dataset for bridge validation via the `matrix-js-sdk`:

- Creates or reuses an admin (`bridge-admin`) and bridge test user (`bridge-tester`) via the shared-secret registration API.
- Logs in as the test user with device ID `MESSIE_BRIDGE_SEEDER`, uploads device/one-time keys, and enables the Rust crypto store.
- Ensures **400 encrypted rooms** named `#messie-seed-0001…0400:<server>` exist and that the bridge user is a member.
- Injects an encrypted seed message in each room exactly once (`Seed message #0001 ready for Simplified Sliding Sync`).

Run the seeder with Synapse already running:

```bash
make matrix-seed
```

The make target installs local dependencies inside `scripts/matrix/` (if
needed), compiles the TypeScript entrypoint, and executes it with the same
`MATRIX_SEED_*` overrides as before. Pass additional CLI arguments with the
`ARGS` variable, e.g. `ARGS="--room-count 100" make matrix-seed`. Inside the
compose network the seeder reaches Synapse at `http://matrix:8008`; set
`MATRIX_SEED_SERVER_URL` if you need to connect to a remote homeserver instead.

### Faster seeding with multiple users

To reduce per-user rate limiting and speed up event sending, the seeder can distribute rooms across multiple users. Configure via environment or CLI flags:

- `MATRIX_SEED_USER_COUNT` / `--user-count` to set the number of users.
- `MATRIX_SEED_USER_PREFIX` / `--user-prefix` to control the username prefix when `user-count > 1`.

Example:

```bash
MATRIX_SEED_USER_COUNT=4 MATRIX_SEED_USER_PREFIX=bridge-tester make matrix-seed
# This registers/logs in bridge-tester-01..04 and splits rooms across them
```

Prefer a single command? `make matrix-setup` (or `./scripts/matrix/setup.sh`)
wraps init → up → build → seed and respects the same environment overrides. Pass
`init-only` if you just need to regenerate config/secrets without starting the
stack.

## Manual validation flow (developer-run)

Manual verification uses the existing Flutter shell talking to the seeded homeserver. Codex does **not** execute these steps automatically.

1. Ensure Synapse is running and seeded as described above.
2. Start the Flutter app normally (Chrome/iOS/Android) and point it at `http://localhost:8008`.
3. Log in with the seeded bridge account (defaults: `bridge-tester` / `bridgeTesterPass!`).
4. Confirm success criteria:
   - The room list contains 400 encrypted rooms delivered via the Simplified Sliding Sync endpoint.
   - Room timelines populate immediately and display the seeded `Seed message #XXXX…` texts.
   - Messages decrypt without manual key share prompts (the seeder uploads keys upfront).
   - Sliding Sync diffs continue to stream when navigating between rooms.
5. When you are done, stop the homeserver with `make matrix-down` (or `docker compose … stop matrix`).

## Automated Flutter bridge test (headless)

A headless test lives under `app/test/bridge/` and exercises the existing Flutter↔Rust bridge against the local Synapse without requiring an emulator:

- `test/bridge/sliding_sync_bridge_test.dart` covers login + session restore, Simplified Sliding Sync list pagination, opening a room timeline, streaming new events, and decrypting the seeded ciphertext.
- The test talks to the FRB layer directly; ensure your native library is available for the host platform when running locally (see README’s “Headless bridge integration test”).

Run the test after Synapse has been seeded:

```bash
# from repo root
make flutter-bridge-test
```

By default the test targets `http://127.0.0.1:8008`. You can override homeserver and credentials via env vars like `MESSIE_MATRIX_HOMESERVER`, `MESSIE_MATRIX_USERNAME`, `MESSIE_MATRIX_PASSWORD`, and `MESSIE_BRIDGE_STORE_PATH`. The Make target will build the Rust FFI (release) if needed and set `MESSIE_FFI_LIB_PATH` automatically.

Expected room count: the test reads `scripts/matrix/.state/seed_state.json` and asserts the exact number of seeded rooms. For custom locations or counts, set `MESSIE_SEED_STATE_FILE` or `MESSIE_SEEDED_ROOM_COUNT`.

Recovery key handling: `make matrix-seed` writes a `recovery_key.json` to `scripts/matrix/.state/`. The headless test auto-discovers this path; otherwise set `MESSIE_MATRIX_RECOVERY_FILE` or `MESSIE_MATRIX_RECOVERY_KEY` explicitly.

## Resetting / cleanup

- Stop only the homeserver: `make matrix-down`
- Reset the dataset (keep keys): `rm -rf scripts/matrix/.state`
- Full cleanup (containers/volumes/state): `make matrix-cleanup` (or
  `./scripts/matrix/cleanup.sh`)
- Manual reset alternative: `docker compose -f docker-compose.dev.yml down -v` (removes the `matrix_data` volume). Re-run the init + seed steps afterwards.
- Inspect logs: `docker compose -f docker-compose.dev.yml --profile matrix logs matrix`

## Pairing with other automated flows

For multi-user frontend E2E suites (Playwright, etc.) reuse the same seeded homeserver so Matrix, email, and todo timelines stay consistent. Refer to `frontend/README.md#multi-user-flows` for additional orchestration tips.
