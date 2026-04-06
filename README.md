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
- Próximo passo de infraestrutura: adicionar `docker-compose` com API, PostgreSQL, Redis e Sidekiq.

## Documento de Referência do MVP

A definição detalhada do MVP e checklist operacional estão mantidas em documentos locais de trabalho (fora do versionamento do Git).
