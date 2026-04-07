# Convenções de Código

## Objetivo

Padronizar formatação e organização de classes para manter a API previsível e fácil de evoluir.

## Formatação

- Editor/arquivos: `.editorconfig`.

## Convenções Gerais

- Use nomes descritivos e curtos, sem abreviações obscuras.
- Prefira métodos pequenos e focados em uma responsabilidade.
- Evite lógica de negócio em controllers.
- Retorne erros de forma explícita (objetos de resultado ou exceções tratadas).

## Organização de Classes

### Controllers

- Caminho: `app/controllers`.
- Responsabilidade: autenticação/autorização da requisição, validação de entrada, chamada de serviço e renderização JSON.
- Não conter regra de negócio complexa.

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

### Serializers

- Caminho: `app/serializers`.
- Nomeação: `<Recurso>Serializer`.
- Responsabilidade: contrato de saída JSON (campos públicos e estrutura).

## Estrutura Recomendada por Feature

Para cada feature nova, preferir criar:

1. controller
2. service
3. policy
4. serializer
5. job (quando assíncrono)
6. testes correspondentes

## Fluxo de Qualidade

Antes de abrir PR:

1. executar testes
2. revisar se controller está fino e regra principal está em service
