#!/bin/sh
set -euo pipefail

# Usage: install_wa_config.sh <CFG_BASENAME>
# - Expects /host to contain the config template and registration.yaml
# - Writes config.yaml + registration.yaml into /data and injects tokens

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <CFG_BASENAME>" >&2
  exit 2
fi

CFG_BASENAME="$1"

if [ ! -f "/host/registration.yaml" ]; then
  echo "Missing /host/registration.yaml" >&2
  exit 2
fi

if [ ! -f "/host/${CFG_BASENAME}" ]; then
  echo "Missing /host/${CFG_BASENAME}" >&2
  exit 2
fi

cp /host/registration.yaml /data/registration.yaml

AS=$(awk '/^as_token:/ {print $2}' /data/registration.yaml)
HS=$(awk '/^hs_token:/ {print $2}' /data/registration.yaml)

cp "/host/${CFG_BASENAME}" /data/config.yaml
sed -i "s/{{AS_TOKEN}}/${AS}/g" /data/config.yaml
sed -i "s/{{HS_TOKEN}}/${HS}/g" /data/config.yaml

chown -R 1337:1337 /data
ls -l /data

