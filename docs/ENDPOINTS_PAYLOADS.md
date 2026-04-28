# Endpoints e Payloads da API (Completo)

Atualizado em: 2026-04-28
Fonte: rotas e controllers atuais do projeto.

## 1. Convenções Globais

## 1.1 Prefixos

- Prefixo oficial: `/api/v1`
- Prefixo legado compatível: `/v1`

Todos os endpoints abaixo funcionam com os dois prefixos, exceto `/up`.

## 1.2 Autenticação

- Endpoints protegidos exigem header:
  - `Authorization: Bearer <access_token>`

## 1.3 Tenant (multi-organização)

- Header opcional quando usuário pertence a múltiplas organizações:
  - `X-Organization-Id: <organization_id>`

## 1.4 Formato de sucesso

```json
{
  "data": {},
  "meta": {}
}
```

Observação: por compatibilidade, quando `data` é objeto, alguns campos também aparecem no topo da resposta.

## 1.5 Formato de erro

```json
{
  "errors": [{ "code": "unauthorized", "message": "..." }],
  "error": "...",
  "error_code": "unauthorized",
  "meta": {
    "request_id": "...",
    "status": 401
  }
}
```

## 1.6 Paginação e ordenação

Endpoints com lista usam:

- `page` (default 1)
- `per_page` (default 20, máximo 100)
- `sort_by` (whitelist por endpoint)
- `sort_dir` (`asc` ou `desc`)

`meta`:

- `page`, `per_page`, `total`, `total_pages`, `sort_by`, `sort_dir`

## 1.7 Idempotência

Endpoints com suporte:

- `POST /prescriptions`
- `POST /prescriptions/:id/revoke`
- `POST /medical_certificates`
- `POST /medical_certificates/:id/revoke`
- `POST /documents/:id/sign`
- `POST /documents/:id/resend`

Header opcional:

- `Idempotency-Key: <chave>`

## 2. Health

## 2.1 GET /up

- Auth: não
- Response 200 (Rails health check)

## 2.2 GET /health

- Auth: não
- Response 200:

```json
{
  "data": { "status": "ok" },
  "status": "ok"
}
```

## 3. Auth

## 3.1 POST /auth/register

- Auth: não
- Rate limit: `auth_register`

Request payload:

```json
{
  "doctor": {
    "full_name": "Dra Ana Lima",
    "email": "ana@example.com",
    "cpf": "12345678901",
    "license_number": "CRM12345",
    "license_state": "SP",
    "specialty": "Cardiologia",
    "password": "password123",
    "password_confirmation": "password123"
  }
}
```

Também aceita envelope `user` com os mesmos campos.

Response 201:

```json
{
  "data": {
    "message": "Registration successful. Please confirm your email.",
    "doctor": {
      "id": "uuid",
      "full_name": "Dra Ana Lima",
      "email": "ana@example.com",
      "license_number": "CRM12345",
      "license_state": "SP",
      "specialty": "Cardiologia",
      "active": true,
      "created_at": "...",
      "updated_at": "...",
      "current_organization_id": "uuid",
      "role": "owner",
      "cpf_masked": "***.***.***-01"
    },
    "user": {
      "id": "uuid",
      "email": "ana@example.com",
      "status": "active",
      "doctor_profile_id": "uuid",
      "current_organization_id": "uuid",
      "roles": ["doctor"]
    }
  }
}
```

## 3.2 POST /auth/login

- Auth: não
- Rate limit: `auth_login`

Request payload:

```json
{
  "doctor": {
    "email": "ana@example.com",
    "password": "password123"
  }
}
```

Também aceita envelope `user`.

Response 200:

```json
{
  "data": {
    "access_token": "jwt",
    "refresh_token": "token",
    "doctor": {
      "id": "uuid",
      "full_name": "Dra Ana Lima",
      "email": "ana@example.com",
      "license_number": "CRM12345",
      "license_state": "SP",
      "specialty": "Cardiologia",
      "active": true,
      "created_at": "...",
      "updated_at": "...",
      "current_organization_id": "uuid",
      "role": "owner",
      "cpf_masked": "***.***.***-01"
    },
    "user": {
      "id": "uuid",
      "email": "ana@example.com",
      "status": "active",
      "doctor_profile_id": "uuid",
      "current_organization_id": "uuid",
      "roles": ["doctor"]
    }
  }
}
```

