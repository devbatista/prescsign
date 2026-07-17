# Integracao SNCR (Anvisa) para receitas de controlados

Este documento registra o **planejamento** da integracao do PrescSign com o
Sistema Nacional de Controle de Receituarios (SNCR) da Anvisa, exigida pela
RDC 1.000/2025 para prescricoes eletronicas de medicamentos controlados e
sujeitos a controle especial.

E um documento vivo de planejamento. Enquanto a documentacao oficial da API do
SNCR nao estiver confirmada no codigo, todos os pontos de contrato com a Anvisa
estao marcados como **pendentes**. Confirmar com o manual/API oficial da Anvisa
antes de implementar.

> Este doc trata do **SNCR** (numeracao nacional + validade regulatoria da
> receita). E complementar, e nao substitui, o
> [EVAL_CRYPTO_CUBO_SIGNATURE.md](EVAL_CRYPTO_CUBO_SIGNATURE.md), que cobre a
> **assinatura qualificada** do PDF. No fluxo de controlados os dois se
> combinam: o SNCR fornece a numeracao e o CryptoCubo assina no passo final.

## 1. Contexto regulatorio

- **RDC 1.000/2025** (publicada 15/12/2025, em vigor desde 15/02/2026) redefine
  as regras da prescricao eletronica de controlados:
  - a receita eletronica de controlado deve ser **nata digital** (produzida
    direto no sistema, nao digitalizacao de papel);
  - so pode ser emitida por **servico de prescricao integrado ao SNCR via API**;
  - cada receita recebe **numeracao nacional unica** gerada pelo sistema,
    vinculada ao profissional;
  - a farmacia faz o **registro de utilizacao** no SNCR na dispensacao,
    garantindo uso unico.
- **RDC 1.028/2026** prorrogou o prazo de adequacao de 01/06/2026 para
  **30/09/2026** e flexibilizou a exigencia de assinatura qualificada nas etapas
  de **autenticacao de acesso** e **requisicao de numeracao**. A assinatura
  qualificada continua **obrigatoria no momento da emissao efetiva** do
  receituario.
- Documentacao de integracao disponibilizada pela Anvisa em junho/2026
  (manuais + webinares) para as desenvolvedoras adaptarem os sistemas.

### Consequencia pratica

Sem integracao ao SNCR, a receita eletronica de controlado emitida pelo
PrescSign **nao e valida** — independentemente da qualidade da assinatura
ICP-Brasil. O PrescSign precisa se tornar um "servico de prescricao integrado ao
SNCR".

## 2. Escopo: quais receitas sao alcancadas

A RDC 1.000 alcanca (nao e so tarja preta):

- Notificacao de Receita **A, B e B2**;
- NR Especial para **retinoides**;
- NR de **Talidomida**;
- Receitas de **Controle Especial (C1/C5)**;
- receitas sujeitas a **retencao**, incluindo **antimicrobianos** e analogos de
  **GLP-1**.

Antibiotico comum entra no escopo. Isso alcanca quase todo clinico geral, ou
seja: **nao e um caso de nicho** — mexe no fluxo principal de receitas.

## 3. Lacuna atual do PrescSign (estado do codigo)

O modelo de dominio atual **nao tem nenhuma nocao de receita controlada**. Isso
precisa ser criado antes de qualquer chamada ao SNCR.

| Necessidade regulatoria | Estado atual no codigo | Gap |
| --- | --- | --- |
| Distinguir tipo de receita (controle especial, NR-A/B, antimicrobiano, etc.) | `Prescription` e generica: so `content` (texto livre) + `valid_until`. Nao existe coluna/enum de tipo. Unica tipificacao e `Document::KINDS = %w[prescription medical_certificate]` (`app/models/document.rb:2`). | Criar tipo/categoria de receita e classificacao de controlado. |
| Prescricao **nata digital** com itens estruturados (medicamento, quantidade, posologia) | `content` e texto livre; **nao ha** model `Medication`/`PrescriptionItem`. Ver `app/models/prescription.rb`. | Estruturar itens da receita (a Anvisa exige dados por medicamento). |
| **Numeracao nacional unica** vinculada ao profissional | `code` e aleatorio local: `SecureRandom.alphanumeric(10).upcase` em loop ate nao colidir (`app/services/documents/lifecycle_service.rb:159-164`). Nao ha numeracao nacional nem vinculo formal profissional. | Persistir a numeracao vinda do SNCR; nao gerar localmente para controlados. |
| Registro de utilizacao / uso unico na dispensacao | Nao existe. | Fora do escopo direto do emissor (a farmacia registra), mas pode exigir endpoint/estado. |
| Assinatura qualificada obrigatoria na emissao | Ja existe via `Signatures::EvalCryptoCuboProvider` (`app/services/signatures/eval_crypto_cubo_provider.rb`) e `Documents::SigningService#sign!` (`app/services/documents/signing_service.rb:22`). | Reaproveitar no passo final; garantir que controlado exige `type=qualified`. |

