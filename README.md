# PrescSign API

API backend para emissão de receita e atestado digital.

## Escopo Atual

- Projeto focado em **API only** com Ruby on Rails.
- Não haverá frontend neste MVP.
- Backend inclui autenticação, autorização, pacientes, documentos, assinatura, validação e envios assíncronos.
- Infraestrutura com Docker faz parte do escopo (base já existente com `Dockerfile`).
- Nginx local opcional para proxy reverso de domínio (ex.: `api.prescsign.local`).

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
  - `nginx` (proxy reverso para a API)
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
NGINX_PORT_HOST=8080
POSTGRES_PORT_HOST=55432
REDIS_PORT_HOST=56379
```

Assim, no host você acessa:

- API em `http://localhost:3300`
- Nginx em `http://localhost:8080` (proxy para a API)
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
  - opcionais: `APP_HOST` (default `api.prescsign.local`), `APP_PORT`, `APP_PROTOCOL`, `RAILS_LOG_LEVEL`
- `test`:
  - `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
  - `POSTGRES_DB_TEST`
- `production`:
  - `APP_HOST` (obrigatória, exemplo `api.prescsign.com`)
  - `CORS_ALLOWED_ORIGINS` (obrigatória; lista separada por vírgula com origens confiáveis)
  - recomendado: `DATABASE_URL`
  - alternativamente: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB_PRODUCTION`
  - `APP_PROTOCOL` (default `https`)
  - `ACTIVE_JOB_QUEUE_ADAPTER` (recomendado `sidekiq`)
  - `ACTIVE_STORAGE_SERVICE` (recomendado `s3` para provider cloud)
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
  - `AUTH_USERS_REQUIRED` (default `false`; habilita exigência de identidade em `users`)
  - `AUTH_USERS_FALLBACK_PROVISIONING` (default `true`; permite provisionamento de fallback)
- Migração de `users`:
  - `USERS_MIGRATION_PHASE` (default `phase2_users_auth_enabled`; identifica a fase ativa do rollout)
  - `USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK` (default `true`; liga/desliga fallback de médicos)
- Observabilidade de rollout:
  - `OBS_ROLLOUT_PHASE` (default `users_migration`; etiqueta a fase nos eventos de observabilidade)
- CORS:
  - `CORS_ALLOWED_ORIGINS` define allowlist de origens (CSV)
  - default local: `http://localhost:5173,http://127.0.0.1:5173`
  - em `production`, deve conter apenas domínios confiáveis do frontend
- S3/R2:
  - `S3_BUCKET` habilita integração
  - quando habilitada em `production`, exige `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_REGION`
  - opcionais: `S3_ENDPOINT`, `S3_FORCE_PATH_STYLE`

#### Convenção de nomenclatura (versionamento de PDF)

- Diretório: `documents/{document_id}/v{version_number}`
- Nome do arquivo: `{document_kind}_{timestamp_utc}.pdf`
  - exemplo: `prescription_20260414T123456Z.pdf`
- Chave completa (Active Storage): `documents/{document_id}/v{version_number}/{document_kind}_{timestamp_utc}.pdf`
- Retenção operacional (MVP): ver [docs/RETENTION_POLICY.md](docs/RETENTION_POLICY.md)
- SendGrid:
  - `SENDGRID_API_KEY` habilita integração
  - quando habilitada em `production`, exige `SENDGRID_FROM_EMAIL`
  - timeout de envio por canal: `DELIVERIES_TIMEOUT_SECONDS` (default `10`)
