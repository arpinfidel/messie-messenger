DATABASE_URL = postgres://user:password@localhost:5432/todo_db?sslmode=disable

ARGS = $(filter-out $@,$(MAKECMDGOALS))

MATRIX_SERVER_URL ?= http://localhost:8008
MATRIX_SERVER_NAME ?= messie.localhost
MATRIX_REGISTRATION_SHARED_SECRET ?= dev_matrix_shared_secret
MATRIX_REPORT_STATS ?= no
MATRIX_ENABLE_REGISTRATION ?= true

MATRIX_SEED_ADMIN_USER ?= bridge-admin
MATRIX_SEED_ADMIN_PASSWORD ?= bridgeAdminPass!
MATRIX_SEED_USER ?= bridge-tester
MATRIX_SEED_PASSWORD ?= bridgeTesterPass!
MATRIX_SEED_USER_COUNT ?= 3
MATRIX_SEED_USER_PREFIX ?= bridge-tester
MATRIX_SEED_ROOM_COUNT ?= 400
MATRIX_SEED_SERVER_URL ?= $(MATRIX_SERVER_URL)
MATRIX_SEED_DEVICE_ID ?= MESSIE_BRIDGE_SEEDER
MATRIX_SEED_DEVICE_NAME ?= Messie\ Seeder
MATRIX_SEED_STATE_MOUNT ?= scripts/matrix/.state
MATRIX_SEED_STATE_DIR ?= scripts/matrix/.state
# Absolute path used by the local seeder to avoid nested prefixes
SEED_STATE_DIR_ABS := $(CURDIR)/$(MATRIX_SEED_STATE_DIR)

# -------- v2 test env (defaults) --------
# These feed the Rust v2 + Dart tests. Override as needed when running against
# a different homeserver/user.
export MESSIE_MATRIX_HOMESERVER ?= $(MATRIX_SERVER_URL)
export MESSIE_MATRIX_USERNAME  ?= $(MATRIX_SEED_USER)
export MESSIE_MATRIX_PASSWORD  ?= $(MATRIX_SEED_PASSWORD)
export MESSIE_MATRIX_STORE_BASE ?= $(CURDIR)/.messie_store_v2
export MESSIE_GROUP_ROOM ?= !WHJjpbPRQHMZAjbIAM:messie.localhost
export MESSIE_DM_ROOM ?= !lOCTzMDIPbNkteJDKI:messie.localhost
export MESSIE_SENDER_USERNAME ?= bridge-tester-2
export MESSIE_SENDER_PASSWORD ?= bridgeTesterPass!

# Backend API base URL for Flutter (used via --dart-define)
# For Android emulator, 10.0.2.2 points to host loopback. Override for iOS/desktop if needed.
APP_API_BASE_URL ?= http://10.0.2.2:8080/api/v1
# Default Rust log level for the native library (override per-invocation as needed)
RUST_LOG ?= messie_matrix=debug

STACK ?= dev
COMPOSE = docker compose -f docker-compose.$(STACK).yml
COMPOSE_MATRIX = $(COMPOSE) --profile matrix

.PHONY: up down build ps logs sh

.PHONY: jira-pull jira-push

up:
	$(COMPOSE) up -d $(ARGS)

down:
	$(COMPOSE) down $(ARGS)

up-build:
	$(COMPOSE) up --build -d $(ARGS)

restart:
	$(COMPOSE) restart $(ARGS)

build:
	$(COMPOSE) build $(ARGS)

rebuild:
	$(COMPOSE) up --build -d $(ARGS)

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f $(ARGS)

sh:
	$(COMPOSE) exec $(firstword $(ARGS)) sh

jira-pull:
	@echo "Syncing Jira issues to YAML..."
	cd backend && go run ./cmd/jira-sync pull

jira-push:
	@echo "Pushing local YAML changes to Jira (then refreshing YAML)..."
	cd backend && go run ./cmd/jira-sync push

