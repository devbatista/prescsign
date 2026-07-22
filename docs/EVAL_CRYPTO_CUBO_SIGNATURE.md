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

URL base sugerida por ambiente:

```bash
EVAL_CRYPTO_CUBO_BASE_URL=https://api.cryptocubo.com.br
```

## Autenticação

Pendente de confirmação.

A implementação deve confirmar qual mecanismo a API exige:

- `Authorization: Bearer <token>`
- chave em header customizado;
- mTLS/certificado cliente;
- outro mecanismo.

Variável sugerida caso a autenticação seja por token:

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

| Campo | Obrigatório | Descrição |
| --- | --- | --- |
| `format` | Sim | Formato da assinatura. Deve acompanhar o path `format`. |
| `type` | Sim | Tipo de assinatura. Deve acompanhar o path `type`. |
| `documents` | Sim | Lista de documentos a assinar. |
| `documents[].content` | Sim | Conteúdo do PDF em Base64. |
| `alias` | Pendente | Nome/alias do certificado, quando exigido. |
| `pin` | Pendente | PIN do certificado, quando exigido. Deve vir de segredo/env. |
| `documentContentType` | Pendente | Tipo do documento, se a API exigir. Provável valor: `application/pdf`. |
| `documentName` | Pendente | Nome do arquivo/documento, se a API aceitar. |

Variáveis sugeridas:

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

- mecanismo real de autenticação;
- valores válidos para `operatorId` e `format`;
- valores e obrigatoriedade de `signer` e `package` na verificação;
- necessidade de `alias` e `pin`;
- se o PIN pode/deve ser armazenado como variável de ambiente;
- se o formato `attached` corresponde ao PDF PAdES final esperado;
- campos reais retornados para certificado, carimbo de tempo e status de
  validação;
- campo oficial que determina sucesso/falha da verificação de assinatura;
- limites de tamanho do PDF e timeout recomendado.

## Segurança

- Nunca registrar `EVAL_CRYPTO_CUBO_API_KEY`, `EVAL_CRYPTO_CUBO_PIN` ou conteúdo
  Base64 do PDF em logs.
- Incluir esses campos em filtros de parâmetros caso passem por controllers ou
  logs estruturados.
- Em produção, validar presença das variáveis obrigatórias quando
  `SIGNATURE_PROVIDER=eval_crypto_cubo`.
