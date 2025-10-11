# WhatsApp Bridge (mautrix-whatsapp)

This repo ships a development-ready mautrix-whatsapp appservice wired to the local Synapse from `docs/local-matrix.md`. It keeps portal rooms private (no public aliases) and disables federation for isolation.

## Prerequisites

- Synapse (profile `matrix`) prepared per `docs/local-matrix.md`
- Docker + Docker Compose v2

## One-time setup

1. Generate the appservice registration file (creates tokens and IDs):

   ```bash
   make bridge-wa-generate-registration
   ```

   This writes `infra/mautrix-whatsapp/registration.yaml` and uses `infra/mautrix-whatsapp/config.yaml`.
   If Synapse was already running, restart it to pick up the new registration.

2. Install config into the bridge volume (injects tokens from registration):

   ```bash
   make bridge-wa-install-config-safe
   ```

   This writes `/data/config.yaml` and `/data/registration.yaml` inside the
   `whatsapp_data` volume and injects `as_token`/`hs_token` so the bridge and
   Synapse stay in sync.

3. Start Synapse + the WhatsApp bridge:

   ```bash
   make bridge-wa-up
   ```

   The bridge does not expose ports on the host. Synapse calls it internally at
   `http://mautrix-whatsapp:29319`. A provisioning API is reachable only from other
   containers in the Compose network (e.g., the backend) and is not published.

4. Inspect logs:

   ```bash
   make bridge-wa-logs
   ```

## Configuration overview

- `infra/matrix/conf.d/appservices.yaml` makes Synapse load appservice registrations from `/data/appservices/*`.
- `docker-compose.dev.yml` mounts the WhatsApp registration at `/data/appservices/whatsapp-registration.yaml` inside Synapse.
- `infra/mautrix-whatsapp/config.yaml` is the bridge config used for dev:
  - Homeserver at `http://matrix:8008` with domain `messie.localhost` (change if needed).
  - Appservice listens on `0.0.0.0:29319` inside the container only.
  - `matrix.federate_rooms: false` ensures rooms are not federated by default.
  - No public portal aliases are created; portals remain invite-only by default.
  - Permissions use a domain key, not `@*:`. Example (DM login disabled, commands only):

    ```yaml
    bridge:
      permissions:
        "messie.localhost": commands
        "@bridge-tester:messie.localhost": admin
    ```

  - History sync + personal space (recommended):

    ```yaml
    bridge:
      personal_filtering_spaces: true
    network:
      history_sync:
        max_initial_conversations: -1
        request_full_sync: true
    ```

  Apply changes with `make bridge-wa-install-config-safe` and restart the bridge.

  - Provisioning (admin) API secret:

    The minimal config sets `provisioning.shared_secret` for local development.
    Rotate this value for your environment before exposing the API beyond the
    internal Docker network.

## Daily workflow

1. If you regenerated registration tokens, sync host ⇄ volume and restart:

   ```bash
   make bridge-wa-sync-registration   # copies volume /data/registration.yaml → host
   make matrix-down && make matrix-up matrix
   make bridge-wa-install-config-safe # inject tokens into /data/config.yaml
   make bridge-wa-down && make bridge-wa-up
   ```

2. Log in via DM to the bot:

   - Start a DM with `@whatsappbot:messie.localhost`
   - Send: `login`
   - Follow the QR flow in WhatsApp → Linked devices

3. Import chats:

   - With history sync enabled, portals are created automatically. Otherwise use:
     `sync contacts` and `sync groups` in the bot DM, or `start-chat +15551234567` to create one DM immediately.

## Cleanup

- Stop only the bridge: `make bridge-wa-down`
- Remove bridge data: `make bridge-wa-clean`

## Provisioning (gateway → bridge)

The backend exposes provider-agnostic provisioning endpoints and proxies them to the bridge’s v3 API with `Authorization: Bearer <shared_secret>` and `?user_id=<mxid>`.

- GET `/bridge/provision/v3/login/flows?provider=whatsapp` → `{ flows: [...] }`
- POST `/bridge/provision/v3/login/start/{flow}?provider=whatsapp` → returns a LoginStep (e.g., `display_and_wait` with QR data)
- POST `/bridge/provision/v3/login/step/{process_id}/{step_id}/{action}?provider=whatsapp` → returns next LoginStep
- GET `/bridge/provision/v3/whoami?provider=whatsapp` → includes `logins[]` with states
- POST `/bridge/provision/v3/logout/{login_id}?provider=whatsapp` → `200/204` (use `all` to log out all)

Notes

- The bridge requires shared-secret auth + explicit `user_id` (MXID) for provisioning.
- DM-based login is usually disabled via permissions; pairing happens via the backend gateway.

## Troubleshooting

- 401/403 “as_token not accepted” on startup
  - Ensure Synapse actually loads the registration: `/etc/synapse/conf.d/appservices.yaml` should contain
    `app_service_config_files: [/data/appservices/whatsapp-registration.yaml]`. If your HS ignores conf.d, append the same entry to `/data/homeserver.yaml` and restart Synapse.
  - Keep tokens in sync: run `make bridge-wa-install-config-safe` after changing registration and restart the bridge.

- Bridge leaves DM with “You don’t have permission to interact with this bridge”
  - Use domain-level permissions (key is the domain, not `@*:`). Add explicit admin MXIDs for trusted users.

- Bind mounts cause read-only errors
  - The bridge writes to `/data`. Use the provided `bridge-wa-install-config-safe` target which copies files into the named volume and sets ownership to uid 1337.

- No rooms after login
  - Enable `network.history_sync` and `bridge.personal_filtering_spaces`, then restart.
  - Accept invites for the space and portals in your Matrix client (auto-join can be implemented on the client side later).
