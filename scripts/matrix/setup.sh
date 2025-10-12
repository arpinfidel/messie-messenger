#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STACK=${STACK:-dev}
MODE=${1:-full}

COMPOSE_FILE="$ROOT/docker-compose.${STACK}.yml"
PROFILE=(--profile matrix)
COMPOSE_RUN=(docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" run --rm -T)

export MATRIX_REGISTRATION_SHARED_SECRET=${MATRIX_REGISTRATION_SHARED_SECRET:-dev_matrix_shared_secret}

RUN_INIT=1
RUN_START=1
RUN_SEED=1

case "$MODE" in
  full)
    ;;
  init-only)
    RUN_START=0
    RUN_SEED=0
    ;;
  seed-only)
    RUN_INIT=0
    ;;
  *)
    printf 'Unknown mode: %s\n' "$MODE" >&2
    printf 'Usage: %s [full|init-only|seed-only]\n' "$0" >&2
    exit 2
    ;;
esac

if (( RUN_INIT )); then
  printf '==> Generating Synapse config…\n'
  "${COMPOSE_RUN[@]}" \
    -e MATRIX_REGISTRATION_SHARED_SECRET="$MATRIX_REGISTRATION_SHARED_SECRET" \
    matrix generate

  printf '==> Syncing registration_shared_secret…\n'
  # In this repo, /data/homeserver.yaml may be bind-mounted read-only from
  # infra/matrix/homeserver.dev.yaml. In that case, this write will fail; treat
  # it as best-effort and continue.
  set +e
  docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" run --rm -T \
    --entrypoint python \
    -e MATRIX_REGISTRATION_SHARED_SECRET="$MATRIX_REGISTRATION_SHARED_SECRET" \
    matrix - <<'PY'
import os
from pathlib import Path

path = Path("/data/homeserver.yaml")
secret = os.environ["MATRIX_REGISTRATION_SHARED_SECRET"]
lines = []
found = False
with path.open("r", encoding="utf-8") as fh:
    for line in fh:
        if line.strip().startswith("registration_shared_secret:"):
            lines.append(f"registration_shared_secret: {secret}\n")
            found = True
        else:
            lines.append(line)
if not found:
    lines.append(f"registration_shared_secret: {secret}\n")
path.write_text("".join(lines), encoding="utf-8")
PY
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    printf '   (info) homeserver.yaml appears read-only; skipping secret sync. Ensure it matches infra/matrix/homeserver.dev.yaml\n'
  fi
fi

if (( RUN_START )); then
  printf '==> Starting Synapse containers…\n'
  docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" up -d matrix
fi

if (( RUN_SEED )); then
  printf '==> Running matrix-seed…\n'
  make -C "$ROOT" STACK="$STACK" matrix-seed
fi

if (( RUN_START )); then
  if [[ "${MATRIX_SAS_PEER:-}" == "1" ]]; then
    printf '==> Starting SAS peer helper container…\n'
    make -C "$ROOT" STACK="$STACK" matrix-verify-peer-up
  fi
  printf '\nDone. Homeserver available at %s.\n' "${MATRIX_SERVER_URL:-http://localhost:8008}"
else
  printf '\nDone. Synapse config prepared in matrix_data. Run `make matrix-up` when ready.\n'
fi
