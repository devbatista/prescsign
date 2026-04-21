# PrescSign - Documento Tecnico Detalhado

## 1. Objetivo e Escopo

Este documento consolida o estado atual do backend PrescSign com base no codigo-fonte da branch atual.

Inclui:
- arquitetura da aplicacao;
- fluxo de autenticacao, autorizacao e tenant;
- modelo de dominio e ciclo de vida documental;
- jobs assincronos e camada de entregas;
- observabilidade, seguranca e governanca de dados;
- guia operacional e de manutencao.

Nao inclui desenho de frontend (o projeto e API-only no MVP).

## 2. Stack e Runtime

- Linguagem: Ruby 3.3.1
- Framework: Rails 7.1.6 (API-only)
- Banco: PostgreSQL
- Fila/Jobs: Sidekiq + Redis
- Auth: Devise + JWT (denylist)
- Authorization: Pundit
- Storage de arquivo: Active Storage (com suporte S3/R2)
- PDF: WickedPDF
- QR Code: RQRCode

Referencias:
- `README.md`
- `Gemfile`
- `config/initializers/devise.rb`
- `config/initializers/sidekiq.rb`

## 3. Arquitetura da Aplicacao

### 3.1 Estilo arquitetural

- Monolito Rails organizado por camadas:
  - `app/controllers`: API HTTP
  - `app/models`: dominio e persistencia
  - `app/services`: regras de negocio e integracoes
  - `app/policies`: autorizacao (Pundit)
  - `app/jobs`: processamento assincrono

### 3.2 Versionamento de API

- Prefixo oficial: `/api/v1`
- Compatibilidade legada: `/v1`

Implementacao:
- `config/routes.rb`
- `config/routes/api.rb`

### 3.3 Fluxo de request (resumo)

1. Requisicao entra no controller.
2. `authenticate_user!` valida JWT (quando endpoint protegido).
3. `ensure_tenant_context!` resolve organizacao ativa (`Current.organization`).
4. `authorize` e `policy_scope` aplicam regras Pundit.
5. Resposta em envelope padrao (`data`/`meta` ou `errors`).
6. `around_action` registra observabilidade de latencia/status.

Referencias:
- `app/controllers/application_controller.rb`

## 4. Convencoes de Resposta

### 4.1 Sucesso

Formato principal:
```json
{ "data": { ... }, "meta": { ... } }
```

### 4.2 Erro

Formato:
```json
{
  "errors": [{ "code": "...", "message": "..." }],
  "error": "...",
  "error_code": "...",
  "meta": { "request_id": "...", "status": 4xx/5xx }
}
```

- `422` usa `:unprocessable_content`.
- Existe compatibilidade transitoria para campos no topo quando `data` e hash.

Referencia:
- `app/controllers/application_controller.rb`

## 5. Autenticacao e Identidade

## 5.1 Modelo de identidade atual

Entidades principais:
- `User` (credenciais, status, org atual)
- `DoctorProfile` (dados profissionais)
- `UserRole` (papel global)
- `OrganizationMembership` (papel por organizacao)

A identidade da API e centrada em `User`; o perfil medico fica em `DoctorProfile`.

### 5.2 Endpoints de auth

- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `DELETE /v1/auth/logout`
- `GET /v1/auth/me`
- `PATCH|PUT /v1/auth/me`
- `DELETE /v1/auth/me`
- `POST /v1/auth/password`
- `PUT /v1/auth/password`
- `GET|POST /v1/auth/confirmation`

### 5.3 Tokens

- Access token JWT emitido por Devise/Warden.
- Revogacao de JWT via `JwtDenylist`.
- Refresh token persistido em `auth_refresh_tokens` com `token_digest`, `expires_at`, `revoked_at`.

Referencias:
- `app/controllers/v1/auth/*.rb`
- `app/services/auth/refresh_token_service.rb`
- `app/models/user.rb`
- `app/models/auth_refresh_token.rb`
- `app/models/jwt_denylist.rb`

## 6. Tenant e Contexto Organizacional

### 6.1 Resolucao de tenant

`ApplicationController#resolve_current_tenant_context`:
- tenta `X-Organization-Id`;
- senao usa `current_user.current_organization_id`;
- senao primeira membership ativa.

Se nao houver organizacao ativa, retorna `403`.

### 6.2 `Current`

Estado por request:
- `Current.user`
- `Current.organization`
- `Current.membership`

