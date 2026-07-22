# Integração SNCR (Anvisa) para receitas de controlados

Este documento registra o **planejamento** da integração do PrescSign com o
Sistema Nacional de Controle de Receituários (SNCR) da Anvisa, exigida pela
RDC 1.000/2025 para prescrições eletrônicas de medicamentos controlados e
sujeitos a controle especial.

É um documento vivo de planejamento. Enquanto a documentação oficial da API do
SNCR não estiver confirmada no código, todos os pontos de contrato com a Anvisa
estão marcados como **pendentes**. Confirmar com o manual/API oficial da Anvisa
antes de implementar.

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
- Documentação de integração disponibilizada pela Anvisa em junho/2026
  (manuais + webinares) para as desenvolvedoras adaptarem os sistemas.

### Consequência prática

Sem integração ao SNCR, a receita eletrônica de controlado emitida pelo
PrescSign **não é válida** — independentemente da qualidade da assinatura
ICP-Brasil. O PrescSign precisa se tornar um "serviço de prescrição integrado ao
SNCR".

## 2. Escopo: quais receitas são alcançadas

A RDC 1.000 alcança (não é só tarja preta):

- Notificação de Receita **A, B e B2**;
- NR Especial para **retinoides**;
- NR de **Talidomida**;
- Receitas de **Controle Especial (C1/C5)**;
- receitas sujeitas a **retenção**, incluindo **antimicrobianos** e análogos de
  **GLP-1**.

Antibiótico comum entra no escopo. Isso alcança quase todo clínico geral, ou
seja: **não é um caso de nicho** — mexe no fluxo principal de receitas.

## 3. Lacuna atual do PrescSign (estado do código)

O modelo de domínio atual **não tem nenhuma noção de receita controlada**. Isso
precisa ser criado antes de qualquer chamada ao SNCR.

| Necessidade regulatória | Estado atual no código | Gap |
| --- | --- | --- |
| Distinguir tipo de receita (controle especial, NR-A/B, antimicrobiano, etc.) | `Prescription` é genérica: só `content` (texto livre) + `valid_until`. Não existe coluna/enum de tipo. Única tipificação é `Document::KINDS = %w[prescription medical_certificate]` (`app/models/document.rb:2`). | Criar tipo/categoria de receita e classificação de controlado. |
| Prescrição **nata digital** com itens estruturados (medicamento, quantidade, posologia) | `content` é texto livre; **não há** model `Medication`/`PrescriptionItem`. Ver `app/models/prescription.rb`. | Estruturar itens da receita (a Anvisa exige dados por medicamento). |
| **Numeração nacional única** vinculada ao profissional | `code` é aleatório local: `SecureRandom.alphanumeric(10).upcase` em loop até não colidir (`app/services/documents/lifecycle_service.rb:159-164`). Não há numeração nacional nem vínculo formal profissional. | Persistir a numeração vinda do SNCR; não gerar localmente para controlados. |
| Registro de utilização / uso único na dispensação | Não existe. | Fora do escopo direto do emissor (a farmácia registra), mas pode exigir endpoint/estado. |
| Assinatura qualificada obrigatória na emissão | Já existe via `Signatures::EvalCryptoCuboProvider` (`app/services/signatures/eval_crypto_cubo_provider.rb`) e `Documents::SigningService#sign!` (`app/services/documents/signing_service.rb:22`). | Reaproveitar no passo final; garantir que controlado exige `type=qualified`. |

## 4. Fluxo alvo da receita controlada

Ordem exigida pela RDC (com a flexibilização da RDC 1.028):

```
1. Autenticar acesso ao SNCR        -> API Anvisa, SEM qualificada (flexibilizado)
2. Requisitar numeração ao SNCR     -> API Anvisa, SEM qualificada (flexibilizado)
3. Gerar o receituário nato digital -> com a numeração nacional embutida
4. Assinar no CryptoCubo            -> QUALIFICADA, obrigatória aqui
5. Entregar ao paciente             -> + registrar no prontuário
6. Farmácia registra o uso          -> baixa no SNCR (uso único) [ator externo]
```

Encaixe no fluxo interno atual:

| Passo | Onde encaixa hoje |
| --- | --- |
| 1-2. Auth + numeração SNCR | **Novo.** Antes/durante `Documents::LifecycleService#create_with_initial_version!` (`app/services/documents/lifecycle_service.rb:13`). Para controlados, o `code` deve vir do SNCR em vez de `generate_code`. |
| 3. Receituário nato digital | `Documents::PdfRenderer` + template `documents/pdf/prescription` (`app/services/documents/pdf_renderer.rb:38-47`). Precisa exibir numeração SNCR + dados estruturados. |
| 4. Assinatura qualificada | Sem mudança estrutural: `Documents::SigningService#sign!` -> `EvalCryptoCuboProvider#sign_pdf!` (`type=qualified`). |
| 5. Entrega | Fluxo de entrega atual (`DocumentChannelDeliveryJob`, `Deliveries::ChannelDispatcher`). |
| 6. Dispensação | Ator externo (farmácia). Avaliar se há callback/consulta de status. |

Ponto de atenção de ordem: **a numeração (passo 2) precisa existir antes de
gerar/assinar (passos 3-4)**. Hoje o `code` é gerado na criação do documento; no
fluxo de controlado ele deve ser reservado no SNCR primeiro, e a assinatura só
ocorre depois. Se a assinatura falhar, definir o que acontece com a numeração
reservada (cancelar? reutilizar?).

## 5. Contrato com a API do SNCR (pendente de confirmação)

> Todos os campos, rotas, método de autenticação e formatos abaixo são
> **placeholders** até a confirmação com a documentação oficial da Anvisa. Não
> implementar como verdade sem checar o manual/API real.

### 5.1 Autenticação de acesso (passo 1)

- Mecanismo real: **pendente** (certificado da instituição? credencial de
  serviço? token OAuth? mTLS?).
- Flexibilizado pela RDC 1.028: **não exige** assinatura qualificada nesta etapa.
- Provavelmente vincula o serviço de prescrição (PrescSign/organização) e o
  profissional prescritor.

### 5.2 Requisição de numeração (passo 2)

- Endpoint: **pendente**.
- Entrada provável: identificação do profissional (CRM/CPF), tipo de receita,
  organização/unidade.
- Saída provável: **numeração nacional única** + validade + metadados.
- Flexibilizado: **não exige** assinatura qualificada nesta etapa.
- Idempotência/reserva: definir comportamento se a emissão não se concretizar.

### 5.3 Emissão / vínculo do receituário (passos 3-4)

- Confirmar se há um passo explícito de "registrar receita emitida" no SNCR, ou
  se a numeração já é suficiente até a dispensação.
- Assinatura qualificada **obrigatória** aqui — reaproveitar o contrato do
  [EVAL_CRYPTO_CUBO_SIGNATURE.md](EVAL_CRYPTO_CUBO_SIGNATURE.md).

## 6. Impacto no modelo de domínio (mudanças de código previstas)

Ordem sugerida de trabalho (cada item é um passo verificável):

1. **Classificação de receita controlada**
   - Nova coluna em `prescriptions` (ex.: `controlled_class` / `prescription_type`)
     e/ou tabela de referência de listas (A/B/B2/C1/C5/antimicrobiano/GLP-1).
   - Model: `app/models/prescription.rb`. Schema: `db/schema.rb` (tabela
     `prescriptions`, ~`367-392`).
2. **Itens estruturados da receita (nato digital)**
   - Avaliar model `PrescriptionItem` (medicamento, concentração, quantidade,
     posologia) — hoje inexistente.
3. **Numeração SNCR**
   - Persistir a numeração nacional (nova coluna/tabela vinculada a
     `Prescription`/`Document`).
   - Para controlados, **não** usar `generate_code`
     (`app/services/documents/lifecycle_service.rb:159-164`); usar a numeração do
     SNCR.
4. **Cliente SNCR**
   - Novo service `app/services/sncr/client.rb` (ou módulo `Sncr::`), no mesmo
     padrão `Net::HTTP` puro dos providers de assinatura
     (`app/services/signatures/icp_brasil_provider.rb:34-55`,
     `app/services/signatures/eval_crypto_cubo_provider.rb:115-132`) — o projeto
     não usa Faraday/HTTParty.
   - Métodos previstos: `authenticate!`, `request_numbering!`, e (se aplicável)
     `register_issuance!`.
   - Erros: classe própria `Sncr::Error` (análoga a
     `Signatures::SignatureError`).
