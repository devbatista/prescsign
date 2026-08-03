# Integração SNCR (Anvisa) para receitas de controlados

Este documento registra o **planejamento** da integração do PrescSign com o
Sistema Nacional de Controle de Receituários (SNCR) da Anvisa, exigida pela
RDC 1.000/2025 para prescrições eletrônicas de medicamentos controlados e
sujeitos a controle especial.

O contrato da API abaixo foi extraído do **Manual da API SNCR — 1ª edição
(junho/2026)** da Anvisa. Fonte oficial e demais links em
[SNCR_FONTES_OFICIAIS.md](SNCR_FONTES_OFICIAIS.md). O Swagger de homologação é a
referência viva do contrato; este doc resume o que impacta o PrescSign.

> Este doc trata do **SNCR** (numeração nacional + validade regulatória da
> receita). É complementar, e não substitui, o
> [EVAL_CRYPTO_CUBO_SIGNATURE.md](../EVAL_CRYPTO_CUBO_SIGNATURE.md), que cobre a
> **assinatura qualificada** do PDF. No fluxo de controlados os dois se
> combinam: o SNCR fornece a numeração e o CryptoCubo assina no passo final.

## 1. Contexto regulatório

- **RDC 1.000/2025** (publicada 15/12/2025, em vigor desde 15/02/2026) redefine
  as regras da prescrição eletrônica de controlados:
  - a receita eletrônica de controlado deve ser **nata digital** (produzida
    direto no sistema, não digitalização de papel);
  - só pode ser emitida por **serviço de prescrição integrado ao SNCR via API**;
  - cada receita recebe **numeração nacional única** gerada pelo sistema,
    vinculada ao profissional;
  - a farmácia faz o **registro de utilização** no SNCR na dispensação,
    garantindo uso único.
- **RDC 1.028/2026** prorrogou o prazo de adequação de 01/06/2026 para
  **30/09/2026** e flexibilizou a exigência de assinatura qualificada nas etapas
  de **autenticação de acesso** e **requisição de numeração**. A assinatura
  qualificada continua **obrigatória no momento da emissão efetiva** do
  receituário.
- **RDC 873/2024** institui o SNCR (base do sistema, em vigor desde 18/07/2024).

### Consequência prática

Sem integração ao SNCR, a receita eletrônica de controlado emitida pelo
PrescSign **não é válida** — independentemente da qualidade da assinatura
ICP-Brasil. O PrescSign precisa se tornar um "serviço de prescrição integrado ao
SNCR".

## 2. Escopo: quais receitas são alcançadas

A RDC 1.000 alcança (não é só tarja preta). No contrato da API os tipos são
agrupados em dois endpoints:

- **Notificação de Receita** (endpoint `notificacao-receita`), tipos:
  - `NRA` — Notificação de Receita A (amarela, entorpecentes);
  - `NRB` — Notificação de Receita B (azul);
  - `NRB2` — Notificação de Receita B2 (retinoides sistêmicos);
  - `NRR` — Notificação de Receita Especial (retinoides);
  - `NRT` — Notificação de Receita de Talidomida.
- **Receita de Controle Especial / Retenção** (endpoint
  `receita-especial-retencao`), tipos:
  - `RCE` — Receita de Controle Especial (C1/C5);
  - `RET` — Receita Sujeita a Retenção (inclui antimicrobianos e análogos de
    GLP-1).

Antibiótico comum entra no escopo (`RET`). Isso alcança quase todo clínico
geral, ou seja: **não é um caso de nicho** — mexe no fluxo principal de receitas.

### 2.1 Como o sistema sabe que um medicamento exige SNCR

A exigência é definida pela **substância ativa**, não pelo nome comercial nem
pelo texto que o médico digita. A base legal é a **Portaria SVS/MS nº 344/1998**
(as "listas" de substâncias controladas) e suas atualizações por RDC, mais as
normas de antimicrobianos e de retenção. As listas mapeiam direto para os tipos
de receita do SNCR:

| Lista (Portaria 344/98 e afins) | Exemplo | Tipo SNCR |
| --- | --- | --- |
| A1/A2/A3 (entorpecentes) | morfina, metilfenidato | `NRA` |
| B1/B2 (psicotrópicos) | clonazepam, anfepramona | `NRB` / `NRB2` |
| C2 (retinoides) | isotretinoína | `NRR` / `NRB2` |
| C3 (talidomida) | talidomida | `NRT` |
| C1/C5 (controle especial / anabolizantes) | testosterona | `RCE` |
| Sujeitas a retenção (antimicrobianos, análogos de GLP-1) | amoxicilina, semaglutida | `RET` |

Cadeia de decisão: **substância → lista → tipo de receita SNCR → endpoint**.

**A maioria dos medicamentos NÃO exige SNCR.** Só entram substâncias
controladas + antimicrobianos + sujeitas a retenção. Anti-hipertensivos comuns,
muitos analgésicos etc. usam **receituário comum** — sem numeração nacional e sem
o fluxo Gov.br/CryptoCubo. O caminho controlado é um **desvio especial**,
disparado só quando um item prescrito cai numa lista; o fluxo genérico atual do
PrescSign continua valendo para o resto.

**Dois pré-requisitos — hoje implementados estruturalmente** (falta popular os
dados; ver "Origem dos dados"):

