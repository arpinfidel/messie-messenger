# 0004: WhatsApp bridge — one account per Matrix user

Date: 2025-10-11

Status: Accepted

## Context

We want to enforce exactly one WhatsApp account per Matrix user when using the `mautrix-whatsapp` bridge. DM-based bot logins are undesirable (confusing UX, bypassing backend quotas), and provisioning is implemented via the bridge’s v3 API behind our backend.

Observations:
- The bridge checks per-user permissions even for provisioning endpoints authenticated via the shared secret. Users with only `commands` permission receive `M_FORBIDDEN`.
- Our backend already enforces `max_accounts = 1` by calling `/logins` before starting a new login.

## Decision

1) Allow logins for our local domain via bridge permissions:

```
bridge.permissions:
  "messie.localhost": user
  "@bridge-admin:messie.localhost": admin
```

2) Keep `provisioning.allow_matrix_auth: true` (naming is confusing; in our setup we still authenticate provisioning requests with the shared secret from the backend, and include `?user_id=<mxid>`). The backend continues to enforce quota.

3) Block direct DMs to the bridge bot at the homeserver with a Synapse spam‑checker module:
- Reject invites to `@whatsappbot:messie.localhost` from non-admins.
- Reject creating DM rooms that target the bot by non-admins.
- As a guardrail, reject sending messages in pre-existing 1:1 rooms with the bot by non-admins.

## Implementation

- Added Synapse module at `infra/matrix/modules/block_bot_dms.py` and configured it via `infra/matrix/conf.d/modules.yaml`.
- Mounted custom modules in the Synapse container at `/data/custom_modules` and added it to `python_paths`.
- Updated `infra/mautrix-whatsapp/config.yaml` permissions to grant `user` for the local domain.

Compose wiring (matrix service):

```
volumes:
  - ./infra/matrix/conf.d:/etc/synapse/conf.d:ro
  - ./infra/matrix/modules:/data/custom_modules:ro
  - ./infra/mautrix-whatsapp/registration.yaml:/data/appservices/whatsapp-registration.yaml:ro
```

Synapse module config:

```
python_paths:
  - /data/custom_modules

modules:
  - module: block_bot_dms.BlockBotDMs
    config:
      bot_mxid: "@whatsappbot:messie.localhost"
      admins:
        - "@bridge-admin:messie.localhost"
```

## Consequences

- Users cannot DM the bot to start login; only provisioning (via backend) is available.
- Backend remains the enforcement point for one-account-per-user by rejecting new logins when `/logins` >= 1.
- Existing DMs (if any) won’t be usable due to the message-level block, though they may remain visible.

## Rollout

1) `make matrix-down && make matrix-up matrix` to restart Synapse and load the module.
2) `make bridge-wa-install-config-safe && make bridge-wa-down && make bridge-wa-up` to apply the bridge config changes.
3) Verify:
   - Inviting the bot from a non-admin → rejected.
   - Provisioning `/whoami` for a normal user returns success (domain permission= `user`).
   - Backend rejects additional logins beyond one.

