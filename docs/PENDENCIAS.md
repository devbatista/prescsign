# Pendências do PrescSign

Levantamento do que falta no sistema, feito em **28/08/2026** a partir do código
da branch `main` (commit `6ef6130`), da documentação do repositório e de uma
execução completa da suíte RSpec.

Este documento é um retrato datado. Cada item aponta o arquivo onde a pendência
vive, para que a verificação seja no código e não na memória. Itens que dependem
da Anvisa ou da EVAL estão marcados como **externos** — não são resolvíveis só
com trabalho de desenvolvimento.

Ordem sugerida de ataque, se for preciso escolher:

1. ~~CI + destravar a suíte~~ — feito em 29/08/2026 (seções 1 e 5);
2. domínio `.br` + credenciais de homologação do SNCR (é o único item com data
   marcada e o que mais depende de terceiros);
3. o restante, por seção.

---

## 1. Suíte de testes vermelha (28 falhas) — ✅ resolvido em 29/08/2026

**Estado em 28/08/2026:** `541 examples, 28 failures`.

**Causa:** o banco de **test** estava com o catálogo carregado
(`substances=612`, `medications=10`) e os specs criam substâncias com nomes que
já existiam lá.

```
Substance.create!(name: "tramadol", ...)
  → ActiveRecord::RecordInvalid: Validation failed: Name has already been taken
```

**Specs atingidos:**

- `spec/services/medications/substance_matcher_spec.rb` (8 falhas)
- `spec/services/medications/cmed_catalog_import_spec.rb` (8 falhas)
- `spec/requests/admin/substances_spec.rb` (5 falhas)
- `spec/requests/app/medications_spec.rb` (2 falhas)
- `spec/models/substance_spec.rb` (2 falhas)
- `spec/models/prescription_sncr_classification_spec.rb` (1 falha)
- `spec/requests/app/prescriptions_spec.rb` (1 falha)

**Correção:** `spec/support/clean_database.rb` trunca todas as tabelas (menos
`schema_migrations` e `ar_internal_metadata`) num `before(:suite)`. Renomear as
substâncias dos specs resolveria as 28 falhas e deixaria a próxima carga quebrar
outras — o que faltava era a garantia de tabela vazia, não nomes melhores.
Suíte de volta a `541 examples, 0 failures`.

---

## 2. SNCR — bloqueadores regulatórios

**Prazo regulatório: 30/09/2026** (RDC 1.028/2026). Detalhamento na seção 9 de
[sncr/SNCR_INTEGRATION.md](sncr/SNCR_INTEGRATION.md).

### 2.1 Dependências externas (Anvisa)

- **URL base de produção** do SNCR. Hoje o default em
  `config/initializers/app_config.rb:172` é a de homologação.
- **Credenciais e cadastro de homologação**. O `client-secret` do Keycloak é do
  servidor do SNCR, não do PrescSign (seção 4.2 do documento de integração).
- **Allowlist do `client_url`**: o SNCR valida o callback de forma ingênua e só
  aceita domínio `.br` puro. Sem um domínio registrado não há como exercitar o
  retorno do Gov.br fora do modo simulado (`SNCR_FAKE`).
- **Cadastro prévio do prescritor** no SNCR — pré-requisito das regras, sem
  processo definido.
- **Modelo oficial padronizado** do PDF de NR e RCE, e onde obtê-lo. O layout
  atual é próprio (`app/views/documents/pdf/prescription.html.erb`).
- **Registro de utilização na dispensação** — não consta na 1ª ed. do manual e
  não existe em `app/services/sncr/client.rb`, que cobre apenas `/auth/token` e
  os dois endpoints de numeração.
- **Validade das numerações** e comportamento quando a receita não é emitida ou
  assinada.
- **Peso regulatório da ordem de `SNCR_TYPE_PRECEDENCE`** — resolve produto com
  substâncias de tipos distintos (seção 2.3). Precisa de confirmação.

### 2.2 Lacunas no nosso código