1. **Itens estruturados** — o médico seleciona o medicamento de um catálogo
   (`Medication`) na emissão; cada item vira um `PrescriptionItem` com vínculo ao
   produto. **Feito.**
2. **Base de medicamentos com classificação de controle** — modelada como
   **substância → tipo SNCR**: cada `Substance` guarda `sncr_type` (acionável) e
   `list_344` (referência); o produto associa N substâncias (N:N
   `medication_substances`) e deriva seu **tipo efetivo** (o mais restritivo).
   **Feito** (ver seção 2.3 e 7).

Com isso a classificação **deixa de sair do texto livre e da escolha manual**: a
substância é a fonte de verdade e o tipo SNCR da receita é **derivado** dos itens
do catálogo. O que ainda falta é **popular** a base de substâncias.

**Origem dos dados — build vs. buy (pesquisa em 22/07/2026):** a Anvisa **não
publica um catálogo machine-readable pronto** de "medicamento → lista → tipo
SNCR". O que existe é:

- **Lista de substâncias sujeitas a controle especial** (anexo da 344/98,
  atualizado por RDC): fonte de verdade de _quais substâncias_ são controladas,
  mas em texto legal/PDF, não em API limpa —
  `https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/lista-substancias`.
- **Dados abertos de medicamentos registrados** (Datavisa):
  `https://dados.anvisa.gov.br/dados/DADOS_ABERTOS_MEDICAMENTOS.csv` — mapeia
  produto → substância, mas não entrega o tipo de receita SNCR de forma direta.
- **Dados abertos de controlados/antimicrobianos** (SNGPC): são dados de
  **venda/dispensação**, não uma tabela de classificação.

Conclusão: ou **construir** o mapeamento (lista da 344/98 + base de medicamentos
+ manutenção contínua contra as RDCs que atualizam as listas — alto custo), ou
**comprar** uma base comercial de medicamentos já classificada por tarja/controle
(o que a maioria dos prontuários brasileiros faz — menor manutenção). Análise
detalhada na seção 2.2. Decisão em aberto (ver Pontos pendentes).

### 2.2 Análise build vs. buy da base de medicamentos

Comparativo (pesquisa em 22/07/2026):

| Critério | Build (dados abertos Anvisa) | Buy (base licenciada) |
| --- | --- | --- |
| Custo inicial | Alto — extração do PDF da 344/98 + pipeline + curadoria | Baixo/médio — integrar o feed |
| Custo recorrente | Alto e **perpétuo** — re-parsear cada RDC + curadoria | Assinatura previsível |
| Tempo até funcionar | Semanas a meses | Dias a semanas |
| Fonte estruturada da 344/98 | **Não existe** (só PDF) — é o gargalo | Fornecedor mantém |
| Risco regulatório | Alto — você é responsável pela acurácia e atualização | Menor — parte transferida via SLA/cláusula |
| Atualização (RDC nova) | Manual/IA + revisão sua | SLA do fornecedor |
| Dependência externa | Nenhuma (só dados abertos) | Fornecedor (licença, lock-in) |
| Controle/customização | Total | Limitado ao que o feed traz |

**Recomendação:** como **não existe** a lista 344/98 em formato estruturado
oficial e a classificação errada tem peso regulatório, o ponteiro pende para
**buy**. IA torna o "build" viável (extração do PDF + casamento fuzzy), mas não
remove a curadoria humana nem a manutenção perpétua. Em qualquer cenário, o
PrescSign mantém em casa a **classificação por substância** (`Substance.sncr_type`)
e os **itens estruturados** na tela — a decisão de build/buy é só sobre **como
popular** essa base (ver seção 2.3).

#### Fornecedores e preços (buy)

> **Nenhum fornecedor publica preço** — todos operam **sob cotação** (B2B). Os
> valores abaixo são o que é **confirmável** (modelo de licenciamento); os
> números exatos exigem cotação direta. Não há estimativa oficial de mercado.

| Fornecedor | O que é | Modelo de licenciamento | Preço público? | Como cotar |
| --- | --- | --- | --- | --- |
| **Brasíndice** (Editora Andrei) | Base de referência de medicamentos/preços com tarja; atualização quinzenal | Assinatura (semestral/anual) | Não | Editora Andrei / Bionexo |
| **Simpro** | Base de referência de medicamentos/materiais; atualização bimestral | Assinatura | Não | simpro.com.br |
| **Memed** | Plataforma de prescrição + base de 60k+ apresentações via API | Grátis para o médico; **B2B/white-label negociado** (⚠️ é player do mesmo mercado) | Não | Programa de parceiros Memed |
| **Globais** (Medi-Span/Wolters Kluwer, First Databank, Vidal) | Drug data feeds | Licença anual corporativa | Não | Cotação — **verificar cobertura da classificação 344 BR** |

Observações de custo:
- Brasíndice/Simpro nasceram como **publicações de referência de preço**
  (faturamento hospitalar/TISS) — a assinatura da revista/portal é uma coisa; o
  **licenciamento do dado para integração/API** é negociado à parte.
- Orçar prevendo **assinatura anual** + eventual custo por volume (chamadas/
  assentos). Pedir cotação a **2–3 fornecedores** para ter faixa real.
