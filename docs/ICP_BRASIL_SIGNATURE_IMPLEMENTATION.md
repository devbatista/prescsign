# Implementacao de Assinatura ICP-Brasil

Este documento descreve como evoluir o fluxo atual de assinatura digital do PrescSign para uma assinatura ICP-Brasil real, especialmente em PDF assinado no padrao PAdES.

## Estado atual

O projeto ja possui um fluxo interno de assinatura:

- `POST /v1/documents/:id/sign`
- `Documents::SigningService`
- `Signatures::InternalProvider`
- `Documents::IntegrityService`
- validacao publica por URL e QR Code
- auditoria de eventos de assinatura, status e revogacao

Hoje, a assinatura e um MVP interno baseado em hash SHA-256 do conteudo textual do documento. Esse mecanismo ajuda a controlar integridade dentro do sistema, mas nao gera uma assinatura ICP-Brasil verificavel em leitores de PDF ou validadores oficiais.

Implementacao atual:

```ruby
payload = [content.to_s, principal_id.to_s, occurred_at.to_i.to_s, VERSION].join("|")
Digest::SHA256.hexdigest(payload)
```

Isso deve continuar existindo apenas como provider de desenvolvimento/teste ou como camada complementar de auditoria.

## Objetivo

Implementar assinatura digital ICP-Brasil para receitas e atestados medicos, com PDF final assinado em PAdES e validavel externamente.

Requisitos esperados:

- gerar PDF final antes da assinatura;
- assinar o PDF usando certificado ICP-Brasil;
- anexar o PDF assinado na `DocumentVersion`;
- persistir metadados tecnicos da assinatura;
- manter auditoria e trilha de integridade;
- manter QR Code e validacao publica como camada complementar;
- validar o PDF assinado em ferramenta externa, preferencialmente o verificador oficial do ITI.

## Padrao recomendado

Para PDF, o caminho recomendado e PAdES.

Formatos comuns na ICP-Brasil:

- CAdES: assinatura para conteudos binarios ou documentos em geral;
- XAdES: assinatura XML;
- PAdES: assinatura PDF.

Como o PrescSign gera receitas e atestados em PDF, o provider deve gerar assinatura PAdES.

## Estrategia recomendada

Usar um provedor especializado de assinatura ICP-Brasil em vez de implementar criptografia e manipulacao de PDF manualmente.

Exemplos de capacidades que o provedor deve oferecer:

- assinatura PAdES;
- suporte a certificado ICP-Brasil;
- assinatura remota/cloud ou fluxo compativel com A1/A3;
- carimbo de tempo, quando necessario;
- validacao de cadeia;
- retorno do PDF assinado;
- retorno de metadados do certificado e da assinatura;
- ambiente de homologacao/sandbox;
- evidencia tecnica suficiente para auditoria.

Implementar PAdES diretamente dentro da aplicacao e possivel, mas aumenta muito o risco tecnico e juridico, pois envolve:

- atualizacao incremental de PDF;
- assinatura CMS/CAdES embutida no PDF;
- cadeia de certificados;
- politica de assinatura;
- OCSP/CRL;
- carimbo de tempo;
- LTV;
- compatibilidade com validadores externos.

## Arquitetura proposta

Criar uma interface de provider para assinatura de PDF.

```ruby
module Signatures
  class IcpBrasilProvider
    def sign_pdf!(document:, pdf_io:, signer:)
      # Chama API externa de assinatura ICP-Brasil.
      # Retorna objeto com PDF assinado e metadados da assinatura.
    end
  end
end
```

Criar tambem uma fabrica simples:

```ruby
module Signatures
  class ProviderFactory
    def self.build
      case Rails.application.config.x.signature_provider
      when "icp_brasil"
        Signatures::IcpBrasilProvider.new
      else
        Signatures::InternalProvider.new
      end
    end
  end
end
```

Configuracao sugerida:

```env
SIGNATURE_PROVIDER=internal
ICP_BRASIL_PROVIDER_BASE_URL=
ICP_BRASIL_PROVIDER_API_KEY=
ICP_BRASIL_PROVIDER_TIMEOUT_SECONDS=30
```