- Twilio:
  - `TWILIO_ACCOUNT_SID` habilita integração
  - quando habilitada em `production`, exige `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
- WhatsApp:
  - `WHATSAPP_ACCESS_TOKEN` habilita integração
  - quando habilitada em `production`, exige `WHATSAPP_PHONE_NUMBER_ID`
  - opcional com default: `WHATSAPP_API_VERSION=v20.0`
- Sentry:
  - `SENTRY_DSN` habilita integração
  - opcionais com default: `SENTRY_ENVIRONMENT` (`Rails.env`), `SENTRY_TRACES_SAMPLE_RATE=0.0`, `SENTRY_TIMEOUT_SECONDS=2`
- Geração de PDF:
  - timeout de renderização: `PDF_GENERATION_TIMEOUT_SECONDS` (default `20`)

## Documento de Referência do MVP

A definição detalhada do MVP e checklist operacional estão mantidas em documentos locais de trabalho (fora do versionamento do Git).

## Endpoints e Contratos

- Documento de referência de endpoints e payloads: [docs/API_CONTRACTS.md](docs/API_CONTRACTS.md)

## Versionamento de API

- Prefixo oficial versionado: `/api/v1`
- Compatibilidade temporária: endpoints legados em `/v1` permanecem ativos

## Formato de Resposta

- Sucesso: `{ "data": ..., "meta": ... }`
- Erro: `{ "errors": [{ "code": "...", "message": "..." }], "error": "mensagem principal", "error_code": "...", "meta": { "request_id": "...", "status": 4xx/5xx } }`
- Compatibilidade temporária: respostas com `data` em objeto também expõem os campos no topo.

### Paginação e Ordenação Padrão

- Query params padrão em endpoints de listagem:
  - `page` (default `1`)
  - `per_page` (default `20`, máximo `100`)
  - `sort_by` (whitelist por endpoint)
  - `sort_dir` (`asc`/`desc`, com default por endpoint)
- `meta` inclui: `page`, `per_page`, `total`, `total_pages`, `sort_by`, `sort_dir`.

## Recuperação de Senha (Integração Frontend)

Fluxo disponível na API para o frontend:

1. Usuário informa e-mail no formulário "Esqueci minha senha".
2. Front chama `POST /v1/auth/password`.
3. API sempre retorna `200` com mensagem neutra para evitar enumeração de contas.
4. Usuário recebe token de reset pelos canais definidos pela implementação do frontend.
5. Front abre tela "Nova senha" e envia token + nova senha para `PUT /v1/auth/password`.
6. Com sucesso, redirecionar para login e autenticar com a nova senha.

### Endpoint de solicitação de reset

`POST /v1/auth/password`

Payload:

```json
{
  "doctor": {
    "email": "medico@exemplo.com"
  }
}
```

Resposta (`200`):

```json
{
  "message": "If this email exists, reset instructions were sent"
}
```

### Endpoint de confirmação de nova senha

`PUT /v1/auth/password`

Payload:

```json
{
  "doctor": {
    "reset_password_token": "token_recebido_no_fluxo_de_reset",
    "password": "novaSenha123",
    "password_confirmation": "novaSenha123"
  }
}
```

Resposta de sucesso (`200`):

```json
{
  "message": "Password updated successfully"
}
```

Resposta de validação (`422`):

```json
{
  "errors": [
    "Reset password token is invalid"
  ]
}
```

### Requisitos para o frontend

- Exigir senha e confirmação iguais.
- Exibir erro de token inválido/expirado com ação de "solicitar novo link".
- Não revelar se o e-mail existe no sistema na etapa de solicitação.

## Autorização (Pundit)

A API usa `pundit` para autorização por recurso.

- Integração central em `ApplicationController` com:
  - `include Pundit::Authorization`
  - `rescue_from Pundit::NotAuthorizedError` retornando `403`
  - `pundit_user` baseado no `current_doctor` autenticado
- Fluxo de perfil do médico (`/v1/auth/me`) protegido por `DoctorPolicy`.

### Policies implementadas

- `DoctorPolicy`:
  - permite `show/update/destroy` apenas para o próprio médico autenticado.
- `PrescriptionPolicy`:
  - escopo por `doctor_id`
  - bloqueia `update/destroy` quando `status == "signed"`.
- `MedicalCertificatePolicy`:
  - escopo por `doctor_id`
  - bloqueia `update/destroy` quando `status == "signed"`.
- `DocumentPolicy`:
  - escopo por `doctor_id`
  - permite mutação apenas quando `status` é mutável (`issued`).
- `PatientPolicy`:
  - escopo retorna apenas pacientes vinculados ao médico autenticado
  - vínculo considerado por registros de receitas, atestados ou documentos.

### Testes de autorização

Foram adicionados specs para policies em `spec/policies`.

```bash
# executar somente policies
docker compose run --rm api bundle exec rspec spec/policies

# executar suíte completa
docker compose run --rm api bundle exec rspec
```

## Convenções de Código

- Formatação base de arquivos: `.editorconfig`
- Guia de organização de classes: `docs/CODE_CONVENTIONS.md`
