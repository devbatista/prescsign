# PrescSign - Documento Técnico Detalhado

## 1. Objetivo e Escopo

Este documento consolida o estado atual do PrescSign com base no código-fonte da branch atual.

Inclui:
- arquitetura da aplicação;
- fluxo de autenticação, autorização e tenant;
- modelo de domínio e ciclo de vida documental;
- jobs assíncronos e camada de entregas;
- observabilidade, segurança e governança de dados;
- guia operacional e de manutenção.

O sistema é um **monólito Rails renderizado no servidor** (ERB + Tailwind). Não
existe mais SPA/Vue nem API JSON `/api/v1` separada: as telas são servidas
diretamente pelo Rails e a autenticação é por sessão.

## 2. Stack e Runtime

- Linguagem: Ruby 3.3.1
- Framework: Rails 7.1.6 (server-rendered)
- Camada de view: ERB + Tailwind (tailwindcss-rails), assets via Propshaft + importmap (sem build Node, sem Hotwire/Turbo)
- Banco: PostgreSQL
- Fila/Jobs: Sidekiq + Redis
- Auth: Devise (sessão/cookie, escopo `:user`)
- Authorization: Pundit
- Rate limiting das telas de auth: rack-attack (store em Redis; MemoryStore em test)
- Storage de arquivo: Active Storage (com suporte S3/R2)
- PDF: WickedPDF
- QR Code: RQRCode
- Assinatura: providers plugáveis (interno e ICP-Brasil) via `Signatures::ProviderFactory`

Referências:
- `README.md`
- `Gemfile`
- `config/initializers/devise.rb`
- `config/initializers/sidekiq.rb`
- `config/initializers/rack_attack.rb`

## 3. Arquitetura da Aplicação

### 3.1 Estilo arquitetural

- Monólito Rails organizado por camadas:
  - `app/controllers`: controllers HTTP que renderizam ERB
  - `app/views`: telas ERB + Tailwind
  - `app/models`: domínio e persistência
  - `app/services`: regras de negócio e integrações
  - `app/policies`: autorização (Pundit)
  - `app/jobs`: processamento assíncrono

### 3.2 Roteamento por subdomínios

Todo o roteamento é definido em `config/routes.rb` com `constraints subdomain:`.
O domínio base em desenvolvimento é `prescsign.local`. O cookie de sessão é
compartilhado entre os subdomínios.

- `login.` — autenticação (sessão): `sign-in`, `sign-out`, `forgot-password`,
  `reset-password`, `confirm-account`, `resend-confirmation`.
- `register.` — cadastro por convite: `sign-up`.
- `app.` — painel do tenant. Controllers em `app/controllers/app/`, namespace
  `App::`.
- `admin.` — back-office da plataforma (cross-organização).

Fora dos subdomínios:
- validação pública de documentos (sem auth): `GET /validate` e
  `GET /validate/:code` (`Public::DocumentValidationsController`);
- health check: `GET /up`;
- o host base (apex) redireciona para o subdomínio `login.`.

Implementação:
- `config/routes.rb`

### 3.3 Fluxo de request (resumo)

O controller base é `ApplicationController < ActionController::Base`
(`app/controllers/application_controller.rb`):

1. `around_action :log_request_observability` envolve todo o request (latência,
   status, alerta em 500).
2. `before_action :authenticate_user!` (Devise, sessão) — telas públicas e de
   auth fazem `skip` explícito.
3. `before_action :set_current_tenant` resolve a organização ativa por sessão e
   popula `Current`.
4. `authorize` / `policy_scope` aplicam regras Pundit.
5. A action renderiza a view ERB (ou redireciona).

Recursos transversais do controller base:
- `include Pundit::Authorization`
- `protect_from_forgery with: :exception` (CSRF)
- `rescue_from Pundit::NotAuthorizedError` renderizando `shared/forbidden` (403)
- paginação por offset (`paginate`) para telas de listagem
- helpers de view: `current_organization`, `current_membership`,
  `current_persona`, `available_organizations`, `access_context`

Referências:
- `app/controllers/application_controller.rb`

## 4. Camada Web (Painel `App::`)

Controllers em `app/controllers/app/` (subdomínio `app.`):