Erros comuns:

- 401 `Invalid email or password`
- 401 `Please confirm your email before logging in`
- 401 `Account is inactive`

## 3.3 POST /auth/refresh

- Auth: não
- Rate limit: `auth_refresh`

Request payload:

```json
{
  "refresh_token": "token"
}
```

Response 200: mesmo formato de `POST /auth/login` com novos tokens.

Erro comum:

- 401 `Invalid refresh token`

## 3.4 DELETE /auth/logout

- Auth: sim

Response:

- 204 sem body

## 3.5 POST /auth/password

- Auth: não
- Rate limit: `auth_password_reset`

Request payload:

```json
{
  "doctor": {
    "email": "ana@example.com"
  }
}
```

Também aceita envelope `user`.

Response 200:

```json
{
  "data": {
    "message": "If this email exists, reset instructions were sent"
  }
}
```

## 3.6 PUT /auth/password

- Auth: não

Request payload:

```json
{
  "doctor": {
    "reset_password_token": "token",
    "password": "newpassword123",
    "password_confirmation": "newpassword123"
  }
}
```

Também aceita envelope `user`.

Response 200:

```json
{
  "data": {
    "message": "Password updated successfully"
  }
}
```

Erro comum:

- 422 com mensagens de validação do Devise

## 3.7 GET /auth/confirmation

- Auth: não
- Rate limit: `auth_confirmation_show`

Query params:

- `confirmation_token`

Response 200:

```json
{
  "data": {
    "message": "Email confirmed successfully"
  }
}
```

Erro comum:

- 422 com mensagens de token inválido/expirado

## 3.8 POST /auth/confirmation

- Auth: não
- Rate limit: `auth_confirmation_create`

Request payload:

```json
{
  "doctor": {
    "email": "ana@example.com"
  }
}
```

Também aceita envelope `user`.

Response 200:

```json
{
  "data": {
    "message": "Confirmation instructions sent"
  }
}
```

## 3.9 GET /auth/me

- Auth: sim

Response 200:

```json
{
  "data": {
    "id": "uuid",
    "full_name": "Dra Ana Lima",
    "email": "ana@example.com",
    "license_number": "CRM12345",
    "license_state": "SP",
    "specialty": "Cardiologia",
    "active": true,
    "created_at": "...",
    "updated_at": "...",
    "current_organization_id": "uuid",
    "role": "owner",
    "cpf_masked": "***.***.***-01"
  }
}
```

## 3.10 PATCH /auth/me e PUT /auth/me

- Auth: sim

Request payload:

```json
{
  "doctor": {
    "email": "novo-email@example.com",
    "password": "password123",
    "password_confirmation": "password123",
    "full_name": "Dra Ana Atualizada",
    "cpf": "12345678901",
    "license_number": "CRM54321",
    "license_state": "RJ",
    "specialty": "Clinica Geral"
  }
}
```

Todos os campos são opcionais.

Response 200: mesmo contrato de `GET /auth/me`.

## 3.11 DELETE /auth/me

- Auth: sim

Efeito:

- `user.status = inactive`
- `doctor_profile.active = false`

Response:

- 204 sem body

## 4. Organizações

## 4.1 GET /organizations

- Auth: sim

Query params:

- `page`, `per_page`, `sort_by` (`created_at`), `sort_dir`

Response 200:

```json
{
  "data": {
    "current_organization_id": "uuid",
    "organizations": [
      {
        "id": "uuid",
        "name": "Clinica X",
        "legal_name": "Clinica X LTDA",
        "trade_name": "Clinica X",
        "cnpj": "12345678000199",
        "email": "contato@clinicax.com",
        "phone": "11999990000",
        "zip_code": "01001000",
        "street": "Rua A",
        "number": "123",
        "complement": "Sala 10",
        "district": "Centro",
        "city": "Sao Paulo",
        "state": "SP",
        "country": "BR",
        "kind": "clinica",
        "active": true,
        "metadata": {},
        "units": [
          {
            "id": "uuid",
            "name": "Principal",
            "code": "HQ",
            "active": true
          }
        ],
        "role": "owner",
        "status": "active"
      }
    ]
  },
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 1,
    "total_pages": 1,
    "sort_by": "created_at",
    "sort_dir": "asc"
  }
}
```