## 4. Fluxo alvo da receita controlada

Ordem exigida pela RDC (com a flexibilizacao da RDC 1.028):

```
1. Autenticar acesso ao SNCR        -> API Anvisa, SEM qualificada (flexibilizado)
2. Requisitar numeracao ao SNCR     -> API Anvisa, SEM qualificada (flexibilizado)
3. Gerar o receituario nato digital -> com a numeracao nacional embutida
4. Assinar no CryptoCubo            -> QUALIFICADA, obrigatoria aqui
5. Entregar ao paciente             -> + registrar no prontuario
6. Farmacia registra o uso          -> baixa no SNCR (uso unico) [ator externo]
```

Encaixe no fluxo interno atual:

| Passo | Onde encaixa hoje |
| --- | --- |
| 1-2. Auth + numeracao SNCR | **Novo.** Antes/durante `Documents::LifecycleService#create_with_initial_version!` (`app/services/documents/lifecycle_service.rb:13`). Para controlados, o `code` deve vir do SNCR em vez de `generate_code`. |
| 3. Receituario nato digital | `Documents::PdfRenderer` + template `documents/pdf/prescription` (`app/services/documents/pdf_renderer.rb:38-47`). Precisa exibir numeracao SNCR + dados estruturados. |
| 4. Assinatura qualificada | Sem mudanca estrutural: `Documents::SigningService#sign!` -> `EvalCryptoCuboProvider#sign_pdf!` (`type=qualified`). |
| 5. Entrega | Fluxo de entrega atual (`DocumentChannelDeliveryJob`, `Deliveries::ChannelDispatcher`). |
| 6. Dispensacao | Ator externo (farmacia). Avaliar se ha callback/consulta de status. |

Ponto de atencao de ordem: **a numeracao (passo 2) precisa existir antes de
gerar/assinar (passos 3-4)**. Hoje o `code` e gerado na criacao do documento; no
fluxo de controlado ele deve ser reservado no SNCR primeiro, e a assinatura so
ocorre depois. Se a assinatura falhar, definir o que acontece com a numeracao
reservada (cancelar? reutilizar?).

## 5. Contrato com a API do SNCR (pendente de confirmacao)

> Todos os campos, rotas, metodo de autenticacao e formatos abaixo sao
> **placeholders** ate a confirmacao com a documentacao oficial da Anvisa. Nao
> implementar como verdade sem checar o manual/API real.

### 5.1 Autenticacao de acesso (passo 1)

- Mecanismo real: **pendente** (certificado da instituicao? credencial de
  servico? token OAuth? mTLS?).
- Flexibilizado pela RDC 1.028: **nao exige** assinatura qualificada nesta etapa.
- Provavelmente vincula o servico de prescricao (PrescSign/organizacao) e o
  profissional prescritor.

### 5.2 Requisicao de numeracao (passo 2)

- Endpoint: **pendente**.
- Entrada provavel: identificacao do profissional (CRM/CPF), tipo de receita,
  organizacao/unidade.
- Saida provavel: **numeracao nacional unica** + validade + metadados.
- Flexibilizado: **nao exige** assinatura qualificada nesta etapa.
- Idempotencia/reserva: definir comportamento se a emissao nao se concretizar.

### 5.3 Emissao / vinculo do receituario (passos 3-4)

- Confirmar se ha um passo explicito de "registrar receita emitida" no SNCR, ou
  se a numeracao ja e suficiente ate a dispensacao.
- Assinatura qualificada **obrigatoria** aqui — reaproveitar o contrato do
  [EVAL_CRYPTO_CUBO_SIGNATURE.md](EVAL_CRYPTO_CUBO_SIGNATURE.md).

## 6. Impacto no modelo de dominio (mudancas de codigo previstas)

Ordem sugerida de trabalho (cada item e um passo verificavel):

1. **Classificacao de receita controlada**
   - Nova coluna em `prescriptions` (ex.: `controlled_class` / `prescription_type`)
     e/ou tabela de referencia de listas (A/B/B2/C1/C5/antimicrobiano/GLP-1).
   - Model: `app/models/prescription.rb`. Schema: `db/schema.rb` (tabela
     `prescriptions`, ~`367-392`).
2. **Itens estruturados da receita (nato digital)**
   - Avaliar model `PrescriptionItem` (medicamento, concentracao, quantidade,
     posologia) — hoje inexistente.
3. **Numeracao SNCR**
   - Persistir a numeracao nacional (nova coluna/tabela vinculada a
     `Prescription`/`Document`).
   - Para controlados, **nao** usar `generate_code`
     (`app/services/documents/lifecycle_service.rb:159-164`); usar a numeracao do
     SNCR.