- `App::DashboardController` — dashboard.
- `App::PatientsController` — CRUD de pacientes.
- `App::ConsultationsController` — consultas (com `cancel`).
- `App::Agenda::EventsController` — agenda (calendário mensal).
- `App::PrescriptionsController` — receitas (`new/create/edit/update`, `revoke`, `pdf`).
- `App::MedicalCertificatesController` — atestados (`new/create/edit/update`, `revoke`, `pdf`).
- `App::DocumentsController` — hub do documento (`show`, `sign`, `integrity_check`, `resend`).
- `App::AuditLogsController` — listagem de auditoria.
- `App::DoctorsController` — médicos da organização (convite por e-mail).
- `App::OrganizationsController` — criação e `switch` de organização ativa.
- `App::ProfileController` — perfil do usuário.
- `App::PagesController` — páginas estáticas (`about`, contexto de organização ausente).

Back-office em `app/controllers/admin/` (subdomínio `admin.`), com
`Admin::BaseController` e `Admin::DashboardController`.

## 5. Autenticação e Identidade

### 5.1 Modelo de identidade

Entidades principais:
- `User` (credenciais, status, org atual)
- `DoctorProfile` (dados profissionais)
- `UserRole` (papel global)
- `OrganizationMembership` (papel por organização)

A identidade é centrada em `User`; o perfil médico fica em `DoctorProfile`.

### 5.2 Fluxo de autenticação (sessão)

- Devise no escopo `:user`. As rotas de auth são definidas explicitamente sob
  `login.` (`devise_for :users, skip: :all` + `devise_scope :user`).
- Login cria a sessão (cookie). O cookie é compartilhado com `app.`/`admin.` no
  domínio base via `SESSION_COOKIE_DOMAIN`.
- Cadastro por convite ocorre em `register.` (`registrations#new/create`), a
  partir de `OrganizationRegistrationInvitation`.
- Recuperação de senha: `passwords#new/create` (solicitação) e
  `passwords#edit/update` (reset por token enviado por e-mail).
- Confirmação de conta: `confirmations#show` (link do e-mail) e
  `confirmations#new/create` (reenvio).

Não há mais JWT, refresh tokens ou denylist: a autenticação é inteiramente por
sessão/cookie.

Referências:
- `config/routes.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/passwords_controller.rb`
- `app/controllers/confirmations_controller.rb`
- `app/controllers/registrations_controller.rb`
- `app/models/user.rb`

## 6. Tenant e Contexto Organizacional

### 6.1 Resolução de tenant

`ApplicationController#set_current_tenant` (via `resolve_membership`):
- usa `session[:current_organization_id]`;
- senão `current_user.current_organization_id`;
- senão a primeira membership ativa (em organização ativa).

A troca de organização ativa é feita por `POST organizations/switch`
(`App::OrganizationsController#switch`). Telas que exigem organização ativa usam
`ensure_active_organization!`, que redireciona para `no-organization`
(`organization_context_required`).

### 6.2 `Current`

Estado por request (`ActiveSupport::CurrentAttributes`):
- `Current.user`
- `Current.organization`
- `Current.membership`

Referência:
- `app/models/current.rb`
- `app/controllers/application_controller.rb`

## 7. Autorização (Pundit)

### 7.1 Base

`ApplicationPolicy` fornece helpers de:
- ownership;
- tenant match (mesma organização);
- papéis (`admin?`, `support?`, `organization_admin?`).

A autorização real de cada action é sempre aplicada por Pundit.

### 7.2 Personas e visibilidade de menu

`AccessContext` (`app/models/access_context.rb`) calcula a **persona** do usuário
e a visibilidade de seções/menu no painel:

- `admin`
- `organization_responsible`
- `doctor`
- `unknown`

A persona controla apenas a navegação/menus; a checagem de acesso efetiva
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

Referências:
- `app/policies/*.rb`
- `app/models/access_context.rb`

## 8. Modelo de Domínio

### 8.1 Entidades principais

- Organização:
  - `organizations`, `units`, `organization_memberships`,
    `organization_responsibles`, `organization_registration_invitations`
- Identidade:
  - `users`, `user_roles`, `doctor_profiles`
- Paciente e conteúdo clínico:
  - `patients`, `consultations`, `prescriptions`, `medical_certificates`
- Documento e trilha:
  - `documents`, `document_versions`, `delivery_logs`, `audit_logs`

### 8.2 Relações relevantes

