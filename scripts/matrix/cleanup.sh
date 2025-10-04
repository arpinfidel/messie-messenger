#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STACK=${STACK:-dev}
COMPOSE_FILE="$ROOT/docker-compose.${STACK}.yml"
PROFILE=(--profile matrix)

printf '==> Stopping Synapse and removing volumes…\n'
docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" down -v

printf '==> Removing matrix seeder state…\n'
# Remove canonical state dir
rm -rf "$ROOT/scripts/matrix/.state"
# Also remove legacy nested path some earlier seeds created
rm -rf "$ROOT/scripts/matrix/scripts/matrix/.state"

printf '\nMatrix environment cleaned.\n'
