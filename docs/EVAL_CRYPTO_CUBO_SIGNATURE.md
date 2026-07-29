# Integração EVALCryptoCubo para assinatura digital

Este documento registra o contrato conhecido da API de assinatura do
EVALCryptoCubo e como ela deve se encaixar no fluxo de assinatura do PrescSign.

As informações abaixo foram levantadas a partir da documentação visual enviada
em conversa. Antes de ativar em produção, confirmar os pontos marcados como
pendentes com a documentação oficial/API real.

## Objetivo

Usar o EVALCryptoCubo como provedor externo de assinatura digital de PDFs,
mantendo a interface interna atual baseada em:

- `Documents::SigningService`
- `Signatures::ProviderFactory`
- `Signatures::SignatureResult`

O provider esperado deve receber um PDF gerado pelo PrescSign, enviar o conteúdo
em Base64 para o EVALCryptoCubo e retornar o PDF assinado.

## Endpoint conhecido

```http
POST /api/v1/electronic-signature-v4/{operatorId}/{type}/{format}/sign
```

Parâmetros de path:

| Parâmetro | Obrigatório | Descrição |
| --- | --- | --- |
| `operatorId` | Sim | Código do operador/conta no EVALCryptoCubo. |
| `type` | Sim | Tipo de assinatura. Para assinatura qualificada, usar `qualified`. |
| `format` | Sim | Formato da assinatura. Exemplo observado: `attached`. |

URL base:

```bash
EVAL_CRYPTO_CUBO_BASE_URL=https://api.cryptocubo.com.br
```

## Ambientes (teste vs. produção)

**Não há URL de homologação separada.** A mesma URL base atende teste e produção.
O que define se a operação roda em **teste** ou **produção** é a **chave** usada,
conforme o **plano contratado na conta EVAL** — não um host diferente.

A conta possui duas chaves, `primary_key` e `secondary_key` (padrão de chave
primária + secundária para rotação sem downtime). O comportamento de
teste/produção acompanha o plano associado a essas chaves no lado da EVAL.

Ou seja, para "assinar em homologação" **não** trocamos de URL: usamos a chave/
plano de teste. Ao ir para produção, trocamos a chave/plano — a URL permanece.

> A confirmar com a EVAL: se `primary_key` e `secondary_key` são apenas duas
> chaves válidas equivalentes (rotação) ou se cada uma mapeia explicitamente para
> um ambiente; e como o plano de teste se diferencia do de produção (mesma conta
> vs. contas separadas).

## Autenticação

A autenticação é feita pela **chave da conta** (`primary_key` / `secondary_key`),
não por login de usuário. Enviada como credencial nas chamadas à API.

> A confirmar com a EVAL: o **header exato** (ex.: `Authorization: Bearer <key>`,
> `X-Api-Key: <key>`, ou header próprio) e se a chave secundária é aceita
> simultaneamente à primária (para rotação).

Variáveis:

```bash
EVAL_CRYPTO_CUBO_PRIMARY_KEY=
EVAL_CRYPTO_CUBO_SECONDARY_KEY=
```

## Request

Payload observado:

```json
{
  "format": "attached",
  "type": "qualified",
  "documents": [
    {
      "content": "JVBERi0x..."
    }
  ]
}
```

Campos relevantes:

| Campo | Obrigatório | Descrição |
| --- | --- | --- |
| `format` | Sim | Formato da assinatura. Deve acompanhar o path `format`. |
| `type` | Sim | Tipo de assinatura. Deve acompanhar o path `type`. |
| `documents` | Sim | Lista de documentos a assinar. |
| `documents[].content` | Sim | Conteúdo do PDF em Base64. |
| `documentContentType` | Pendente | Tipo do documento, se a API exigir. Provável valor: `application/pdf`. |
| `documentName` | Pendente | Nome do arquivo/documento, se a API aceitar. |

### Identidade do assinante — CPF do médico

