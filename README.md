# PrescSign

Plataforma para emissao, assinatura e validacao de receitas e atestados medicos digitais.

Aplicacao **Rails monolitica com paginas renderizadas no servidor** (server-rendered). Nao ha SPA/Vue nem API JSON separada: as telas sao ERB + Tailwind e a autenticacao e por sessao (cookie).

## Escopo Atual

- Monolito Rails 7.1 renderizado no servidor (ERB + Tailwind), sem build Node e sem Hotwire/Turbo.
- Backend inclui autenticacao por sessao, autorizacao, pacientes, consultas, agenda, documentos, assinatura, validacao publica e envios assincronos.
- Organizacao por **subdominios**: `login.`, `register.`, `app.` (painel do tenant) e `admin.` (back-office).
- Infraestrutura com Docker faz parte do escopo (`Dockerfile`, `docker-compose.yml`, `nginx`).

## Stack Confirmada

- Ruby: `3.3.1`
- Rails: `7.1.6`
- Banco de dados: PostgreSQL
- Jobs assincronos: Sidekiq + Redis
- Autenticacao: Devise (sessao/cookie, escopo `:user`)
- Autorizacao: Pundit
- Front-end: ERB + Tailwind (tailwindcss-rails), assets via Propshaft + importmap
- PDF: WickedPDF
- Rate limiting das telas de auth: rack-attack (store em Redis)

## Verificacao de Versoes

```bash
ruby -v
bundle exec rails -v
```

Saida esperada:

- `ruby 3.3.1`
- `Rails 7.1.6`

## Arquitetura em Subdominios

Todo o roteamento e feito por `constraints subdomain:` em `config/routes.rb`. O
cookie de sessao e compartilhado entre os subdominios (mesmo dominio base).

- `login.` — autenticacao: sign-in, sign-out, esqueci a senha, reset de senha e
  confirmacao de conta.
- `register.` — cadastro via convite (invitation-based sign-up).
- `app.` — o painel do tenant. Controllers em `app/controllers/app/`, namespace
  `App::`. Telas: Dashboard, Pacientes, Consultas, Agenda (calendario mensal),
  Documentos (emissao de receitas e atestados, hub com assinar / verificar
  integridade / reenviar, PDF via WickedPDF), Logs de auditoria, Medicos
  responsaveis (convite por e-mail), Organizacoes (criacao), Perfil e Sobre.
- `admin.` — back-office da plataforma (cross-organizacao).

Alem dos subdominios, ha a **validacao publica de documentos** (sem auth), em
`GET /validate/:code` (`Public::DocumentValidationsController`), acessivel pelo
codigo/QR impresso no documento.

O `ApplicationController < ActionController::Base` concentra: Pundit,
`protect_from_forgery`, resolucao de tenant por sessao (`Current` +
`session[:current_organization_id]`) e observabilidade via
`around_action :log_request_observability`.

## Como Rodar Localmente

### 1. Variaveis de ambiente

```bash
cp .env.example .env
# ajuste os valores conforme necessario
```

Variaveis relevantes para o ambiente local (ver `.env.example`): `APP_HOST`,
`APP_DOMAIN`, `WEB_PORT_HOST`, `NGINX_PORT_HOST`, `SECRET_KEY_BASE`,
`SESSION_COOKIE_DOMAIN`, `POSTGRES_*`, `REDIS_URL` e as chaves de integracao.

#### Gerar segredos

Os valores sensiveis nao devem ser copiados do template — gere-os localmente.

**`SECRET_KEY_BASE`** (obrigatoria em producao; usada pelo Devise para tokens).
Escolha uma das opcoes:

```bash
# via Rails (dentro do container web)
docker compose exec web rails secret

# sem depender do container (OpenSSL)
openssl rand -hex 64
```

**`POSTGRES_PASSWORD`** e outras senhas — gere um valor aleatorio:

```bash
openssl rand -base64 24
```

Cole o resultado nas variaveis correspondentes do `.env`. Exemplo rapido que ja
grava o `SECRET_KEY_BASE` no arquivo (revise antes de comitar — o `.env` e
ignorado pelo git):

```bash
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env
```

> Nao versione o `.env`: ele contem segredos e ja esta no `.gitignore`. O
> `.env.example` continua sendo o unico arquivo versionado, com placeholders.

### 2. Entradas no /etc/hosts (subdominios)

Como o roteamento depende de subdominios, aponte o dominio base e os subdominios
para o loopback:

```
127.0.0.1  prescsign.local
127.0.0.1  login.prescsign.local
127.0.0.1  register.prescsign.local
127.0.0.1  app.prescsign.local
127.0.0.1  admin.prescsign.local
```

### 3. Subir o ambiente

```bash
docker compose up --build      # ou: make up
docker compose up --build -d   # background: make up-d
```

O nginx faz proxy reverso para `web:3000` e escuta em `NGINX_PORT_HOST` (default
`8080`). Acesse as telas pelos subdominios via nginx, por exemplo:

- Login:   `http://login.prescsign.local:8080/sign-in`
- Painel:  `http://app.prescsign.local:8080`
- Admin:   `http://admin.prescsign.local:8080`

O host base (`http://prescsign.local:8080`) redireciona para o subdominio de
login. O servico `web` (Puma) tambem expoe `WEB_PORT_HOST` (default `4000`)
diretamente, caso queira acessar sem passar pelo nginx. A porta interna do
container continua sendo `3000`; so a publicada no host mudou, para nao conflitar
com outro app Rails local.

### 4. Banco e seeds

O entrypoint ja prepara o banco (`RUN_DB_PREPARE=true`). Para popular dados de
demonstracao:

```bash
docker compose exec web bin/rails db:seed   # ou: make rails cmd='db:seed'
```

### Usuarios de demonstracao (seeds)

Definidos em `db/seeds.rb` (senha padrao `password123`, sobrescrevivel via
`SEED_PASSWORD`):

| E-mail | Papel |
| --- | --- |
| `admin@prescsign.test` | admin |
| `support@prescsign.test` | support |
| `medico@prescsign.test` | medico (atua em duas clinicas) |
| `recepcao@prescsign.test` | responsavel pela clinica |
| `hospital@prescsign.test` | responsavel pelo hospital |
| `hospital.medico@prescsign.test` | medico do hospital |

## Comandos Docker (desenvolvimento)

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

Todos os comandos `bin/rails` sao executados no container `web` via
`docker compose exec web ...` (ou via `make`):

```bash
# logs do web
docker compose logs -f web

# logs do Sidekiq
docker compose logs -f sidekiq

# shell no container web
docker compose exec web bash

# rodar migracoes manualmente
docker compose exec web bin/rails db:migrate
```

### Alterar portas locais (evitar conflito com outros containers)

Defina no `.env`:

```bash
WEB_PORT_HOST=3300
NGINX_PORT_HOST=8080
POSTGRES_PORT_HOST=55432
REDIS_PORT_HOST=56379
```

Assim, no host voce acessa:

- Web (Puma) em `http://localhost:3300`
- Nginx em `http://localhost:8080` (proxy para o web)
- PostgreSQL em `localhost:55432`
- Redis em `localhost:56379`

### Servicos do compose

`docker-compose.yml` define:

- `db` (PostgreSQL)
- `redis`
- `web` (Rails/Puma, renderizacao server-side)
- `nginx` (proxy reverso para `web:3000`)
- `sidekiq` (jobs assincronos)

O `Dockerfile` faz precompilacao de assets (Propshaft + Tailwind).

### Atalhos com Makefile

```bash
make up-d
make logs-web
make migrate
make console
make rails cmd='db:seed'
make shell
make test
```

### Compose de producao

- Arquivo adicional: `docker-compose.prod.yml`

```bash
make prod-up-d
make prod-logs
make prod-down
```

### Healthchecks

- Web: `GET /up`
- PostgreSQL: `pg_isready`
- Redis: `redis-cli ping`
- Sidekiq: verificacao de processo do worker

### Espera explicita de dependencias

O entrypoint usa `bin/wait-for-services` quando `WAIT_FOR_DEPENDENCIES=true` para
aguardar PostgreSQL (`pg_isready`) e Redis (`redis-cli ping`), reduzindo falhas de
boot quando o container inicia antes dos servicos ficarem prontos.

## Autenticacao e Personas (visao geral)

- **Autenticacao por sessao** com Devise no escopo `:user`. Login em
  `login.` cria a sessao; o cookie e compartilhado com `app.`/`admin.` no dominio
  base (`SESSION_COOKIE_DOMAIN`). O `ApplicationController` exige
  `authenticate_user!` por padrao (telas publicas/auth fazem `skip`).
- **Tenant por sessao**: a organizacao ativa e resolvida a partir de
  `session[:current_organization_id]` (com fallback para a org atual do usuario ou
  a primeira membership ativa) e exposta em `Current.organization` /
  `Current.membership`.
- **Autorizacao**: Pundit por recurso (`app/policies/*.rb`). A visibilidade de
  menu/secoes e calculada por `AccessContext`, que define a persona:
  - `admin`
  - `organization_responsible`
  - `doctor`
- **Protecao das telas de auth**: rack-attack aplica throttle por IP/e-mail em
  sign-in, sign-up, recuperacao/reset de senha e reenvio de confirmacao
  (`config/initializers/rack_attack.rb`).

## Testes (RSpec)

```bash
# suite completa
docker compose exec web bundle exec rspec

# somente requests do painel
docker compose exec web bundle exec rspec spec/requests/app

# somente policies
docker compose exec web bundle exec rspec spec/policies
```

Specs de request do painel ficam em `spec/requests/app/` e a validacao publica em
`spec/requests/public/`. Specs de policy, model, service e job tambem sao
mantidos. O helper `spec/support/web_spec_helpers.rb` fornece login por sessao
(`sign_in_web`) e hosts de subdominio para os testes.

## Configuracao de Ambientes

Este projeto usa tres ambientes padrao:

- `development`: foco em produtividade local, reload habilitado.
- `test`: foco em previsibilidade (`active_job` em `:test`, mailer em `:test`).
- `production`: foco em seguranca/performance, eager load ligado, SSL forcado e
  configuracoes por variaveis de ambiente.

### Template de variaveis de ambiente

- Arquivo versionado: `.env.example`
- Uso local: copie para `.env` e ajuste os valores.

### Mapa de configuracao e fallback seguro

- Leitura padronizada: `config/initializers/app_config.rb` (via
  `Rails.application.config.x`).
- Em `production`, variaveis criticas sem valor levantam erro explicito no boot.
- Em `development`/`test`, o app usa defaults seguros para nao bloquear o setup.
- Integracoes externas ficam desabilitadas por padrao ate receberem credenciais.

#### Integracoes e variaveis

- Redis: `REDIS_URL` (`redis://localhost:6379/1` por padrao)
- Sessao/cookies: `SECRET_KEY_BASE` (obrigatoria em producao), `SESSION_COOKIE_DOMAIN`
- S3/R2: `S3_BUCKET` habilita a integracao; quando habilitada em `production`,
  exige `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_REGION`; opcionais
  `S3_ENDPOINT`, `S3_FORCE_PATH_STYLE`
- SMTP (AWS SES ou qualquer relay): `SMTP_ADDRESS` habilita a entrega por SMTP
  e vale apenas em `production`; quando habilitada, exige `SMTP_USER_NAME`,
  `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`; opcionais `SMTP_PORT` (587),
  `SMTP_DOMAIN` (default `APP_HOST`), `SMTP_AUTHENTICATION` (`login`),
  `SMTP_ENABLE_STARTTLS_AUTO` (`true`). No SES as credenciais SMTP sao por
  regiao: use o host da mesma regiao em que foram geradas. `development` usa
  `letter_opener_web` e `test` usa `:test`; nenhum dos dois le estas variaveis
- Twilio: `TWILIO_ACCOUNT_SID` habilita a integracao; quando habilitada em
  `production`, exige `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
- WhatsApp: `WHATSAPP_ACCESS_TOKEN` habilita a integracao; quando habilitada em
  `production`, exige `WHATSAPP_PHONE_NUMBER_ID`; opcional `WHATSAPP_API_VERSION`
- Sentry: `SENTRY_DSN` habilita a integracao; opcionais `SENTRY_ENVIRONMENT`,
  `SENTRY_TRACES_SAMPLE_RATE`, `SENTRY_TIMEOUT_SECONDS`

#### Convencao de nomenclatura (versionamento de PDF)

- Diretorio: `documents/{document_id}/v{version_number}`
- Nome do arquivo: `{document_kind}_{timestamp_utc}.pdf`
  - exemplo: `prescription_20260414T123456Z.pdf`
- Chave completa (Active Storage):
  `documents/{document_id}/v{version_number}/{document_kind}_{timestamp_utc}.pdf`
- Retencao operacional (MVP): ver [docs/RETENTION_POLICY.md](docs/RETENTION_POLICY.md)

## Documentacao Complementar

- Documento tecnico detalhado: [docs/SISTEMA_TECNICO_DETALHADO.md](docs/SISTEMA_TECNICO_DETALHADO.md)
- Politica de retencao: [docs/RETENTION_POLICY.md](docs/RETENTION_POLICY.md)
- Convencoes de codigo: [docs/CODE_CONVENTIONS.md](docs/CODE_CONVENTIONS.md)

## Convencoes de Codigo

- Formatacao base de arquivos: `.editorconfig`
- Guia de organizacao de classes: `docs/CODE_CONVENTIONS.md`
