# SNCR — Manual da API (1ª edição, 2026)

> Transcrição fiel do PDF **"Manual API SNCR - 1ed"** da Anvisa (Brasília, junho
> de 2026). Fonte oficial: [Documentos do SNCR](https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/documentos-do-sncr).
>
> Copyright © 2026. Agência Nacional de Vigilância Sanitária (Anvisa). É
> permitida a reprodução parcial ou total desta obra, desde que citada a fonte.
>
> Elaboração/Redação: Antônio Carlos de Lima Mendes Junior (Arquiteto de Software
> — Spassu), Thiago Brasil Silvério (Assessor/Gerente Substituto — Anvisa),
> Wesley Vieira Bandeira (Analista de Negócios — Spassu). Gerência de Produtos
> Controlados: Renata de Morais Souza.
>
> **Nota:** este arquivo é a transcrição do manual. A interpretação, os achados
> de homologação e as decisões de implementação do PrescSign estão no
> [SNCR_INTEGRATION.md](SNCR_INTEGRATION.md). Todas as URLs abaixo marcadas como
> homologação usam o host `hmg`.

---

## 1. Apresentação

### 1.1. Objetivo do Manual

Este manual tem por objetivo estabelecer orientações para a integração com a API
do Sistema Nacional de Controle de Receituários (SNCR), disponibilizando
informações técnicas e operacionais necessárias à implementação e ao consumo dos
serviços oferecidos pela plataforma.

O documento visa apoiar desenvolvedores, analistas e demais profissionais de
tecnologia da informação responsáveis pela integração de sistemas ao SNCR,
servindo como referência para a correta utilização dos recursos disponibilizados.

### 1.2. Público-Alvo

Profissionais da área de tecnologia da informação, empresas desenvolvedoras de
software, plataformas de prescrição eletrônica e prestadores de serviços digitais
em saúde que tenham interesse em integrar suas soluções ao SNCR.

---

## 2. API SNCR

Serviço para fornecimento de numerações de notificação de receitas eletrônicas
para elaboração de prescrições eletrônicas.

- **Base URL** (homologação): `https://sncr-api.hmg.apps.anvisa.gov.br/api/v1`

### 2.1. Swagger

- **URL** (homologação): `https://sncr-api.hmg.apps.anvisa.gov.br/swagger-ui/index.html#/`

Detalhes técnicos da API disponíveis no Swagger:

- Métodos HTTP;
- Schemas;
- Exemplos de requisição e resposta;
- Autenticação técnica;
- Payloads completos.

### 2.2. Autenticação

#### 2.2.1. Visão Geral

A API SNCR utiliza um mecanismo de autenticação integrado à plataforma Gov.br,
garantindo que apenas usuários devidamente identificados e autorizados possam
acessar seus recursos.

Para que uma requisição seja processada com sucesso, o profissional requisitante
deve possuir uma conta Gov.br ativa e válida. O processo de autenticação é
realizado por meio do protocolo **OAuth 2.0 com OpenID Connect (OIDC)**,
utilizando o Gov.br como provedor de identidade.

A integração é realizada pelo **GovBrRedirectFilter**, componente de autenticação
que implementa o fluxo OAuth2/OIDC para integração com o Gov.br via Keycloak, com
suporte a múltiplos clientes frontend em domínios diferentes (cross-domain).

#### 2.2.2. Fluxo

```
Frontend (Plataforma)   Backend (API SNCR)   Keycloak   Gov.br

1.  GET /login  ───────►
2.                        Gera state (nonce, client_url)
3.                        Redirect ──────────►
4.                                             Autenticação Gov.br ──►
5.                                             ◄── Callback (code)
6.                        ◄── Valida state, troca code por token
7.                        Gera session_token (Tk)
8.  ◄── Redirect com session_id
9.  GET /token (session_id) ─►
10. ◄── Access Token
11. API Request (Bearer) ─────►
```

#### 2.2.3. Endpoints de autenticação

##### 2.2.3.1. `[GET] /api/v1/auth/login` — inicia o fluxo

**Dados para requisição:**

| Parâmetro | Obrigatório | Descrição |
| --- | --- | --- |
| `client_url` | Sim | URL de retorno do frontend. |
| `state` | Não | Estado arbitrário do cliente. |

**Comportamento:**

