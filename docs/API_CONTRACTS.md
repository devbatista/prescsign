# Contratos de API (MVP)

Este documento define os contratos HTTP da API no MVP.

## Base URL e Versionamento

- Prefixo oficial: `/api/v1`
- Compatibilidade temporária: `/v1`

## Convenções Globais

- Autenticação: `Authorization: Bearer <jwt>` (quando aplicável).
- Contexto de tenant: `X-Organization-Id` opcional quando o médico pertence a múltiplas organizações.
- Sucesso: envelope `data` (e `meta` em listagens).
- Erro: `errors` com `{ code, message }`, além de `error`, `error_code` e `meta`.

### Exemplo de sucesso

```json
{
  "data": {
    "status": "ok"
  }
}
```

### Exemplo de erro

```json
{
  "errors": [
    { "code": "not_found", "message": "Document not found" }
  ],
  "error": "Document not found",
  "error_code": "not_found",
  "meta": {
    "request_id": "7d4f3f7c-5c6a-4e6f-9f63-2c7b2d8b9b87",
    "status": 404
  }
}
```

## Health

- `GET /api/v1/health`
- Auth: não
- Retorno: `data.status`

## Auth

- `POST /api/v1/auth/register`
  - Payload:
```json
{
  "doctor": {
    "full_name": "Dra Ana",
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
  - Retorno: `data.message`, `data.doctor`

- `POST /api/v1/auth/login`
  - Payload:
```json
{
  "doctor": {
    "email": "ana@example.com",
    "password": "password123"
  }
}
```
  - Retorno: `data.access_token`, `data.refresh_token`, `data.doctor`

- `POST /api/v1/auth/refresh`
  - Payload:
```json
{ "refresh_token": "<token>" }
```
  - Retorno: novos tokens em `data`

- `DELETE /api/v1/auth/logout`
  - Auth: sim
  - Retorno: `204 No Content`

- `POST /api/v1/auth/password`
  - Payload:
```json
{
  "doctor": { "email": "ana@example.com" }
}
```
  - Retorno: `data.message`

- `PUT /api/v1/auth/password`
  - Payload:
```json
{
  "doctor": {
    "reset_password_token": "<token>",
    "password": "newpassword123",
    "password_confirmation": "newpassword123"
  }
}
```
  - Retorno: `data.message`

- `GET /api/v1/auth/confirmation?confirmation_token=<token>`
  - Retorno: `data.message`

- `POST /api/v1/auth/confirmation`
  - Payload:
```json
{
  "doctor": { "email": "ana@example.com" }
}
```
  - Retorno: `data.message`

- `GET /api/v1/auth/me`
- `PATCH /api/v1/auth/me`
- `DELETE /api/v1/auth/me`
  - Auth: sim
  - `PATCH` payload:
```json
{
  "doctor": {
    "full_name": "Dra Ana Atualizada",
    "specialty": "Clínica Geral"
  }
}
```

## Organizações

- `GET /api/v1/organizations`
  - Auth: sim
  - Retorno: `data.current_organization_id`, `data.organizations[]`, `meta` de paginação/ordenação

- `POST /api/v1/organizations/:organization_id/switch`
  - Auth: sim
  - Retorno: organização ativa em `data`

## Pacientes

- `GET /api/v1/patients`
  - Auth: sim
  - Query params: `q`, `page`, `per_page`, `sort_by`, `sort_dir`
  - Retorno: `data[]` + `meta`

- `GET /api/v1/patients/:id`
- `POST /api/v1/patients`
- `PATCH /api/v1/patients/:id`
- `DELETE /api/v1/patients/:id`
  - Auth: sim
  - `POST/PATCH` payload:
```json
{
  "patient": {
    "full_name": "Paciente Teste",
    "cpf": "12345678901",
    "birth_date": "1990-01-01",
    "email": "paciente@example.com",
    "phone": "11999990000"
  }
}
```

## Prescrições

- `POST /api/v1/prescriptions`
- `GET /api/v1/prescriptions/:id`
- `PATCH /api/v1/prescriptions/:id`
- `POST /api/v1/prescriptions/:id/revoke`
- `GET /api/v1/prescriptions/:id/pdf`
  - Auth: sim
  - `POST` payload:
```json
{
  "prescription": {
    "patient_id": 1,
    "unit_id": 1,
    "content": "Tomar 1 comprimido ao dia",
    "issued_on": "2026-04-17",
    "valid_until": "2026-05-17"
  }
}
```

## Atestados

- `POST /api/v1/medical_certificates`
- `GET /api/v1/medical_certificates/:id`
- `PATCH /api/v1/medical_certificates/:id`
- `POST /api/v1/medical_certificates/:id/revoke`
- `GET /api/v1/medical_certificates/:id/pdf`
  - Auth: sim
  - `POST` payload:
```json
{
  "medical_certificate": {
    "patient_id": 1,
    "unit_id": 1,
    "content": "Afastamento por 3 dias",
    "issued_on": "2026-04-17",
    "rest_start_on": "2026-04-17",
    "rest_end_on": "2026-04-19",
    "icd_code": "J11"
  }
}
```

## Documentos

- `GET /api/v1/documents/:id`
- `POST /api/v1/documents/:id/sign`
- `POST /api/v1/documents/:id/integrity_check`
- `POST /api/v1/documents/:id/resend`
  - Auth: sim
  - `resend` payload:
```json
{
  "resend": {
    "channel": "email",
    "recipient": "destino@example.com",
    "idempotency_key": "document:10:channel:email:recipient:destino@example.com",
    "metadata": {
      "trigger": "manual"
    }
  }
}
```

## Auditoria

- `GET /api/v1/audit_logs`
  - Auth: sim
  - Requer ao menos um filtro: `document_id` ou `patient_id`
  - Query params: `document_id`, `patient_id`, `page`, `per_page`, `sort_by`, `sort_dir`
  - Retorno: `data[]` + `meta`

## Validação Pública

- `GET /api/v1/public/documents/:code/validation`
  - Auth: não
  - Retorno: `data.valid`, `data.status_reason`, `data.document`, `data.issuer`, `data.validation`
