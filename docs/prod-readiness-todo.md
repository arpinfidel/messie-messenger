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