## 4.2 POST /organizations/:organization_id/switch

- Auth: sim

Request payload:

- sem body

Response 200:

```json
{
  "data": {
    "current_organization_id": "uuid",
    "organization": {
      "id": "uuid",
      "name": "Clinica X",
      "legal_name": "Clinica X LTDA",
      "trade_name": "Clinica X",
      "cnpj": "12345678000199",
      "email": "contato@clinicax.com",
      "phone": "11999990000",
      "zip_code": "01001000",
      "street": "Rua A",
      "number": "123",
      "complement": "Sala 10",
      "district": "Centro",
      "city": "Sao Paulo",
      "state": "SP",
      "country": "BR",
      "kind": "clinica",
      "active": true,
      "metadata": {},
      "units": [
        {
          "id": "uuid",
          "name": "Principal",
          "code": "HQ",
          "active": true
        }
      ]
    },
    "membership": {
      "role": "doctor",
      "status": "active"
    }
  }
}
```

Erro comum:

- 404 `Organization not found for current user`

## 5. Pacientes

## 5.1 GET /patients

- Auth: sim

Query params:

- `q` (busca por nome/cpf)
- `page`, `per_page`, `sort_by` (`full_name`, `created_at`, `updated_at`), `sort_dir`

Response 200:

```json
{
  "data": [
    {
      "id": "uuid",
      "organization_id": "uuid",
      "user_id": "uuid",
      "full_name": "Paciente Teste",
      "cpf": "12345678901",
      "birth_date": "1990-01-01",
      "email": "paciente@example.com",
      "phone": "11999990000",
      "active": true,
      "created_at": "...",
      "updated_at": "..."
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 1,
    "total_pages": 1,
    "sort_by": "full_name",
    "sort_dir": "asc"
  }
}
```

## 5.2 GET /patients/:id

- Auth: sim

Response 200: objeto de paciente igual ao item da listagem.

## 5.3 POST /patients

- Auth: sim

Request payload:

```json
{
  "patient": {
    "full_name": "Paciente Teste",
    "cpf": "12345678901",
    "birth_date": "1990-01-01",
    "email": "paciente@example.com",
    "phone": "11999990000",
    "active": true
  }
}
```

Response 201: objeto de paciente igual ao item da listagem.

## 5.4 PATCH /patients/:id

- Auth: sim

Request payload:

```json
{
  "patient": {
    "full_name": "Paciente Atualizado",
    "phone": "11988887777"
  }
}
```

Response 200: objeto de paciente atualizado.

## 5.5 DELETE /patients/:id

- Auth: sim

Efeito:

- soft delete lógico: `active = false`

Response:

- 204 sem body

## 6. Prescrições

## 6.1 POST /prescriptions

- Auth: sim
- Idempotência: suportada

Request payload:

```json
{
  "prescription": {
    "patient_id": "uuid",
    "unit_id": "uuid",
    "content": "Tomar 1 comprimido ao dia",
    "issued_on": "2026-04-21",
    "valid_until": "2026-05-21"
  }
}
```

`unit_id` é opcional (usa unidade padrão da organização).

Response 201:

```json
{
  "data": {
    "prescription": {
      "id": "uuid",
      "organization_id": "uuid",
      "user_id": "uuid",
      "patient_id": "uuid",
      "code": "ABC123DEF4",
      "content": "Tomar 1 comprimido ao dia",
      "issued_on": "2026-04-21",
      "valid_until": "2026-05-21",
      "status": "draft",
      "created_at": "...",
      "updated_at": "..."
    },
    "document": {
      "id": "uuid",
      "organization_id": "uuid",
      "unit_id": "uuid",
      "code": "XYZ987ABCD",
      "kind": "prescription",
      "status": "issued",
      "current_version": 1,
      "issued_on": "2026-04-21",
      "cancelled_at": null,
      "created_at": "...",
      "updated_at": "..."
    },
    "latest_version": {
      "id": "uuid",
      "version_number": 1,
      "checksum": "sha256...",
      "generated_at": "...",
      "pdf_signed_url": null,
      "pdf_signed_url_expires_in": 900
    }
  }
}
```

