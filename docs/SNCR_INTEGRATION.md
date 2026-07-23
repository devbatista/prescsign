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
> [EVAL_CRYPTO_CUBO_SIGNATURE.md](EVAL_CRYPTO_CUBO_SIGNATURE.md), que cobre a
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

## 3. Lacuna atual do PrescSign (estado do código)

O modelo de domínio atual **não tem nenhuma noção de receita controlada**. Isso
precisa ser criado antes de qualquer chamada ao SNCR.

| Necessidade regulatória | Estado atual no código | Gap |
| --- | --- | --- |
| Distinguir tipo de receita (NRA/NRB/NRB2/NRR/NRT/RCE/RET) | `Prescription` é genérica: só `content` (texto livre) + `valid_until`. Não existe coluna/enum de tipo. Única tipificação é `Document::KINDS = %w[prescription medical_certificate]` (`app/models/document.rb:2`). | Criar tipo/categoria de receita e classificação de controlado. |
| Prescrição **nata digital** com itens estruturados (medicamento, quantidade, posologia) | `content` é texto livre; **não há** model `Medication`/`PrescriptionItem`. Ver `app/models/prescription.rb`. | Estruturar itens da receita (a Anvisa exige dados por medicamento). |
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
de fundo sem o médico ter autenticado. Modelar a UX em torno disso (ex.: reservar
lote de numerações enquanto o médico está logado e consumir depois).

## 6. Impacto no modelo de domínio (mudanças de código previstas)

Ordem sugerida de trabalho (cada item é um passo verificável):

1. **Classificação de receita controlada**
   - Coluna em `prescriptions` (ex.: `sncr_type` com enum
     `NRA/NRB/NRB2/NRR/NRT/RCE/RET`) e flag de controlado.
   - Model `app/models/prescription.rb`; schema `db/schema.rb` (~`367-392`).
2. **Itens estruturados da receita (nato digital)** — avaliar `PrescriptionItem`.
3. **Numeração SNCR** — persistir número no formato `NNNN.N-NN.NNNNNNN`
   (individual para NR; bloco `inicio`/`fim` para RCE/RET). Para controlados,
   **não** usar `generate_code` (`lifecycle_service.rb:159-164`).
4. **Autenticação Gov.br (OIDC)** — módulo próprio para
   `login → callback → token`, guardando o `access_token` de curta duração.
5. **Cliente SNCR** — `app/services/sncr/client.rb` (`Net::HTTP` puro, padrão de
   `signatures/icp_brasil_provider.rb:34-55`). Métodos: `request_notificacao!`,
   `request_especial_retencao!`. Erros: `Sncr::Error` mapeando os códigos do
   manual (400/401/403/404/500 e as mensagens específicas).
6. **Config / ambiente** — `config.x.sncr` em `config/initializers/app_config.rb`
   (padrão de `eval_crypto_cubo_provider_options`, ~`131-146`), com validação
   obrigatória em produção (~`app_config.rb:169-222`). Novas vars no `.env.example`.
7. **PDF / template** — modelo padronizado Anvisa + QR do SNCR no `PdfRenderer`.
8. **Auditoria** — registrar requisição/resposta de numeração via `AuditLog`.
9. **Testes** — `spec/services/sncr/client_spec.rb`, fluxo controlado, auth OIDC.

## 7. Variáveis de ambiente sugeridas

```bash
# Integração SNCR (Anvisa) - controlados
SNCR_ENABLED=false
SNCR_BASE_URL=https://sncr-api.hmg.apps.anvisa.gov.br/api/v1   # homologação
SNCR_TIMEOUT_SECONDS=30

# OAuth2 / OIDC Gov.br (Keycloak da Anvisa)
SNCR_KEYCLOAK_AUTH_SERVER_URL=https://acesso.apps.anvisa.gov.br/auth
SNCR_KEYCLOAK_REALM=anvisa
SNCR_KEYCLOAK_RESOURCE=sncr-api
SNCR_KEYCLOAK_CLIENT_SECRET=          # fornecido pela Anvisa
SNCR_AUTH_CALLBACK_URL=               # client_url de retorno do PrescSign

# CNPJ da plataforma (obrigatório no endpoint RCE/RET)
SNCR_PLATFORM_CNPJ=

# Assinatura qualificada no passo final (ver EVAL_CRYPTO_CUBO_SIGNATURE.md):
# SIGNATURE_PROVIDER=eval_crypto_cubo
# EVAL_CRYPTO_CUBO_TYPE=qualified
```

Segurança:

- nunca logar `SNCR_KEYCLOAK_CLIENT_SECRET`, `access_token`, `session_id` ou
  conteúdo do PDF;
- incluir esses campos no `filter_parameter_logging`
  (`config/initializers/filter_parameter_logging.rb`);
- em produção, exigir as variáveis obrigatórias quando `SNCR_ENABLED=true`.

## 8. Pontos pendentes

Já resolvidos pelo Manual 1ª ed.: autenticação (Gov.br/OIDC), endpoints, campos,
formato da numeração, limites e códigos de erro. Restam:

- **URL base de produção** do SNCR;
- fluxo/endpoint de **registro de utilização na dispensação** (não consta na 1ª ed.);
- processo de **cadastro prévio do prescritor** no SNCR (pré-requisito das regras);
- **modelo oficial padronizado** de NR e RCE (layout do PDF) e onde obtê-lo;
- obtenção do `client-secret` do Keycloak e credenciais de homologação;
- estratégia de **reserva/consumo** das numerações (NR vem em lista; RCE/RET vem
  em bloco de 1.000) e como casar com a emissão individual de cada receita;
- validade das numerações e comportamento se a receita não for emitida/assinada.

## 9. Cronograma

- Prazo regulatório: **30/09/2026** (RDC 1.028/2026).
- Documentação/API e ambiente de homologação já disponíveis (junho/2026).
- Recomendado priorizar os passos 1-5 do bloco 6 (domínio + auth + client
  desbloqueiam o resto).

## 10. Referências

Código:

- `app/models/prescription.rb` — model de receita (genérico hoje).
- `app/models/document.rb` — entidade assinável/entregável; `KINDS`.
- `app/services/documents/lifecycle_service.rb` — criação + `generate_code`.
- `app/services/documents/signing_service.rb` — orquestração da assinatura.
- `app/services/documents/pdf_renderer.rb` — geração do PDF + QR.
- `app/services/signatures/eval_crypto_cubo_provider.rb` — assinatura qualificada.
- `app/services/signatures/icp_brasil_provider.rb` — padrão `Net::HTTP`.
- `config/initializers/app_config.rb` — config por ambiente (`config.x.*`).
- `db/schema.rb` — tabelas `prescriptions`, `documents`, `document_versions`.

Docs e fontes:

- `docs/SNCR_FONTES_OFICIAIS.md` — links oficiais e Manual API SNCR.
- `docs/EVAL_CRYPTO_CUBO_SIGNATURE.md` — contrato da assinatura (complementar).
- `docs/SISTEMA_TECNICO_DETALHADO.md` — visão geral do sistema.
- Manual da API SNCR — 1ª ed. (jun/2026) e Swagger de homologação (ver
  `SNCR_FONTES_OFICIAIS.md`).
