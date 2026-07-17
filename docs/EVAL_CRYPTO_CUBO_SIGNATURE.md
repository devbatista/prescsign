# Integracao EVALCryptoCubo para assinatura digital

Este documento registra o contrato conhecido da API de assinatura do
EVALCryptoCubo e como ela deve se encaixar no fluxo de assinatura do PrescSign.

As informacoes abaixo foram levantadas a partir da documentacao visual enviada
em conversa. Antes de ativar em producao, confirmar os pontos marcados como
pendentes com a documentacao oficial/API real.

## Objetivo

Usar o EVALCryptoCubo como provedor externo de assinatura digital de PDFs,
mantendo a interface interna atual baseada em:

- `Documents::SigningService`
- `Signatures::ProviderFactory`
- `Signatures::SignatureResult`

O provider esperado deve receber um PDF gerado pelo PrescSign, enviar o conteudo
em Base64 para o EVALCryptoCubo e retornar o PDF assinado.

## Endpoint conhecido

```http
POST /api/v1/electronic-signature-v4/{operatorId}/{type}/{format}/sign
```

Parametros de path:

| Parametro | Obrigatorio | Descricao |
| --- | --- | --- |
| `operatorId` | Sim | Codigo do operador/conta no EVALCryptoCubo. |
| `type` | Sim | Tipo de assinatura. Para assinatura qualificada, usar `qualified`. |
| `format` | Sim | Formato da assinatura. Exemplo observado: `attached`. |

URL base sugerida por ambiente:

```bash
EVAL_CRYPTO_CUBO_BASE_URL=https://api.cryptocubo.com.br
```

## Autenticacao

Pendente de confirmacao.

A implementacao deve confirmar qual mecanismo a API exige:

- `Authorization: Bearer <token>`
- chave em header customizado;
- mTLS/certificado cliente;
- outro mecanismo.

Variavel sugerida caso a autenticacao seja por token:

```bash
EVAL_CRYPTO_CUBO_API_KEY=
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

| Campo | Obrigatorio | Descricao |
| --- | --- | --- |
| `format` | Sim | Formato da assinatura. Deve acompanhar o path `format`. |
| `type` | Sim | Tipo de assinatura. Deve acompanhar o path `type`. |
| `documents` | Sim | Lista de documentos a assinar. |
| `documents[].content` | Sim | Conteudo do PDF em Base64. |
| `alias` | Pendente | Nome/alias do certificado, quando exigido. |
| `pin` | Pendente | PIN do certificado, quando exigido. Deve vir de segredo/env. |
| `documentContentType` | Pendente | Tipo do documento, se a API exigir. Provavel valor: `application/pdf`. |
| `documentName` | Pendente | Nome do arquivo/documento, se a API aceitar. |

Variaveis sugeridas:

```bash
SIGNATURE_PROVIDER=eval_crypto_cubo
EVAL_CRYPTO_CUBO_BASE_URL=
EVAL_CRYPTO_CUBO_OPERATOR_ID=
EVAL_CRYPTO_CUBO_TYPE=qualified
EVAL_CRYPTO_CUBO_FORMAT=attached
EVAL_CRYPTO_CUBO_API_KEY=
EVAL_CRYPTO_CUBO_ALIAS=
EVAL_CRYPTO_CUBO_PIN=
EVAL_CRYPTO_CUBO_TIMEOUT_SECONDS=30
```

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

| Campo | Descricao |
| --- | --- |
| `documents` | Lista de documentos assinados. |
| `documents[].content` | PDF assinado em Base64. |
| `documents[].signatureName` | Nome/identificacao da assinatura, se retornado. |
| `documents[].signatureTime` | Data/hora da assinatura, se retornada. |

Mapeamento para `Signatures::SignatureResult`:

| `SignatureResult` | Origem sugerida |
| --- | --- |
| `signed_pdf` | `Base64.strict_decode64(response["documents"].first["content"])` |
| `provider` | `eval_crypto_cubo` |
| `method` | Valor interno sugerido: `eval_crypto_cubo_pades` |
| `signed_at` | `documents[].signatureTime`, se presente; caso contrario `Time.current` |
| `timestamped` | Pendente de confirmacao pela API |
| `validation_status` | Valor retornado pela API, se houver; caso contrario `not_available` |
| `raw_metadata` | Payload tecnico relevante sem incluir segredos |

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

- erros HTTP nao 2xx devem gerar `Signatures::SignatureError`;
- payload invalido ou sem `documents[].content` deve gerar `SignatureError`;
- timeouts e falhas de conexao devem gerar `SignatureError`;
- a mensagem de erro nao deve expor PIN, token, certificado ou conteudo do PDF.

## Implementacao esperada

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

## Verificacao de assinatura

A API tambem possui operacao de verificacao de assinaturas eletronicas. Essa
operacao deve ser documentada e implementada separadamente da assinatura, mas
pode viver no mesmo provider `Signatures::EvalCryptoCuboProvider`.

### Endpoint conhecido

```http
POST /api/v1/electronic-signature-v4/verify/{type}/{format}/{signer}/{package}
```

Parametros observados:

| Parametro | Origem | Obrigatorio | Descricao |
| --- | --- | --- | --- |
| `type` | path | Sim | Tipo de assinatura a verificar. Para assinatura qualificada, usar `qualified`, se a API usar o mesmo valor da assinatura. |
| `format` | path | Sim | Formato da assinatura. Exemplo observado: `attached`. |
| `signer` | path/query | Pendente | Indica certificado/assinante a considerar na verificacao. Confirmar origem real. |
| `package` | path/query | Pendente | Indica pacote/estrutura da assinatura. Confirmar origem real. |

Observacao: no print, `signer` e `package` aparecem como parametros opcionais,
mas a URL exibida tambem mostra esses valores no path. Confirmar na
documentacao oficial antes de implementar.

### Request de verificacao

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

| Campo | Obrigatorio | Descricao |
| --- | --- | --- |
| `format` | Sim | Formato da assinatura/documento enviado para verificacao. |
| `type` | Sim | Tipo de assinatura/documento enviado para verificacao. |
| `documents` | Sim | Lista de documentos a verificar. |
| `documents[].content` | Sim | Conteudo do PDF assinado em Base64. |

Variaveis sugeridas, caso sejam diferentes da assinatura:

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

### Response de sucesso da verificacao

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

| Campo | Descricao |
| --- | --- |
| `documents` | Lista de documentos/processamentos retornados pela verificacao. |
| `documents[].content` | Conteudo Base64 retornado pela API, se houver. Pode ser o proprio PDF ou payload processado. |
| `documents[].signatureName` | Nome/identificacao da assinatura, se retornado. |
| `documents[].signatureTime` | Data/hora da assinatura, se retornada. |

Pendente de confirmacao:

- campo exato que indica assinatura valida/invalida;
- campo exato que indica certificado expirado/revogado;
- detalhes de cadeia ICP-Brasil;
- informacoes de carimbo de tempo;
- comportamento quando ha mais de uma assinatura no mesmo PDF.

### Mapeamento sugerido no PrescSign

Criar um objeto de retorno especifico para verificacao, por exemplo:

```ruby
Signatures::VerificationResult
```

Campos sugeridos:

| Campo | Origem sugerida |
| --- | --- |
| `provider` | `eval_crypto_cubo` |
| `valid` | Campo oficial de validacao quando confirmado |
| `validation_status` | Status textual retornado pela API |
| `signatures` | Lista de assinaturas/certificados retornados |
| `checked_at` | `Time.current` |
| `raw_metadata` | Payload tecnico sem segredos e sem PDF Base64 |

No provider:

```ruby
def verify_pdf!(document:, pdf_io:)
  # envia PDF assinado em Base64 para /verify
  # retorna Signatures::VerificationResult
end
```

Integracao futura com o fluxo atual:

- `Documents::IntegrityService#verify!` hoje faz verificacao por checksum e
  revogacao em caso de divergencia;
- a verificacao EVALCryptoCubo deve complementar esse fluxo, nao substituir a
  validacao local de integridade sem decisao explicita;
- o resultado externo pode ser gravado em `document.metadata["signature_verification"]`
  ou em nova estrutura propria, se for necessario manter historico.

### Erros da verificacao

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

- erro HTTP nao 2xx deve gerar `Signatures::SignatureError` ou uma classe
  especifica como `Signatures::VerificationError`;
- resposta sem `documents` ou sem campos oficiais de validacao deve ser tratada
  como resposta invalida;
- nao registrar PDF Base64, token, PIN ou informacoes sensiveis em logs.

## Pontos pendentes

Confirmar antes da implementacao final:

- mecanismo real de autenticacao;
- valores validos para `operatorId` e `format`;
- valores e obrigatoriedade de `signer` e `package` na verificacao;
- necessidade de `alias` e `pin`;
- se o PIN pode/deve ser armazenado como variavel de ambiente;
- se o formato `attached` corresponde ao PDF PAdES final esperado;
- campos reais retornados para certificado, carimbo de tempo e status de
  validacao;
- campo oficial que determina sucesso/falha da verificacao de assinatura;
- limites de tamanho do PDF e timeout recomendado.

## Seguranca

- Nunca registrar `EVAL_CRYPTO_CUBO_API_KEY`, `EVAL_CRYPTO_CUBO_PIN` ou conteudo
  Base64 do PDF em logs.
- Incluir esses campos em filtros de parametros caso passem por controllers ou
  logs estruturados.
- Em producao, validar presenca das variaveis obrigatorias quando
  `SIGNATURE_PROVIDER=eval_crypto_cubo`.