## 6.2 GET /prescriptions/:id

- Auth: sim

Response 200: mesmo contrato de `POST /prescriptions`.

## 6.3 PATCH /prescriptions/:id

- Auth: sim

Request payload:

```json
{
  "prescription": {
    "content": "Novo conteúdo",
    "issued_on": "2026-04-21",
    "valid_until": "2026-05-21"
  }
}
```

Response 200: mesmo contrato de `POST /prescriptions`.

Erro comum:

- 422 `Prescription can only be updated before signature`

## 6.4 POST /prescriptions/:id/revoke

- Auth: sim
- Idempotência: suportada

Request payload:

```json
{
  "revoke": {
    "reason": "texto opcional"
  }
}
```

Response 200: mesmo contrato de `POST /prescriptions`.

## 6.5 GET /prescriptions/:id/pdf

- Auth: sim

Response 200:

- `Content-Type: application/pdf`
- Body binário (PDF inline)

Erro comum:

- 504 `PDF generation timed out`

## 7. Atestados

## 7.1 POST /medical_certificates

- Auth: sim
- Idempotência: suportada

Request payload:

```json
{
  "medical_certificate": {
    "patient_id": "uuid",
    "unit_id": "uuid",
    "content": "Afastamento por 3 dias",
    "issued_on": "2026-04-21",
    "rest_start_on": "2026-04-21",
    "rest_end_on": "2026-04-23",
    "icd_code": "J11"
  }
}
```

Response 201:

```json
{
  "data": {
    "medical_certificate": {
      "id": "uuid",
      "organization_id": "uuid",
      "user_id": "uuid",
      "patient_id": "uuid",
      "code": "ABC123DEF4",
      "content": "Afastamento por 3 dias",
      "issued_on": "2026-04-21",
      "rest_start_on": "2026-04-21",
      "rest_end_on": "2026-04-23",
      "icd_code": "J11",
      "status": "draft",
      "created_at": "...",
      "updated_at": "..."
    },
    "document": {
      "id": "uuid",
      "organization_id": "uuid",
      "unit_id": "uuid",
      "code": "XYZ987ABCD",
      "kind": "medical_certificate",
      "status": "issued",
      "current_version": 1,
      "issued_on": "2026-04-21",
      "cancelled_at": null,
      "created_at": "...",
      "updated_at": "..."
    },
    "latest_version": {
      "id": "uuid",
      "version_number": 1,
      "checksum": "sha256...",
      "generated_at": "...",
      "pdf_signed_url": null,
      "pdf_signed_url_expires_in": 900
    }
  }
}
```

## 7.2 GET /medical_certificates/:id

- Auth: sim

Response 200: mesmo contrato de `POST /medical_certificates`.

## 7.3 PATCH /medical_certificates/:id

- Auth: sim

Request payload:

```json
{
  "medical_certificate": {
    "content": "Novo conteúdo",
    "issued_on": "2026-04-21",
    "rest_start_on": "2026-04-21",
    "rest_end_on": "2026-04-23",
    "icd_code": "A00"
  }
}
```

Response 200: mesmo contrato de `POST /medical_certificates`.

Erro comum:

- 422 `Medical certificate can only be updated before signature`

## 7.4 POST /medical_certificates/:id/revoke

- Auth: sim
- Idempotência: suportada

Request payload:

```json
{
  "revoke": {
    "reason": "texto opcional"
  }
}
```

Response 200: mesmo contrato de `POST /medical_certificates`.

## 7.5 GET /medical_certificates/:id/pdf

- Auth: sim

Response 200:

- `Content-Type: application/pdf`
- Body binário (PDF inline)

Erro comum:

- 504 `PDF generation timed out`

## 8. Documentos

## 8.1 GET /documents/:id

- Auth: sim

Response 200:

```json
{
  "data": {
    "id": "uuid",
    "organization_id": "uuid",
    "unit_id": "uuid",
    "user_id": "uuid",
    "patient_id": "uuid",
    "code": "XYZ987ABCD",
    "kind": "prescription",
    "status": "issued",
    "current_version": 1,
    "signed_at": null,
    "cancelled_at": null,
    "metadata": {},
    "documentable_type": "Prescription",
    "documentable_id": "uuid"
  }
}
```