- `User` pertence a uma `current_organization` opcional e possui memberships.
- `Patient` pertence a `user` + `organization`.
- `Prescription`/`MedicalCertificate` pertencem a `user` + `patient` + `organization`.
- `Consultation` pertence a `user` + `patient` + `organization`.
- `Document` pertence a `user` + `patient` + `organization` + `unit`, e `documentable` polimórfico.
- `DocumentVersion` pertence a `document` e é imutável.
- `DeliveryLog` e `AuditLog` vinculam trilha operacional/auditoria.

Referências:
- `app/models/*.rb`
- `db/schema.rb`

## 9. Estados e Regras de Ciclo de Vida

### 9.1 Prescrição/Atestado

Status:
- `draft`
- `signed`
- `cancelled`

### 9.2 Consulta

Status:
- `scheduled`
- `completed`
- `cancelled`

Transições válidas:
- `scheduled -> completed`
- `scheduled -> cancelled`

Transições inválidas:
- qualquer retorno para `scheduled`
- mudanças a partir de `completed` para outro status
- mudanças a partir de `cancelled` para outro status

### 9.3 Documento

Status:
- `issued`
- `sent`
- `viewed`
- `revoked`
- `expired`

### 9.4 Fluxo principal de emissão e assinatura

1. Criação de prescrição/atestado (`draft`) nas telas `new/create`.
2. `Documents::LifecycleService#create_with_initial_version!` cria `Document` em
   `issued` + `DocumentVersion v1`.
3. `Documents::SigningService#sign!` (ação `sign` do documento):
  - renderiza o PDF e assina via `Signatures::ProviderFactory` (provider interno
    ou ICP-Brasil);
  - cria nova versão com o PDF assinado anexado;
  - muda `Document` para `sent`;
  - muda o recurso clínico para `signed`;
  - gera eventos de auditoria.
4. `Documents::IntegrityService#verify!` (ação `integrity_check`):
  - compara checksum assinado x conteúdo atual;
  - em mismatch, revoga o documento e cancela o recurso.

Referências:
- `app/services/documents/lifecycle_service.rb`
- `app/services/documents/signing_service.rb`
- `app/services/documents/integrity_service.rb`
- `app/services/signatures/*.rb`

## 10. PDFs e Validação Pública

- Geração de PDF nas actions `pdf` de prescrições/atestados (via
  `Documents::PdfRenderer`, WickedPDF), com timeout configurável.
- Anexo de PDF em `DocumentVersion#attach_pdf!`.
- Naming padrão de chave:
  - `documents/{document_id}/v{version}/{kind}_{timestamp}.pdf`
- URL assinada apenas em `production/staging`.
- Validação pública por código (sem auth):
  - `GET /validate/:code` (`Public::DocumentValidationsController#show`)
  - retorna validade/status + dados do emissor + QR.

Referências:
- `app/controllers/app/prescriptions_controller.rb`
- `app/controllers/app/medical_certificates_controller.rb`
- `app/controllers/public/document_validations_controller.rb`
- `app/services/documents/pdf_renderer.rb`
- `app/models/document_version.rb`
- `app/services/documents/public_validation_service.rb`

## 11. Entregas Assíncronas (Email/SMS/WhatsApp)

### 11.1 Job

`DocumentChannelDeliveryJob`:
- valida canal e destinatário;
- cria/atualiza `DeliveryLog` com idempotência;
- faz lock para evitar processamento duplicado;
- despacha via `Deliveries::ChannelDispatcher`;
- marca sucesso/falha e registra auditoria.

### 11.2 Reenvio a partir do painel

Ação `resend` do documento (`App::DocumentsController#resend`,
`POST documents/:id/resend`):
- valida permissão e canal;
- resolve destinatário (parâmetro ou contato do paciente);
- enfileira o job com metadados.

### 11.3 Política de retries

- `retry_on`: timeout/transient/unexpected provider
- máximo de tentativas: 5
- backoff exponencial (base 5s, máximo 300s)
- `discard_on`: erros permanentes, invalidez de entrada, documento inexistente

### 11.4 Adaptadores

- `EmailAdapter`: ActionMailer; em produção o relay é SMTP (AWS SES)
- `WhatsappAdapter`: Twilio (Programmable Messaging API), via `Deliveries::TwilioClient`
- `SmsAdapter`: sem provedor integrado — levanta `PermanentProviderError`