.PHONY: test-e2e-codegen matrix-init matrix-up matrix-down matrix-register matrix-seed matrix-setup matrix-cleanup flutter-bridge-build-lib flutter-bridge-test bridge-generate bridge-build-android bridge-build-ios flutter-run-android flutter-run-ios
.PHONY: v2-help \
        v2-build-ffi-host \
        v2-flutter-login-sync v2-flutter-backup v2-flutter-all \
        v2-rust-test v2-rust-test-ignored matrix-latest-event-test

flutter-run-android:
	# Ensure Rust Android FFI is built and copied into app/android
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d emulator-5554 --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-run-ios:
	# Ensure Rust iOS/macOS libraries are built (if needed for your flow)
	make bridge-build-ios
	cd app && flutter pub get
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d ios --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

# -------- Flutter profiling helpers --------
.PHONY: profile-help \
        flutter-profile-android flutter-profile-android-trace flutter-profile-android-sksl \
        flutter-build-android-sksl \
        flutter-profile-ios flutter-profile-ios-trace flutter-profile-ios-sksl \
        flutter-build-ios-sksl \
        flutter-build-android flutter-build-android-split flutter-install-android flutter-install-android-abi flutter-run-android-release

# Default devices (override: make flutter-profile-android DEVICE=<id>)
DEVICE ?= emulator-5554
# Default ABI for split APK install (most devices): arm64-v8a
ABI ?= arm64-v8a
IOS_DEVICE ?= ios
# Path to a saved SkSL warmup file exported from DevTools Performance (override as needed)
SKSL_PATH ?= app/flutter_sksl.json

profile-help:
	@echo "Profiling targets:"
	@echo "  make flutter-profile-android            # Run on Android in --profile (press 'P' to show overlay)"
	@echo "  make flutter-profile-android-trace      # Run with --trace-startup and --trace-skia (diagnose jank)"
	@echo "  make flutter-profile-android-sksl       # Run with --cache-sksl to capture SkSL (reduce shader jank)"
	@echo "  make flutter-build-android-sksl         # Build APK bundling SKSL_PATH=$(SKSL_PATH)"
	@echo "  make flutter-profile-ios                # Run on iOS in --profile (press 'P' to show overlay)"
	@echo "  make flutter-profile-ios-trace          # Run with --trace-startup and --trace-skia (diagnose jank)"
	@echo "  make flutter-profile-ios-sksl           # Run with --cache-sksl to capture SkSL (reduce shader jank)"
	@echo "  make flutter-build-ios-sksl             # Build iOS app bundling SKSL_PATH=$(SKSL_PATH)"
	@echo "Notes:"
	@echo "  - What is TRACE? Adds startup + Skia GPU timeline events for DevTools."
	@echo "    Use *trace* to FIND the cause of jank (UI vs GPU)."
	@echo "    Steps: run trace target → open DevTools Performance → Record 10s → Stop → inspect long frames."
	@echo "  - What is SKSL? Skia shader compile warmup."
	@echo "    Use *sksl* to REDUCE first-run GPU stutters after you've seen GPU graph spikes."
	@echo "    Steps: run sksl target → open DevTools Performance → Export SkSL → save to $(SKSL_PATH) → build with *build-*-sksl*."
	@echo "  - Overlay: Press 'P' in the 'flutter run' terminal to toggle the performance overlay (top=UI, bottom=GPU)."
	@echo "  - DevTools: A link appears in 'flutter run' output; open it → Performance tab."

flutter-profile-android:
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(DEVICE) --profile --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-profile-android-trace:
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(DEVICE) --profile --trace-startup --trace-skia --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-profile-android-sksl:
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(DEVICE) --profile --cache-sksl --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-build-android-sksl:
	@echo "Building Android APK with SkSL warmup from $(SKSL_PATH)"
	cd app && flutter build apk --bundle-sksl-path ../$(SKSL_PATH)

# -------- Android release builds (APK) --------
flutter-build-android:
	# Ensure Rust Android FFI is built and copied into app/android
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter build apk --release --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-build-android-split:
	# Split per ABI (smaller APKs). Use flutter-install-android-abi to install.
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter build apk --release --split-per-abi --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-run-android-release:
	# Directly run on a connected device in --release
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(DEVICE) --release --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-install-android:
	# Install the universal release APK built by flutter-build-android
	adb install -r build/app/outputs/flutter-apk/app-release.apk