- Gera `nonce` e `state` assinado com HMAC-SHA256.
- Cria sessão temporária (apenas para validação do nonce).
- Redireciona para o Keycloak com `kc_idp_hint=govbr`.

**Callback configurável (`${app.auth.auth-callback}`) — processamento:**

1. Recebe `code` e `state` do Keycloak.
2. Valida assinatura e expiração do `state`.
3. Valida `nonce` (não depende de cookie!).
4. Troca `code` por `access_token` via Keycloak.
5. Gera `session_token` de uso único (30s).
6. Redireciona para `client_url` com `?session_id={token}`.

##### 2.2.3.2. `[GET] /api/v1/auth/token` — recupera o Access Token

**Resposta (200 OK):**

```json
{
  "access_token": "jwt_token_aqui",
  "token_type": "Bearer"
}
```

**Erro:**

```json
{
  "error": "Sessão inválida ou expirada"
}
```

> **Observação:** o token é removido da sessão após a requisição (uso único).

##### 2.2.3.3. Variáveis de configuração (`application.yml`)

```yaml
app:
  auth:
    auth-callback: "/api/v1/auth/callback"
    callback-url: https://sncr-api.apps.anvisa.gov.br/api/v1/auth/callback
    allowed-domains:
      - https://*.br

keycloak:
  auth-server-url: https://acesso.apps.anvisa.gov.br/auth
  realm: anvisa
  resource: sncr-api
  credentials:
    secret: <client-secret>
```

> Estes parâmetros configuram **o servidor do SNCR** (o cliente OIDC registrado no
> Keycloak da Anvisa é a própria `sncr-api`), não a plataforma consumidora.

**Segurança:**

| Mecanismo | Descrição |
| --- | --- |
| HMAC State | `state` assinado com HMAC-SHA256. |
| Nonce Validation | Previne replay attacks (timeout: 5 minutos). |
| Session Token One-Time | `session_token` expira em 30s e é removido após uso. |
| State Expiry | Timeout configurável (5 minutos). |
| Domain Whitelist | Apenas domínios `.br` são permitidos. |

O estado da autenticação é mantido via: (a) `nonce` no state para validação do
callback; (b) `session_token` na URL para recuperação do token.

**Estrutura do state assinado:**

```
Payload:     {clientUrl}|{nonce}|{clientState}|{expiry}
Assinatura:  HMAC-SHA256(payload)
State Final: Base64Url(payload + "|" + assinatura)
```

**Notas de segurança:**

1. HTTPS obrigatório em produção;
2. Session token com expiração curta (30s) e uso único;
3. State com expiração de 5 minutos;
4. Nonce armazenado em memória com timeout.

---

## 2.3. Endpoints de numeração

### 2.3.1. Notificação de Receita

Disponibilização de números para notificações de receita autorizadas pela
Vigilância Sanitária.

**URL:** `[POST] /numeracoes/notificacao-receita`

#### 2.3.1.3. Dados para requisição

| Parâmetro | Tipo | Obrigatório | Exemplo | Descrição |
| --- | --- | --- | --- | --- |
| `receita` | string | Sim | `NRA` | Tipo de receita. Valores permitidos: `NRA`, `NRB`, `NRB2`, `NRR`, `NRT`. |
| `conselho` | string | Sim | `CRM` | Conselho no qual o prescritor possui inscrição. Valores permitidos: `CRM`, `CRMV`, `CRO`. |
| `uf` | string | Sim | `RJ` | Unidade Federativa (UF) do conselho. |
| `documento` | string | Sim | `123456` | Número de identificação do prescritor no conselho. |
| `quantidade` | integer(32) | Sim | `25` | Quantidade de números desejados. **Mín: 10 – Máx: 50**. |

**Exemplo:**

```json
{
  "receita": "NRA",
  "conselho": "CRM",
  "uf": "RJ",
  "documento": "123456",
  "quantidade": 25
}
```

#### 2.3.1.4. Resposta

| Campo | Tipo | Exemplo | Descrição |
| --- | --- | --- | --- |
| `numeroReceita` | string[] | `2411.1-00.0000001` | Número(s) de receita disponibilizado(s). Mais de um número poderá ser informado. |
| `saldoReceitas` | integer(32) | `49` | Quantidade de numerações do tipo informado disponíveis. |
| `mensagem` | string | `"Saldo inferior a 50 receitas disponíveis."` | Alerta exibido quando o saldo do prescritor é inferior a 50. |

