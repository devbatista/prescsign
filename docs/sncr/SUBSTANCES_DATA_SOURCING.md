# Origem e atualização dos dados de substâncias (classificação SNCR)

Este documento é o **plano** de como popular e manter a base de substâncias
controladas (`Substance`) e, depois, o catálogo de medicamentos (`Medication`).
É a "origem dos dados" deixada em aberto no
[SNCR_INTEGRATION.md](SNCR_INTEGRATION.md) (seções 2.1–2.3 e Pontos pendentes).

> Nada aqui está implementado — é planejamento. A **estrutura** de classificação
> por substância já existe (`Substance`, N:N `medication_substances`,
> `Medication#effective_sncr_type`, derivação na `Prescription`); falta a
> **curadoria e a carga** dos dados.

## 1. Decisão e princípio

- **Build com IA + revisão humana** (decisão de 2026-07-31). Não há base oficial
  estruturada; comprar (Brasíndice/Simpro/global) fica como alternativa futura
  (ver `SNCR_INTEGRATION.md` §2.2).
- **A classificação vive na substância, não no produto.** A tabela crítica
  (`substances`) é **pequena** (centenas de linhas) e muda **raramente** (só quando
  sai RDC). O catálogo de produtos (`medications`, dezenas de milhares) é grande e
  volátil, mas **não** carrega classificação — só aponta para substâncias. Isso
  minimiza a superfície de curadoria.

## 2. A realidade da fonte

Não existe arquivo estruturado oficial (sem CSV, sem planilha, sem API limpa). A
fonte de verdade é **texto legal** — o Anexo I da Portaria SVS/MS 344/1998, que a
Anvisa mantém atualizado por RDCs, em **PDF/HTML**.

A base **não sai de um documento só** — são três frentes, que alimentam tipos
SNCR diferentes:

| Frente | Cobre | Vira `sncr_type` | Onde pegar |
| --- | --- | --- | --- |
| **Anexo I da 344/98** (consolidado) | entorpecentes, psicotrópicos, retinoides, talidomida, controle especial, anabolizantes | `NRA`, `NRB`, `NRB2`, `NRR`, `NRT`, `RCE` | página de listas + RDCs de atualização |
| **RDC 471/2021** (antimicrobianos) | antibióticos sujeitos a retenção (consolidou a RDC 20/2011) | `RET` | texto da RDC 471/2021 |
| **RDC de GLP-1** (2024 — *a confirmar o nº*) | semaglutida e análogos sob retenção | `RET` | RDC específica |

### Links oficiais

- **Página de listas (hub):**
  https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/lista-substancias
- **RDC 999/2025 (24/11/2025)** — atualização mais recente do Anexo I (PDF):
  https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/RDC9992025.pdf
- **RDC 970/2025 (19/03/2025)** — atualização do Anexo I:
  https://anvisalegis.datalegis.net/action/ActionDatalegis.php?acao=abrirTextoAto&link=S&tipo=RDC&numeroAto=00000970&seqAto=000&valorAno=2025&orgao=RDC/DC/ANVISA/MS

> Preferir o **anexo consolidado** (texto vigente com todas as substâncias), não
> cada RDC de emenda isolada. As RDCs de emenda servem para o processo de
> **atualização** (§6), não para a carga inicial.

## 3. Pipeline de extração (build com IA + revisão)

1. **Baixar** o texto consolidado do Anexo I (as listas são tabeladas por lista:
   A1/A2/A3, B1/B2, C1–C5, D1/D2, E, F1–F4).
2. **Extrair com IA** para uma planilha bruta: `nome_substancia | lista_344`.
3. **Mapear `lista_344` → `sncr_type`** segundo a tabela do §4.
4. **Revisar à mão** os casos ambíguos (é aqui que a IA não decide sozinha) e
   marcar as listas que **não geram receituário** com `sncr_type` vazio.
5. Repetir para **antimicrobianos** (RDC 471/2021) e **GLP-1**, todos → `RET`.
6. Consolidar num **CSV de curadoria** (§5) e carregar (§6).

## 4. Mapa lista → `sncr_type` (ponto de partida — revisar)

