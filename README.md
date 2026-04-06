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

## Documento de Referência do MVP

A definição detalhada do MVP e checklist operacional estão mantidas em documentos locais de trabalho (fora do versionamento do Git).

## Convenções de Código

- Lint: `RuboCop` (`rubocop`, `rubocop-rails`, `rubocop-performance`)
- Configuração: `.rubocop.yml`
- Formatação base de arquivos: `.editorconfig`
- Comando padrão: `bin/lint`
- Guia de organização de classes: `docs/CODE_CONVENTIONS.md`