**Disponibilidade de canal.** Cada adapter responde `self.available?`, e
`Deliveries::AdapterFactory.available?/available_channels` é a fonte única
consultada tanto pela tela do documento (que monta o seletor a partir dela)
quanto pelo `resend` (que recusa antes de enfileirar o job). O default em
`BaseAdapter` é `false`: adapter novo nasce indisponível e não vira promessa de
envio por esquecimento. `DeliveryLog::CHANNELS` mantém `sms` e `whatsapp`
porque registros históricos usam esses valores.

Nenhum adapter simula entrega. Antes existia um adapter falso que respondia
`sent` para SMS e WhatsApp, o que gravava no `DeliveryLog` e na auditoria uma
entrega ao paciente que nunca ocorreu.

### 11.5 WhatsApp via Twilio

`Deliveries::TwilioClient` fala direto com a API (Net::HTTP puro, como
`Sncr::Client` e os providers de assinatura — sem gem adicional):
`POST /2010-04-01/Accounts/{AccountSid}/Messages.json`, Basic Auth com
`AccountSid`/`AuthToken`, corpo form-encoded. `To` e `From` levam o prefixo de
canal `whatsapp:` sobre o número em E.164.

Configuração (`config.x.twilio`): `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`,
`TWILIO_WHATSAPP_FROM` e `TWILIO_TIMEOUT_SECONDS` (default 8s, propositalmente
abaixo do timeout do dispatcher, para que o erro que chega ao job seja o do
HTTP e não o genérico). O canal só fica disponível com `ACCOUNT_SID` e
`WHATSAPP_FROM` preenchidos.

Telefone: `Patient` guarda só dígitos, sem DDI. `Deliveries::PhoneNumber.to_e164`
aceita número nacional (10 ou 11 dígitos, ao qual aplica o DDI 55) e número que
já traz o DDI; qualquer outro comprimento é recusado com falha permanente, em
vez de adivinhar e mandar documento de saúde para o número errado.

Classificação de erro:
- 4xx (exceto 429) e mensagem devolvida com status `failed`/`undelivered`, mesmo
  sob HTTP 2xx: `PermanentProviderError` (sem retry);
- 429 e 5xx: `TransientProviderError` (entra na política de retry);
- falhas de rede sobem cruas e o `ErrorClassifier` as trata como transitórias.

**Limites do Sandbox** (ambientes de teste): o destinatário precisa enviar
`join <código>` para o número compartilhado `+14155238886`, a adesão expira em
três dias, o número envia no máximo uma mensagem a cada três segundos e mensagem
livre só sai dentro da janela de 24h aberta pela última mensagem do
destinatário. Fora da janela o Twilio exige template aprovado e recusa o envio —
a recusa vira `failed` no `DeliveryLog`, com `error_code` do Twilio no metadata.

**Ainda não implementado:** webhook de status (`StatusCallback`). Sem ele,
`sent` significa "o Twilio aceitou a mensagem", não "o paciente recebeu" — a
mesma limitação que o e-mail tem hoje com o SES.

Remetente dos e-mails (`Mailers::SenderAddress`): o endereço é sempre
`SMTP_FROM_EMAIL`, do domínio verificado no SES — trocar o domínio quebraria
DKIM/DMARC. Só o nome exibido varia: e-mails de plataforma saem como
`SMTP_FROM_NAME` (default "PrescSign") e o e-mail de documento ao paciente sai
como "Dr. Fulano via PrescSign", creditando o profissional que o paciente
reconhece.

Referências:
- `app/jobs/document_channel_delivery_job.rb`
- `app/services/deliveries/*.rb` (incl. `twilio_client.rb`, `phone_number.rb`)
- `app/mailers/document_delivery_mailer.rb`
- `app/services/mailers/sender_address.rb`
- `app/services/documents/patient_links.rb`

## 12. Rate Limiting das Telas de Auth

O antigo limitador header-based da API JSON foi removido. A proteção das telas
públicas de autenticação é feita por **rack-attack**
(`config/initializers/rack_attack.rb`), com contadores compartilhados entre
processos via Redis (MemoryStore em `test`).

Throttles configurados (mesmo path em qualquer subdomínio):
- `POST /sign-in` por IP e por e-mail
- `POST /sign-up` por IP
- `POST /forgot-password` e `PUT /reset-password` por IP
- `POST /resend-confirmation` por IP

