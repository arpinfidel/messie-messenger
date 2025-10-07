#!/usr/bin/env bash
set -euo pipefail

# Synapse (matrix) volume snapshot management
# - Create snapshots of the Synapse data volume
# - List available snapshots
# - Restore from a chosen snapshot
# - Delete a chosen snapshot

ROOT=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STACK=${STACK:-dev}
COMPOSE_FILE="$ROOT/docker-compose.${STACK}.yml"
PROFILE=(--profile matrix)

SNAP_DIR="$ROOT/scripts/matrix/.snapshots"
mkdir -p "$SNAP_DIR"

err() { printf "Error: %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }

# Resolve Compose project name to derive the actual volume name
resolve_project_name() {
  local proj
  if proj=$(docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" ps --format '{{.Project}}' 2>/dev/null | head -n1); then
    if [[ -n "$proj" ]]; then
      echo "$proj"
      return 0
    fi
  fi
  # Fallback to folder basename
  basename "$ROOT"
}

PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$(resolve_project_name)}
VOL_NAME="${PROJECT_NAME}_matrix_data"

require_volume() {
  if ! docker volume inspect "$VOL_NAME" >/dev/null 2>&1; then
    die "Docker volume '$VOL_NAME' not found. Ensure matrix is initialized (make matrix-init or matrix-up)."
  fi
}

list_snapshots() {
  # Portable listing sorted by mtime (newest first)
  # shellcheck disable=SC2012
  if ls -1t "$SNAP_DIR"/*.tar.gz >/dev/null 2>&1; then
    ls -1t "$SNAP_DIR"/*.tar.gz 2>/dev/null | xargs -n1 basename
  fi
}

print_snapshots_with_index() {
  local i=1
  while IFS= read -r f; do
    printf '%2d) %s\n' "$i" "$f"
    i=$((i+1))
  done < <(list_snapshots)
}

choose_snapshot() {
  local count
  mapfile -t SNAPS < <(list_snapshots)
  count=${#SNAPS[@]}
  if (( count == 0 )); then
    die "No snapshots found in $SNAP_DIR"
  fi
  print_snapshots_with_index
  local choice
  while true; do
    read -rp "Select snapshot [1-$count]: " choice || exit 1
    [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Enter a number."; continue; }
    if (( choice >= 1 && choice <= count )); then
      echo "${SNAPS[choice-1]}"
      return 0
    fi
    echo "Out of range."
  done
}

create_snapshot() {
  require_volume
  local label=${1:-}
  if [[ -n "$label" ]]; then
    # sanitize label: lowercase, alnum and dashes/underscores only
    label=$(echo "$label" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+|-+$//g')
    label="-$label"
  fi
  local ts name
  ts=$(date +%Y%m%d-%H%M%S)
  name="synapse-${STACK}-${ts}${label}.tar.gz"
  echo "==> Creating snapshot $name from volume $VOL_NAME"
  docker run --rm \
    -v "$VOL_NAME:/data:ro" \
    -v "$SNAP_DIR:/snapshots" \
    alpine:3.20 sh -lc "tar czf \"/snapshots/$name\" -C /data ."
  echo "Saved: $SNAP_DIR/$name"
}

restore_snapshot() {
  require_volume
  local file=${1:-}
  if [[ -z "$file" ]]; then
    echo "==> Choose a snapshot to restore"
    file=$(choose_snapshot)
  fi
  # Accept bare filename or absolute/relative path within SNAP_DIR
  if [[ -f "$file" ]]; then
    SNAP_FILE="$file"
  else
    SNAP_FILE="$SNAP_DIR/$file"
  fi
  [[ -f "$SNAP_FILE" ]] || die "Snapshot not found: $SNAP_FILE"

  echo "==> Stopping matrix service"
  docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" stop matrix >/dev/null

  echo "==> Restoring snapshot $(basename "$SNAP_FILE") into $VOL_NAME"
  local SNAP_BASE
  SNAP_BASE=$(basename "$SNAP_FILE")
  docker run --rm \
    -e SNAP_BASE="$SNAP_BASE" \
    -v "$VOL_NAME:/data" \
    -v "$SNAP_DIR:/snapshots:ro" \
    alpine:3.20 sh -lc '
      set -euo pipefail;
      cd /data;
      to_remove=$(ls -A || true);
      if [ -n "$to_remove" ]; then
        echo "$to_remove" | xargs rm -rf --;
      fi;
      tar xzf "/snapshots/$SNAP_BASE" -C /data;
    '

  echo "==> Starting matrix service"
  docker compose -f "$COMPOSE_FILE" "${PROFILE[@]}" start matrix >/dev/null
  echo "Restore complete."
}

delete_snapshot() {
  local file=${1:-}
  if [[ -z "$file" ]]; then
    echo "==> Choose a snapshot to delete"
    file=$(choose_snapshot)
  fi
  # Accept bare filename or path
  if [[ -f "$file" ]]; then
    SNAP_FILE="$file"
  else
    SNAP_FILE="$SNAP_DIR/$file"
  fi
  [[ -f "$SNAP_FILE" ]] || die "Snapshot not found: $SNAP_FILE"

  read -rp "Delete $(basename "$SNAP_FILE")? [y/N]: " yn
  case "$yn" in
    [Yy]*) rm -f -- "$SNAP_FILE" && echo "Deleted." ;;
    *) echo "Aborted." ;;
  esac
}

usage() {
  cat <<USAGE
Usage: STACK=dev $0 <command> [args]

Commands:
  create [label]   Create a snapshot (optional label)
  list             List available snapshots
  restore [file]   Restore from snapshot (interactive if omitted)
  delete [file]    Delete a snapshot (interactive if omitted)

Environment:
  STACK=dev|prod   Select docker-compose.<STACK>.yml (default: dev)
USAGE
}

# Interactive menu to choose a subcommand when none is provided
interactive_menu() {
  echo "Synapse snapshots (STACK=$STACK)"
  echo "--------------------------------"
  echo "1) Create snapshot"
  echo "2) List snapshots"
  echo "3) Restore snapshot"
  echo "4) Delete snapshot"
  echo "q) Quit"
  local choice
  while true; do
    read -rp "Select option: " choice || exit 1
    case "$choice" in
      1)
        read -rp "Optional label (enter to skip): " lbl || true
        create_snapshot "${lbl:-}"
        return ;;
      2)
        list_snapshots || true
        return ;;
      3)
        restore_snapshot
        return ;;
      4)
        delete_snapshot
        return ;;
      q|Q)
        echo "Bye"; return ;;
      *)
        echo "Invalid selection." ;;
    esac
  done
}

cmd=${1:-}
case "$cmd" in
  create)
    shift; create_snapshot "${1:-}" ;;
  list)
    list_snapshots ;;
  restore)
    shift; restore_snapshot "${1:-}" ;;
  delete)
    shift; delete_snapshot "${1:-}" ;;
  "")
    interactive_menu ;;
  -h|--help|help)
    usage ;;
  *)
    err "Unknown command: $cmd"; usage; exit 2 ;;
esac
