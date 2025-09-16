DATABASE_URL = postgres://user:password@localhost:5432/todo_db?sslmode=disable

ARGS = $(filter-out $@,$(MAKECMDGOALS))

STACK ?= dev
COMPOSE = docker compose -f docker-compose.$(STACK).yml

.PHONY: up down build ps logs sh

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