Quando o médico assina, a **solicitação de assinatura é feita através do CPF
dele**, referenciando um **registro (certificado) que já existe na conta EVAL**
da plataforma. O assinante **não** é um `alias`/`pin` único global — é resolvido
pelo **CPF do prescritor**, que precisa estar **previamente cadastrado como
registro na conta EVAL**.

Consequências:

- O payload de assinatura precisa carregar o **CPF do médico** como identificador
  do assinante (campo exato a confirmar — provável `signer`/`document`/`cpf`).
- **Pré-requisito operacional:** cada médico só consegue assinar se houver um
  registro correspondente ao seu CPF na conta EVAL. Isso vira um passo de
  onboarding do médico (provisionar/validar o registro na EVAL) antes da 1ª
  assinatura, e uma verificação a exibir no painel.
- O par `alias` + `pin`, antes cogitado, é **substituído** por esse modelo
  baseado em CPF (ou, no máximo, o `pin`/2º fator vem do próprio médico no ato —
  a confirmar). O CPF **não é segredo**, mas é dado pessoal: tratar como PII.

> A confirmar com a EVAL: nome exato do campo do CPF no payload; se há segundo
> fator (PIN/OTP) por assinatura; e como o registro do médico é criado/validado
> na conta (API de provisionamento vs. cadastro manual no painel EVAL).

Variáveis sugeridas:

```bash
SIGNATURE_PROVIDER=eval_crypto_cubo
EVAL_CRYPTO_CUBO_BASE_URL=
EVAL_CRYPTO_CUBO_OPERATOR_ID=
EVAL_CRYPTO_CUBO_TYPE=qualified
EVAL_CRYPTO_CUBO_FORMAT=attached
EVAL_CRYPTO_CUBO_PRIMARY_KEY=
EVAL_CRYPTO_CUBO_SECONDARY_KEY=
EVAL_CRYPTO_CUBO_TIMEOUT_SECONDS=30
```

O CPF do assinante **não** é variável de ambiente: vem do `DoctorProfile` do
médico autenticado, por assinatura.

## Response de sucesso

Status esperado:

```http
200 OK
```

Payload observado:

```json
{
  "documents": [
    {
      "content": "JVBERi0x...",
      "signatureName": "...",
      "signatureTime": "..."
    }
  ]
}
```

Campos relevantes:

| Campo | Descrição |
| --- | --- |
| `documents` | Lista de documentos assinados. |
| `documents[].content` | PDF assinado em Base64. |
| `documents[].signatureName` | Nome/identificação da assinatura, se retornado. |
| `documents[].signatureTime` | Data/hora da assinatura, se retornada. |

Mapeamento para `Signatures::SignatureResult`:

| `SignatureResult` | Origem sugerida |
| --- | --- |
| `signed_pdf` | `Base64.strict_decode64(response["documents"].first["content"])` |
| `provider` | `eval_crypto_cubo` |
| `method` | Valor interno sugerido: `eval_crypto_cubo_pades` |
| `signed_at` | `documents[].signatureTime`, se presente; caso contrário `Time.current` |
| `timestamped` | Pendente de confirmação pela API |
| `validation_status` | Valor retornado pela API, se houver; caso contrário `not_available` |
| `raw_metadata` | Payload técnico relevante sem incluir segredos |

## Responses de erro

Erros observados:

```http
400 Bad Request
500 Internal Server Error
```

Formato observado:

```json
{
  "error_code": "string",
  "error_message": "string",
  "error_additionalInfo": "string"
}
```

Mapeamento esperado no PrescSign:

- erros HTTP não 2xx devem gerar `Signatures::SignatureError`;
- payload inválido ou sem `documents[].content` deve gerar `SignatureError`;
- timeouts e falhas de conexão devem gerar `SignatureError`;
- a mensagem de erro não deve expor PIN, token, certificado ou conteúdo do PDF.

## Implementação esperada

Arquivos principais:

- `app/services/signatures/eval_crypto_cubo_provider.rb`
- `app/services/signatures/provider_factory.rb`
- `config/initializers/app_config.rb`
- `.env.example`
- `spec/services/signatures/eval_crypto_cubo_provider_spec.rb`
- `spec/services/signatures/provider_factory_spec.rb`

