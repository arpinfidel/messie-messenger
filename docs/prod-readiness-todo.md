# Prod Readiness TODO

## Bridge Secrets

- Move WhatsApp bridge appservice secrets out of checked-in config before any shared or production deployment.
- Replace hardcoded values in `infra/mautrix-whatsapp/config.yaml` and `infra/mautrix-whatsapp/registration.yaml` with environment- or secret-managed values.
- Generate unique per-environment values for:
  - appservice `as_token`
  - appservice `hs_token`
  - provisioning `shared_secret`
- Ensure Synapse and `mautrix-whatsapp` consume the same injected registration/token material at deploy time.
- Rotate the current dev tokens before reusing this setup anywhere outside local development.

## Bridge Flow Validation

- Add a release-check/manual-test item for the WhatsApp QR login flow; the pairing-code path has been exercised more heavily, but QR still needs explicit end-to-end validation in FluffyChat.

## Bridge Sync Notifications

- Add explicit handling for bridge history sync / backfill notifications before production rollout.
- Current problem: mautrix-whatsapp forwards backfill as ordinary Matrix timeline traffic, so clients can show noisy per-message notifications for historical messages.
- Product goal: avoid notification spam during bridge bootstrap/catch-up while still allowing normal fresh-message notifications.
- Preferred direction for now: keep upstream bridges unpatched unless necessary; avoid baking long-lived heuristics deep into Fluffy alone.
- Evaluate a Messie-owned bridge activity observer that derives per-login `history_sync` / `backfilling` state from bridge runtime logs and exposes that state to clients.
- If we do the observer, keep it source-agnostic:
  - Docker log tailing can be the first adapter in dev.
  - Do not hardcode Docker assumptions into the core design; we may move away from Docker later.
  - Normalize around `provider`, `user_mxid`, and `login_id`.
- Use existing room-to-login mappings in Fluffy to scope notification suppression/aggregation to the affected bridge login.
- Fallback/client-only idea if observer work is deferred: aggregate or suppress notifications for clearly old messages instead of emitting one notification per historical message.
- Rejected/less preferred ideas:
  - direct mautrix carry patch just to add notification markers
  - product logic driven directly by Docker-specific scripts
  - global suppression for all bridge notifications without login scoping