flutter-install-android-abi:
	# Install a split APK for a specific ABI (default: $(ABI))
	adb install -r build/app/outputs/flutter-apk/app-$(ABI)-release.apk

flutter-profile-ios:
	make bridge-build-ios
	cd app && flutter pub get
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(IOS_DEVICE) --profile --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-profile-ios-trace:
	make bridge-build-ios
	cd app && flutter pub get
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(IOS_DEVICE) --profile --trace-startup --trace-skia --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-profile-ios-sksl:
	make bridge-build-ios
	cd app && flutter pub get
	cd app && RUST_LOG="$(RUST_LOG)" flutter run -d $(IOS_DEVICE) --profile --cache-sksl --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)

flutter-build-ios-sksl:
	@echo "Building iOS app with SkSL warmup from $(SKSL_PATH)"
	cd app && flutter build ios --no-codesign --bundle-sksl-path ../$(SKSL_PATH)

test-e2e-codegen:
	cd frontend && npm run test:e2e:codegen

matrix-setup:
	STACK=$(STACK) ./scripts/matrix/setup.sh

matrix-cleanup:
	STACK=$(STACK) ./scripts/matrix/cleanup.sh

matrix-init:
	STACK=$(STACK) ./scripts/matrix/setup.sh init-only

matrix-up:
	$(COMPOSE_MATRIX) up -d $(if $(ARGS),$(ARGS),matrix)

matrix-down:
	$(COMPOSE_MATRIX) stop $(if $(ARGS),$(ARGS),matrix)


# -------- WhatsApp bridge (mautrix-whatsapp) --------
.PHONY: bridge-wa-generate-registration bridge-wa-install-config bridge-wa-sync-registration bridge-wa-up bridge-wa-down bridge-wa-logs bridge-wa-clean
 .PHONY: bridge-wa-install-config-safe

bridge-wa-generate-registration:
	@echo "Generating mautrix-whatsapp appservice registration..."
	@mkdir -p infra/mautrix-whatsapp
	# The container entrypoint supports registration generation flags.
	docker run --rm \
	  -v $(CURDIR)/infra/mautrix-whatsapp:/data \
	  dock.mau.dev/mautrix/whatsapp:latest \
	  mautrix-whatsapp --generate-registration --config /data/config.yaml --registration /data/registration.yaml
	@echo "Wrote registration to infra/mautrix-whatsapp/registration.yaml"
	@echo "Note: Restart Synapse if it was already running to pick up the registration."

bridge-wa-install-config:
	@echo "Installing WhatsApp bridge config and registration into Docker volume..."
	@vol=$$(basename $$(pwd))_whatsapp_data; \
	CFG=infra/mautrix-whatsapp/config.yaml; \
	if [ ! -f infra/mautrix-whatsapp/registration.yaml ]; then \
	  echo "Missing infra/mautrix-whatsapp/registration.yaml. Run: make bridge-wa-generate-registration"; exit 2; \
	fi; \
	docker run --rm -v $$vol:/data -v $(CURDIR)/infra/mautrix-whatsapp:/host alpine:3.20 \
	  sh -lc '
	    set -e;
	    cp /host/registration.yaml /data/registration.yaml;
	    AS=$$(awk '\''/^as_token:/ {print $$2}'\'' /data/registration.yaml);
	    HS=$$(awk '\''/^hs_token:/ {print $$2}'\'' /data/registration.yaml);
	    cp /host/$$(basename $$CFG) /data/config.yaml;
	    sed -i "s/{{AS_TOKEN}}/$$AS/g" /data/config.yaml;
	    sed -i "s/{{HS_TOKEN}}/$$HS/g" /data/config.yaml;
	    chown -R 1337:1337 /data;
	    echo "Tokens injected into config:";
	    grep -n "as_token\|hs_token" -n /data/config.yaml || true;
	    ls -l /data;
	  '; \
	echo "Installed to volume $$vol:/data"