- Verificar na cotação: SLA de atualização atrelado à RDC, cobertura de
  antimicrobianos/retenção (GLP-1), identificadores (registro Anvisa/EAN),
  direito de exibir o dado no PDF do receituário.

### 2.3 Modelo implementado (2026-07-31)

A cadeia **substância → tipo SNCR → item → receita** foi implementada. A
classificação deixou de ser escolha manual do médico e passou a ser derivada do
catálogo.

- **`Substance`** (`app/models/substance.rb`, tabela `substances`): substância
  ativa com `sncr_type` (o **campo acionável** — `NRA…RET` ou nulo = comum) e
  `list_344` (lista da 344/98, só referência/auditoria). Decisão: guardar o tipo
  SNCR **direto na substância**, porque o mapeamento lista→tipo tem exceções
  (B1/B2 → NRB ou NRB2) e resolver no cadastro é mais seguro.
- **N:N `medication_substances`** (`app/models/medication_substance.rb`): um
  produto pode associar mais de uma substância (associações).
- **`Medication#effective_sncr_type`**: o tipo **mais restritivo** entre as
  substâncias controladas do produto (`Prescription::SNCR_TYPE_PRECEDENCE`).
- **`PrescriptionItem#sncr_type`**: **snapshot** herdado do medicamento no momento
  da emissão — o item mantém a classificação mesmo que a substância mude depois.
- **`Prescription`**: deriva o `sncr_type` dos itens (a **substância vence** a
  escolha manual) e **barra** receitas cujos itens resolvam para tipos diferentes
  (cada tipo exige um receituário próprio) — `controlled_items_must_share_type`.
- **Back-office**: CRUD de substâncias (`Admin::SubstancesController`) e vínculo
  de substâncias no formulário de medicamento (multi-select), exibindo o tipo
  SNCR efetivo.

**Ordem preliminar** de `SNCR_TYPE_PRECEDENCE` (`NRA > NRT > NRB2 > NRB > NRR >
RCE > RET`): usada só para resolver o caso raro de um produto com substâncias de
tipos distintos — o peso regulatório exato ainda precisa ser confirmado.

**Ainda em aberto:** **popular** a base de substâncias (build vs. buy — seção 2.2)
e a UX do formulário de emissão (o select manual de `sncr_type` continua como
fallback para receita em texto livre; para itens do catálogo a derivação vence).

## 3. Lacuna atual do PrescSign (estado do código)

Parte do modelo de domínio de receita controlada **já foi criada** (tipo SNCR,
itens estruturados, catálogo com classificação por substância, pool de
numerações). O que resta é sobretudo **infra de integração** (auth Gov.br,
cliente HTTP, template oficial). A tabela abaixo marca ✅ o que já existe.

| Necessidade regulatória | Estado atual no código | Gap |
| --- | --- | --- |
| Distinguir tipo de receita (NRA/NRB/NRB2/NRR/NRT/RCE/RET) | ✅ **Feito.** `prescriptions.sncr_type` (enum `NRA…RET`, nulo = comum) + `Prescription#controlled?` (`app/models/prescription.rb`). | — |
| Prescrição **nata digital** com itens estruturados (medicamento, quantidade, posologia) | ✅ **Feito.** `PrescriptionItem` (vínculo opcional a `Medication`) + catálogo `Medication`/`Substance` com classificação por substância; `sncr_type` derivado dos itens (seção 2.3). | Popular a base de substâncias (build vs. buy). |
| **Numeração nacional única** no formato `NNNN.N-NN.NNNNNNN` | `code` é aleatório local: `SecureRandom.alphanumeric(10).upcase` em loop (`app/services/documents/lifecycle_service.rb:159-164`). | Persistir a numeração vinda do SNCR; não gerar localmente para controlados. |
| **Autenticação do prescritor via Gov.br (OIDC)** | Auth é Devise por sessão/cookie (`config/initializers/devise.rb`). Não há login federado Gov.br. | Implementar o fluxo OAuth2/OIDC Gov.br exigido pela API do SNCR. |
| **QR Code apontando para o SNCR** | `PdfRenderer` embute QR para `/validate/{code}` interno (`app/services/documents/pdf_renderer.rb`). | Para controlados, QR deve apontar para `sncr.anvisa.gov.br/receita/consultar?numero=...`. |
| **Modelos de receituário padronizados** (não customizáveis) | Templates próprios em `app/views/documents/pdf/`. | Usar o modelo oficial da Anvisa para NR e RCE. |
| Assinatura qualificada obrigatória na emissão | Já existe via `Signatures::EvalCryptoCuboProvider` + `Documents::SigningService#sign!` (`app/services/documents/signing_service.rb:22`). | Reaproveitar no passo final; controlado exige `type=qualified`. |

## 4. Contrato da API do SNCR (confirmado — Manual 1ª ed.)

### 4.1 Base URL e Swagger

| Ambiente | Base URL | Swagger |
| --- | --- | --- |
| **Homologação** | `https://sncr-api.hmg.apps.anvisa.gov.br/api/v1` | `https://sncr-api.hmg.apps.anvisa.gov.br/swagger-ui/index.html#/` |
| Produção | (a confirmar no material da Anvisa) | — |

