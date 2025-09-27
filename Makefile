DATABASE_URL = postgres://user:password@localhost:5432/todo_db?sslmode=disable

ARGS = $(filter-out $@,$(MAKECMDGOALS))

MATRIX_SERVER_URL ?= http://localhost:8008
MATRIX_REGISTRATION_SHARED_SECRET ?= dev_matrix_shared_secret

JAVA_HOME ?= $(shell /usr/libexec/java_home -v 17 2>/dev/null)
GRADLE_USER_HOME ?= $(CURDIR)/frontend/android/.gradle-user

STACK ?= dev
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

.PHONY: mobile-assets mobile-sync mobile-run-android mobile-run-ios mobile-open-android mobile-open-ios mobile-add-android mobile-add-ios mobile-build-android mobile-build-apk test-e2e-codegen matrix-init matrix-up matrix-down matrix-register

mobile-assets:
	cd frontend && npm run mobile:assets

mobile-sync:
	cd frontend && npm run mobile:sync

mobile-run-android:
	cd frontend && npm run mobile:run:android

mobile-run-ios:
	cd frontend && npm run mobile:run:ios

mobile-build-android:
	$(MAKE) mobile-build-apk

mobile-open-android:
	cd frontend && npm run mobile:android

mobile-open-ios:
	cd frontend && npm run mobile:ios

mobile-add-android:
	cd frontend && npm run mobile:add:android

mobile-add-ios:
	cd frontend && npm run mobile:add:ios

mobile-build-apk:
	cd frontend/android && \
	  export JAVA_HOME=$(JAVA_HOME) GRADLE_USER_HOME=$(GRADLE_USER_HOME) && \
	  mkdir -p "$$GRADLE_USER_HOME" && \
	  ./gradlew assembleDebug

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