- ~~**⚠️ Controlado digitado à mão sai como receita comum, em silêncio.**~~
  ✅ **Resolvido em 02/09/2026.** Reclassificado de "Produto" em 31/08/2026 (era
  descrito como atrito de operação, quando o modo de falha real era outro) e
  corrigido em seguida.

  **A falha:** o `medication_id` era opcional e o nome do medicamento é texto
  livre, então item digitado à mão não tinha de onde derivar o tipo e a receita
  saía comum, sem numeração SNCR e sem aviso. Não era caso raro — amoxicilina,
  azitromicina e cefalexina exigem `RET` pela IN 360/2025.

  **A correção**, detalhada em
  [CLASSIFICACAO_CONTROLADA.md](CLASSIFICACAO_CONTROLADA.md): o default passou de
  "não reconheci, logo é comum" para "não reconheci, logo não sei" — e não saber
  bloqueia a emissão. Quatro camadas: casamento automático sobre o texto livre,
  aviso quando o nome existe no catálogo, identificação assistida na lista das
  612, e bloqueio para o que sobrar.

  A regra de 27/08/2026 seguiu intacta: o médico **identifica a substância**,
  nunca escolhe o tipo. Isso é possível porque a base é exclusivamente a lista
  controlada, então não estar nela já é a resposta "não é controlado" — e é o que
  faz o **manipulado controlado passar a funcionar**, sem depender de cadastro no
  back-office.

  **Dívida que esta correção criou:** ela se apoia inteiramente na qualidade das
  612. Ver o item de curadoria na seção 2.3, que deixou de ser higiene de dados e
  virou pré-requisito de conformidade desta correção.

- ~~**⚠️ Controlado do catálogo sem substância vinculada sai como receita
  comum.**~~ ✅ **Resolvido em 09/09/2026.**

  **A falha:** a correção acima fechou o texto livre, mas item **com**
  `medication_id` continuava sendo dado por resolvido só por ter o vínculo, e o
  tipo vinha de `Medication#effective_sncr_type` — nulo quando o produto não tem
  substância controlada ligada. Produto da CMED com tarja preta e sem vínculo
  saía comum, em silêncio: a mesma falha, pela porta do catálogo, com população
  conhecida (a fila de 86 da seção 2.3).

  **A correção:** a **tarja** publicada pela CMED (`Medication#control_class`),
  até então só exibida, virou segunda fonte de verificação. Tarja de controlado
  sem substância que classifique é contradição, e contradição bloqueia a emissão;
  a única saída é identificar o princípio ativo. Detalhe na seção 5 de
  [CLASSIFICACAO_CONTROLADA.md](CLASSIFICACAO_CONTROLADA.md).

  O valor está em ser uma fonte **independente da nossa curadoria**: ela erra por
  motivos diferentes, então pega furo que a base das 612 não pegaria.

- **A revogação não fala com o SNCR.** `Documents::LifecycleService#revoke!`
  (`app/services/documents/lifecycle_service.rb:71`) marca `revoked` e não tem
  uma única referência a SNCR. O número consumido não volta ao pool nem é
  reportado como cancelado. Se o SNCR exigir a comunicação do cancelamento, isso
  é lacuna de conformidade, não só de UX.
