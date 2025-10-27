#!/usr/bin/env bash
set -euo pipefail

# Setup a project-local Java truststore for Gradle on macOS
#
# Why: Gradle uses the JDK truststore, which often doesn't include your
# corporate proxy's Root CA. That breaks HTTPS to Google Maven with
# PKIX path building failed. This script builds a local truststore from
# your corporate root certificate and configures Gradle to use it.
#
# Usage:
#   scripts/setup-gradle-ssl-macos.sh --file /path/to/corp-root.crt [--password changeit]
#
# Notes:
# - The certificate must be a root CA in PEM/CRT/CER format.
# - No sudo required; this does NOT modify your system JDK.
# - It updates app/android/gradle.properties to point at the truststore.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/app/android"
CERTS_DIR="$ANDROID_DIR/certs"
TRUSTSTORE_PATH="$CERTS_DIR/corp-truststore.jks"
STOREPASS="changeit"
CERT_FILE=""

print_help() {
  cat <<EOF
Usage: $0 --file /path/to/corp-root.crt [--password changeit]

Creates/upgrades a local truststore at:
  $TRUSTSTORE_PATH
and configures Gradle (app/android/gradle.properties) to use it via:
  -Djavax.net.ssl.trustStore=certs/corp-truststore.jks
  -Djavax.net.ssl.trustStorePassword=changeit

Options:
  --file PATH        Path to your corporate Root CA certificate (PEM/CRT/CER)
  --password PASS    Truststore password (default: changeit)
  -h, --help         Show this help

To export the Root CA from macOS Keychain:
  1) Open Keychain Access -> System Roots or System.
  2) Find your corporate proxy Root CA (e.g., Zscaler Root CA).
  3) Right click -> Export... -> .cer (or .pem).
  4) Run this script with --file pointing to that exported file.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      CERT_FILE="${2:-}"
      shift 2
      ;;
    --password)
      STOREPASS="${2:-}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_help
      exit 1
      ;;
  esac
done

if [[ -z "$CERT_FILE" ]]; then
  echo "Error: --file is required (path to corporate Root CA certificate)." >&2
  print_help
  exit 1
fi

if [[ ! -f "$CERT_FILE" ]]; then
  echo "Error: certificate file not found: $CERT_FILE" >&2
  exit 1
fi

mkdir -p "$CERTS_DIR"

# Derive a stable alias from the certificate subject CN or SHA1 if CN missing
ALIAS=""
if command -v openssl >/dev/null 2>&1; then
  CN_LINE=$(openssl x509 -noout -subject -in "$CERT_FILE" 2>/dev/null || true)
  if [[ -n "$CN_LINE" ]]; then
    # subject= /CN=Corp Root CA/... => extract CN
    ALIAS=$(echo "$CN_LINE" | sed -E 's|.*CN=([^,/]+).*|\1|' | tr ' ' '_' | tr -cd '[:alnum:]_\-')
  fi
  if [[ -z "$ALIAS" ]]; then
    ALIAS=$(openssl x509 -noout -fingerprint -sha1 -in "$CERT_FILE" 2>/dev/null | awk -F= '{print $2}' | tr -d ':' )
  fi
fi

if [[ -z "$ALIAS" ]]; then
  # Fallback generic alias
  ALIAS="corp_root_$(date +%s)"
fi

echo "Creating/updating truststore: $TRUSTSTORE_PATH"

# If alias already exists, remove it to ensure idempotence
if [[ -f "$TRUSTSTORE_PATH" ]]; then
  if keytool -list -keystore "$TRUSTSTORE_PATH" -storepass "$STOREPASS" -alias "$ALIAS" >/dev/null 2>&1; then
    echo "Existing alias found; removing before re-import: $ALIAS"
    keytool -delete -alias "$ALIAS" -keystore "$TRUSTSTORE_PATH" -storepass "$STOREPASS"
  fi
fi

# Import certificate
keytool -importcert -noprompt -trustcacerts \
  -alias "$ALIAS" \
  -file "$CERT_FILE" \
  -keystore "$TRUSTSTORE_PATH" \
  -storepass "$STOREPASS"

echo "Imported alias '$ALIAS' into $TRUSTSTORE_PATH"

# Wire Gradle to use this truststore by appending to org.gradle.jvmargs
GRADLE_PROPS="$ANDROID_DIR/gradle.properties"
TRUST_OPTS=("-Djavax.net.ssl.trustStore=certs/corp-truststore.jks" "-Djavax.net.ssl.trustStorePassword=$STOREPASS")

if [[ ! -f "$GRADLE_PROPS" ]]; then
  echo "Creating $GRADLE_PROPS"
  printf 'org.gradle.jvmargs=%s %s\n' "${TRUST_OPTS[0]}" "${TRUST_OPTS[1]}" > "$GRADLE_PROPS"
else
  # Update existing org.gradle.jvmargs preserving current options
  if grep -q '^org\.gradle\.jvmargs=' "$GRADLE_PROPS"; then
    CURRENT=$(grep '^org\.gradle\.jvmargs=' "$GRADLE_PROPS" | sed 's/^org\.gradle\.jvmargs=//')
    for opt in "${TRUST_OPTS[@]}"; do
      if ! grep -q "$opt" <<<"$CURRENT"; then
        CURRENT+=" $opt"
      fi
    done
    # Replace the line
    awk -v repl="$CURRENT" 'BEGIN{printed=0} {if($0 ~ /^org\.gradle\.jvmargs=/ && !printed){print "org.gradle.jvmargs=" repl; printed=1} else if($0 !~ /^org\.gradle\.jvmargs=/){print $0}} END{if(printed==0){print "org.gradle.jvmargs=" repl}}' "$GRADLE_PROPS" > "$GRADLE_PROPS.tmp"
    mv "$GRADLE_PROPS.tmp" "$GRADLE_PROPS"
  else
    echo "Appending org.gradle.jvmargs with truststore options"
    printf '\norg.gradle.jvmargs=%s %s\n' "${TRUST_OPTS[0]}" "${TRUST_OPTS[1]}" >> "$GRADLE_PROPS"
  fi
fi

echo "Done. Next steps:"
echo "  1) Re-run your Gradle/Flutter build."
echo "  2) If it still fails, ensure the certificate is the correct Root CA (not an end-entity cert)."
echo "     You can inspect it with: openssl x509 -in '$CERT_FILE' -noout -text | less"