Em producao, o ideal e usar:

```env
SIGNATURE_PROVIDER=icp_brasil
```

## Fluxo de assinatura proposto

Fluxo atual resumido:

1. usuario cria receita ou atestado;
2. sistema cria `Document` com status `issued`;
3. `POST /documents/:id/sign` chama `Documents::SigningService`;
4. assinatura interna gera hash;
5. documento passa para `sent`;
6. recurso clinico passa para `signed`.

Fluxo ICP-Brasil proposto:

1. usuario cria receita ou atestado;
2. sistema cria `Document` com status `issued`;
3. usuario chama `POST /documents/:id/sign`;
4. `SigningService` gera o PDF final do documento;
5. `IcpBrasilProvider` assina o PDF em PAdES;
6. provider retorna PDF assinado e metadados;
7. sistema cria nova `DocumentVersion`;
8. sistema anexa o PDF assinado na versao;
9. sistema grava metadados de assinatura em `document.metadata["signature"]`;
10. documento passa para `sent`;
11. recurso clinico passa para `signed`;
12. auditoria registra assinatura e mudancas de status.

## Mudancas no SigningService

O `Documents::SigningService` deve deixar de assinar apenas `document.documentable.content`.

Ele deve operar sobre o PDF final:

```ruby
pdf = Documents::PdfRenderer.new(document: document).render
signature_result = @signature_provider.sign_pdf!(
  document: document,
  pdf_io: StringIO.new(pdf),
  signer: @actor
)
```

O resultado esperado do provider pode seguir este formato:

```ruby
SignatureResult = Data.define(
  :signed_pdf,
  :provider,
  :method,
  :policy,
  :certificate_subject,
  :certificate_issuer,
  :certificate_serial,
  :certificate_cpf,
  :signed_at,
  :timestamped,
  :validation_status,
  :raw_metadata
)
```

## Metadados recomendados

Salvar em `document.metadata["signature"]`:

```json
{
  "method": "icp_brasil_pades",
  "provider": "provider_name",
  "policy": "AD-RB",
  "certificate_subject": "CN=...",
  "certificate_issuer": "CN=...",
  "certificate_serial": "...",
  "certificate_cpf": "...",
  "signed_by_user_id": "uuid",
  "signed_at": "2026-05-13T12:00:00Z",
  "timestamped": true,
  "validation_status": "valid",
  "signed_version": 2,
  "signed_pdf_checksum": "sha256..."
}
```

Evitar armazenar:

- chave privada;
- senha de certificado;
- arquivo de certificado A1 em texto puro;
- tokens sensiveis do provedor;
- payloads completos com dados sensiveis sem sanitizacao.

## Certificados A1, A3 e assinatura remota

### A1

Certificado em arquivo/software. E mais simples para automacao no backend, mas traz risco alto de custodia da chave privada.

Recomendacao: evitar armazenar certificado A1 do medico no PrescSign, a menos que exista uma estrategia robusta de seguranca, criptografia, auditoria e consentimento.

### A3

Certificado em token/cartao. Normalmente depende de interacao local com o dispositivo do usuario, middleware no computador ou app/bridge.

Recomendacao: usar provider que resolva o fluxo A3 ou oferecer assinatura remota.

### Assinatura remota/cloud

Geralmente e o melhor caminho para UX e seguranca. O usuario autoriza a assinatura no provedor e o PrescSign recebe o PDF assinado.

Recomendacao: priorizar esse modelo.

## Impacto no banco de dados

O modelo atual pode suportar a primeira versao usando `metadata` JSON e `ActiveStorage`.

Possivel evolucao futura:

Criar tabela `document_signatures`:

```ruby
create_table :document_signatures, id: :uuid do |t|
  t.references :document, null: false, foreign_key: true, type: :uuid
  t.references :document_version, null: false, foreign_key: true, type: :uuid
  t.references :user, null: false, foreign_key: true, type: :uuid
  t.string :provider, null: false
  t.string :method, null: false
  t.string :policy
  t.string :certificate_subject
  t.string :certificate_issuer
  t.string :certificate_serial
  t.string :certificate_cpf
  t.string :validation_status
  t.datetime :signed_at, null: false
  t.boolean :timestamped, null: false, default: false
  t.jsonb :metadata, null: false, default: {}
  t.timestamps
end
```

Para MVP, `document.metadata["signature"]` e suficiente. Para auditoria mais forte, uma tabela dedicada e melhor.

## Validacao publica

A validacao publica atual deve continuar existindo, mas ela nao substitui a assinatura ICP-Brasil.

Ela deve informar:

- status do documento no PrescSign;
- codigo do documento;
- dados publicos do emissor;
- versao atual;
- hash do PDF assinado;
- status de revogacao/expiracao no sistema.

O QR Code deve apontar para a validacao publica do PrescSign, enquanto a validade juridica da assinatura deve estar no PDF PAdES.

## Criterios de aceite

Uma implementacao ICP-Brasil deve ser considerada pronta apenas quando:

- o endpoint `POST /documents/:id/sign` gera PDF assinado;
- o PDF assinado e anexado na `DocumentVersion`;
- o PDF assinado abre em leitor de PDF reconhecendo assinatura digital;
- o PDF passa no validador externo definido pelo time;
- o sistema salva metadados da assinatura;
- auditoria registra usuario, IP, user-agent, request ID e horario;
- falhas do provider geram alerta critico;
- testes cobrem sucesso, falha do provider, idempotencia e integridade;
- dados sensiveis nao aparecem em logs.

## Plano de implementacao

### Fase 1: Preparar abstracao

- Criar `Signatures::ProviderFactory`.
- Manter `Signatures::InternalProvider` para desenvolvimento e testes.
- Criar contrato comum para resultado de assinatura.
- Adicionar configuracao `SIGNATURE_PROVIDER`.

### Fase 2: Gerar PDF antes da assinatura

- Extrair geracao de PDF dos controllers para um service reutilizavel.
- Usar esse service no endpoint de assinatura.
- Garantir que o PDF assinado seja o mesmo documento exibido ao usuario.

### Fase 3: Integrar provider ICP-Brasil

- Criar `Signatures::IcpBrasilProvider`.
- Implementar client HTTP com timeout e tratamento de erro.
- Mapear resposta do provider para `SignatureResult`.
- Sanitizar logs.

### Fase 4: Persistir PDF assinado

- Criar nova `DocumentVersion` com o conteudo assinado.
- Anexar PDF assinado via ActiveStorage.
- Salvar checksum do PDF assinado.
- Atualizar `document.metadata["signature"]`.

### Fase 5: Validacao e auditoria

- Atualizar `IntegrityService` para validar o PDF assinado quando aplicavel.
- Adicionar status/metadados de validacao.
- Garantir trilha de auditoria completa.

### Fase 6: Homologacao

- Testar com certificados reais ou ambiente sandbox do provider.
- Validar PDFs assinados em ferramenta externa.
- Documentar evidencias de validacao.
- Definir procedimento operacional para falhas do provider.

## Riscos importantes

- Custodia indevida de chave privada de medico.
- PDF assinado diferente do PDF visualizado pelo usuario.
- Assinatura interna ser confundida com assinatura ICP-Brasil.
- Falta de validacao externa do PDF.
- Vazamento de certificado, senha ou token em logs.
- Dependencia de provider sem SLA adequado.
- Falhas de idempotencia gerando multiplas assinaturas.

## Recomendacao final

Para o PrescSign, o caminho mais seguro e pragmatico e:

1. manter o provider interno apenas para desenvolvimento;
2. integrar um provider ICP-Brasil que gere PAdES;
3. assinar o PDF final, nao apenas o conteudo textual;
4. salvar o PDF assinado em `DocumentVersion`;
5. manter QR Code, checksum e auditoria como camadas complementares;
6. usar validacao externa como criterio de aceite tecnico.