### 4.2 Autenticação — OAuth 2.0 / OpenID Connect via Gov.br

> **Achado crítico de arquitetura:** a API **não** usa API key servidor-a-servidor.
> O **prescritor** autentica interativamente com a **conta Gov.br dele** (OIDC,
> via Keycloak da Anvisa). A numeração fica atrelada ao profissional autenticado
> — o CPF do login Gov.br precisa corresponder ao prescritor da requisição. Isso
> resolve a dúvida de "identidade do assinante": é sempre o médico, não um
> certificado institucional.

Parâmetros do Keycloak (do manual):

- `auth-server-url`: `https://acesso.apps.anvisa.gov.br/auth`
- `realm`: `anvisa`
- `resource` (client): `sncr-api`
- `credentials.secret`: `<client-secret>` (fornecido pela Anvisa)
- redireciona ao Gov.br com `kc_idp_hint=govbr`

> **Estes parâmetros configuram o servidor do SNCR, não o PrescSign.** Quem é o
> cliente OIDC registrado no Keycloak da Anvisa é a **própria API do SNCR**
> (`resource: sncr-api`) — o `client-secret` é dela. O PrescSign **não** faz o
> dance OIDC nem guarda esse segredo: apenas (1) redireciona o navegador para
> `/auth/login?client_url=<callback>`, (2) recebe o `session_id` no callback e
> (3) troca por `access_token` em `/auth/token`. Por isso não há variáveis
> `SNCR_KEYCLOAK_*` na config do PrescSign.

Fluxo (endpoints de auth):

1. **`GET /api/v1/auth/login`** — inicia o fluxo.
   - Query: `client_url` (obrigatório, URL de retorno do frontend); `state`
     (opcional, estado arbitrário do cliente).
   - Gera `nonce` e `state` assinado com HMAC-SHA256, cria sessão temporária e
     redireciona ao Keycloak.
2. **Callback** (`/api/v1/auth/callback`) — recebe `code`+`state` do Keycloak,
   valida assinatura/expiração do `state` e o `nonce`, troca `code` por
   `access_token`, gera um **`session_token` de uso único (expira em 30s)** e
   redireciona para `client_url` com `?session_id={token}`.
3. **`GET /api/v1/auth/token`** — troca o `session_id` pelo access token.
   - Resposta `200`: `{ "access_token": "<jwt>", "token_type": "Bearer" }`.
   - Erro: `{ "error": "Sessão inválida ou expirada" }`.
   - O token é removido da sessão após a requisição (uso único).
4. As chamadas de numeração usam `Authorization: Bearer <access_token>`.

Notas de segurança do manual: HTTPS obrigatório em produção; `session_token`
uso único/30s; `state` expira em 5 min; apenas domínios `.br` na allowlist.

#### 4.2.1 Achado de homologação — allowlist do `client_url` (2026-07-25)

Teste real contra a homologação (`GET .../auth/login` com o callback local
`http://app.prescsign.local:8080/sncr/auth/callback`) retornou:

```http
HTTP/1.1 403 Forbidden
Content-Type: application/json
{"error": "Domínio não autorizado"}
```

Ou seja: **o PrescSign redireciona corretamente**, mas a Anvisa **corta o fluxo
antes do Gov.br** porque o domínio do `client_url` não está na allowlist dela. Ao
clicar em "Conectar ao Gov.br" com um callback não autorizado, o usuário **não
chega na tela de login** — recebe esse 403.

Confirmações do teste:

- o ambiente de homologação **está no ar e conectado ao Gov.br** — a resposta
  traz uma CSP com `sso.acesso.gov.br`, `login.acesso.gov.br`, `auth.acesso.gov.br`
  e `acesso.dev.apps.anvisa.gov.br`;
- o **único** bloqueio para o login funcionar é o **cadastro/autorização do
  domínio de callback** junto à Anvisa;
- callbacks locais/`.local`/`http` não são aceitos — presumivelmente exige-se um
  domínio **público `.br` via `https`** (a confirmar com a Anvisa).

**Regra exata da validação (confirmada por teste, 2026-08-03).** A Anvisa **não
faz parse do host** — ela pega o **último segmento do `client_url` depois da
última `/`** e exige que termine em `.br`:

| `client_url` enviado | último segmento | resultado |
| --- | --- | --- |
| `https://app.prescsign.com.br` | `app.prescsign.com.br` | **302** ✅ |
| `https://app.prescsign.com.br/` | `app.prescsign.com.br` | **302** ✅ |
| `https://app.prescsign.com.br/sncr/auth/callback` | `callback` | **403** ❌ |
| `https://app.prescsign.com.br?return_to=/sncr` | `sncr` | **403** ❌ |

Ou seja, o campo `client_url` é tratado como a **origem** do app (padrão de broker
OIDC para SPA), não como uma rota de callback dedicada. Um path qualquer quebra a
validação ingênua.