Fluxo:

1. `Documents::SigningService#sign!` renderiza o PDF.
2. `Signatures::ProviderFactory.build` instancia `EvalCryptoCuboProvider` quando
   `SIGNATURE_PROVIDER=eval_crypto_cubo`.
3. Provider monta request com PDF Base64.
4. EVALCryptoCubo retorna PDF assinado Base64.
5. Provider converte para `SignatureResult`.
6. `SigningService` cria nova `DocumentVersion`, anexa PDF assinado e grava
   metadados de assinatura.

## Verificação de assinatura

> **⚠️ Superado.** A verificação **implementada** usa o APIM **v0** — ver
> ["Verificação (APIM v0) — confirmada contra a API real"](#verificação-apim-v0--confirmada-contra-a-api-real).
> A descrição `electronic-signature-v4` abaixo é histórica (contrato não confirmado)
> e foi mantida só como referência.

A API também possui operação de verificação de assinaturas eletrônicas. Essa
operação deve ser documentada e implementada separadamente da assinatura, mas
pode viver no mesmo provider `Signatures::EvalCryptoCuboProvider`.

### Endpoint conhecido

```http
POST /api/v1/electronic-signature-v4/verify/{type}/{format}/{signer}/{package}
```

Parâmetros observados:

| Parâmetro | Origem | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `type` | path | Sim | Tipo de assinatura a verificar. Para assinatura qualificada, usar `qualified`, se a API usar o mesmo valor da assinatura. |
| `format` | path | Sim | Formato da assinatura. Exemplo observado: `attached`. |
| `signer` | path/query | Pendente | Indica certificado/assinante a considerar na verificação. Confirmar origem real. |
| `package` | path/query | Pendente | Indica pacote/estrutura da assinatura. Confirmar origem real. |

Observação: no print, `signer` e `package` aparecem como parâmetros opcionais,
mas a URL exibida também mostra esses valores no path. Confirmar na
documentação oficial antes de implementar.

### Request de verificação

Payload observado:

```json
{
  "format": "attached",
  "type": "qualified",
  "documents": [
    {
      "content": "JVBERi0x..."
    }
  ]
}
```

Campos relevantes:

| Campo | Obrigatório | Descrição |
| --- | --- | --- |
| `format` | Sim | Formato da assinatura/documento enviado para verificação. |
| `type` | Sim | Tipo de assinatura/documento enviado para verificação. |
| `documents` | Sim | Lista de documentos a verificar. |
| `documents[].content` | Sim | Conteúdo do PDF assinado em Base64. |

Variáveis sugeridas, caso sejam diferentes da assinatura:

```bash
EVAL_CRYPTO_CUBO_VERIFY_TYPE=
EVAL_CRYPTO_CUBO_VERIFY_FORMAT=attached
EVAL_CRYPTO_CUBO_VERIFY_SIGNER=
EVAL_CRYPTO_CUBO_VERIFY_PACKAGE=
```

Se os valores forem os mesmos da assinatura, o provider pode reutilizar:

```bash
EVAL_CRYPTO_CUBO_TYPE=qualified
EVAL_CRYPTO_CUBO_FORMAT=attached
```

### Response de sucesso da verificação

Status esperado:

```http
200 OK
```

Payload observado:

```json
{
  "documents": [
    {
      "content": "JVBERi0x...",
      "signatureName": "...",
      "signatureTime": "..."
    }
  ]
}
```

Campos relevantes:

| Campo | Descrição |
| --- | --- |
| `documents` | Lista de documentos/processamentos retornados pela verificação. |
| `documents[].content` | Conteúdo Base64 retornado pela API, se houver. Pode ser o próprio PDF ou payload processado. |
| `documents[].signatureName` | Nome/identificação da assinatura, se retornado. |
| `documents[].signatureTime` | Data/hora da assinatura, se retornada. |

Pendente de confirmação:

- campo exato que indica assinatura válida/inválida;
- campo exato que indica certificado expirado/revogado;
- detalhes de cadeia ICP-Brasil;
- informações de carimbo de tempo;
- comportamento quando há mais de uma assinatura no mesmo PDF.

### Mapeamento sugerido no PrescSign

Criar um objeto de retorno específico para verificação, por exemplo:

```ruby
Signatures::VerificationResult
```

Campos sugeridos:

| Campo | Origem sugerida |
| --- | --- |
| `provider` | `eval_crypto_cubo` |
| `valid` | Campo oficial de validação quando confirmado |
| `validation_status` | Status textual retornado pela API |
| `signatures` | Lista de assinaturas/certificados retornados |
| `checked_at` | `Time.current` |
| `raw_metadata` | Payload técnico sem segredos e sem PDF Base64 |

No provider:

```ruby
def verify_pdf!(document:, pdf_io:)
  # envia PDF assinado em Base64 para /verify
  # retorna Signatures::VerificationResult
end
```

Integração futura com o fluxo atual:

- `Documents::IntegrityService#verify!` hoje faz verificação por checksum e
  revogação em caso de divergência;
- a verificação EVALCryptoCubo deve complementar esse fluxo, não substituir a
  validação local de integridade sem decisão explícita;
- o resultado externo pode ser gravado em `document.metadata["signature_verification"]`
  ou em nova estrutura própria, se for necessário manter histórico.

### Erros da verificação

Erros observados:

```http
400 Bad Request
500 Internal Server Error
```

Formato observado:

```json
{
  "error_code": "string",
  "error_message": "string",
  "error_additionalInfo": "string"
}
```

Mapeamento esperado:

- erro HTTP não 2xx deve gerar `Signatures::SignatureError` ou uma classe
  específica como `Signatures::VerificationError`;
- resposta sem `documents` ou sem campos oficiais de validação deve ser tratada
  como resposta inválida;
- não registrar PDF Base64, token, PIN ou informações sensíveis em logs.

## Pontos pendentes

Confirmar antes da implementação final:

- **header exato** que carrega a chave (`Authorization: Bearer` vs. `X-Api-Key`
  vs. próprio) e se `secondary_key` é aceita junto da `primary_key` (rotação);
- **semântica de teste vs. produção**: se `primary`/`secondary` mapeiam ambientes
  ou são só rotação, e se teste/produção são a mesma conta ou contas separadas;
- **campo do CPF do assinante** no payload de assinatura (`signer`/`document`/`cpf`)
  e se há segundo fator (PIN/OTP) por assinatura;
- **provisionamento do registro do médico** na conta EVAL (API vs. cadastro
  manual) e como validar que o CPF tem registro antes de permitir assinar;
- valores válidos para `operatorId` e `format`;
- valores e obrigatoriedade de `signer` e `package` na verificação;
- se o formato `attached` corresponde ao PDF PAdES final esperado;
- campos reais retornados para certificado, carimbo de tempo e status de
  validação;
- campo oficial que determina sucesso/falha da verificação de assinatura;
- limites de tamanho do PDF e timeout recomendado.

Resolvidos (via atualização da conta EVAL):

- **Não há URL de homologação** — teste/produção são definidos por chave/plano,
  não por host (ver "Ambientes");
- autenticação é por **chave de conta** (`primary_key`/`secondary_key`), não por
  login de usuário;
- o assinante é identificado pelo **CPF do médico** (registro na conta EVAL), não
  por `alias`/`pin` global.

## Endpoint alternativo (APIM v0) — testado manualmente

Além do `electronic-signature-v4` descrito acima, existe uma variante exposta via
**Azure API Management** que foi **exercitada com sucesso** contra a API real
(status `200 OK`, PDF assinado retornado). Este é o endpoint que o script de teste
`tmp/scripts/test_qualified_sign.rb` usa como base.

```http
POST /api/eletronic-signatures/v0/sign/qualified/pdf?profile={profile}&icpbr={true|false}
```

Diferenças em relação ao `electronic-signature-v4`:

| Aspecto | `electronic-signature-v4` | `eletronic-signatures/v0` (APIM) |
| --- | --- | --- |
| Autenticação | `Authorization: Bearer <key>` (a confirmar) | Header `Ocp-Apim-Subscription-Key: <subscription-key>` |
| Tipo/formato | No path (`/{type}/{format}/`) | `type` fixo (`qualified`) no path; `format` no corpo |
| Seleção de política | path `operatorId/type/format` | query `profile` + `icpbr` |
| Identidade | CPF do médico (registro na conta) | corpo: `alias` (CPF) + `pin` (Base64) |

Parâmetros de query:

| Parâmetro | Obrigatório | Descrição |
| --- | --- | --- |
| `profile` | Sim | Perfil que seleciona a **política de execução** server-side (ver abaixo). Valor testado: `adrb`. |
| `icpbr` | Sim | `true`/`false` — indica se a assinatura é ICP-Brasil. Testado com `false`. |

Request testado:

```json
{
  "format": "detached",
  "alias": "39932899860",
  "pin": "MTIzNDU2Nzg=",
  "documents": [
    { "content": "JVBERi0x..." }
  ]
}
```

| Campo | Descrição |
| --- | --- |
| `format` | Formato da assinatura. Testado: `detached` (mesmo assim o retorno é um PDF PAdES com o carimbo embutido). |
| `alias` | CPF do assinante (registro na conta EVAL). |
| `pin` | PIN do assinante em **Base64**. |
| `documents[].content` | PDF em Base64. |

Response de sucesso (`200 OK`): o PDF assinado vem em
`documents[].signatures[].value` (Base64) — note que aqui é `signatures[].value`,
diferente do `documents[].content` do `electronic-signature-v4`.

### Verificação (APIM v0) — confirmada contra a API real

O **verify** também usa o APIM v0 e foi **exercitado com sucesso** (PDF válido,
PDF sem assinatura e PDF adulterado). Este é o contrato que o
`Signatures::EvalCryptoCuboProvider#verify_pdf!` implementa.

```http
POST /api/eletronic-signatures/v0/verify/qualified/pdf?icpbr={true|false}
```

Diferença importante em relação ao sign: o PDF assinado vai em
`documents[].signatures[].value` (**não** em `documents[].content`).

Request testado:

```json
{ "documents": [ { "signatures": [ { "value": "JVBERi0x..." } ] } ] }
```

Vereditos (confirmados empiricamente com `tmp/scripts/probe_verify_v0*.rb`):

| Cenário | HTTP | `error.code` | Interpretação no provider |
| --- | --- | --- | --- |
| Assinatura válida | `200` | — | `valid: true`; `documents[].signatures[].signers[]` traz `subject` (ex.: `RAFAEL:39932899860`), `issuer`, `validFrom`/`validTo`, `signingTime` |
| PDF sem assinatura | `400` | `-309` "Lista de assinaturas vazia" | `valid: false` (veredito, não erro) |
| **PDF adulterado** | `400` | `-725` "Resumo criptográfico da mensagem incorreto." | `valid: false` (integridade quebrada) |
| Indisponível/manutenção | `5xx` | — | `ProviderUnavailableError` |
| Auth/credencial | outro `4xx` | — | `SignatureError` |

Ou seja, o verify **valida integridade de verdade** (rejeita PDF adulterado com
`-725`), não é só extração de metadados.

Resposta de sucesso (com o `value` Base64 omitido):

```json
{
  "documents": [
    {
      "signatures": [
        {
          "signers": [
            {
              "cpf": null, "cnpj": null,
              "signingTime": "28/07/2026 19:43:39",
              "validFrom": "24/07/2026 15:17:55",
              "validTo": "24/07/2027 15:17:54",
              "issuer": "E-VAL Autoridade Certificadora v4",
              "subject": "RAFAEL:39932899860"
            }
          ]
        }
      ]
    }
  ]
}
```

> Nota: `signers[].cpf` veio `null`; o CPF aparece no `subject` (`NOME:CPF`).

#### Fluxo no PrescSign — camada criptográfica com degradação suave

`Documents::IntegrityService#verify!` (botão "Verificar integridade"):

1. **Checksum local (SHA256)** continua o gate autoritativo — detecta adulteração
   do PDF armazenado sem depender de rede.
2. Se o checksum local passou **e** a assinatura foi feita pela EVAL
   (`metadata.signature.provider == "eval_crypto_cubo"`), chama o `verify_pdf!`
   como validação criptográfica adicional (cadeia do certificado + integridade real).
3. **Degradação suave**: se a EVAL estiver indisponível (`5xx`/timeout — ex.: 504
   fora do horário comercial) ou falhar, o veredito **local** é mantido; nunca
   revoga por indisponibilidade. Só revoga quando a EVAL **reprova** explicitamente.

### Script de teste

`tmp/scripts/test_qualified_sign.rb` — lê um PDF de `tmp/pdf/`, envia em Base64 e
grava o PDF assinado em `tmp/pdf/signed/<nome>_signed.pdf`.

```bash
# coloque um PDF em tmp/pdf/ e rode:
ruby tmp/scripts/test_qualified_sign.rb tmp/pdf/test.pdf
```

Parametrizável por variáveis de ambiente (`SUBSCRIPTION_KEY`, `ALIAS`, `PIN`,
`PROFILE`, `ICPBR`, `FORMAT`) — os defaults do script são valores de **teste**.
Não commitar `SUBSCRIPTION_KEY`/`PIN` reais; tratar como segredo.

### Representação visual (posição/tamanho do carimbo) é server-side

Ponto **importante**, confirmado empiricamente: a aparência do carimbo visível
(posição, tamanho e o template "ASSINADO DIGITALMENTE / validade jurídica / logo
EVAL") **não é controlável pelo cliente** neste endpoint. Ela está embutida na
**política de execução** associada ao `profile`.

- Com `profile=adrb` + `icpbr=false`, a política server-side é
  `SignPdfAdrbNonicp` (a mensagem de erro `-734` para profiles inexistentes revela
  o padrão de nome: `SignPdf{Profile}{Nonicp|Icp}`).
- O carimbo default sai em `/Rect[37.37 67.67 217.37 157.67]` — **180×90 pt** no
  canto inferior esquerdo.
- Foram testadas e **ignoradas** pela API todas estas tentativas de reposicionar/
  redimensionar via requisição: campos no documento e no topo do corpo
  (`visualRepresentation`, `visual`, `appearance`, `stamp`, `signatureRectangle`,
  `signatureField`) e query-params (`x`/`y`/`width`/`height`, `llx`/`lly`/`urx`/
  `ury`). Todos retornaram exatamente o mesmo `/Rect`.

**Conclusão:** para deixar o carimbo menor ou em outra posição, a mudança é no
**painel EVAL/CryptoCubo** — editar a política `SignPdfAdrbNonicp` (retângulo da
representação visual) ou criar uma nova política e chamar via novo `profile`. Não
há ajuste possível pelo nosso código além de trocar o valor de `profile`.

> A confirmar com a EVAL: se existe uma versão do endpoint/política que aceite
> representação visual manual por requisição; e o catálogo de `profile`s
> disponíveis na conta.

## Assinatura qualificada ICP-Brasil, controle exclusivo e armazenamento do PIN

Esta seção registra por que o **armazenamento do PIN** do certificado é uma
decisão sensível quando a assinatura precisa ser **ICP-Brasil qualificada** — e o
que precisa ser confirmado com a EVAL antes de qualquer cache/persistência.

### Estado atual do código (é assinatura AVANÇADA, não qualificada)

Hoje o provider assina com `profile=adrb` + `icpbr=false`, `alias` = CPF do médico
e PIN por chamada. Isso produz uma **assinatura eletrônica avançada** (válida por
MP 2.200-2/2001), **não** uma **ICP-Brasil qualificada**. Tornar qualificada **não
é só** trocar `icpbr=true`: implica

- cada médico ter um **certificado ICP-Brasil** provisionado na EVAL (em nuvem/HSM
  ou A3);
- o **modelo de ativação** conforme o fluxo de assinatura remota deles;
- o `profile`/parâmetros corretos.

### Controle exclusivo do titular

A validade jurídica de uma assinatura qualificada (presunção de autenticidade e
**não-repúdio**) depende de o **titular** — o médico — ter **controle exclusivo**
da ativação da chave privada. O PIN é o dado que ativa a chave.

Se a **plataforma armazena o PIN**, ela passa a poder ativar a chave do médico
sozinha, e o "controle exclusivo" cai. Consequências:

1. **A assinatura pode ser contestada/invalidada** — em litígio/auditoria, alega-se
   que a plataforma poderia ter assinado sem o médico; o não-repúdio se perde.
2. **Compliance da controlada** — para receita de controlado (Portaria 344 / SNCR),
   a cadeia de responsabilidade exige que a assinatura seja comprovadamente ato do
   prescritor.
3. **Regras da AC/EVAL** — o termo de titularidade e as normas ICP-Brasil
   (DOC-ICP-15 e, para nuvem, as regras de assinatura remota do ITI) tipicamente
   **proíbem** armazenar/compartilhar o dado de ativação.

### Assinatura em nuvem (modelo da EVAL)

A EVAL/CryptoCubo é **assinatura em nuvem**: a chave fica em **HSM** deles e o médico
autoriza via um fator (PIN/OTP). A norma de assinatura remota empurra para
**autorização por operação** (ou por sessão com controles fortes) sob controle do
titular — ou seja, **autenticar a cada assinatura** ou usar um **token curto por
sessão** emitido após uma autenticação, **não** um PIN persistido.

### Diretriz para o PrescSign

- **PIN salvo no banco** → provavelmente **incompatível** com qualificada (quebra o
  controle exclusivo). Não implementar sem aval de compliance/EVAL.
- **PIN em sessão** (efêmero, opt-in, TTL curto, limpo no logout) → zona cinza;
  melhor que banco, mas ainda relaxa o "por operação". Só com aval.
- **Padrão recomendado** → pedir o PIN **a cada assinatura**; ou guardar um
  **token de sessão de assinatura** (não o PIN) se a EVAL oferecer.
- Independente disso: **receita controlada sempre pede PIN** (nunca usa cache).

### A confirmar com a EVAL (bloqueia a decisão de cache/persistência)

1. O fluxo de nuvem permite **cachear o PIN** por sessão, ou exige autenticação
   **por assinatura**?
2. Existe **token/sessão de assinatura** curto após uma autenticação? Qual a
   duração e como renovar?
3. O que o **termo de titularidade** do certificado diz sobre armazenar o dado de
   ativação (PIN)?
4. Quais `profile`/parâmetros e que provisionamento de certificado por médico são
   necessários para a assinatura sair como **ICP-Brasil qualificada** (`icpbr=true`)?

> Observação: este documento não é parecer jurídico. As respostas 1–4 (EVAL +
> jurídico) definem se e como o PIN pode ser mantido; até lá, manter PIN por
> assinatura.

## Segurança

- Nunca registrar `EVAL_CRYPTO_CUBO_PRIMARY_KEY`, `EVAL_CRYPTO_CUBO_SECONDARY_KEY`
  ou conteúdo Base64 do PDF em logs. As chaves são credenciais de conta com poder
  de assinar em nome dos médicos — tratar como segredo de alto valor.
- O **CPF do médico** é PII: não logar em texto claro nem expor em mensagens de
  erro; incluir em filtros de parâmetros.
- Incluir esses campos em filtros de parâmetros caso passem por controllers ou
  logs estruturados.
- Em produção, validar presença das variáveis obrigatórias quando
  `SIGNATURE_PROVIDER=eval_crypto_cubo` (ao menos `primary_key`).
