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

- **A revogação não fala com o SNCR.** `Documents::LifecycleService#revoke!`
  (`app/services/documents/lifecycle_service.rb:71`) marca `revoked` e não tem
  uma única referência a SNCR. O número consumido não volta ao pool nem é
  reportado como cancelado. Se o SNCR exigir a comunicação do cancelamento, isso
  é lacuna de conformidade, não só de UX.
- **Estratégia de reserva e consumo** das numerações: NR vem em lista, RCE/RET
  vem em bloco de 1.000. Como casar com a emissão individual de cada receita
  ainda não está fechado.
- **Auto-refill do pool** não implementado: falta decidir onde roda (job
  agendado) e com que gatilho de saldo mínimo.

### 2.3 Curadoria de dados

- **Revisão humana da curadoria** das 612 substâncias carregadas em 25/08/2026 —
  a extração ainda não passou por revisão manual. Ver seção 7 de
  [sncr/SUBSTANCES_DATA_SOURCING.md](sncr/SUBSTANCES_DATA_SOURCING.md).
- **86 princípios ativos na fila de revisão** do casamento CMED↔substância
  (seção 8.3). O catálogo de produtos em si já está carregado: 25.701
  apresentações da CMED, em 26/08/2026.

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
- **Retenção documentada mas não executada.** [RETENTION_POLICY.md](RETENTION_POLICY.md)
  define os prazos e `config/initializers/app_config.rb` valida as variáveis,
  mas não existe job nem rake que expurgue nada. Não há sidekiq-cron nem
  qualquer agendador no projeto.
- **Sem webhook de status de entrega.** Nenhuma rota de callback existe em
  `config/routes/`: falta o `StatusCallback` do Twilio e o retorno de bounce do
  SES. Hoje "enviado" significa "aceito pelo provedor", não "entregue" — a
  limitação está registrada em
  [SISTEMA_TECNICO_DETALHADO.md:400](SISTEMA_TECNICO_DETALHADO.md).
- **Sem estratégia de backup do Postgres** definida em lugar nenhum do
  repositório.
- **Rails 7.1 fora do suporte desde 01/10/2025 — 10 CVEs em aberto.** As duas
  filas de segurança do CI convergiram nisso por caminhos diferentes: o Brakeman
  pelo `EOLRails` (confiança alta) e o bundler-audit por **10 advisories** em
  `actionview`, `activestorage` e `activesupport` 7.1.6, todos com a mesma
  correção — subir para a série 7.2 ou 8.x.

  O mais grave é o **CVE-2026-66066**: leitura arbitrária de arquivo e execução
  remota de código no processamento de variante do Active Storage. Este sistema
  guarda os **PDFs assinados** no Active Storage. Acompanham path traversal
  (`CVE-2026-33195`) e glob injection (`CVE-2026-33202`) no `DiskService`.

  Os avisos estão silenciados em `config/brakeman.ignore` e `.bundler-audit.yml`
  com a justificativa — permanentes até a atualização, deixariam a fila vermelha
  para sempre e treinariam o time a ignorar o CI. **O silêncio é do CI, não da
  dívida:** hoje esta é a pendência de segurança mais concreta do projeto, à
  frente de qualquer item de integração.

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
- **Controlado fora do catálogo sai como receita comum.** Limite conhecido e
  decidido em 27/08/2026 (medicamento manipulado, importado ou fora da lista da
  CMED não tem de onde derivar o tipo). O caminho é o cadastro no back-office
  (`Admin::MedicationsController`); se isso virar atrito na operação, a saída é
  cadastro assistido, não devolver o select ao médico.

---

## Referências

- [sncr/SNCR_INTEGRATION.md](sncr/SNCR_INTEGRATION.md) — seção 9, pontos pendentes do SNCR.
- [sncr/SUBSTANCES_DATA_SOURCING.md](sncr/SUBSTANCES_DATA_SOURCING.md) — seções 7 e 8.3, curadoria.
- [EVAL_CRYPTO_CUBO_SIGNATURE.md](EVAL_CRYPTO_CUBO_SIGNATURE.md) — contrato da assinatura.
- [SISTEMA_TECNICO_DETALHADO.md](SISTEMA_TECNICO_DETALHADO.md) — visão geral do sistema.
- [RETENTION_POLICY.md](RETENTION_POLICY.md) — política de retenção do MVP.