- ~~**Estratégia de reserva e consumo** das numerações.~~ ✅ **Fechada em
  11/09/2026** — e a descrição anterior estava **errada**, o que vale registrar.

  Ela dizia que "como casar o bloco de 1.000 com a emissão individual não está
  fechado". Já estava: o pool guarda **uma linha por número** (`import_range!`
  explode o bloco), `consume_next!` consome com `FOR UPDATE SKIP LOCKED`, e o
  consumo acontece dentro da transação da assinatura. O lado do consumo estava
  pronto desde a implementação do pool.

  O que faltava era o **abastecimento**, e é o que entrou: `sncr_numbering_requests`
  (uma linha por solicitação, não por número) e `Sncr::NumberingQuota` passam a
  contar a cota da Anvisa — 50 por tipo/dia na notificação, 3 solicitações e
  3.000 números por mês no RCE/RET. A reserva **commita antes da chamada HTTP**:
  se o processo morrer no meio, a cota fica bloqueada em vez de sumir.

  Três detalhes que custaram a achar e não devem se perder:
  - **`failed` e `unknown` são coisas diferentes.** 4xx é recusa antes do
    processamento e não queima requisição; timeout ou 5xx pode ter sido
    processado do outro lado e conta contra a cota.
  - **A cota conta no fuso de Brasília.** O app roda em UTC e a Anvisa vira o
    mês no horário local — `Time.current.all_month` abriria três horas por mês
    em que as duas contas discordam, justamente na fronteira irreversível.
  - **O retorno do Gov.br não traz o `state`.** A Anvisa devolve o navegador na
    raiz do `app.` só com `?session_id`, então o caminho de volta agora vive em
    `session[:sncr_return_to]`.

  Sem numeração, a assinatura agora leva o **tipo que faltou** e o caminho de
  volta ao documento, em vez de largar o médico no painel para adivinhar entre
  sete tipos.
- **Auto-refill do pool** não implementado. O desenho está fechado e a decisão
  de onde roda também: **não é job agendado**. O `access_token` do Gov.br é
  artefato de sessão (Redis, TTL ≤ 1h, obtido por OIDC interativo), então um job
  periódico acordaria sem token na maior parte das execuções. O gatilho é por
  evento — após a assinatura e na visita ao painel —, e sem token o
  reabastecimento degrada para aviso na tela. Falta implementar.

### 2.3 Curadoria de dados

- **⚠️ Revisão humana da curadoria** das 612 substâncias carregadas em
  25/08/2026 — a extração ainda não passou por revisão manual. Ver seção 7 de
  [sncr/SUBSTANCES_DATA_SOURCING.md](sncr/SUBSTANCES_DATA_SOURCING.md).

  **Subiu de prioridade em 02/09/2026:** deixou de ser higiene de dados e virou
  **pré-requisito de conformidade**. A correção da classificação (seção 2.2) se
  apoia em "não está nas 612, logo não é controlado" — se a lista tiver furo, uma
  controlada ausente não casa, não aparece na busca assistida, e o médico
  confirma de boa-fé que nada se aplica. A falha silenciosa volta por outra porta.

  **Estreitada em 09/09/2026** pelo cross-check da tarja (seção 5 de
  [CLASSIFICACAO_CONTROLADA.md](CLASSIFICACAO_CONTROLADA.md)): produto do catálogo
  cuja tarja da CMED diz "controlado" e que não tem substância vinculada passa a
  **bloquear a emissão** em vez de sair comum. Continua descoberto o que não tem
  tarja a consultar — texto livre, manipulado, e produto que a CMED publica com
  `- (*)`. A revisão segue sendo pré-requisito; o que mudou é que ela deixou de
  ser a **única** barreira.
- **86 princípios ativos na fila de revisão** do casamento CMED↔substância
  (seção 8.3). O catálogo de produtos em si já está carregado: 25.701
  apresentações da CMED, em 26/08/2026.

  Desde 09/09/2026 essa fila é **visível e acionável**: filtro
  **Classificação → Pendente** em `admin/medications`
  (`Medication.unclassified_controlled`). Ela deixou de ser um CSV em `tmp/` e
  virou trabalho de back-office — e cada item nela é uma emissão bloqueada.

---

## 3. Assinatura (EVAL Crypto Cubo)

`SIGNATURE_PROVIDER=internal` continua sendo o default em `.env.example:143`. O
provider real existe (`app/services/signatures/eval_crypto_cubo_provider.rb`) e
já foi exercitado contra a API, mas a lista de
[pontos pendentes](EVAL_CRYPTO_CUBO_SIGNATURE.md) ainda tem itens que decidem se
dá para assinar em produção:

- **Provisionamento do registro do médico** na conta EVAL (API ou cadastro
  manual) e como validar que o CPF tem registro **antes** de permitir assinar.
  Hoje `effective_alias` (linha 109) pega o CPF do `doctor_profile` e o problema
  só aparece no erro da chamada.
- **Header exato** que carrega a chave (`Authorization: Bearer` vs.
  `X-Api-Key`) e se `secondary_key` é aceita junto da `primary_key` (rotação).
- **Semântica de teste vs. produção**: se `primary`/`secondary` mapeiam
  ambientes ou são só rotação, e se são a mesma conta ou contas separadas.
- **Campo do CPF do assinante** no payload e se há segundo fator por assinatura.
- Valores válidos para `operatorId` e `format`; obrigatoriedade de `signer` e
  `package` na verificação.
- Se o formato `attached` corresponde ao PDF PAdES final esperado.
- Campo oficial que determina sucesso/falha da verificação de assinatura.
- Limites de tamanho do PDF e timeout recomendado.

---

## 4. Produção e operação

- **Sem TLS no compose de produção.** `docker/nginx/default.conf` só escuta na
  porta 80, enquanto `config/environments/production.rb:45` tem
  `force_ssl = true`. Falta o terminador TLS (load balancer externo ou
  certificado no nginx) — hoje o `docker-compose.prod.yml` não sobe HTTPS
  sozinho.
- **Retenção: implementada, ainda não ativada.** ✅ **Metade resolvida em
  10/09/2026.** Existe `Retention::CleanupService`, com `RetentionCleanupJob` e
  `rake retention:cleanup` como pontos de entrada — a política deixou de ser só
  um documento. Detalhe em [RETENTION_POLICY.md](RETENTION_POLICY.md).

  **O que segue aberto:** nada roda sozinho. Continua sem sidekiq-cron ou
  qualquer agendador, e simular é o padrão nos dois pontos de entrada. Isso é
  decisão, não esquecimento: a própria política condiciona a ativação em
  produção a validação jurídica e a uma **estratégia de backup** — que é o item
  logo abaixo, ainda aberto. Agendar a limpeza antes disso é apagar sem rede.

  A ordem, então, é: backup primeiro, validação jurídica depois, agendador por
  último.

  **Achado do caminho:** `DocumentVersion` tem `before_destroy
  :prevent_destroy`, e um `delete_all` teria passado por cima dessa guarda em
  silêncio. O serviço não varre versões de documento — reporta `0` e diz no log
  que a política é permanente. O efeito colateral é que
  `RETENTION_DOCUMENT_VERSIONS_DAYS` com um número de dias hoje não faz nada:
  em produção o boot exige `permanent`, e fora dela a variável é aceita e
  ignorada. Vale decidir se ela some ou ganha sentido.
- **Sem webhook de status de entrega.** Nenhuma rota de callback existe em
  `config/routes/`: falta o `StatusCallback` do Twilio e o retorno de bounce do
  SES. Hoje "enviado" significa "aceito pelo provedor", não "entregue" — a
  limitação está registrada em
  [SISTEMA_TECNICO_DETALHADO.md:400](SISTEMA_TECNICO_DETALHADO.md).
- **Sem estratégia de backup do Postgres** definida em lugar nenhum do
  repositório.