4. **Cliente SNCR**
   - Novo service `app/services/sncr/client.rb` (ou modulo `Sncr::`), no mesmo
     padrao `Net::HTTP` puro dos providers de assinatura
     (`app/services/signatures/icp_brasil_provider.rb:34-55`,
     `app/services/signatures/eval_crypto_cubo_provider.rb:115-132`) — o projeto
     nao usa Faraday/HTTParty.
   - Metodos previstos: `authenticate!`, `request_numbering!`, e (se aplicavel)
     `register_issuance!`.
   - Erros: classe propria `Sncr::Error` (analoga a
     `Signatures::SignatureError`).
5. **Orquestracao do fluxo controlado**
   - Estender `Documents::LifecycleService`/`SigningService` (ou novo service
     `Documents::ControlledPrescriptionService`) para: reservar numeracao ->
     gerar PDF nato digital -> assinar qualificada -> registrar.
   - `sign!` hoje exige `document.status == "issued"` e
     `documentable.status == "draft"` (`app/services/documents/signing_service.rb:94-96`);
     validar que, para controlado, a numeracao SNCR ja esta presente antes de
     assinar.
6. **Config / ambiente**
   - Novas chaves em `config/initializers/app_config.rb` (`config.x.sncr`),
     seguindo o padrao de `eval_crypto_cubo_provider_options`
     (`config/initializers/app_config.rb:131-146`) e a validacao obrigatoria em
     producao (`validate_integrations!`, ~`app_config.rb:169-222`).
   - Novas variaveis no `.env.example` (secao de integracao).
7. **PDF / template**
   - `documents/pdf/prescription` deve exibir numeracao SNCR, classe do
     controlado e dados estruturados (`app/services/documents/pdf_renderer.rb`).
8. **Auditoria**
   - Registrar eventos de numeracao/emissao SNCR via `AuditLog.record!`
     (padrao ja usado em `LifecycleService`/`SigningService`).
9. **Testes**
   - `spec/services/sncr/client_spec.rb`, cobertura do fluxo controlado e
     ajustes nos specs de assinatura existentes.

## 7. Variaveis de ambiente sugeridas (placeholders)

```bash
# Integracao SNCR (Anvisa) - controlados
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

Regras de seguranca (mesmas do padrao atual):

- nunca logar segredos do SNCR, tokens, certificados ou conteudo do PDF;
- incluir chaves sensiveis no `filter_parameter_logging`
  (`config/initializers/filter_parameter_logging.rb`);
- em producao, exigir as variaveis obrigatorias quando `SNCR_ENABLED=true`
  (via `require_in_production!` em `app_config.rb`).

## 8. Pontos pendentes (confirmar com a Anvisa antes de implementar)

- mecanismo real de autenticacao de acesso ao SNCR;
- endpoint e contrato exatos da requisicao de numeracao;
- formato da numeracao nacional e sua validade;
- se ha um passo explicito de "registrar receita emitida" alem da numeracao;
- comportamento de reserva/cancelamento da numeracao se a emissao falhar;
- se ha consulta/callback do status de dispensacao (uso unico);
- lista completa e criterio de classificacao dos tipos alcancados
  (A/B/B2/C1/C5/antimicrobianos/GLP-1/retinoides/talidomida);
- dados estruturados minimos exigidos por medicamento na receita nata digital;
- integracao entre o vinculo profissional no SNCR e o `DoctorProfile` atual;
- limites de tamanho, timeout e rate limits da API do SNCR.

## 9. Cronograma

- Prazo regulatorio: **30/09/2026** (RDC 1.028/2026).
- Documentacao de integracao ja disponivel (junho/2026).
- Janela para adaptacao: comecar imediatamente; recomendado priorizar (passos 1-3
  do bloco 6 desbloqueiam o resto).

## 10. Referencias de codigo

- `app/models/prescription.rb` — model de receita (generico hoje).
- `app/models/document.rb` — entidade assinavel/entregavel; `KINDS`.
- `app/services/documents/lifecycle_service.rb` — criacao + `generate_code`.
- `app/services/documents/signing_service.rb` — orquestracao da assinatura.
- `app/services/documents/pdf_renderer.rb` — geracao do PDF.
- `app/services/signatures/eval_crypto_cubo_provider.rb` — assinatura qualificada.
- `app/services/signatures/icp_brasil_provider.rb` — padrao `Net::HTTP` de referencia.
- `config/initializers/app_config.rb` — config por ambiente (`config.x.*`).
- `db/schema.rb` — tabelas `prescriptions`, `documents`, `document_versions`.
- `docs/EVAL_CRYPTO_CUBO_SIGNATURE.md` — contrato da assinatura (complementar).
- `docs/SISTEMA_TECNICO_DETALHADO.md` — visao geral do sistema.