**Exemplo:**

```json
{
  "numeracoesReceita": ["2411.1-00.0000001", "2411.1-00.0000002"],
  "saldoReceitas": 49,
  "mensagem": "Saldo inferior a 50 receitas disponíveis."
}
```

#### 2.3.1.5. Regras de negócio e restrições

**i. Validação do prescritor:**

- O profissional autenticado via Gov.br durante a autenticação da API SNCR deve
  corresponder ao prescritor informado na requisição.
- O prescritor deve ter sido **previamente cadastrado no sistema SNCR**.
- Os dados de conselho, UF e número de documento informados na requisição devem
  corresponder a um registro válido existente na base de dados do SNCR.

**ii. Numerações atribuídas:**

- O prescritor deve possuir numerações disponíveis e atribuídas ao seu cadastro
  para o tipo de receita solicitado (`NRA`, `NRB`, `NRB2`, `NRR` ou `NRT`).

**iii. Limite de numerações de receita:**

- A disponibilização é limitada a **50 números por tipo de receita, por
  prescritor e por dia**.
- Caso a quantidade solicitada seja superior à disponível, a API retorna apenas a
  quantidade existente em estoque.

#### 2.3.1.6. Códigos de status

| Código | Descrição |
| --- | --- |
| 201 | Numeração de receita disponibilizada com sucesso. |
| 204 | Nenhuma numeração de receita disponível. |
| 400 | Parâmetros inválidos, prescritor não encontrado, limite diário alcançado ou quantidade solicitada inválida. |
| 401 | Não autorizado. |
| 403 | Acesso negado. |
| 404 | Página não foi encontrada. |
| 500 | Erro interno do servidor. |

#### 2.3.1.7. Mensagens de erro

| HTTP | Mensagem | Descrição |
| --- | --- | --- |
| 400 | Tipo da receita não pode ser nulo | O campo `receita` não foi informado. |
| 400 | Tipo de receita inválido para esta requisição. | Valor de `receita` não suportado. Aceitos: `NRA`, `NRB`, `NRB2`, `NRR`, `NRT`. |
| 400 | Conselho não pode ser nulo | O campo `conselho` não foi informado. |
| 400 | Conselho inválido | O conselho informado não é suportado pela API. |
| 400 | UF não pode ser nulo | O campo `uf` não foi informado. |
| 400 | Número de identificação do prescritor não pode ser nulo | O campo `documento` não foi informado. |
| 400 | Quantidade de receitas não pode ser nulo | O campo `quantidade` não foi informado. |
| 400 | A quantidade mínima permitida é 10 | Valor de `quantidade` inferior ao mínimo. |
| 400 | A quantidade máxima permitida é 50 | Valor de `quantidade` superior ao máximo. |
| 400 | Limite diário de 50 receitas atingido. Já disponibilizadas hoje: X. Saldo restante para hoje: Y. | A quantidade solicitada ultrapassa o limite diário do prescritor. |
| **404** | **Inscrição fornecida é diferente da autenticada.** | **O conselho, número de inscrição ou UF informados não correspondem a uma inscrição ativa vinculada ao CPF do profissional autenticado via Gov.br.** |

### 2.3.2. Receita de Controle Especial / Receita Sujeita a Retenção

Criação do bloco de numeração para receitas de controle especial e receitas
sujeitas à retenção.

**URL:** `[POST] /numeracoes/receita-especial-retencao`

#### 2.3.2.3. Dados para requisição

| Parâmetro | Tipo | Obrigatório | Exemplo | Descrição |
| --- | --- | --- | --- | --- |
| `conselho` | string | Sim | `CRM` | Conselho ao qual o prescritor possui inscrição. Valores permitidos: `CRM`, `CRMV`, `CRO`. |
| `tipo` | string | Sim | `RCE` | Tipo de receita. Valores permitidos: `RCE`, `RET`. |
| `documento` | string | Sim | `123456` | Número de identificação do prescritor no conselho. |
| `uf` | string | Sim | `RJ` | Unidade Federativa (UF) do conselho. |
| `cnpj` | string | Sim | `11111111111111` | CNPJ da empresa responsável pela plataforma de prescrição eletrônica que consome a API. |

**Exemplo:**

```json
{
  "conselho": "CRM",
  "tipo": "RCE",
  "documento": "11111",
  "uf": "RJ",
  "cnpj": "11111111111111"
}
```

