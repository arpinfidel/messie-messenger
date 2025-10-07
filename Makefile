DATABASE_URL = postgres://user:password@localhost:5432/todo_db?sslmode=disable

ARGS = $(filter-out $@,$(MAKECMDGOALS))

MATRIX_SERVER_URL ?= http://localhost:8008
MATRIX_SERVER_NAME ?= messie.localhost
MATRIX_REGISTRATION_SHARED_SECRET ?= dev_matrix_shared_secret

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
	$(COMPOSE) up -d $(ARGS)
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

flutter-run-android:
	# Ensure Rust Android FFI is built and copied into app/android
	make bridge-build-android
	cd app && flutter pub get
	cd app && flutter run -d emulator-5554

flutter-run-ios:
	# Ensure Rust iOS/macOS libraries are built (if needed for your flow)
	make bridge-build-ios
	cd app && flutter pub get
	cd app && flutter run -d ios

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
		--device-id "$(MATRIX_SEED_DEVICE_ID)" \
		--device-name "$(MATRIX_SEED_DEVICE_NAME)" \
		--state-dir "$(SEED_STATE_DIR_ABS)" $(if $(strip $(ARGS)),$(strip $(ARGS)))

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
	cd app && MESSIE_FFI_LIB_PATH=../$(FFI_LIB) MESSIE_SEED_STATE_FILE=$(SEED_STATE_DIR_ABS)/seed_state.json flutter test test/bridge/sliding_sync_bridge_test.dart


# swallow extra targets so make doesn’t complain or rerun them
%:
	@:

psql:
	@echo "Connecting to PostgreSQL database..."
	$(COMPOSE) exec -it postgres psql -U user -d todo_db

gen-fe:
	@echo "Generating frontend API client..."
	cd frontend && openapi-generator-cli generate -i ../docs/openapi.yaml -g typescript-fetch -o src/api/generated
	cd frontend && npx prettier --write src/api/generated

gen-be:
	@echo "Generating backend API server stubs..."
	cd backend && go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen -package generated -generate types,chi-server -o api/generated/todo_api.go ../docs/openapi.yaml

gen: gen-fe gen-be
	@echo "Code generation complete."

# -------- FRB bindings & native builds --------
bridge-generate:
	./bindings/generate.sh

bridge-build-android:
	./bindings/android/build.sh

bridge-build-ios:
	./bindings/ios/build.sh
