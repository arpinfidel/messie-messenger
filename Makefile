ARGS = $(filter-out $@,$(MAKECMDGOALS))

STACK ?= dev
COMPOSE = docker compose -f docker-compose.$(STACK).yml

.PHONY: up down build ps logs sh

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

up-build:
	$(COMPOSE) up --build -d

build:
	$(COMPOSE) build

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f $(ARGS)

sh:
	$(COMPOSE) exec $(firstword $(ARGS)) sh

# swallow extra targets so make doesn’t complain or rerun them
%:
	@:
