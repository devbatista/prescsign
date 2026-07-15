# PrescSign - Documento Tecnico Detalhado

## 1. Objetivo e Escopo

Este documento consolida o estado atual do PrescSign com base no codigo-fonte da branch atual.

Inclui:
- arquitetura da aplicacao;
- fluxo de autenticacao, autorizacao e tenant;
- modelo de dominio e ciclo de vida documental;
- jobs assincronos e camada de entregas;
- observabilidade, seguranca e governanca de dados;
- guia operacional e de manutencao.

O sistema e um **monolito Rails renderizado no servidor** (ERB + Tailwind). Nao
existe mais SPA/Vue nem API JSON `/api/v1` separada: as telas sao servidas
diretamente pelo Rails e a autenticacao e por sessao.

## 2. Stack e Runtime

- Linguagem: Ruby 3.3.1
- Framework: Rails 7.1.6 (server-rendered)
- Camada de view: ERB + Tailwind (tailwindcss-rails), assets via Propshaft + importmap (sem build Node, sem Hotwire/Turbo)
- Banco: PostgreSQL
- Fila/Jobs: Sidekiq + Redis
- Auth: Devise (sessao/cookie, escopo `:user`)
- Authorization: Pundit
- Rate limiting das telas de auth: rack-attack (store em Redis; MemoryStore em test)
- Storage de arquivo: Active Storage (com suporte S3/R2)
- PDF: WickedPDF
- QR Code: RQRCode
- Assinatura: providers plugaveis (interno e ICP-Brasil) via `Signatures::ProviderFactory`

Referencias:
- `README.md`
- `Gemfile`
- `config/initializers/devise.rb`
- `config/initializers/sidekiq.rb`
- `config/initializers/rack_attack.rb`

## 3. Arquitetura da Aplicacao

### 3.1 Estilo arquitetural

- Monolito Rails organizado por camadas:
  - `app/controllers`: controllers HTTP que renderizam ERB
  - `app/views`: telas ERB + Tailwind
  - `app/models`: dominio e persistencia
  - `app/services`: regras de negocio e integracoes
  - `app/policies`: autorizacao (Pundit)
  - `app/jobs`: processamento assincrono

### 3.2 Roteamento por subdominios

Todo o roteamento e definido em `config/routes.rb` com `constraints subdomain:`.
O dominio base em desenvolvimento e `prescsign.local`. O cookie de sessao e
compartilhado entre os subdominios.

- `login.` — autenticacao (sessao): `sign-in`, `sign-out`, `forgot-password`,
  `reset-password`, `confirm-account`, `resend-confirmation`.
- `register.` — cadastro por convite: `sign-up`.
- `app.` — painel do tenant. Controllers em `app/controllers/app/`, namespace
  `App::`.
- `admin.` — back-office da plataforma (cross-organizacao).

Fora dos subdominios:
- validacao publica de documentos (sem auth): `GET /validate` e
  `GET /validate/:code` (`Public::DocumentValidationsController`);
- health check: `GET /up`;
- o host base (apex) redireciona para o subdominio `login.`.

Implementacao:
- `config/routes.rb`

### 3.3 Fluxo de request (resumo)

O controller base e `ApplicationController < ActionController::Base`
(`app/controllers/application_controller.rb`):

1. `around_action :log_request_observability` envolve todo o request (latencia,
   status, alerta em 500).
2. `before_action :authenticate_user!` (Devise, sessao) — telas publicas e de
   auth fazem `skip` explicito.
3. `before_action :set_current_tenant` resolve a organizacao ativa por sessao e
   popula `Current`.
4. `authorize` / `policy_scope` aplicam regras Pundit.
5. A action renderiza a view ERB (ou redireciona).

Recursos transversais do controller base:
- `include Pundit::Authorization`
- `protect_from_forgery with: :exception` (CSRF)
- `rescue_from Pundit::NotAuthorizedError` renderizando `shared/forbidden` (403)
- paginacao por offset (`paginate`) para telas de listagem
- helpers de view: `current_organization`, `current_membership`,
  `current_persona`, `available_organizations`, `access_context`

Referencias:
- `app/controllers/application_controller.rb`

## 4. Camada Web (Painel `App::`)

Controllers em `app/controllers/app/` (subdominio `app.`):

- `App::DashboardController` — dashboard.
- `App::PatientsController` — CRUD de pacientes.
- `App::ConsultationsController` — consultas (com `cancel`).
- `App::Agenda::EventsController` — agenda (calendario mensal).
- `App::PrescriptionsController` — receitas (`new/create/edit/update`, `revoke`, `pdf`).
- `App::MedicalCertificatesController` — atestados (`new/create/edit/update`, `revoke`, `pdf`).
- `App::DocumentsController` — hub do documento (`show`, `sign`, `integrity_check`, `resend`).
- `App::AuditLogsController` — listagem de auditoria.
- `App::DoctorsController` — medicos da organizacao (convite por e-mail).
- `App::OrganizationsController` — criacao e `switch` de organizacao ativa.
- `App::ProfileController` — perfil do usuario.
- `App::PagesController` — paginas estaticas (`about`, contexto de organizacao ausente).

Back-office em `app/controllers/admin/` (subdominio `admin.`), com
`Admin::BaseController` e `Admin::DashboardController`.

## 5. Autenticacao e Identidade

### 5.1 Modelo de identidade

Entidades principais:
- `User` (credenciais, status, org atual)
- `DoctorProfile` (dados profissionais)
- `UserRole` (papel global)
- `OrganizationMembership` (papel por organizacao)

A identidade e centrada em `User`; o perfil medico fica em `DoctorProfile`.

### 5.2 Fluxo de autenticacao (sessao)

- Devise no escopo `:user`. As rotas de auth sao definidas explicitamente sob
  `login.` (`devise_for :users, skip: :all` + `devise_scope :user`).
- Login cria a sessao (cookie). O cookie e compartilhado com `app.`/`admin.` no
  dominio base via `SESSION_COOKIE_DOMAIN`.
- Cadastro por convite ocorre em `register.` (`registrations#new/create`), a
  partir de `OrganizationRegistrationInvitation`.
- Recuperacao de senha: `passwords#new/create` (solicitacao) e
  `passwords#edit/update` (reset por token enviado por e-mail).
- Confirmacao de conta: `confirmations#show` (link do e-mail) e
  `confirmations#new/create` (reenvio).

Nao ha mais JWT, refresh tokens ou denylist: a autenticacao e inteiramente por
sessao/cookie.

Referencias:
- `config/routes.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/passwords_controller.rb`
- `app/controllers/confirmations_controller.rb`
- `app/controllers/registrations_controller.rb`
- `app/models/user.rb`

## 6. Tenant e Contexto Organizacional

### 6.1 Resolucao de tenant

`ApplicationController#set_current_tenant` (via `resolve_membership`):
- usa `session[:current_organization_id]`;
- senao `current_user.current_organization_id`;
- senao a primeira membership ativa (em organizacao ativa).

A troca de organizacao ativa e feita por `POST organizations/switch`
(`App::OrganizationsController#switch`). Telas que exigem organizacao ativa usam
`ensure_active_organization!`, que redireciona para `no-organization`
(`organization_context_required`).

### 6.2 `Current`

Estado por request (`ActiveSupport::CurrentAttributes`):
- `Current.user`
- `Current.organization`
- `Current.membership`

Referencia:
- `app/models/current.rb`
- `app/controllers/application_controller.rb`

## 7. Autorizacao (Pundit)

### 7.1 Base

`ApplicationPolicy` fornece helpers de:
- ownership;
- tenant match (mesma organizacao);
- papeis (`admin?`, `support?`, `organization_admin?`).

A autorizacao real de cada action e sempre aplicada por Pundit.

### 7.2 Personas e visibilidade de menu

`AccessContext` (`app/models/access_context.rb`) calcula a **persona** do usuario
e a visibilidade de secoes/menu no painel:

- `admin`
- `organization_responsible`
- `doctor`
- `unknown`

A persona controla apenas a navegacao/menus; a checagem de acesso efetiva
permanece nas policies.

### 7.3 Policies implementadas

- `PatientPolicy`
- `ConsultationPolicy`
- `PrescriptionPolicy`
- `MedicalCertificatePolicy`
- `DocumentPolicy`
- `AuditLogPolicy`
- `OrganizationPolicy`
- `DoctorProfilePolicy`

Referencias:
- `app/policies/*.rb`
- `app/models/access_context.rb`

## 8. Modelo de Dominio

### 8.1 Entidades principais

- Organizacao:
  - `organizations`, `units`, `organization_memberships`,
    `organization_responsibles`, `organization_registration_invitations`
- Identidade:
  - `users`, `user_roles`, `doctor_profiles`
- Paciente e conteudo clinico:
  - `patients`, `consultations`, `prescriptions`, `medical_certificates`
- Documento e trilha:
  - `documents`, `document_versions`, `delivery_logs`, `audit_logs`

### 8.2 Relacoes relevantes

- `User` pertence a uma `current_organization` opcional e possui memberships.
- `Patient` pertence a `user` + `organization`.
- `Prescription`/`MedicalCertificate` pertencem a `user` + `patient` + `organization`.
- `Consultation` pertence a `user` + `patient` + `organization`.
- `Document` pertence a `user` + `patient` + `organization` + `unit`, e `documentable` polimorfico.
- `DocumentVersion` pertence a `document` e e imutavel.
- `DeliveryLog` e `AuditLog` vinculam trilha operacional/auditoria.