| Lista (344/98) | `sncr_type` sugerido | Observação |
| --- | --- | --- |
| A1, A2, A3 | `NRA` | entorpecentes/psicotrópicos (tarja preta) |
| B1, B2 | `NRB` (alguns `NRB2`) | curar caso a caso |
| C1 | `RCE` | outras sob controle especial |
| C2 (retinoides) | `NRR` **ou** `NRB2` | tópico vs. sistêmico — **curar** |
| C3 (talidomida) | `NRT` | |
| C5 (anabolizantes) | `RCE` | |
| C4, D1, D2, E, F1–F4 | *(vazio)* | antirretrovirais/precursores/insumos/proscritas **não geram receituário controlado** → `sncr_type` nulo |
| Antimicrobianos (RDC 471/2021) | `RET` | fonte separada da 344/98 |
| GLP-1 e análogos (RDC 2024) | `RET` | fonte separada; confirmar nº da RDC |

> **Boa parte das listas não vira receituário SNCR.** `substances` só precisa de
> `sncr_type` preenchido nas listas que efetivamente disparam o fluxo controlado;
> as demais podem nem entrar na base (ou entrar com tipo nulo, para consulta).
>
> A ambiguidade de B1/B2 e C2 é justamente o motivo de guardarmos `sncr_type`
> **por substância** (resolvido na curadoria) em vez de derivar da lista em código
> (ver `SNCR_INTEGRATION.md` §2.3).

## 5. Formato do CSV de curadoria

Uma linha por substância. Colunas espelham `Substance`:

```csv
name,list_344,sncr_type
clonazepam,B1,NRB
isotretinoína,C2,NRR
talidomida,C3,NRT
testosterona,C5,RCE
morfina,A1,NRA
amoxicilina,RDC 471/2021,RET
semaglutida,RDC GLP-1,RET
efavirenz,C4,
```

- `name` — nome canônico da substância (DCB), minúsculo/normalizado. Único
  (case-insensitive) — é a chave de upsert e de casamento com o produto (§7).
- `list_344` — texto de referência/auditoria (a lista de origem). Não decide nada.
- `sncr_type` — vazio = não controlada / não gera receituário.

## 6. Carga e atualização

**Carga inicial**
- **Seed idempotente** versionada (ex.: `db/seeds/NN_substances.rb`) que faz
  **upsert por `name`** a partir do CSV curado — reproduz a base em
  dev/staging/prod.
- **Import CSV no back-office** (upload em `Admin::SubstancesController`) para
  correções pontuais sem depender de deploy.

**Atualização quando sai RDC nova**
- RDC de emenda ao Anexo I → identificar inclusões/exclusões/mudança de lista →
  atualizar o CSV curado → re-rodar seed/import (upsert). Processo **manual +
  revisão** (raro, alto valor regulatório).
- Registrar em cada carga a **RDC de referência** e a data (auditoria).

## 7. Fase 2 — catálogo de medicamentos (produtos)

Depois das substâncias:

- **Importar dados abertos da Anvisa (Datavisa)**:
  `https://dados.anvisa.gov.br/dados/DADOS_ABERTOS_MEDICAMENTOS.csv` — mapeia
  produto → princípio(s) ativo(s). Rake task / job que faz upsert por registro
  Anvisa/EAN.
- **Casamento produto → substância**: normalizar o princípio ativo (minúsculo,
  sem acento, quebrar associações em `+`) e casar com `substances.name`. Produto
  cujo ativo casa com substância controlada herda o tipo via
  `Medication#effective_sncr_type`.
- **Default seguro**: casamento **incerto não auto-classifica** — vai para uma
  **fila de revisão** no back-office. Errar para "comum" um controlado tem peso
  regulatório.
- **Refresh periódico**: re-importar o CSV (job) e re-rodar o matching.

## 8. Riscos e pontos a confirmar

- **Nº da RDC de GLP-1** e a **lista exata de antimicrobianos** (RDC 471/2021) —
  ainda a confirmar antes da curadoria de `RET`.
- **Acurácia do matching** produto→substância (fila de revisão mitiga).
- **Versão consolidada vs. emendas**: garantir que a carga inicial usa o Anexo I
  **vigente**, não uma RDC de emenda isolada.
- **Manutenção perpétua**: cada RDC nova exige revisão — é o custo do "build"
  (ver `SNCR_INTEGRATION.md` §2.2).

## 9. Referências

- `SNCR_INTEGRATION.md` §2.1–2.3 (modelo implementado), §9 (pendências).
- `app/models/substance.rb`, `app/models/medication.rb`,
  `app/models/medication_substance.rb`.
- Portaria SVS/MS 344/1998 e RDCs de atualização (links no §2).