- ~~**Rails 7.1 fora do suporte desde 01/10/2025 — 10 CVEs em aberto.**~~
  ✅ **Resolvido em 09/09/2026.** `Gemfile` subiu de `~> 7.1.6` para
  `~> 8.1.3, >= 8.1.3.1`.

  **O que estava aberto:** as duas filas de segurança do CI convergiram no mesmo
  ponto por caminhos diferentes — o Brakeman pelo `EOLRails` e o bundler-audit
  por **10 advisories** em `actionview`, `activestorage` e `activesupport`
  7.1.6. O mais grave era o **CVE-2026-66066**: leitura arbitrária de arquivo e
  execução remota de código no processamento de variante do Active Storage, que
  é onde este sistema guarda os **PDFs assinados**.

  **Por que o piso é `>= 8.1.3.1` e não `8.1`:** nove dos dez advisories são
  corrigidos a partir do 8.1.2.1, mas o CVE-2026-66066 só em **8.1.3.1**. Um
  `~> 8.1.3` sozinho resolveria para 8.1.3 e deixaria justamente o pior em
  aberto. Daí os dois requisitos no `Gemfile`.

  **A atualização não exigiu mudança de código:** suíte em `569 examples, 0
  failures`, `zeitwerk:check` limpo, RuboCop sem ofensas. As gems do projeto já
  estavam modernas (devise 5.0.4, sidekiq 8.1.2, propshaft 1.3.2, puma 7.2.1) e
  nem o `rspec-rails` preso em 6.1.5 precisou se mover.

  **Silenciamentos removidos:** `.bundler-audit.yml` foi apagado inteiro, como
  o próprio arquivo mandava fazer, e a entrada do `EOLRails` saiu de
  `config/brakeman.ignore`. As duas filas passam sem ignorar nada do Rails.

  **Dívida deixada para trás:** `config/application.rb:22` segue em
  `config.load_defaults 7.1`. As correções dos CVEs estão no código das gems e
  não dependem dessa flag, então a atualização de segurança está completa — mas
  o app ainda roda com o comportamento de framework do 7.1. Adotar os defaults
  do 7.2, 8.0 e 8.1, um degrau por vez, é trabalho à parte: mistura mudança de
  comportamento com o que aqui foi só troca de versão.

---

## 5. Qualidade

- ~~**Não há CI.**~~ ✅ **Resolvido em 29/08/2026.** `.github/workflows/ci.yml`
  roda cinco filas em paralelo em PR e em push na `main`: RuboCop, Brakeman,
  bundler-audit, Importmap audit e RSpec. **Limites conhecidos:** o CI cria um
  `tailwind.css` vazio em vez de rodar o build do Tailwind (nenhum spec afirma
  nada sobre CSS), então uma quebra na configuração do Tailwind não aparece ali;
  e a fila do Importmap é um no-op enquanto o `config/importmap.rb` não fixar
  nenhum pacote de terceiro.
- ~~**Sem rubocop, brakeman ou bundler-audit** no `Gemfile`.~~ ✅ **Resolvido em
  29/08/2026.** **Dívida deixada para trás:** as 182 ofensas de
  `Layout/SpaceInsideArrayLiteralBrackets` foram registradas em
  `.rubocop_todo.yml` em vez de corrigidas — reformatar 40 arquivos numa PR de
  CI misturaria assuntos e criaria conflito com toda branch em andamento. São
  todas autocorrigíveis: `bundle exec rubocop -a` seguido de apagar a entrada do
  cop no `.rubocop_todo.yml` resolve, quando não houver branch aberta.
- **Atestado médico sem request spec.** `spec/requests/app/` cobre receitas mas
  não `app/controllers/app/medical_certificates_controller.rb`.

---

## 6. Produto

- **Só dois tipos de documento** (`Document::KINDS = %w[prescription
  medical_certificate]`). Solicitação de exames, encaminhamento e relatório
  médico não existem.
- ~~Controlado fora do catálogo sai como receita comum.~~ **Reclassificado em
  31/08/2026 para a seção 2.2** — não é limitação de produto, é falha silenciosa
  de conformidade.

---

## Referências

- [sncr/SNCR_INTEGRATION.md](sncr/SNCR_INTEGRATION.md) — seção 9, pontos pendentes do SNCR.
- [sncr/SUBSTANCES_DATA_SOURCING.md](sncr/SUBSTANCES_DATA_SOURCING.md) — seções 7 e 8.3, curadoria.
- [EVAL_CRYPTO_CUBO_SIGNATURE.md](EVAL_CRYPTO_CUBO_SIGNATURE.md) — contrato da assinatura.
- [SISTEMA_TECNICO_DETALHADO.md](SISTEMA_TECNICO_DETALHADO.md) — visão geral do sistema.
- [RETENTION_POLICY.md](RETENTION_POLICY.md) — política de retenção do MVP.
