# PrescSign API

API backend para emissão de receita e atestado digital.

## Escopo Atual

- Projeto focado em **API only** com Ruby on Rails.
- Não haverá frontend neste MVP.
- Backend inclui autenticação, autorização, pacientes, documentos, assinatura, validação e envios assíncronos.
- Infraestrutura com Docker faz parte do escopo (base já existente com `Dockerfile`).

## Stack Confirmada

- Ruby: `3.3.1`
- Rails: `7.1.6`
- Banco de dados: PostgreSQL
- Jobs assíncronos: Sidekiq + Redis
- Autenticação: Devise + JWT
- Autorização: Pundit

## Verificação de Versões

```bash
ruby -v
bundle exec rails -v
```

Saída esperada:

- `ruby 3.3.1`
- `Rails 7.1.6`

## Infraestrutura

- Arquivo existente: `Dockerfile`
- `docker-compose.yml` com serviços:
  - `api` (Rails)
  - `db` (PostgreSQL)
  - `redis`
  - `sidekiq`

### Comandos Docker (desenvolvimento)

```bash
# subir ambiente completo
docker compose up --build

# subir em background
docker compose up --build -d

# derrubar ambiente
docker compose down

# derrubar ambiente e volumes (reset de banco/redis)
docker compose down -v
```

### Alterar portas locais (evitar conflito com outros containers)

Defina no `.env`:

```bash
API_PORT_HOST=3300
POSTGRES_PORT_HOST=55432
REDIS_PORT_HOST=56379
```

Assim, no host você acessa:

- API em `http://localhost:3300`
- PostgreSQL em `localhost:55432`
- Redis em `localhost:56379`

```bash
# logs da API
docker compose logs -f api

# logs do Sidekiq
docker compose logs -f sidekiq

# shell no container da API
docker compose exec api bash

# rodar migrações manualmente
docker compose exec api bin/rails db:migrate
```

### Healthchecks

- API: `GET /up`
- PostgreSQL: `pg_isready`
- Redis: `redis-cli ping`
- Sidekiq: verificação de processo do worker

### Atalhos com Makefile

```bash
make up-d
make logs-api
make migrate
make console
make rails cmd='db:seed'
```

Todos os comandos `bin/rails` devem ser executados no container da API via `docker compose exec api ...` (ou via `make`).

### Compose de produção

- Arquivo adicional: `docker-compose.prod.yml`
- Uso:

```bash
make prod-up-d
make prod-logs
make prod-down
```

### Espera explícita de dependências

O entrypoint usa `bin/wait-for-services` quando `WAIT_FOR_DEPENDENCIES=true` para aguardar:

- PostgreSQL (`pg_isready`)
- Redis (`redis-cli ping`)

Isso reduz falhas de boot em cenários onde o container inicia antes dos serviços ficarem prontos.

## Configuração de Ambientes

Este projeto usa três ambientes padrão:

- `development`: foco em produtividade local, reload habilitado, `active_job` padrão `async`.
- `test`: foco em previsibilidade, `active_job` em `:test`, mailer em `:test`.
- `production`: foco em segurança/performance, eager load ligado, SSL forçado e configurações por variáveis de ambiente.

### Template de variáveis de ambiente

- Arquivo versionado: `.env.example.erb`
- Uso local:
  1. copie `.env.example.erb` para `.env`
  2. ajuste os valores para o seu ambiente

Observação: o repositório ignora `.env*`, então o template versionável foi definido como `.env.example.erb`.

### Variáveis obrigatórias por ambiente

- `development`:
  - `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
  - `POSTGRES_DB_DEVELOPMENT`
  - opcionais: `APP_HOST`, `APP_PORT`, `APP_PROTOCOL`, `RAILS_LOG_LEVEL`
- `test`:
  - `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
  - `POSTGRES_DB_TEST`
- `production`:
  - `APP_HOST` (obrigatória)
  - recomendado: `DATABASE_URL`
  - alternativamente: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB_PRODUCTION`
  - `APP_PROTOCOL` (default `https`)
  - `ACTIVE_JOB_QUEUE_ADAPTER` (recomendado `sidekiq`)
  - `ACTIVE_STORAGE_SERVICE` (recomendado provider cloud)
  - `JWT_SECRET_KEY` (obrigatória)

### Mapa de configuração e fallback seguro

- Leitura padronizada: `config/initializers/app_config.rb` (via `Rails.application.config.x`)
- Estratégia:
  - em `production`, variáveis críticas sem valor levantam erro explícito no boot
  - em `development`/`test`, o app usa defaults seguros para não bloquear setup local
  - integrações externas ficam desabilitadas por padrão até receberem credenciais

#### Integrações e variáveis

- Redis:
  - `REDIS_URL` (`redis://localhost:6379/1` por padrão)
- JWT:
  - `JWT_SECRET_KEY` (obrigatória em `production`; default local `dev-only-change-me`)
- S3/R2:
  - `S3_BUCKET` habilita integração
  - quando habilitada em `production`, exige `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_REGION`
  - opcionais: `S3_ENDPOINT`
- SendGrid:
  - `SENDGRID_API_KEY` habilita integração
  - quando habilitada em `production`, exige `SENDGRID_FROM_EMAIL`
- Twilio:
  - `TWILIO_ACCOUNT_SID` habilita integração
  - quando habilitada em `production`, exige `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
- WhatsApp:
  - `WHATSAPP_ACCESS_TOKEN` habilita integração
  - quando habilitada em `production`, exige `WHATSAPP_PHONE_NUMBER_ID`
  - opcional com default: `WHATSAPP_API_VERSION=v20.0`
- Sentry:
  - `SENTRY_DSN` habilita integração
  - opcionais com default: `SENTRY_ENVIRONMENT` (`Rails.env`), `SENTRY_TRACES_SAMPLE_RATE=0.0`

## Documento de Referência do MVP

A definição detalhada do MVP e checklist operacional estão mantidas em documentos locais de trabalho (fora do versionamento do Git).

## Convenções de Código

- Lint: `RuboCop` (`rubocop`, `rubocop-rails`, `rubocop-performance`)
- Configuração: `.rubocop.yml`
- Formatação base de arquivos: `.editorconfig`
- Comando padrão: `bin/lint`
- Guia de organização de classes: `docs/CODE_CONVENTIONS.md`