**Solução adotada (sem cadastro prévio necessário no hmg).** Enviar o `client_url`
como o **domínio puro** (`https://app.prescsign.com.br`) e capturar o retorno na
**raiz do subdomínio `app.`**: a Anvisa devolve o navegador para
`https://app.prescsign.com.br/?session_id=X&state=<return_to>` após o Gov.br. Uma
rota-raiz condicional (`config/routes/app.rb`) roteia esse landing — só quando há
`session_id` — para o mesmo `App::Sncr::AuthController#callback`, que troca o
`session_id` pelo `access_token` e o guarda em `session[:sncr]`. O `state` que
enviamos é **preservado** pela Anvisa (vai assinado no blob de state e volta como
`?state=`), então o `redirect_to safe_return_to` retorna direto à tela de origem
(ex.: `/sncr/numberings`).

Config: `SNCR_AUTH_CALLBACK_URL=https://app.prescsign.com.br` (origem, sem path).

> Isto é um **bug de validação da Anvisa** (deveria fazer parse do host); vale
> reportar. Callbacks locais/`.local`/`http` seguem sem funcionar — o teste
> end-to-end exige um domínio público `.br` via `https`.

### 4.3 Endpoint — Notificação de Receita

`POST /numeracoes/notificacao-receita`

Request:

| Campo | Tipo | Obrigatório | Exemplo | Regras |
| --- | --- | --- | --- | --- |
| `receita` | string | Sim | `NRA` | Um de: `NRA`, `NRB`, `NRB2`, `NRR`, `NRT`. |
| `conselho` | string | Sim | `CRM` | Um de: `CRM`, `CRMV`, `CRO`. |
| `uf` | string | Sim | `RJ` | UF do conselho. |
| `documento` | string | Sim | `123456` | Número de inscrição do prescritor no conselho. |
| `quantidade` | integer | Sim | `25` | Mín. **10**, máx. **50**. |

```json
{ "receita": "NRA", "conselho": "CRM", "uf": "RJ", "documento": "123456", "quantidade": 25 }
```

Response (`201`):

| Campo | Tipo | Descrição |
| --- | --- | --- |
| `numeroReceita` | string[] | Lista de números liberados. Formato `2411.1-00.0000001`. |
| `saldoReceitas` | integer | Saldo de numerações disponíveis do tipo. |
| `mensagem` | string | Alerta quando saldo < 50. |

```json
{ "numeracoesReceita": ["2411.1-00.0000001", "2411.1-00.0000002"], "saldoReceitas": 49, "mensagem": "Saldo inferior a 50 receitas disponíveis." }
```

Regras: o prescritor autenticado no Gov.br deve ser o mesmo da requisição e estar
cadastrado no SNCR; **limite de 50 por tipo, por prescritor, por dia**. Se pedir
mais que o saldo, a API retorna só o disponível.

Status: `201` sucesso · `204` nenhuma disponível · `400` inválido/limite ·
`401` não autorizado · `403` negado · `404` não encontrado · `500` erro interno.

### 4.4 Endpoint — Receita de Controle Especial / Retenção

`POST /numeracoes/receita-especial-retencao`

Request:

| Campo | Tipo | Obrigatório | Exemplo | Regras |
| --- | --- | --- | --- | --- |
| `conselho` | string | Sim | `CRM` | Um de: `CRM`, `CRMV`, `CRO`. |
| `tipo` | string | Sim | `RCE` | Um de: `RCE`, `RET`. |
| `documento` | string | Sim | `123456` | Inscrição do prescritor no conselho. |
| `uf` | string | Sim | `RJ` | UF do conselho. |
| `cnpj` | string | Sim | `11111111111111` | CNPJ da **plataforma** (PrescSign/organização) que consome a API. |

```json
{ "conselho": "CRM", "tipo": "RCE", "documento": "11111", "uf": "RJ", "cnpj": "11111111111111" }
```

Response (`201`) — retorna um **bloco de 1.000 numerações** (não uma lista):

| Campo | Tipo | Descrição |
| --- | --- | --- |
| `inicio` | string | Numeração inicial. Formato `2602.6-53.0000001`. |
| `fim` | string | Numeração final. Formato `2602.6-53.0001000`. |
| `quantidade` | integer | Constante `1000`. |
| `mensagem` | string | Ex.: `"Numeração gerada com sucesso."`. |

Regras: prescritor autenticado == requisição; **CNPJ válido** (dígitos
verificadores); **limite de 3 requisições/mês por inscrição** e **máx. 3.000
numerações RCE+RET por mês por profissional**.

Status: `201` · `400` · `401` · `403` · `404` · `500`.

### 4.5 O que NÃO está neste manual

- O **registro de utilização/dispensação** (baixa na farmácia, uso único) **não
  consta** na 1ª edição — este manual cobre só a **emissão de numeração** pelo
  prescritor. Ator/endpoint da dispensação a confirmar em material futuro.
- URL base de **produção**.
- Detalhes do cadastro prévio do prescritor no SNCR (pré-requisito citado nas
  regras de negócio).

## 5. Fluxo alvo da receita controlada

```
1. Prescritor autentica no Gov.br      -> OIDC (login/callback/token), access_token
2. Requisitar numeração ao SNCR        -> POST /numeracoes/... com Bearer
3. Gerar o receituário nato digital    -> modelo Anvisa + numeração + QR do SNCR
4. Assinar no CryptoCubo               -> QUALIFICADA, obrigatória aqui
5. Entregar ao paciente                -> + registrar no prontuário
6. Farmácia registra o uso             -> baixa no SNCR [fora deste manual]
```

