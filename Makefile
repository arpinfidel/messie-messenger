DATABASE_URL = postgres://user:password@localhost:5432/todo_db?sslmode=disable

ARGS = $(filter-out $@,$(MAKECMDGOALS))

MATRIX_SERVER_URL ?= http://localhost:8008
MATRIX_SERVER_NAME ?= messie.localhost
MATRIX_REGISTRATION_SHARED_SECRET ?= dev_matrix_shared_secret

MATRIX_SEED_ADMIN_USER ?= bridge-admin
MATRIX_SEED_ADMIN_PASSWORD ?= bridgeAdminPass!
MATRIX_SEED_USER ?= bridge-tester
MATRIX_SEED_PASSWORD ?= bridgeTesterPass!
MATRIX_SEED_ROOM_COUNT ?= 20
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

.PHONY: mobile-assets mobile-sync mobile-run-android mobile-run-ios mobile-open-android mobile-open-ios mobile-add-android mobile-add-ios test-e2e-codegen matrix-init matrix-up matrix-down matrix-register matrix-seed matrix-setup matrix-cleanup flutter-bridge-build-lib flutter-bridge-test bridge-generate bridge-build-android bridge-build-ios

mobile-assets:
	cd frontend && npm run mobile:assets

mobile-sync:
	cd frontend && npm run mobile:sync

mobile-run-android:
	cd frontend && npm run mobile:run:android

mobile-run-ios:
	cd frontend && npm run mobile:run:ios

mobile-build-android:
	cd frontend/android && ./gradlew assembleDebug

mobile-open-android:
	cd frontend && npm run mobile:android

mobile-open-ios:
	cd frontend && npm run mobile:ios

mobile-add-android:
	cd frontend && npm run mobile:add:android

mobile-add-ios:
	cd frontend && npm run mobile:add:ios

mobile-emu-list-android:
	$(ANDROID_SDK_ROOT)/emulator/emulator -list-avds

mobile-emu-start-android:
	$(ANDROID_SDK_ROOT)/emulator/emulator -avd $(ARGS)

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
		--room-count "$(MATRIX_SEED_ROOM_COUNT)" \
		--device-id "$(MATRIX_SEED_DEVICE_ID)" \
		--device-name "$(MATRIX_SEED_DEVICE_NAME)" \
		--state-dir "$(SEED_STATE_DIR_ABS)" $(if $(strip $(ARGS)),$(strip $(ARGS)))

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