Referencias:
- `app/models/*.rb`
- `db/schema.rb`

## 9. Estados e Regras de Ciclo de Vida

### 9.1 Prescricao/Atestado

Status:
- `draft`
- `signed`
- `cancelled`

### 9.2 Consulta

Status:
- `scheduled`
- `completed`
- `cancelled`

Transicoes validas:
- `scheduled -> completed`
- `scheduled -> cancelled`

Transicoes invalidas:
- qualquer retorno para `scheduled`
- mudancas a partir de `completed` para outro status
- mudancas a partir de `cancelled` para outro status

### 9.3 Documento

Status:
- `issued`
- `sent`
- `viewed`
- `revoked`
- `expired`

### 9.4 Fluxo principal de emissao e assinatura

1. Criacao de prescricao/atestado (`draft`) nas telas `new/create`.
2. `Documents::LifecycleService#create_with_initial_version!` cria `Document` em
   `issued` + `DocumentVersion v1`.
3. `Documents::SigningService#sign!` (acao `sign` do documento):
  - renderiza o PDF e assina via `Signatures::ProviderFactory` (provider interno
    ou ICP-Brasil);
  - cria nova versao com o PDF assinado anexado;
  - muda `Document` para `sent`;
  - muda o recurso clinico para `signed`;
  - gera eventos de auditoria.
4. `Documents::IntegrityService#verify!` (acao `integrity_check`):
  - compara checksum assinado x conteudo atual;
  - em mismatch, revoga o documento e cancela o recurso.

Referencias:
- `app/services/documents/lifecycle_service.rb`
- `app/services/documents/signing_service.rb`
- `app/services/documents/integrity_service.rb`
- `app/services/signatures/*.rb`

## 10. PDFs e Validacao Publica

- Geracao de PDF nas actions `pdf` de prescricoes/atestados (via
  `Documents::PdfRenderer`, WickedPDF), com timeout configuravel.
- Anexo de PDF em `DocumentVersion#attach_pdf!`.
- Naming padrao de chave:
  - `documents/{document_id}/v{version}/{kind}_{timestamp}.pdf`
- URL assinada apenas em `production/staging`.
- Validacao publica por codigo (sem auth):
  - `GET /validate/:code` (`Public::DocumentValidationsController#show`)
  - retorna validade/status + dados do emissor + QR.

Referencias:
- `app/controllers/app/prescriptions_controller.rb`
- `app/controllers/app/medical_certificates_controller.rb`
- `app/controllers/public/document_validations_controller.rb`
- `app/services/documents/pdf_renderer.rb`
- `app/models/document_version.rb`
- `app/services/documents/public_validation_service.rb`

## 11. Entregas Assincronas (Email/SMS/WhatsApp)

### 11.1 Job

`DocumentChannelDeliveryJob`:
- valida canal e destinatario;
- cria/atualiza `DeliveryLog` com idempotencia;
- faz lock para evitar processamento duplicado;
- despacha via `Deliveries::ChannelDispatcher`;
- marca sucesso/falha e registra auditoria.

### 11.2 Reenvio a partir do painel

Acao `resend` do documento (`App::DocumentsController#resend`,
`POST documents/:id/resend`):
- valida permissao e canal;
- resolve destinatario (parametro ou contato do paciente);
- enfileira o job com metadados.

### 11.3 Politica de retries

- `retry_on`: timeout/transient/unexpected provider
- max tentativas: 5
- backoff exponencial (base 5s, max 300s)
- `discard_on`: erros permanentes, invalidez de entrada, documento inexistente

### 11.4 Adaptadores

- `EmailAdapter`: ActionMailer/SendGrid
- `SmsAdapter`: fake adapter (provider nomeado como Twilio)
- `WhatsappAdapter`: fake adapter (provider nomeado Cloud API)

Referencias:
- `app/jobs/document_channel_delivery_job.rb`
- `app/services/deliveries/*.rb`
- `app/mailers/document_delivery_mailer.rb`

## 12. Rate Limiting das Telas de Auth

O antigo limitador header-based da API JSON foi removido. A protecao das telas
publicas de autenticacao e feita por **rack-attack**
(`config/initializers/rack_attack.rb`), com contadores compartilhados entre
processos via Redis (MemoryStore em `test`).

Throttles configurados (mesmo path em qualquer subdominio):
- `POST /sign-in` por IP e por e-mail
- `POST /sign-up` por IP
- `POST /forgot-password` e `PUT /reset-password` por IP
- `POST /resend-confirmation` por IP

Resposta em excesso:
- status `429`
- header `Retry-After`
- corpo com mensagem amigavel em portugues

Referencia:
- `config/initializers/rack_attack.rb`

## 13. Observabilidade e Logs

### 13.1 Logging estruturado