| Passo | Onde encaixa hoje |
| --- | --- |
| 1. Auth Gov.br | **Novo.** Fluxo OIDC próprio; a sessão Devise atual não cobre. Guardar o `access_token` (curta duração) para usar no passo 2. |
| 2. Numeração | **Novo `Sncr::Client`.** Antes de `LifecycleService#create_with_initial_version!` (`app/services/documents/lifecycle_service.rb:13`); para controlados o `code`/numeração vem do SNCR, não de `generate_code`. |
| 3. Receituário | `Documents::PdfRenderer` (`app/services/documents/pdf_renderer.rb`): modelo padronizado + numeração + QR `sncr.anvisa.gov.br`. |
| 4. Assinatura | Sem mudança estrutural: `SigningService#sign!` -> `EvalCryptoCuboProvider#sign_pdf!` (`type=qualified`). |
| 5. Entrega | Fluxo atual (`DocumentChannelDeliveryJob`). |
| 6. Dispensação | Fora do escopo deste manual. |

Ponto de atenção: como a numeração exige **login interativo do médico no
Gov.br**, o passo 2 **não é headless** — não dá para reservar numeração num job
de fundo sem o médico ter autenticado. Modelar a UX em torno disso (ver decisão
na seção 6).

## 6. Decisão de arquitetura: Opção B — pool de numerações por médico

**Decisão (2026-07-22):** a obtenção de numeração e o login Gov.br ficam numa
**área dedicada do painel**, com um **pool (estoque) de numerações por médico**.
A emissão de receita controlada apenas **consome** desse pool.

**Motivação:** o endpoint de RCE/RET tem limite de **3 requisições/mês** e devolve
**blocos de 1.000** números — pedir numeração "na hora" por receita estouraria o
limite no 3º receituário do mês. A API foi desenhada para pré-carregar lotes e
consumir aos poucos. Por isso o modelo inline por receita foi descartado.

**Desenho:**

- Nova área "SNCR / Numerações" no painel (persona `doctor`): conectar ao
  Gov.br, puxar lotes por tipo e ver saldo.
- Model de pool (ex.: `SncrNumbering`) amarrado ao `DoctorProfile` — os números
  são do prescritor (CPF do Gov.br) e atravessam as organizações em que ele atua.
- Na emissão (Receitas), **consumir** o próximo número disponível do tipo; se o
  saldo zerou, direcionar o médico à área SNCR / re-login.
- Controllers sob o subdomínio `app.`: `App::Sncr::AuthController`
  (`start`/`callback`, o login) e `App::Sncr::NumberingsController`
  (`index` = saldo, `create` = pedir lote).

**Sub-decisões ainda em aberto:**

- modelar o bloco de 1.000 (RCE/RET) como **faixa** `inicio`/`fim` + cursor, ou
  **explodir** em 1.000 linhas (faixa é mais enxuto);
- como o painel apresenta o saldo (global por CPF vs. contexto de organização);
- validade do `access_token` e das numerações não usadas (confirmar com a Anvisa
  / Swagger — ver Pontos pendentes).

**Alternativa descartada — Opção A (inline por receita):** login e numeração
dentro do "Nova receita controlada". Mais simples, mas **inviável para RCE/RET**
pelo limite de 3 requisições/mês.

### 6.1 Saldo é por tipo — estratégia de solicitação e reabastecimento

A Anvisa emite numeração **vinculada ao tipo de receita**: cada solicitação
carrega **um único tipo** (`receita` em NRA/NRB/NRB2/NRR/NRT; `tipo` em RCE/RET)
e devolve números **daquele tipo**. Não existe "pedir tudo de uma vez". Portanto:

- O médico tem um **saldo independente por tipo**. Para ter saldo em todos os 7
  tipos, precisaria de **≥ 1 solicitação por tipo** (5 chamadas de notificação de
  até 50 + 2 de especial/retenção de 1.000).
- O pool (`SncrNumbering`) já guarda cada número com seu `sncr_type`; `balance_for`
  agrupa por tipo e o consumo na emissão filtra `of_type(sncr_type)`.

**Não se deve encher todos os tipos indiscriminadamente.** Um prescritor costuma
usar só um subconjunto (psiquiatra → NRB/RCE; dermatologista → NRB2/NRR; NRT é
raríssimo). Puxar numeração de um tipo que ele nunca vai usar gera número parado
e, em RCE/RET, **desperdiça uma das 3 solicitações mensais**.

**Estratégia definida (recomendada — combinar 1 + 2):**

1. **Sob demanda (gatilho na emissão).** Ao emitir uma receita controlada cujo
   tipo está com saldo zerado, o "portão" da emissão redireciona o médico para a
   área SNCR / login e solicita **aquele tipo**. Só se puxa numeração de tipo que
   ele efetivamente usa. É o piso do comportamento.
2. **Reabastecimento automático por tipo.** O sistema monitora o saldo e, quando
   um tipo **já utilizado antes** cai abaixo de um limite (ex.: notificação < 5;
   RCE/RET < 100), solicita mais **daquele tipo** proativamente, para o médico não
   ficar sem número no meio de um atendimento. Nunca reabastece tipo nunca usado.
3. **Manual, tipo a tipo (estado atual).** A tela lista uma linha por tipo com
   botão "Solicitar"; o médico decide e puxa o lote. Continua disponível como
   fallback e para o primeiro carregamento.