#### 2.3.2.4. Resposta

Retorna um **bloco de 1.000 numerações** (não uma lista):

| Campo | Tipo | Exemplo | Descrição |
| --- | --- | --- | --- |
| `inicio` | string | `2602.6-53.0000001` | Numeração inicial do intervalo de 1000 números. |
| `fim` | string | `2602.6-53.0001000` | Numeração final do intervalo de 1000 números. |
| `quantidade` | integer(32) | `1000` | Quantidade disponibilizada. Neste cenário, sempre 1000 (constante). |
| `mensagem` | string | `"Numeração gerada com sucesso."` | Mensagem exibida após requisição bem-sucedida. |

**Exemplo:**

```json
{
  "inicio": "2602.6-53.0000001",
  "fim": "2602.6-53.0001000",
  "quantidade": 1000,
  "mensagem": "Numeração gerada com sucesso."
}
```

#### 2.3.2.5. Regras de negócio e restrições

**i. Validação do prescritor:**

- O profissional autenticado via Gov.br deve corresponder ao prescritor da
  requisição.
- O prescritor deve possuir inscrição ativa no conselho profissional indicado.
- Conselho, UF e documento informados devem corresponder a um registro válido na
  base do SNCR.

**ii. Validação do CNPJ:**

- O CNPJ informado deve corresponder ao CNPJ da empresa responsável pela
  plataforma de prescrição eletrônica que consome a API.
- O CNPJ deve ser válido conforme os dígitos verificadores.

**iii. Limite de numerações de receita:**

- O endpoint disponibiliza **1.000 numerações por requisição**.
- Limite de **3 requisições mensais** por inscrição profissional para RCE/RET.
- Cada profissional está limitado a **3.000 numerações entre RCE e RET por mês**.

#### 2.3.2.6. Códigos de status

| Código | Descrição |
| --- | --- |
| 201 | Numeração de receita disponibilizada com sucesso. |
| 400 | Parâmetros inválidos ou regra de negócio não atendida. |
| 401 | Não autorizado. |
| 403 | Acesso negado. |
| 404 | Página não foi encontrada. |
| 500 | Erro interno do servidor. |

#### 2.3.2.7. Mensagens de erro

| HTTP | Mensagem | Descrição |
| --- | --- | --- |
| 400 | Tipo de receita não pode ser nulo. | O campo `tipo` não foi informado. |
| 400 | UF não pode ser nulo. | O campo `uf` não foi informado. |
| 400 | Conselho não pode ser nulo. | O campo `conselho` não foi informado. |
| 400 | Documento não pode ser nulo. | O campo `documento` não foi informado. |
| 400 | CNPJ não pode ser nulo. | O campo `cnpj` não foi informado. |
| 400 | CNPJ inválido. | Formato inválido ou reprovado na validação dos dígitos verificadores. |
| 400 | Tipo da receita inválido. Valores permitidos: [RCE, RET] | Apenas receitas dos tipos `RCE` e `RET` podem ser emitidas. |
| 400 | UF não encontrada: {UF} | A UF deve existir na base cadastral do sistema. |
| 400 | Usuário atingiu o limite máximo de receita para o tipo de receita no mês atual. | Limite mensal de 3.000 receitas por tipo. |
| 400 | Usuário autenticado não encontrado: {USER_ID} | O usuário autenticado via Gov.br ainda não possui cadastro no SNCR. É necessário realizar o cadastro antes de utilizar a operação. |
| **404** | **O usuário informado não possui vínculo ativo no conselho {CONSELHO} para o documento {DOCUMENTO} e UF {UF}.** | **O prescritor deve possuir inscrição ativa e compatível com conselho, UF e registro informados.** |

---

## Observações de leitura (não fazem parte do manual)

- O **404 de numeração é erro de negócio**, não de rota: significa que o trio
  `conselho` + `uf` + `documento` não bate com uma inscrição ativa vinculada ao
  CPF autenticado no Gov.br (2.3.1.7 e 2.3.2.7). Para testar em homologação é
  preciso um prescritor previamente cadastrado no SNCR.
- Este manual (1ª ed.) **não traz** as instruções de acesso ao ambiente de
  treinamento — essas estão no documento **"Instruções de Integração API SNCR
  v.1.0"** (Documentos do SNCR, 29/07/2026).
