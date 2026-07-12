# Convenções de Código

## Objetivo

Padronizar formatação e organização de classes para manter o app previsível e fácil de evoluir.

O app é um **monolito Rails server-rendered** (views ERB + Tailwind, sem API JSON,
sem SPA). Para criar uma tela nova, siga [ADDING_A_SCREEN.md](./ADDING_A_SCREEN.md).

## Formatação

- Editor/arquivos: `.editorconfig`.

## Convenções Gerais

- Use nomes descritivos e curtos, sem abreviações obscuras.
- Prefira métodos pequenos e focados em uma responsabilidade.
- Evite lógica de negócio em controllers.
- Retorne erros de forma explícita (objetos de resultado ou exceções tratadas).

## Organização de Classes

### Controllers

- Caminho: `app/controllers`. Telas do painel em `app/controllers/app/` (namespace `App::`), herdando de `ApplicationController`.
- Responsabilidade: autenticação/autorização (Devise + Pundit), validação de entrada, chamada de serviço e renderização de **views ERB**.
- Não conter regra de negócio complexa. `form_with` sem Turbo; erro de validação re-renderiza com `status: :unprocessable_entity` (422).

### Services

- Caminho: `app/services`.
- Nomeação: `<Dominio>/<Acao>Service` (ex.: `Documents/IssuePrescriptionService`).
- Interface padrão: método de classe `.call(...)` delegando para instância.
- Um serviço por caso de uso principal.

### Policies

- Caminho: `app/policies`.
- Nomeação: `<Recurso>Policy`.
- Responsabilidade: autorização por ação e escopos (`Scope`) para listagens.

### Jobs

- Caminho: `app/jobs`.
- Nomeação: `<Acao><Canal>Job` (ex.: `SendPrescriptionEmailJob`).
- Responsabilidade: tarefas assíncronas idempotentes, com retry controlado.

### Views

- Caminho: `app/views/<namespace>/<recurso>/`. ERB puro + Tailwind (paleta `ps-*`), **sem JS de framework**.
- Componentes reutilizáveis como partials (`_form.html.erb`, `shared/_pagination.html.erb`).
- Helpers de apresentação em `app/helpers`; a autorização é sempre validada no servidor (Pundit), não só na view.

## Estrutura Recomendada por Feature

Para cada feature nova, preferir criar:

1. controller (fino)
2. service (regra de negócio)
3. policy
4. views ERB (+ partials)
5. job (quando assíncrono)
6. testes correspondentes (request spec: happy path + autorização negada)

## Fluxo de Qualidade

Antes de abrir PR:

1. executar testes
2. revisar se controller está fino e regra principal está em service