**Restrições que o reabastecimento automático deve respeitar:**

- Notificação (NRA–NRT): **50 por tipo, por prescritor, por dia** — o auto-refill
  não pode ultrapassar o teto diário nem disparar em loop.
- Especial/Retenção (RCE, RET): **3 solicitações/mês por inscrição** e **máx.
  3.000 números RCE+RET/mês** — o auto-refill precisa contar as solicitações já
  feitas no mês e **parar antes do 3º pedido**, reservando margem para picos.
- "Já utilizado antes" deve ser derivado do histórico de consumo (ex.: houve
  `consumed` daquele tipo), para não reabastecer tipos que o médico não pratica.

**Pendências para o auto-refill (item futuro, não implementado):** onde rodar o
monitoramento (job Sidekiq periódico vs. verificação na própria emissão), como
persistir o contador mensal de solicitações RCE/RET por inscrição, e se o médico
pode ligar/desligar o reabastecimento por tipo.

## 7. Impacto no modelo de domínio (mudanças de código previstas)

Ordem sugerida de trabalho (cada item é um passo verificável):

1. **Classificação de receita controlada — ✅ implementado.**
   - `prescriptions.sncr_type` (enum `NRA/NRB/NRB2/NRR/NRT/RCE/RET`, nulo = comum)
     + `Prescription#controlled?` (`app/models/prescription.rb`).
2. **Itens estruturados + catálogo classificado — ✅ implementado.**
   - `PrescriptionItem` (vínculo opcional a `Medication`, snapshot dos campos e do
     `sncr_type`).
   - Catálogo: `Medication` (produto) em N:N com `Substance` (substância +
     `sncr_type`/`list_344`) via `medication_substances`. Classificação por
     **substância** é a fonte de verdade; `Medication#effective_sncr_type` deriva
     o tipo mais restritivo e a `Prescription` deriva o seu dos itens, barrando
     tipos divergentes (seção 2.3).
   - Back-office: `Admin::MedicationsController` + `Admin::SubstancesController`.
   - **Pendente:** popular a base de substâncias (build vs. buy — seções 2.2/2.3).
3. **Numeração SNCR + pool por médico** — model `SncrNumbering` amarrado ao
   `DoctorProfile`, guardando número no formato `NNNN.N-NN.NNNNNNN` (uma linha por
   número, inclusive expandindo o bloco de 1.000 do RCE/RET) e status
   `disponível/consumido`. Nova área de painel `App::Sncr::NumberingsController`
   (saldo + pedir lote). Ver desenho na seção 6.

   **Portão de consumo (implementado):** o número é consumido **na assinatura**,
   não na criação do rascunho — assim rascunhos controlados abandonados não gastam
   numeração escassa (RCE/RET, 3 solicitações/mês). `Sncr::NumberingAssignment.
   ensure_for!` roda **dentro da transação** de `Documents::SigningService#sign!`:
   se a receita é controlada e ainda não tem número, `SncrNumbering.consume_next!`
   puxa o próximo do tipo; sem saldo, `PoolEmpty` faz **rollback** (nada é assinado)
   e o `App::DocumentsController#sign` redireciona à área de numerações. É no-op
   para documentos comuns e idempotente. Decisão: a numeração fica em
   `prescription.sncr_numbering` (associação), **sem** sobrescrever o `code` da
   receita — mantém semântica uniforme entre comum/controlada e a rastreabilidade
   por número. O tipo (`sncr_type`) é escolhido no formulário de emissão e é fixo
   após a criação.
4. **Autenticação Gov.br (OIDC)** — módulo próprio para
   `login → callback → token`, guardando o `access_token` de curta duração.
5. **Cliente SNCR** — `app/services/sncr/client.rb` (`Net::HTTP` puro, padrão de
   `signatures/icp_brasil_provider.rb:34-55`). Métodos: `request_notificacao!`,
   `request_especial_retencao!`. Erros: `Sncr::Error` mapeando os códigos do
   manual (400/401/403/404/500 e as mensagens específicas).
6. **Config / ambiente** — `config.x.sncr` em `config/initializers/app_config.rb`
   (padrão de `eval_crypto_cubo_provider_options`, ~`131-146`), com validação
   obrigatória em produção (~`app_config.rb:169-222`). Novas vars no `.env.example`.
7. **PDF / template (parcial — implementado)** — o template
   `app/views/documents/pdf/prescription.html.erb` exibe, quando a receita é
   controlada, um **banner com o tipo (`sncr_type` + rótulo) e a numeração
   nacional** (`prescription.sncr_numbering.number`); em rascunho ainda sem
   número mostra "pendente de assinatura". CSS em `layouts/pdf.html.erb`. O PDF é
   renderizado na assinatura (após o portão consumir o número) e sob demanda.
   **Pendente:** o **modelo oficial padronizado da Anvisa** (layout exato do
   receituário) e o **QR específico do SNCR** — só o QR de validação próprio
   existe hoje; ambos dependem do material oficial (ver Pontos pendentes).
8. **Auditoria** — registrar requisição/resposta de numeração via `AuditLog`.
9. **Testes** — `spec/services/sncr/client_spec.rb`, fluxo controlado, auth OIDC.