Formatter JSON com sanitizacao de campos sensiveis (`token`, `cpf`, `email`,
`phone`, etc). A instrumentacao central e o `around_action
:log_request_observability` do `ApplicationController`, que mede latencia e
status por request.

Eventos principais:
- `http_endpoint_monitor` (sempre)
- `http_slow_request` (acima do threshold configurado)
- `http_error` (excecao nao tratada)

### 13.2 Alertas criticos

`Observability::CriticalAlertService` (acionado em erros 500 no
`log_request_observability`):
- deduplicacao por excecao;
- log estruturado;
- envio opcional para Sentry com timeout.

Referencias:
- `lib/prescsign/json_log_formatter.rb`
- `app/controllers/application_controller.rb`
- `app/services/observability/critical_alert_service.rb`

## 14. Seguranca

- Devise com confirmable e reset de senha (autenticacao por sessao/cookie).
- CSRF habilitado (`protect_from_forgery with: :exception`).
- Cookie de sessao compartilhado por subdominio (`SESSION_COOKIE_DOMAIN`); em
  producao a sessao trafega sob SSL forcado.
- rack-attack nas telas de auth (brute-force/abuso).
- `filter_parameter_logging` para mascarar parametros sensiveis.
- Constraints de banco e validacoes de modelo para integridade.

Referencias:
- `config/initializers/devise.rb`
- `config/initializers/rack_attack.rb`
- `config/initializers/filter_parameter_logging.rb`
- `db/schema.rb`

## 15. Configuracao por Ambiente

Centralizada em `config/initializers/app_config.rb` (`config.x.*`).

Blocos principais:
- app host/protocol e dominio base
- Redis
- observabilidade (rollout phase, threshold de slow request)
- retencao
- integracoes externas (S3, SendGrid, Twilio, WhatsApp, Sentry)
- sessao/cookies (`SECRET_KEY_BASE`, `SESSION_COOKIE_DOMAIN`)

Validacoes importantes em `production`:
- variaveis obrigatorias de integracoes habilitadas;
- retencao minima de logs;
- `RETENTION_DOCUMENT_VERSIONS_DAYS` permanente.

Referencia:
- `config/initializers/app_config.rb`
- `.env.example`

## 16. Retencao e Governanca de Dados

Politica MVP documentada em:
- `docs/RETENTION_POLICY.md`

Padrao atual:
- versoes/PDF: permanente
- audit logs: 6 anos
- delivery logs: 5 anos
- tmp: 7 dias
- unattached blobs: 2 dias

## 17. Telas do Painel (Resumo)

- Dashboard
- Pacientes: CRUD
- Consultas: listagem/criacao/edicao + `cancel`
- Agenda: calendario mensal de eventos
- Receitas: `new/create/edit/update`, `revoke`, `pdf`
- Atestados: `new/create/edit/update`, `revoke`, `pdf`
- Documentos: `show`, `sign`, `integrity_check`, `resend`
- Auditoria: listagem
- Medicos responsaveis: listagem + convite por e-mail
- Organizacoes: criacao + troca de tenant ativo
- Perfil e Sobre
- Validacao publica de documento (`/validate/:code`, sem auth)

## 18. Qualidade e Testes

Suite RSpec cobre:
- requests do painel (`spec/requests/app/`), incluindo rate limiting e
  observabilidade
- validacao publica (`spec/requests/public/`)
- policies, models, services e jobs

Helper de suporte: `spec/support/web_spec_helpers.rb` (login por sessao
`sign_in_web` e hosts de subdominio).

Execucao:
```bash
docker compose exec web bundle exec rspec
```

Diretorio:
- `spec/`

## 19. Operacao e Execucao Local

Com Docker Compose (servicos `db`, `redis`, `web`, `nginx`, `sidekiq`):
```bash
docker compose up --build
```

Acesso via nginx (proxy para `web:3000`, porta `NGINX_PORT_HOST`, default `8080`)
usando os subdominios configurados em `/etc/hosts`
(`login.`/`register.`/`app.`/`admin.` sob `prescsign.local`).

Atalhos Make:
```bash
make up-d
make logs-web
make migrate
make console
make rails cmd='db:seed'
```

Health check:
- `GET /up`

## 20. Fontes Primarias Utilizadas

- `README.md`
- `docs/RETENTION_POLICY.md`
- `config/routes.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/app/**`, `app/controllers/public/**`, `app/controllers/admin/**`
- `app/models/**` (incl. `access_context.rb`, `current.rb`)
- `app/policies/**`
- `app/services/**` (incl. `documents/**`, `signatures/**`, `deliveries/**`, `observability/**`)
- `app/jobs/document_channel_delivery_job.rb`
- `config/initializers/**` (incl. `rack_attack.rb`, `app_config.rb`)
- `lib/prescsign/**`
- `db/schema.rb`
- `spec/support/web_spec_helpers.rb`
