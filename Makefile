SHELL := /bin/bash

.PHONY: help up up-d down reset logs logs-web logs-sidekiq shell migrate console rails test prod-up prod-up-d prod-down prod-logs prod-cert-init prod-backup-now prod-backup-list prod-restore

help:
	@echo "Available targets:"
	@echo "  make up           - Start development stack in foreground"
	@echo "  make up-d         - Start development stack in background"
	@echo "  make down         - Stop development stack"
	@echo "  make reset        - Stop development stack and remove volumes"
	@echo "  make logs         - Follow all development logs"
	@echo "  make logs-web     - Follow web logs"
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
	@echo "  make prod-cert-init   - Emite o certificado TLS (uma vez, com o nginx parado)"
	@echo "  make prod-backup-now  - Roda um backup do Postgres agora"
	@echo "  make prod-backup-list - Lista os backups do bucket"
	@echo "  make prod-restore key=<chave> db=<banco-novo> - Restaura um backup num banco novo"

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

logs-web:
	docker compose logs -f web

logs-sidekiq:
	docker compose logs -f sidekiq

shell:
	docker compose exec web bash

migrate:
	docker compose exec web bin/rails db:migrate

console:
	docker compose exec web bin/rails console

rails:
	docker compose exec web bin/rails $(cmd)

test:
	docker compose exec web bin/rails test

prod-up:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build

prod-up-d:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d

prod-down:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml down

prod-logs:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f

# Primeira emissão do certificado: standalone na porta 80, então o nginx de
# produção precisa estar parado. Ver docs/DEPLOY_PRODUCAO.md.
prod-cert-init:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm -p 80:80 --entrypoint /opt/prescsign/issue.sh certbot

prod-backup-now:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm backup backup.sh

prod-backup-list:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm backup restore.sh list

prod-restore:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm backup restore.sh $(key) $(db)