## 8. Variáveis de ambiente sugeridas

```bash
# Integração SNCR (Anvisa) - controlados
SNCR_ENABLED=false
SNCR_BASE_URL=https://sncr-api.hmg.apps.anvisa.gov.br/api/v1   # homologação
SNCR_TIMEOUT_SECONDS=30

# client_url de retorno do PrescSign — ORIGEM do app (domínio puro .br, sem path).
# Ex.: https://app.prescsign.com.br  (ver 4.2.1 sobre a validação do client_url)
SNCR_AUTH_CALLBACK_URL=

# CNPJ da plataforma (obrigatório no endpoint RCE/RET)
SNCR_PLATFORM_CNPJ=

# Assinatura qualificada no passo final (ver EVAL_CRYPTO_CUBO_SIGNATURE.md):
# SIGNATURE_PROVIDER=eval_crypto_cubo
# EVAL_CRYPTO_CUBO_TYPE=qualified
```

Não há variáveis `SNCR_KEYCLOAK_*`: o dance OIDC é do servidor do SNCR, não do
PrescSign (ver nota na seção 4.2). Obrigatórias quando `SNCR_ENABLED=true`:
`SNCR_BASE_URL`, `SNCR_AUTH_CALLBACK_URL`, `SNCR_PLATFORM_CNPJ`.

Segurança:

- nunca logar `access_token`, `session_id` ou conteúdo do PDF;
- incluir esses campos no `filter_parameter_logging`
  (`config/initializers/filter_parameter_logging.rb`);
- em produção, exigir as variáveis obrigatórias quando `SNCR_ENABLED=true`.

## 9. Pontos pendentes

Já resolvidos pelo Manual 1ª ed.: autenticação (Gov.br/OIDC), endpoints, campos,
formato da numeração, limites e códigos de erro. Restam:

- **URL base de produção** do SNCR;
- fluxo/endpoint de **registro de utilização na dispensação** (não consta na 1ª ed.);
- processo de **cadastro prévio do prescritor** no SNCR (pré-requisito das regras);
- **modelo oficial padronizado** de NR e RCE (layout do PDF) e onde obtê-lo;
- **allowlist do `client_url`** na homologação: confirmar se o SNCR aceita um
  callback local/não-`.br` para teste, ou se exige um domínio `.br` registrado;
- credenciais/cadastro de homologação (o `client-secret` do Keycloak é do
  servidor do SNCR, não do PrescSign — ver seção 4.2);
- estratégia de **reserva/consumo** das numerações (NR vem em lista; RCE/RET vem
  em bloco de 1.000) e como casar com a emissão individual de cada receita;
- validade das numerações e comportamento se a receita não for emitida/assinada.
- **popular a base de substâncias** (build vs. buy) — a estrutura de classificação
  por substância **já existe** (`Substance`, seção 2.3); falta a origem/curadoria
  dos dados. Ver seções 2.2/2.3.
- confirmar o **peso regulatório** da ordem de `SNCR_TYPE_PRECEDENCE` (resolve
  produto com substâncias de tipos distintos — seção 2.3).
- **UX da emissão**: decidir se o select manual de `sncr_type` some/vira read-only
  quando há item controlado do catálogo (hoje é fallback para texto livre).

## 10. Cronograma

- Prazo regulatório: **30/09/2026** (RDC 1.028/2026).
- Documentação/API e ambiente de homologação já disponíveis (junho/2026).
- Recomendado priorizar os passos 1-5 do bloco 6 (domínio + auth + client
  desbloqueiam o resto).

## 11. Referências

Código:

- `app/models/prescription.rb` — receita; classificação SNCR + derivação por item.
- `app/models/prescription_item.rb` — item estruturado (snapshot do `sncr_type`).
- `app/models/medication.rb` — catálogo de produtos; `effective_sncr_type`.
- `app/models/substance.rb` — substância + classificação (`sncr_type`/`list_344`).
- `app/models/medication_substance.rb` — junção N:N produto↔substância.
- `app/controllers/admin/substances_controller.rb` — CRUD de substâncias.
- `app/models/document.rb` — entidade assinável/entregável; `KINDS`.
- `app/services/documents/lifecycle_service.rb` — criação + `generate_code`.
- `app/services/documents/signing_service.rb` — orquestração da assinatura.
- `app/services/documents/pdf_renderer.rb` — geração do PDF + QR.
- `app/services/signatures/eval_crypto_cubo_provider.rb` — assinatura qualificada.
- `app/services/signatures/icp_brasil_provider.rb` — padrão `Net::HTTP`.
- `config/initializers/app_config.rb` — config por ambiente (`config.x.*`).
- `db/schema.rb` — tabelas `prescriptions`, `documents`, `document_versions`.

Docs e fontes:

- `docs/sncr/SNCR_FONTES_OFICIAIS.md` — links oficiais e Manual API SNCR.
- `docs/EVAL_CRYPTO_CUBO_SIGNATURE.md` — contrato da assinatura (complementar).
- `docs/SISTEMA_TECNICO_DETALHADO.md` — visão geral do sistema.
- Manual da API SNCR — 1ª ed. (jun/2026) e Swagger de homologação (ver
  `SNCR_FONTES_OFICIAIS.md`).