bridge-wa-sync-registration:
	@set -e; \
	  echo "Regenerating registration from current volume config and syncing to host..."; \
	  vol=$$(basename $$(pwd))_whatsapp_data; \
	  docker run --rm -v $$vol:/data dock.mau.dev/mautrix/whatsapp:latest \
	    mautrix-whatsapp --generate-registration --config /data/config.yaml --registration /data/registration.yaml; \
	  docker run --rm -v $$vol:/data -v $(CURDIR)/infra/mautrix-whatsapp:/host alpine:3.20 \
	    sh -c "cp /data/registration.yaml /host/registration.yaml && ls -l /host/registration.yaml"; \
	  echo "Registration synchronized. Restart Synapse if running: make matrix-down && make matrix-up matrix"

bridge-wa-up:
	@echo "Starting Synapse + WhatsApp bridge (mautrix-whatsapp) ..."
	@if [ ! -f infra/mautrix-whatsapp/registration.yaml ]; then \
	  echo "Missing registration.yaml. Run: make bridge-wa-generate-registration"; \
	  exit 2; \
	fi
	@echo "Tip: If first run, pre-install config into volume: make bridge-wa-install-config"
	$(COMPOSE_MATRIX) up -d matrix mautrix-whatsapp

bridge-wa-down:
	@echo "Stopping WhatsApp bridge (leaves Synapse running) ..."
	$(COMPOSE_MATRIX) stop mautrix-whatsapp

bridge-wa-logs:
	$(COMPOSE_MATRIX) logs -f mautrix-whatsapp

bridge-wa-clean:
	@echo "Removing WhatsApp bridge data volume..."
	$(COMPOSE) down -v mautrix-whatsapp || true
	docker volume rm $$(basename $$(pwd))_whatsapp_data 2>/dev/null || true

# Safe installer that avoids complex quoting. Prefer this if the other target fails.
bridge-wa-install-config-safe:
	@echo "Installing WhatsApp bridge config and registration into Docker volume (safe)..."
	@vol=$$(basename $$(pwd))_whatsapp_data; \
	CFG=infra/mautrix-whatsapp/config.yaml; \
	if [ ! -f infra/mautrix-whatsapp/registration.yaml ]; then \
	  echo "Missing infra/mautrix-whatsapp/registration.yaml. Run: make bridge-wa-generate-registration"; exit 2; \
	fi; \
	CFG_BASE=$$(basename $$CFG); \
	docker run --rm \
	  -v $$vol:/data \
	  -v $(CURDIR)/infra/mautrix-whatsapp:/host:ro \
	  -v $(CURDIR)/scripts/matrix:/scripts:ro \
	  alpine:3.20 \
	  sh /scripts/install_wa_config.sh $$CFG_BASE; \
	echo "Installed to volume $$vol:/data"


# -------- Matrix snapshots --------
.PHONY: matrix-snapshot matrix-snapshot-create matrix-snapshot-list matrix-snapshot-restore matrix-snapshot-delete

matrix-snapshot:
	STACK=$(STACK) bash ./scripts/matrix/snapshots.sh

matrix-snapshot-create:
	STACK=$(STACK) bash ./scripts/matrix/snapshots.sh create $(ARGS)

matrix-snapshot-list:
	bash ./scripts/matrix/snapshots.sh list

matrix-snapshot-restore:
	STACK=$(STACK) bash ./scripts/matrix/snapshots.sh restore $(ARGS)

matrix-snapshot-delete:
	bash ./scripts/matrix/snapshots.sh delete $(ARGS)

# Force Synapse to regenerate /data/homeserver.yaml by deleting it from the volume.
.PHONY: matrix-reset-config
matrix-reset-config:
	@echo "Removing /data/homeserver.yaml from matrix_data volume to force regen..."
	@vol=$$(basename $$(pwd))_matrix_data; \
	docker run --rm -v $$vol:/data alpine:3.20 sh -lc 'rm -f /data/homeserver.yaml && echo "Deleted /data/homeserver.yaml"'

matrix-register:
	@if [ -z "$(ARGS)" ]; then \
		echo "Usage: make matrix-register ARGS='-u user-a -p passw0rd --admin'"; \
		exit 1; \
	fi
	$(COMPOSE_MATRIX) exec matrix register_new_matrix_user $(ARGS) -k $(MATRIX_REGISTRATION_SHARED_SECRET) $(MATRIX_SERVER_URL)

