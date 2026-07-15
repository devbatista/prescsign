# Orientações para agentes de IA

Este arquivo reúne regras para qualquer agente de IA trabalhando neste repositório, incluindo Codex, Claude e ferramentas similares.

## Comunicação

- Responda sempre em português, salvo pedido explícito em outro idioma.
- Seja direto, objetivo e prático.
- Explique decisões técnicas quando houver risco, trade-off ou mudança de comportamento.
- Ao citar comandos executados, informe o resultado relevante.

## Git e Pull Requests

- Nunca faça commit, push, merge, rebase, reset destrutivo ou abra PR sem pedido explícito do usuário.
- Antes de commitar, confirme que o escopo do diff pertence à tarefa atual.
- Não inclua alterações não relacionadas no mesmo commit/PR.
- PRs devem ser sempre em português:
  - título em português;
  - descrição em português;
  - seções como `Resumo`, `O que mudou`, `Impacto` e `Validação`.
- Commits devem ter mensagens curtas e claras. Use português quando o usuário não pedir outro padrão.
- Se um PR já estiver fechado ou mergeado, crie uma nova branch limpa antes de abrir outro PR.
- Nunca reverta alterações feitas pelo usuário sem autorização explícita.

## Fluxo de trabalho

- Antes de alterar código, leia os arquivos relacionados e siga os padrões existentes.
- Prefira mudanças pequenas e focadas.
- Não introduza abstrações novas sem necessidade clara.
- Ao encontrar comportamento ambíguo, confirme com o usuário antes de assumir algo que possa afetar dados ou fluxo de produção.
- Se a tarefa envolver UI, preserve o estilo visual existente e valide responsividade básica.

## Projeto

- Aplicação Rails server-rendered.
- Use Docker Compose para comandos que dependem dos serviços locais.
- Comandos de teste comuns:

```bash
docker compose exec -T web bundle exec rspec
```

- Para testes focados, rode apenas os arquivos afetados, por exemplo:

```bash
docker compose exec -T web bundle exec rspec spec/requests/app/sessions_spec.rb
```

- Quando migrations forem adicionadas, rode as migrations no ambiente necessário e confirme `db/schema.rb`.

## Qualidade

- Alterações de regra de negócio devem ter cobertura de teste.
- Erros exibidos ao usuário devem ser claros, preferencialmente em português.
- Evite duplicar mensagens de erro na interface.
- Mantenha validações importantes também no backend, não apenas no HTML.

## Segurança e dados

- Não exponha segredos, tokens ou credenciais em respostas, commits ou logs.
- Não execute comandos destrutivos sem autorização explícita.
- Não altere dados de produção sem pedido claro e confirmação do escopo.