Referencia:
- `app/models/current.rb`
- `app/controllers/application_controller.rb`

## 7. Autorizacao (Pundit)

### 7.1 Base

`ApplicationPolicy` fornece helpers:
- ownership (`owner_record?`)
- tenant match (`same_organization_record?`)
- papeis (`admin?`, `support?`, `organization_admin?`)

### 7.2 Padrao de escopo

Em geral:
- `admin`: escopo global
- `organization_admin`/`support`: todos registros da organizacao ativa
- usuario comum: registros proprios (`user_id`)

### 7.3 Policies implementadas

- `PatientPolicy`
- `PrescriptionPolicy`
- `MedicalCertificatePolicy`
- `DocumentPolicy`
- `AuditLogPolicy`
- `OrganizationPolicy`
- `DoctorProfilePolicy`

Referencias:
- `app/policies/*.rb`

## 8. Modelo de Dominio

## 8.1 Entidades principais

- Organizacao:
  - `organizations`, `units`, `organization_memberships`
- Identidade:
  - `users`, `user_roles`, `doctor_profiles`, `auth_refresh_tokens`, `jwt_denylists`
- Paciente e conteudo clinico:
  - `patients`, `prescriptions`, `medical_certificates`
- Documento e trilha:
  - `documents`, `document_versions`, `delivery_logs`, `audit_logs`
- Confiabilidade de requisicoes:
  - `idempotency_keys`

### 8.2 Relacoes relevantes

- `User` pertence a uma `current_organization` opcional e possui memberships.
- `Patient` pertence a `user` + `organization`.
- `Prescription`/`MedicalCertificate` pertencem a `user` + `patient` + `organization`.
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

### 9.2 Documento

Status:
- `issued`
- `sent`
- `viewed`
- `revoked`
- `expired`

### 9.3 Fluxo principal de emissao e assinatura

1. Criacao de prescricao/atestado (`draft`).
2. `LifecycleService#create_with_initial_version!` cria `Document` em `issued` + `DocumentVersion v1`.
3. `SigningService#sign!`:
  - gera assinatura interna;
  - cria nova versao;
  - muda `Document` para `sent`;
  - muda recurso clinico para `signed`;
  - gera eventos de auditoria.
4. `IntegrityService#verify!`:
  - compara checksum assinado x conteudo atual;
  - em mismatch, revoga documento e cancela recurso.

Referencias:
- `app/services/documents/lifecycle_service.rb`
- `app/services/documents/signing_service.rb`
- `app/services/documents/integrity_service.rb`

## 10. PDFs e Validacao Publica

- Geracao de PDF em endpoints `/pdf` com timeout configuravel.
- Anexo de PDF em `DocumentVersion#attach_pdf!`.
- Naming padrao de chave:
  - `documents/{document_id}/v{version}/{kind}_{timestamp}.pdf`
- URL assinada apenas em `production/staging`.
- Validacao publica por codigo:
  - `GET /v1/public/documents/:code/validation`
  - retorna validade/status + dados do emissor + QR.

Referencias:
- `app/controllers/v1/prescriptions_controller.rb`
- `app/controllers/v1/medical_certificates_controller.rb`
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

### 11.2 Reenvio via API

`POST /v1/documents/:id/resend`:
- valida permissao e canal;
- resolve destinatario (payload ou contato do paciente);
- enfileira job com metadados.

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

## 12. Rate Limiting e Idempotencia

### 12.1 Rate limiting

Implementado em `ApplicationController` + `Prescsign::RateLimiter`.

Buckets configurados:
- `auth_register`
- `auth_login`
- `auth_refresh`
- `auth_password_reset`
- `auth_confirmation_show`
- `auth_confirmation_create`
- `public_document_validation`

Resposta em excesso:
- status `429`
- header `Retry-After`

Referencias:
- `config/initializers/rate_limits.rb`
- `lib/prescsign/rate_limiter.rb`
- `app/controllers/application_controller.rb`

### 12.2 Idempotencia HTTP

- Header: `Idempotency-Key`
- Persistencia: tabela `idempotency_keys`
- Fingerprint: `METHOD|PATH|RAW_BODY` (SHA256)
- Comportamento:
  - mesma chave + mesmo payload: replay da resposta 2xx
  - mesma chave + payload diferente: `409`
  - chave em processamento: `409`

Referencias:
- `app/controllers/application_controller.rb`
- `app/models/idempotency_key.rb`