## 8.2 POST /documents/:id/sign

- Auth: sim
- Idempotência: suportada

Request payload:

- sem body

Response 200: mesmo contrato de `GET /documents/:id` (com status atualizado quando assinado).

Erro comum:

- 422 `Document is not signable`

## 8.3 POST /documents/:id/integrity_check

- Auth: sim

Request payload:

- sem body

Response 200:

```json
{
  "data": {
    "valid": true,
    "document": {
      "id": "uuid",
      "organization_id": "uuid",
      "unit_id": "uuid",
      "user_id": "uuid",
      "patient_id": "uuid",
      "code": "XYZ987ABCD",
      "kind": "prescription",
      "status": "sent",
      "current_version": 2,
      "signed_at": "...",
      "cancelled_at": null,
      "metadata": {},
      "documentable_type": "Prescription",
      "documentable_id": "uuid"
    }
  }
}
```

## 8.4 POST /documents/:id/resend

- Auth: sim
- Idempotência: suportada

Request payload:

```json
{
  "resend": {
    "channel": "email",
    "recipient": "destino@example.com",
    "idempotency_key": "document:uuid:channel:email:recipient:destino@example.com",
    "metadata": {
      "trigger": "manual"
    }
  }
}
```

`recipient` opcional. Se ausente:

- `email` usa `patient.email`
- `sms`/`whatsapp` usam `patient.phone`

Response 202:

```json
{
  "data": {
    "message": "Document resend queued",
    "document_id": "uuid",
    "channel": "email",
    "recipient": "destino@example.com",
    "idempotency_key": "document:uuid:channel:email:recipient:destino@example.com"
  }
}
```

Erros comuns:

- 422 `Unsupported channel`
- 422 `Recipient is required for selected channel`

## 9. Auditoria

## 9.1 GET /audit_logs

- Auth: sim

Query params:

- obrigatório ao menos um: `document_id` ou `patient_id`
- opcionais: `page`, `per_page`, `sort_by` (`occurred_at`, `created_at`), `sort_dir`

Response 200:

```json
{
  "data": [
    {
      "id": "uuid",
      "organization_id": "uuid",
      "unit_id": "uuid",
      "user_id": "uuid",
      "actor_type": "User",
      "actor_id": "uuid",
      "patient_id": "uuid",
      "document_id": "uuid",
      "resource_type": "Document",
      "resource_id": "uuid",
      "action": "viewed",
      "before_data": {},
      "after_data": { "context": "documents_show" },
      "request_id": "...",
      "request_origin": "...",
      "ip_address": "...",
      "user_agent": "...",
      "occurred_at": "...",
      "created_at": "..."
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 1,
    "total_pages": 1,
    "sort_by": "occurred_at",
    "sort_dir": "desc"
  }
}
```

Erro comum:

- 422 `At least one filter is required: document_id or patient_id`

## 10. Validação Pública

## 10.1 GET /public/documents/:code/validation

- Auth: não
- Rate limit: `public_document_validation`

Request payload:

- sem body

Response 200:

```json
{
  "data": {
    "valid": true,
    "status_reason": null,
    "document": {
      "code": "XYZ987ABCD",
      "kind": "prescription",
      "status": "sent",
      "issued_on": "2026-04-21",
      "current_version": 2
    },
    "issuer": {
      "full_name": "Dra Ana Lima",
      "license_number": "CRM12345",
      "license_state": "SP"
    },
    "validation": {
      "url": "https://api.exemplo.com/v1/public/documents/XYZ987ABCD/validation",
      "qr_code_svg": "<svg ...>...</svg>"
    }
  }
}
```

Erro comum:

- 404 `Document not found`
- nesse erro, `meta.valid` é retornado como `false`

## 11. Consultas (Consultations)

## 11.1 Regras de autorização

- Auth: sim em todos endpoints de consultas
- `support`: somente leitura (`index`, `show`)
- membro da organização ativa (`doctor`, `manager`, `owner`, `admin` de membership): leitura e escrita
- `admin`/`super_admin` (user role): escopo ampliado conforme policy
- isolamento por tenant sempre aplicado via `policy_scope` + `current_organization`