Resposta em excesso:
- status `429`
- header `Retry-After`
- corpo com mensagem amigável em português

Referência:
- `config/initializers/rack_attack.rb`

## 13. Observabilidade e Logs

### 13.1 Logging estruturado

Formatter JSON com sanitização de campos sensíveis (`token`, `cpf`, `email`,
`phone`, etc). A instrumentação central é o `around_action
:log_request_observability` do `ApplicationController`, que mede latência e
status por request.

Eventos principais:
- `http_endpoint_monitor` (sempre)
- `http_slow_request` (acima do threshold configurado)
- `http_error` (exceção não tratada)

### 13.2 Alertas críticos

`Observability::CriticalAlertService` (acionado em erros 500 no
`log_request_observability`):
- deduplicação por exceção;
- log estruturado;
- envio opcional para Sentry com timeout.

Referências:
- `lib/prescsign/json_log_formatter.rb`
- `app/controllers/application_controller.rb`
- `app/services/observability/critical_alert_service.rb`

## 14. Segurança

- Devise com confirmable e reset de senha (autenticação por sessão/cookie).
- CSRF habilitado (`protect_from_forgery with: :exception`).
- Cookie de sessão compartilhado por subdomínio (`SESSION_COOKIE_DOMAIN`); em
  produção a sessão trafega sob SSL forçado.
- rack-attack nas telas de auth (brute-force/abuso).
- `filter_parameter_logging` para mascarar parâmetros sensíveis.
- Constraints de banco e validações de modelo para integridade.

Referências:
- `config/initializers/devise.rb`
- `config/initializers/rack_attack.rb`
- `config/initializers/filter_parameter_logging.rb`
- `db/schema.rb`

## 15. Configuração por Ambiente

Centralizada em `config/initializers/app_config.rb` (`config.x.*`).

Blocos principais:
- app host/protocol e domínio base
- Redis
- observabilidade (rollout phase, threshold de slow request)
- retenção
- integrações externas (S3, SMTP/SES, Twilio, WhatsApp, Sentry)
- sessão/cookies (`SECRET_KEY_BASE`, `SESSION_COOKIE_DOMAIN`)

Validações importantes em `production`:
- variáveis obrigatórias de integrações habilitadas;
- retenção mínima de logs;
- `RETENTION_DOCUMENT_VERSIONS_DAYS` permanente.

Referência:
- `config/initializers/app_config.rb`
- `.env.example`

## 16. Retenção e Governança de Dados

Política MVP documentada em:
- `docs/RETENTION_POLICY.md`

Padrão atual:
- versões/PDF: permanente
- audit logs: 6 anos
- delivery logs: 5 anos
- tmp: 7 dias
- unattached blobs: 2 dias

## 17. Telas do Painel (Resumo)

- Dashboard
- Pacientes: CRUD
- Consultas: listagem/criação/edição + `cancel`
- Agenda: calendário mensal de eventos
- Receitas: `new/create/edit/update`, `revoke`, `pdf`
- Atestados: `new/create/edit/update`, `revoke`, `pdf`
- Documentos: `show`, `sign`, `integrity_check`, `resend`
- Auditoria: listagem
- Médicos responsáveis: listagem + convite por e-mail
- Organizações: criação + troca de tenant ativo
- Perfil e Sobre
- Validação pública de documento (`/validate/:code`, sem auth)

## 18. Qualidade e Testes

Suíte RSpec cobre:
- requests do painel (`spec/requests/app/`), incluindo rate limiting e
  observabilidade
- validação pública (`spec/requests/public/`)
- policies, models, services e jobs

Helper de suporte: `spec/support/web_spec_helpers.rb` (login por sessão
`sign_in_web` e hosts de subdomínio).

Execução:
```bash
docker compose exec web bundle exec rspec
```

Diretório:
- `spec/`

## 19. Operação e Execução Local

Com Docker Compose (serviços `db`, `redis`, `web`, `nginx`, `sidekiq`):
```bash
docker compose up --build
```

Acesso via nginx (proxy para `web:3000`, porta `NGINX_PORT_HOST`, default `8080`)
usando os subdomínios configurados em `/etc/hosts`
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

## 20. Fontes Primárias Utilizadas

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