5. **Orquestração do fluxo controlado**
   - Estender `Documents::LifecycleService`/`SigningService` (ou novo service
     `Documents::ControlledPrescriptionService`) para: reservar numeração ->
     gerar PDF nato digital -> assinar qualificada -> registrar.
   - `sign!` hoje exige `document.status == "issued"` e
     `documentable.status == "draft"` (`app/services/documents/signing_service.rb:94-96`);
     validar que, para controlado, a numeração SNCR já está presente antes de
     assinar.
6. **Config / ambiente**
   - Novas chaves em `config/initializers/app_config.rb` (`config.x.sncr`),
     seguindo o padrão de `eval_crypto_cubo_provider_options`
     (`config/initializers/app_config.rb:131-146`) e a validação obrigatória em
     produção (`validate_integrations!`, ~`app_config.rb:169-222`).
   - Novas variáveis no `.env.example` (seção de integração).
7. **PDF / template**
   - `documents/pdf/prescription` deve exibir numeração SNCR, classe do
     controlado e dados estruturados (`app/services/documents/pdf_renderer.rb`).
8. **Auditoria**
   - Registrar eventos de numeração/emissão SNCR via `AuditLog.record!`
     (padrão já usado em `LifecycleService`/`SigningService`).
9. **Testes**
   - `spec/services/sncr/client_spec.rb`, cobertura do fluxo controlado e
     ajustes nos specs de assinatura existentes.

## 7. Variáveis de ambiente sugeridas (placeholders)

```bash
# Integração SNCR (Anvisa) - controlados
SNCR_ENABLED=false
SNCR_BASE_URL=
SNCR_AUTH_MODE=              # pendente: token | mtls | certificate | oauth
SNCR_CLIENT_ID=
SNCR_CLIENT_SECRET=
SNCR_TIMEOUT_SECONDS=30
# Reaproveita a assinatura qualificada existente no passo final:
# SIGNATURE_PROVIDER=eval_crypto_cubo
# EVAL_CRYPTO_CUBO_TYPE=qualified
```

Regras de segurança (mesmas do padrão atual):

- nunca logar segredos do SNCR, tokens, certificados ou conteúdo do PDF;
- incluir chaves sensíveis no `filter_parameter_logging`
  (`config/initializers/filter_parameter_logging.rb`);
- em produção, exigir as variáveis obrigatórias quando `SNCR_ENABLED=true`
  (via `require_in_production!` em `app_config.rb`).

## 8. Pontos pendentes (confirmar com a Anvisa antes de implementar)

- mecanismo real de autenticação de acesso ao SNCR;
- endpoint e contrato exatos da requisição de numeração;
- formato da numeração nacional e sua validade;
- se há um passo explícito de "registrar receita emitida" além da numeração;
- comportamento de reserva/cancelamento da numeração se a emissão falhar;
- se há consulta/callback do status de dispensação (uso único);
- lista completa e critério de classificação dos tipos alcançados
  (A/B/B2/C1/C5/antimicrobianos/GLP-1/retinoides/talidomida);
- dados estruturados mínimos exigidos por medicamento na receita nata digital;
- integração entre o vínculo profissional no SNCR e o `DoctorProfile` atual;
- limites de tamanho, timeout e rate limits da API do SNCR.

## 9. Cronograma

- Prazo regulatório: **30/09/2026** (RDC 1.028/2026).
- Documentação de integração já disponível (junho/2026).
- Janela para adaptação: começar imediatamente; recomendado priorizar (passos 1-3
  do bloco 6 desbloqueiam o resto).

## 10. Referências de código

- `app/models/prescription.rb` — model de receita (genérico hoje).
- `app/models/document.rb` — entidade assinável/entregável; `KINDS`.
- `app/services/documents/lifecycle_service.rb` — criação + `generate_code`.
- `app/services/documents/signing_service.rb` — orquestração da assinatura.
- `app/services/documents/pdf_renderer.rb` — geração do PDF.
- `app/services/signatures/eval_crypto_cubo_provider.rb` — assinatura qualificada.
- `app/services/signatures/icp_brasil_provider.rb` — padrão `Net::HTTP` de referência.
- `config/initializers/app_config.rb` — config por ambiente (`config.x.*`).
- `db/schema.rb` — tabelas `prescriptions`, `documents`, `document_versions`.
- `docs/EVAL_CRYPTO_CUBO_SIGNATURE.md` — contrato da assinatura (complementar).
- `docs/SISTEMA_TECNICO_DETALHADO.md` — visão geral do sistema.
