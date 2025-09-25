# Local Matrix Homeserver

Messie Messenger ships with an opt-in [Synapse](https://github.com/matrix-org/synapse) container for realistic local testing without depending on a public homeserver.

## Prerequisites

- Docker + Docker Compose v2
- `.env` populated with any non-default ports or credentials you plan to use

## First-time setup

1. Generate configuration and secrets (writes to the `matrix_data` volume):

   ```bash
   make matrix-init
   ```

   Override the shared registration secret by exporting `MATRIX_REGISTRATION_SHARED_SECRET=your-secret` before running the command.
2. Bring the homeserver online:

   ```bash
   make matrix-up
   ```

   The service listens on `http://localhost:8008` by default. Change the external port via `MATRIX_PORT` in `.env` if needed.

## Creating accounts

Use Synapse's helper to provision users via the Makefile wrapper:

```bash
make matrix-register ARGS="-u user-a -p Pass1234 --no-admin"
make matrix-register ARGS="-u user-b -p Pass1234 --no-admin"
```

- Append `--admin` when you need an administrator for provisioning rooms or inspecting server state.
- The wrapper automatically passes the shared secret (`-k ...`) so you do not have to edit `homeserver.yaml` manually.

Once users exist, sign in from the Messie login screen using `http://localhost:8008` as the homeserver URL.

## Stopping and troubleshooting

- Stop only the homeserver: `make matrix-down`
- Start the full stack plus Synapse: `COMPOSE_PROFILES=matrix make up`
- Inspect logs: `docker compose -f docker-compose.dev.yml --profile matrix logs matrix`

If you need a clean slate, remove the volume with `docker volume rm messie-messenger_matrix_data` and repeat the init steps above.

## Pairing with Playwright tests

For multi-user end-to-end flows, keep the homeserver running while you record storage states with Playwright. Refer to `frontend/README.md#multi-user-flows` for the recorder workflow.