matrix-seed:
	@echo "Seeding Synapse with encrypted sliding-sync dataset..."
	@mkdir -p $(SEED_STATE_DIR_ABS)
	npm --prefix scripts/matrix install --no-audit --no-fund >/dev/null
		npm --prefix scripts/matrix run --silent seed -- \
			--server-url "$(MATRIX_SEED_SERVER_URL)" \
			--server-name "$(MATRIX_SERVER_NAME)" \
			--shared-secret "$(MATRIX_REGISTRATION_SHARED_SECRET)" \
			--admin-username "$(MATRIX_SEED_ADMIN_USER)" \
			--admin-password "$(MATRIX_SEED_ADMIN_PASSWORD)" \
			--user-username "$(MATRIX_SEED_USER)" \
			--user-password "$(MATRIX_SEED_PASSWORD)" \
			--user-count "$(MATRIX_SEED_USER_COUNT)" \
			--user-prefix "$(MATRIX_SEED_USER_PREFIX)" \
			--room-count "$(MATRIX_SEED_ROOM_COUNT)" \
matrix-healthcheck:
	@echo "Healthchecking Simplified Sliding Sync endpoint..."
	npm --prefix scripts/matrix run --silent healthcheck -- \
	  --server-url "$(MATRIX_SEED_SERVER_URL)"

matrix-verify-peer:
	@echo "Starting SAS peer helper (matrix-js-sdk)"
	npm --prefix scripts/matrix run --silent verify-peer -- \
		--server-url "$(MATRIX_SEED_SERVER_URL)" \
		--username "$(MATRIX_SEED_USER)" \
		--password "$(MATRIX_SEED_PASSWORD)" \
		--device-name "Messie SAS Peer"

matrix-verify-peer-image:
	@echo "Building SAS peer helper Docker image"
	docker build -t messie-matrix-peer:latest scripts/matrix

matrix-verify-peer-docker: matrix-verify-peer-image
	@echo "Running SAS peer helper in Docker"
	# Map host loopback for Docker-based peer
	SERVER_URL=$(MATRIX_SEED_SERVER_URL); \
	if echo "$$SERVER_URL" | grep -Eq "127.0.0.1|localhost"; then \
	  SERVER_URL=$$(echo "$$SERVER_URL" | sed -E 's/127\.0\.0\.1|localhost/host.docker.internal/g'); \
	fi; \
	# Ensure predictable container name and clean previous instance
	docker rm -f messie-matrix-peer >/dev/null 2>&1 || true; \
	docker run --rm --name messie-matrix-peer --network host -v $(CURDIR)/scripts/matrix/scripts/matrix/.state:/state:ro messie-matrix-peer:latest \
	  --server-url "$$SERVER_URL" \
	  --username "$(MATRIX_SEED_USER)" \
	  --password "$(MATRIX_SEED_PASSWORD)" \
	  --device-name "Messie SAS Peer"

matrix-verify-peer-up: matrix-verify-peer-image
	@echo "Starting SAS peer helper container (detached)"
	SERVER_URL=$(MATRIX_SEED_SERVER_URL); \
	if echo "$$SERVER_URL" | grep -Eq "127.0.0.1|localhost"; then \
	  SERVER_URL=$$(echo "$$SERVER_URL" | sed -E 's/127\.0\.0\.1|localhost/host.docker.internal/g'); \
	fi; \
	docker rm -f messie-matrix-peer >/dev/null 2>&1 || true; \
	docker run -d --name messie-matrix-peer --network host --restart unless-stopped \
	  -v $(CURDIR)/scripts/matrix/scripts/matrix/.state:/state:ro \
	  messie-matrix-peer:latest \
	  --server-url "$$SERVER_URL" \
	  --username "$(MATRIX_SEED_USER)" \
	  --password "$(MATRIX_SEED_PASSWORD)" \
	  --device-name "Messie SAS Peer" >/dev/null

