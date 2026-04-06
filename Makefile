SHELL := /bin/bash

.PHONY: help up up-d down reset logs logs-api logs-sidekiq shell migrate console rails test prod-up prod-up-d prod-down prod-logs

help:
	@echo "Available targets:"
	@echo "  make up           - Start development stack in foreground"
	@echo "  make up-d         - Start development stack in background"
	@echo "  make down         - Stop development stack"
	@echo "  make reset        - Stop development stack and remove volumes"
	@echo "  make logs         - Follow all development logs"
	@echo "  make logs-api     - Follow API logs"
	@echo "  make logs-sidekiq - Follow Sidekiq logs"
	@echo "  make shell        - Open bash in API container"
	@echo "  make migrate      - Run db:migrate in API container"
	@echo "  make console      - Open Rails console in API container"
	@echo "  make rails cmd='db:seed' - Run any bin/rails command in API container"
	@echo "  make test         - Run test suite in API container"
	@echo "  make prod-up      - Start production compose stack in foreground"
	@echo "  make prod-up-d    - Start production compose stack in background"
	@echo "  make prod-down    - Stop production compose stack"
	@echo "  make prod-logs    - Follow production stack logs"

up:
	docker compose up --build

up-d:
	docker compose up --build -d

down:
	docker compose down

reset:
	docker compose down -v

logs:
	docker compose logs -f

logs-api:
	docker compose logs -f api

logs-sidekiq:
	docker compose logs -f sidekiq

shell:
	docker compose exec api bash

migrate:
	docker compose exec api bin/rails db:migrate

console:
	docker compose exec api bin/rails console

rails:
	docker compose exec api bin/rails $(cmd)

test:
	docker compose exec api bin/rails test

prod-up:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build

prod-up-d:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d

prod-down:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml down

prod-logs:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f