## 11.2 Status e transições

Status suportados:

- `scheduled`
- `completed`
- `cancelled`

Transições válidas no update:

- `scheduled -> completed`
- `scheduled -> cancelled`

Transições inválidas:

- qualquer retorno para `scheduled`
- mudança de `completed` para outro status
- mudança de `cancelled` para outro status

Em `POST /consultations/:id/cancel`, o status é definido para `cancelled` e `finished_at` é preenchido com `now` se estiver nulo.

## 11.3 GET /patients/:patient_id/consultations

- Auth: sim

Query params:

- `status` (`scheduled`, `completed`, `cancelled`)
- `scheduled_from` (datetime ISO8601)
- `scheduled_to` (datetime ISO8601)
- `page`, `per_page`
- `sort_by` (`scheduled_at`, `created_at`, `updated_at`)
- `sort_dir` (`asc`, `desc`)

Response 200:

```json
{
  "data": [
    {
      "id": "uuid",
      "organization_id": "uuid",
      "patient_id": "uuid",
      "user_id": "uuid",
      "scheduled_at": "2026-04-28T14:00:00Z",
      "finished_at": null,
      "status": "scheduled",
      "chief_complaint": "Dor de cabeca",
      "notes": null,
      "diagnosis": null,
      "metadata": {},
      "created_at": "...",
      "updated_at": "..."
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 1,
    "total_pages": 1,
    "sort_by": "scheduled_at",
    "sort_dir": "desc"
  }
}
```

## 11.4 POST /patients/:patient_id/consultations

- Auth: sim

Request payload:

```json
{
  "consultation": {
    "scheduled_at": "2026-04-29T13:30:00Z",
    "finished_at": null,
    "status": "scheduled",
    "chief_complaint": "Dor lombar",
    "notes": "Paciente relata piora ha 2 dias",
    "diagnosis": null,
    "metadata": { "source": "app" }
  }
}
```

Response 201:

```json
{
  "data": {
    "id": "uuid",
    "organization_id": "uuid",
    "patient_id": "uuid",
    "user_id": "uuid",
    "scheduled_at": "2026-04-29T13:30:00Z",
    "finished_at": null,
    "status": "scheduled",
    "chief_complaint": "Dor lombar",
    "notes": "Paciente relata piora ha 2 dias",
    "diagnosis": null,
    "metadata": { "source": "app" },
    "created_at": "...",
    "updated_at": "..."
  }
}
```

## 11.5 GET /consultations/:id

- Auth: sim

Response 200: mesmo contrato do item `POST /patients/:patient_id/consultations`.

## 11.6 PATCH /consultations/:id

- Auth: sim

Request payload:

```json
{
  "consultation": {
    "status": "completed",
    "finished_at": "2026-04-29T14:10:00Z",
    "notes": "Evolucao favoravel",
    "diagnosis": "Cefaleia tensional",
    "metadata": { "reviewed": true }
  }
}
```

Campos sensíveis bloqueados por strong params:

- `organization_id`
- `patient_id`
- `user_id`

Response 200: mesmo contrato do item `POST /patients/:patient_id/consultations`.

Erros comuns:

- 422 em transição inválida de status
- 404 para recurso fora do tenant

## 11.7 POST /consultations/:id/cancel

- Auth: sim

Request payload:

- sem body

Response 200: mesmo contrato do item `POST /patients/:patient_id/consultations`, com `status = "cancelled"`.

## 12. Códigos HTTP por endpoint (resumo)

- 200: consultas e atualizações síncronas com sucesso
- 201: criação (`register`, `patients#create`, `prescriptions#create`, `medical_certificates#create`, `consultations#create`)
- 202: fila de reenvio (`documents#resend`)
- 204: ações sem body (`logout`, `auth/me DELETE`, `patients DELETE`)
- 401: autenticação inválida/ausente
- 403: sem autorização/sem tenant disponível
- 404: recurso não encontrado
- 409: conflito de idempotência
- 422: validação de negócio
- 429: rate limit
- 504: timeout de geração de PDF