matrix-token:
	@echo "Generating access token file for seeded user (to avoid login 429s)"
	npm --prefix scripts/matrix run --silent token -- \
	  --server-url "$(MATRIX_SEED_SERVER_URL)" \
	  --username "$(MATRIX_SEED_USER)" \
	  --password "$(MATRIX_SEED_PASSWORD)" \
	  --device-id "MESSIE_SAS_PEER" \
	  --device-name "Messie SAS Peer" \
	  --state-dir "$(SEED_STATE_DIR_ABS)"

matrix-verify-peer-down:
	@echo "Stopping SAS peer helper container"
	docker rm -f messie-matrix-peer >/dev/null 2>&1 || true

# -------- Flutter <-> Rust bridge (headless) --------
# Derive host-specific lib extension for the Rust FFI
UNAME_S := $(shell uname -s)
FFI_EXT := $(if $(filter $(UNAME_S),Darwin),dylib,so)
FFI_LIB := core/target/release/libmessie_ffi.$(FFI_EXT)

# Build the Rust FFI library in release mode
flutter-bridge-build-lib:
	cd core && cargo build --release

# Run the headless Flutter bridge test against local Synapse.
# Honors env overrides like MESSIE_MATRIX_HOMESERVER, MESSIE_MATRIX_USERNAME, etc.
flutter-bridge-test: flutter-bridge-build-lib
	cd app && flutter pub get
	cd app && RUST_LOG="$(RUST_LOG)" MESSIE_FFI_LIB_PATH=../$(FFI_LIB) MESSIE_SEED_STATE_FILE=$(SEED_STATE_DIR_ABS)/seed_state.json flutter test test/bridge/sliding_sync_bridge_test.dart
	# Headless bridge test (sliding sync)

# Run the v1 bridge unread-counts fallback test which uses the CS API endpoint
# to fetch `/_matrix/client/v3/rooms/{roomId}/unread_notifications`. This test
# runs alongside Sliding Sync and uses a persisted sender token to avoid 429s.
.PHONY: flutter-bridge-unread
flutter-bridge-unread: flutter-bridge-build-lib
	cd app && flutter pub get
	cd app && \
	  RUST_LOG="$(RUST_LOG)" \
	  MESSIE_FFI_LIB_PATH=../$(FFI_LIB) \
	  flutter test test/bridge/unread_notifications_bridge_test.dart test/bridge/v1_counts_baseline_test.dart

.PHONY: flutter-bridge-all
flutter-bridge-all: flutter-bridge-build-lib
	cd app && flutter pub get
	cd app && \
	  RUST_LOG="$(RUST_LOG)" \
	  MESSIE_FFI_LIB_PATH=../$(FFI_LIB) \
	flutter test test/bridge

# -------- Headless Rust matrix tests --------
# Run the latest-event headless test (ignored by default). Requires env vars:
#  - MESSIE_MATRIX_HOMESERVER
#  - MESSIE_MATRIX_USERNAME
#  - MESSIE_MATRIX_PASSWORD
.PHONY: matrix-latest-event-test
matrix-latest-event-test:
	cd core && \
	  RUST_LOG="$(RUST_LOG)" \
	  cargo test --test latest_event -- --nocapture --ignored


# swallow extra targets so make doesn’t complain or rerun them
%:
	@:

psql:
	@echo "Connecting to PostgreSQL database..."
	$(COMPOSE) exec -it postgres psql -U user -d todo_db

gen-fe:
	@echo "Generating frontend API client..."
	cd frontend && npx openapi-generator-cli generate -i ../docs/openapi.yaml -g typescript-fetch -o src/api/generated
	cd frontend && npx prettier --write src/api/generated

gen-be:
	@echo "Generating backend API server stubs..."
	cd backend && go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen -package generated -generate types,chi-server -o api/generated/todo_api.go ../docs/openapi.yaml

gen: gen-fe gen-be
	@echo "Code generation complete."

# (removed) client codegen targets for mautrix; sticking to manual adapter for now

# ------- Bridge Provisioning quick tests (dev) -------
.PHONY: bridge-wa-provision-test-start bridge-wa-provision-test-list bridge-wa-provision-test-unlink
WA_BRIDGE_URL ?= http://mautrix-whatsapp:29319
WA_PROV_SECRET ?= TqVJ7k4v2YcZp3xJw9Lm6sAbN2qR8fH5dC1eG7yK0mP4rU6t
WA_PROVISION_USER ?= $(MATRIX_SEED_ADMIN_USER)