## 13. Observabilidade e Logs

### 13.1 Logging estruturado

Formatter JSON com sanitizacao de campos sensiveis (`token`, `cpf`, `email`, `phone`, etc).

Eventos principais:
- `http_endpoint_monitor`
- `http_request`
- `http_slow_request`
- `http_error`
- `critical_alert`

### 13.2 Alertas criticos

`Observability::CriticalAlertService`:
- deduplicacao por excecao;
- log estruturado;
- envio opcional para Sentry com timeout.

Referencias:
- `lib/prescsign/json_log_formatter.rb`
- `app/controllers/application_controller.rb`
- `app/services/observability/critical_alert_service.rb`

## 14. Seguranca

- Devise com confirmable e reset de senha.
- JWT com denylist para logout/revogacao.
- CORS por allowlist (`CORS_ALLOWED_ORIGINS`).
- `filter_parameter_logging` para mascarar parametros sensiveis.
- Constrains de banco e validacoes de modelo para integridade.

Referencias:
- `config/initializers/devise.rb`
- `config/initializers/cors.rb`
- `config/initializers/filter_parameter_logging.rb`
- `db/schema.rb`

## 15. Configuracao por Ambiente

Centralizada em `config/initializers/app_config.rb` (`config.x.*`).

Blocos principais:
- endpoint/app host/protocol
- Redis/JWT
- auth/migration flags
- observabilidade
- retencao
- integracoes externas (S3, SendGrid, Twilio, WhatsApp, Sentry)

Validacoes importantes em `production`:
- variaveis obrigatorias de integracoes habilitadas;
- retencao minima de logs;
- `RETENTION_DOCUMENT_VERSIONS_DAYS` permanente.

## 16. Retencao e Governanca de Dados

Politica MVP documentada em:
- `docs/RETENTION_POLICY.md`

Padrao atual:
- versoes/PDF: permanente
- audit logs: 6 anos
- delivery logs: 5 anos
- tmp: 7 dias
- unattached blobs: 2 dias

## 17. Migacao para modelo User-Centrico

Runbook e flags:
- `docs/USERS_MIGRATION_CUTOVER.md`
- `USERS_MIGRATION_PHASE`
- `AUTH_USERS_REQUIRED`
- `AUTH_USERS_FALLBACK_PROVISIONING`
- `USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK`
- `OBS_ROLLOUT_PHASE`

Objetivo: operacao 100% em `users` sem fallback legado.

## 18. Endpoints de Dominio (Resumo)

- Pacientes: CRUD (`/v1/patients`)
- Prescricoes: create/show/update/revoke/pdf
- Atestados: create/show/update/revoke/pdf
- Documentos: show/sign/integrity_check/resend
- Auditoria: listagem filtrada por `document_id` ou `patient_id`
- Organizacoes: listagem e switch de tenant

Contratos detalhados:
- `docs/API_CONTRACTS.md`

## 19. Qualidade e Testes

Suite cobre:
- requests (auth, dominio, rate limit, idempotencia, observabilidade)
- policies
- models
- services
- jobs

Diretorio:
- `spec/`

## 20. Operacao e Execucao Local

Com Docker Compose:
```bash
docker compose up --build
```

Atalhos Make:
```bash
make up-d
make logs-api
make migrate
make console
```

Health checks:
- `GET /up`
- `GET /v1/health`

## 21. Riscos Tecnicos Atuais (observados no estado atual)

- Observabilidade HTTP pode divergir em cenarios de auth no stack Rack (ex.: log interno indicando 200 e resposta final 401 em fluxo do Devise/Warden). Recomendacao: mover metrica de status final para middleware Rack de fim de cadeia.
- Parte da documentacao de contratos ainda usa nomenclaturas antigas (ex.: `doctor`) junto com modelo atual user-centrico; manter revisao periodica para evitar drift.

## 22. Fontes Primarias Utilizadas

- `README.md`
- `docs/API_CONTRACTS.md`
- `docs/RETENTION_POLICY.md`
- `docs/USERS_MIGRATION_CUTOVER.md`
- `config/routes.rb`, `config/routes/api.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/v1/**`
- `app/models/**`
- `app/policies/**`
- `app/services/**`
- `app/jobs/document_channel_delivery_job.rb`
- `config/initializers/**`
- `lib/prescsign/**`
- `db/schema.rb`
