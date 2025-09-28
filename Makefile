DATABASE_URL = postgres://user:password@localhost:5432/todo_db?sslmode=disable

ARGS = $(filter-out $@,$(MAKECMDGOALS))

MATRIX_SERVER_URL ?= http://localhost:8008
MATRIX_REGISTRATION_SHARED_SECRET ?= dev_matrix_shared_secret

STACK ?= dev
ANDROID_SDK_ROOT ?= /opt/homebrew/share/android-commandlinetools
ANDROID_AVD_NAME ?= MessiePixel6Api34
ANDROID_SYSTEM_IMAGE ?= system-images;android-34;google_apis;arm64-v8a
ANDROID_SYSTEM_IMAGE_DIR ?= $(ANDROID_SDK_ROOT)/system-images/android-34/google_apis/arm64-v8a
ANDROID_PLATFORM_TOOLS_DIR ?= $(ANDROID_SDK_ROOT)/platform-tools
ANDROID_EMULATOR_ARGS ?= -netdelay none -netspeed full -gpu host
JAVA_HOME ?= /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

COMPOSE = docker compose -f docker-compose.$(STACK).yml

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

.PHONY: mobile-assets mobile-sync mobile-run-android mobile-run-ios mobile-open-android mobile-open-ios mobile-add-android mobile-add-ios test-e2e-codegen matrix-init matrix-up matrix-down matrix-register
.PHONY: android-emulator android-emulator-install android-emulator-avd android-emulator-run

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

test-e2e-codegen:
	cd frontend && npm run test:e2e:codegen

matrix-init:
	COMPOSE_PROFILES=matrix $(COMPOSE) run --rm matrix generate

matrix-up:
	COMPOSE_PROFILES=matrix $(COMPOSE) up -d $(if $(ARGS),$(ARGS),matrix)

matrix-down:
	COMPOSE_PROFILES=matrix $(COMPOSE) stop $(if $(ARGS),$(ARGS),matrix)

matrix-register:
	@if [ -z "$(ARGS)" ]; then \
		echo "Usage: make matrix-register ARGS='-u user-a -p passw0rd --admin'"; \
		exit 1; \
	fi
	COMPOSE_PROFILES=matrix $(COMPOSE) exec matrix register_new_matrix_user $(ARGS) -k $(MATRIX_REGISTRATION_SHARED_SECRET) $(MATRIX_SERVER_URL)


android-emulator: android-emulator-install android-emulator-avd android-emulator-run

android-emulator-install:
	@if ! command -v sdkmanager >/dev/null 2>&1; then \
		echo 'sdkmanager not found on PATH.'; \
		exit 1; \
	fi
	@if [ -x '$(ANDROID_SDK_ROOT)/emulator/emulator' ] && [ -d '$(ANDROID_SYSTEM_IMAGE_DIR)' ] && [ -d '$(ANDROID_PLATFORM_TOOLS_DIR)' ]; then \
		echo 'Android emulator, system image, and platform-tools already present in $(ANDROID_SDK_ROOT).'; \
	else \
		yes | ANDROID_SDK_ROOT='$(ANDROID_SDK_ROOT)' JAVA_HOME='$(JAVA_HOME)' sdkmanager --install 'emulator' 'platform-tools' '$(ANDROID_SYSTEM_IMAGE)'; \
	fi

android-emulator-avd:
	@if ! command -v avdmanager >/dev/null 2>&1; then \
		echo 'avdmanager not found on PATH.'; \
		exit 1; \
	fi
	@if [ -d "$$HOME/.android/avd/$(ANDROID_AVD_NAME).avd" ]; then \
		echo 'AVD $(ANDROID_AVD_NAME) already exists.'; \
	else \
		printf 'no\n' | ANDROID_SDK_ROOT='$(ANDROID_SDK_ROOT)' JAVA_HOME='$(JAVA_HOME)' avdmanager create avd --name '$(ANDROID_AVD_NAME)' --package '$(ANDROID_SYSTEM_IMAGE)' --device 'pixel_6' --tag google_apis --abi arm64-v8a; \
	fi

android-emulator-run:
	@if [ ! -x '$(ANDROID_SDK_ROOT)/emulator/emulator' ]; then \
		echo 'emulator binary not found at $(ANDROID_SDK_ROOT)/emulator/emulator'; \
		exit 1; \
	fi
	"$(ANDROID_SDK_ROOT)/platform-tools/adb" start-server
	ANDROID_SDK_ROOT="$(ANDROID_SDK_ROOT)" \
	ANDROID_HOME="$(ANDROID_SDK_ROOT)" \
	PATH="$(ANDROID_SDK_ROOT)/platform-tools:$(ANDROID_SDK_ROOT)/emulator:$(ANDROID_SDK_ROOT)/cmdline-tools/latest/bin:$$PATH" \
	"$(ANDROID_SDK_ROOT)/emulator/emulator" '@$(ANDROID_AVD_NAME)' $(ANDROID_EMULATOR_ARGS)

android-emulator-logs:
	$(ANDROID_SDK_ROOT)/platform-tools/adb logcat "Capacitor:D" "Messie:D" "*:S"

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