bridge-wa-provision-test-start:
	@echo "Starting WA QR login via provisioning v3..."
	$(COMPOSE_MATRIX) exec -T mautrix-whatsapp sh -lc "wget -qO- --header 'Authorization: Bearer $(WA_PROV_SECRET)' --header 'Content-Type: application/json' --post-data='{}' \
	  '$(WA_BRIDGE_URL)/_matrix/provision/v3/login/start/qr?user_id=@$(WA_PROVISION_USER):$(MATRIX_SERVER_NAME)'" | jq .

bridge-wa-provision-test-list:
	@echo "Listing WA logins (IDs) via provisioning v3..."
	$(COMPOSE_MATRIX) exec -T mautrix-whatsapp sh -lc "wget -qO- --header 'Authorization: Bearer $(WA_PROV_SECRET)' \
	  '$(WA_BRIDGE_URL)/_matrix/provision/v3/logins?user_id=@$(WA_PROVISION_USER):$(MATRIX_SERVER_NAME)'" | jq .

.PHONY: bridge-wa-provision-test-whoami bridge-wa-provision-test-flows
bridge-wa-provision-test-whoami:
	@echo "Whoami (details + states) via provisioning v3..."
	$(COMPOSE_MATRIX) exec -T mautrix-whatsapp sh -lc "wget -qO- --header 'Authorization: Bearer $(WA_PROV_SECRET)' \
	  '$(WA_BRIDGE_URL)/_matrix/provision/v3/whoami?user_id=@$(WA_PROVISION_USER):$(MATRIX_SERVER_NAME)'" | jq .

bridge-wa-provision-test-flows:
	@echo "Login flows via provisioning v3..."
	$(COMPOSE_MATRIX) exec -T mautrix-whatsapp sh -lc "wget -qO- --header 'Authorization: Bearer $(WA_PROV_SECRET)' \
	  '$(WA_BRIDGE_URL)/_matrix/provision/v3/login/flows?user_id=@$(WA_PROVISION_USER):$(MATRIX_SERVER_NAME)'" | jq .

bridge-wa-provision-test-unlink:
	@echo "Logging out WA session via provisioning v3... SESSION_ID=<id> make bridge-wa-provision-test-unlink"
	$(COMPOSE_MATRIX) exec -T mautrix-whatsapp sh -lc "wget -qO- --header 'Authorization: Bearer $(WA_PROV_SECRET)' --post-data='' \
	  '$(WA_BRIDGE_URL)/_matrix/provision/v3/logout/$(SESSION_ID)?user_id=@$(WA_PROVISION_USER):$(MATRIX_SERVER_NAME)'" | jq .

# Generate Flutter (Dart) API client from OpenAPI
.PHONY: gen-app
gen-app:
	@echo "Generating Flutter (Dart) API client as a standalone package..."
	mkdir -p packages
	cd frontend && npx openapi-generator-cli generate -i ../docs/openapi.yaml -g dart-dio -o ../packages/messie_api --additional-properties=pubName=messie_api,pubLibrary=messie_api
	cd packages/messie_api && flutter pub get && dart run build_runner build --delete-conflicting-outputs

# -------- FRB bindings & native builds --------
bridge-generate:
	./bindings/generate.sh

bridge-build-android:
	./bindings/android/build.sh

bridge-build-ios:
	./bindings/ios/build.sh
app-dev:
	@echo "Generating API client, resolving deps, and running Flutter (Android emulator)..."
	$(MAKE) gen-app
	cd app && flutter pub get
	cd app && flutter gen-l10n
	cd app && flutter run -d emulator-5554 --dart-define=MESSIE_API_BASE_URL=$(APP_API_BASE_URL)
backend-tidy:
	@echo "Tidying Go modules inside backend container..."
	$(COMPOSE) exec -T backend sh -lc 'cd /backend && go mod tidy && go mod download'
	@echo "Done. If files changed, update your local repo (bind-mount overwrites container files)."
