# Origem e atualização dos dados de substâncias (classificação SNCR)

Este documento descreve **de onde vem** e **como se mantém** a base de substâncias
controladas (`Substance`) que decide o tipo de receituário SNCR, e o que ainda
falta para o catálogo de medicamentos (`Medication`).

> **Estado (26/08/2026):** a **Fase 1 está carregada** — 612 substâncias no
> `db/data/substances.csv`, aplicadas pelo seed `db/seeds/14_substances.rb`.
> A extração é automática e foi conferida contra a numeração oficial, mas a
> **revisão humana da curadoria ainda não foi feita** (ver §7). A **Fase 2**
> (catálogo de produtos) **está carregada** — 25.701 apresentações da lista da
> CMED, 7.523 delas com substância controlada (§8); o que o casamento não
> alcançou virou fila de revisão, não vínculo.

## 1. Decisão e princípio

- **Build com IA + revisão humana** (decisão de 2026-07-31). Não há base oficial
  estruturada; comprar (Brasíndice/Simpro/global) fica como alternativa futura
  (ver `SNCR_INTEGRATION.md` §2.2).
- **A classificação vive na substância, não no produto.** A tabela crítica
  (`substances`) é **pequena** (centenas de linhas) e muda **raramente** (só quando
  sai RDC). O catálogo de produtos (`medications`, dezenas de milhares) é grande e
  volátil, mas **não** carrega classificação — só aponta para substâncias. Isso
  minimiza a superfície de curadoria.

## 2. As fontes (confirmadas)

A base sai de **duas frentes**, não de um documento só:

| Frente | Cobre | Vira `sncr_type` |
| --- | --- | --- |
| **Anexo I da Portaria SVS/MS 344/98** (texto consolidado) | entorpecentes, psicotrópicos, controle especial, retinoides, imunossupressoras, anabolizantes | `NRA`, `NRB`, `NRB2`, `NRR`, `NRT`, `RCE` |
| **IN nº 360/2025** (define a lista da RDC 471/2021) | antimicrobianos (art. 1º) e agonistas de GLP-1 (art. 2º) | `RET` |

### 2.1 Anexo I da 344/98 — pegar o texto CONSOLIDADO

O ponto que mais confunde: cada RDC de atualização publica, no seu próprio
Anexo I, **a íntegra consolidada das listas** ("ATUALIZAÇÃO N. xx"), não só o
diff. Então basta pegar a **RDC mais recente** — nunca é preciso aplicar emendas
uma a uma.

- **Hub das listas** (mostra qual RDC está marcada "Versão vigente"):
  https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/lista-substancias
- **Vigente em 25/08/2026: RDC nº 1.036/2026** (09/07/2026) — Atualização nº 101.

O portal `anvisalegis.datalegis.net` é uma SPA: a URL `ActionDatalegis.php` só
devolve o menu do portal. O texto do ato vem do endpoint público:

```
https://anvisalegis.datalegis.net/action/UrlPublicasAction.php\
?acao=abrirAtoPublico&num_ato=00001036&sgl_tipo=RDC\
&sgl_orgao=RDC/DC/ANVISA/MS&vlr_ano=2026&seq_ato=000&cod_modulo=134&cod_menu=1696
```

Trocar `num_ato` (8 dígitos, zero-padded), `vlr_ano` e `sgl_tipo` (`RDC` ou `INM`
para Instrução Normativa; a IN usa `sgl_orgao=DC/ANVISA/MS`). Algumas RDCs também
saem em PDF no gov.br, mas aí é preciso o sufixo `/@@display-file/file` — a URL
`.pdf` "pura" devolve a página HTML do Plone, não o arquivo.

### 2.2 IN 360/2025 — antimicrobianos e GLP-1

A RDC 471/2021 **não tem mais a lista no próprio anexo**: a RDC 973/2025 alterou-a
e moveu a lista para Instrução Normativa, ao mesmo tempo em que ampliou o escopo
de "antimicrobianos" para "substâncias de uso sob prescrição e retenção da
receita". A **IN nº 360/2025** é hoje a lista única das duas frentes:

- art. 1º — 131 antimicrobianos (validade da receita: 10 dias);
- art. 2º — 5 agonistas de GLP-1 (validade da receita: 90 dias):
  semaglutida, liraglutida, dulaglutida, tirzepatida, lixisenatida.

> Isso resolve o "confirmar o nº da RDC de GLP-1" que estava em aberto. Note que
> **exenatida não está na lista oficial**, embora apareça em várias matérias de
> imprensa sobre a norma.

## 3. Mapa lista → `sncr_type` (definitivo)

O tipo **não é convenção nossa**: cada lista do Anexo I traz no subtítulo o
receituário que exige. É esse subtítulo que a carga usa.

| Lista | Subtítulo oficial | `sncr_type` |
| --- | --- | --- |
| A1, A2, A3 | "Sujeitas à Notificação de Receita 'A'" | `NRA` |
| B1 | "Sujeitas à Notificação de Receita 'B'" | `NRB` |
| B2 | "Sujeitas à Notificação de Receita 'B2'" | `NRB2` |
| C1 | "Sujeitas à Receita de Controle Especial em duas vias" | `RCE` |
| C2 (retinoicas) | "Sujeitas à Notificação de Receita Especial" | `NRR` |
| C3 (imunossupressoras) | "Sujeitas à Notificação de Receita Especial" | `NRT` |
| C5 (anabolizantes) | "Sujeitas à Receita de Controle Especial em duas vias" | `RCE` |
| D1 | "Sujeitas à Receita Médica sem Retenção" | *(fora da base)* |
| D2 | controle do Ministério da Justiça | *(fora da base)* |
| E, F1–F4 | plantas proscritas / uso proscrito | *(fora da base)* |
| IN 360/2025 art. 1º e 2º | retenção de receita | `RET` |

Duas correções em relação ao que este documento supunha antes:

- **B2 é anorexígenos, não retinoides.** A Lista B2 é "SUBSTÂNCIAS PSICOTRÓPICAS
  ANOREXÍGENAS" (sibutramina, femproporex, mazindol…). Não há ambiguidade
  "B1/B2 → NRB ou NRB2": B1 é sempre `NRB` e B2 é sempre `NRB2`.
- **C2 é `NRR`, nunca `NRB2`.** Retinoides sistêmicos exigem Notificação de
  Receita Especial.
- **A lista C4 não existe** no Anexo I vigente.

**D1/D2/E/F ficam fora da base** (e não entram nem com tipo nulo): são
precursores, insumos químicos, plantas proscritas e substâncias de uso proscrito
— nenhuma aparece numa prescrição. Carregá-las adicionaria ~1.100 linhas de
ruído e aumentaria o risco de falso casamento na Fase 2.

## 4. O que está carregado

`db/data/substances.csv` — 612 linhas, uma por substância:

```csv
name,list_344,sncr_type
morfina,A1,NRA
clonazepam,B1,NRB
sibutramina,B2,NRB2
isotretinoína,C2,NRR
ftalimidoglutarimida (talidomida),C3,NRT
testosterona,C5,RCE
amoxicilina,IN 360/2025 art. 1º (antimicrobiano),RET
semaglutida,IN 360/2025 art. 2º (GLP-1),RET
```

- `name` — nome como publicado no ato, em minúsculas. Único (case-insensitive),
  é a chave de upsert e de casamento com o produto (§8).
- `list_344` — lista/artigo de origem. Referência e auditoria; não decide nada.
- `sncr_type` — o campo acionável.

Distribuição: `NRA` 121 · `NRB` 95 · `NRB2` 8 · `NRR` 5 · `NRT` 3 · `RCE` 244 ·
`RET` 136. Não há colisão de nome entre as duas frentes.

## 5. Carga e atualização

**Carga**

```bash
bin/rails substances:load     # standalone, idempotente (staging/prod)
bin/rails db:seed             # dev; roda seed_substances! junto do resto
```

Ambos passam por `seed_substances!` (`db/seeds/14_substances.rb`), que faz
**upsert por nome case-insensitive**. Rodar de novo não duplica nem reverte
edições feitas no back-office.

Substâncias que existem no banco mas **não** constam do CSV são **listadas para
revisão humana, não desativadas**. Desativar sozinho apagaria cadastro manual do
back-office; deixar uma substância controlada a mais erra para o lado seguro.

**Quando sai RDC nova**

1. Conferir no hub (§2.1) qual RDC está marcada "Versão vigente".
2. Baixar o texto pelo endpoint `UrlPublicasAction.php` e regerar o CSV.
3. Revisar o diff do CSV (é aí que a revisão humana entra) e commitar.
4. Rodar `bin/rails substances:load`.

Registrar em cada carga a **RDC/IN de referência** e a data — hoje isso vive no
cabeçalho de `db/seeds/14_substances.rb`.

## 6. Como o CSV foi gerado

Extração programática do texto oficial, e **não** transcrição manual nem
"de memória" do modelo:

1. Baixar o ato pelo endpoint público (§2.1).
2. Limpar o HTML e recortar do marcador "ATUALIZAÇÃO N. xx" em diante.
3. Quebrar em blocos por cabeçalho `LISTA - Xn`, coletar os itens numerados até
   o marcador `ADENDO:`, e aplicar o mapa do §3.
4. Idem para a IN 360 (art. 1º e art. 2º).
5. Normalizar (minúsculas), deduplicar mantendo o tipo mais restritivo, ordenar.

**Conferência feita:** o número do último item capturado em cada lista bate com
a numeração do ato (A1 94, A2 13, A3 14, B1 95, B2 8, C1 213, C2 5, C3 3, C5 31).
Sem essa checagem, uma quebra de numeração trunca a lista silenciosamente — foi
exatamente o que aconteceu na IN 360, cujo texto publicado **pula o item 42** e
alterna "42 -" com "46.". A carga aceita as duas formas e reporta as lacunas.

## 7. Pendente: a revisão humana da curadoria

A extração está conferida contra o ato, mas a metade "revisão humana" do
"build com IA + revisão" **ainda não foi feita**. O que precisa de olho:

- **18 nomes compostos ou com sinônimo** que a Fase 2 não vai casar direto:
  `ftalimidoglutarimida (talidomida)`, `canabidiol (cbd)`,
  `metilfenobarbital (prominal)`, `fluoximesterona ou fluoximetiltestosterona`,
  `metandienona ou metandrostenolona`, `prasterona (deidroepiandrosterona - dhea)`,
  `somatropina (hormônio do crescimento humano)`, `periciazina (propericiazina)`,
  `oxibuprocaína (benoxinato)`, `norcanfano (fencanfamina)`,
  `etilanfetamina (n-etilanfetamina)`, `ghb - (ácido gama - hidroxibutírico)`,
  `dimefeptanol (metadol)`, os 5 `intermediário …`.
  Decidir se viram sinônimo, se o nome canônico muda, ou se ficam como estão.
- **Adendos que mudam o tipo por apresentação**, não por substância. O modelo
  hoje classifica só por substância, então esses casos ficam **mais restritivos
  do que a norma**:
  - C2 adendo 2: retinoide **tópico** é venda sem retenção (base marca `NRR`).
  - A1 adendos 2/3/5/8 e A2 adendos 2–6: preparações abaixo de certa dose caem
    para Receita de Controle Especial (base marca `NRA`).
  - B1 adendo 16: carisoprodol é venda sem retenção (base marca `NRB`).
  - IN 360 art. 1º §1º: não se aplica a antimicrobiano de uso hospitalar exclusivo.
- **Sais, éteres, ésteres e isômeros** ficam sob controle por adendo em todas as
  listas, mas não estão nominalmente no CSV. O casamento da Fase 2 precisa tratar
  isso (ex.: "cloridrato de tramadol" → `tramadol`).

## 8. Fase 2 — catálogo de medicamentos (produtos)

**Carregada em 26/08/2026** a partir da **Lista de Preços de Medicamentos da
CMED/Anvisa** (`https://dados.anvisa.gov.br/dados/TA_PRECO_MEDICAMENTO_GOV.csv`,
publicação de 21/07/2026): **25.701 apresentações**, 13.088 em comercialização.

Por que a lista da CMED e não os "dados abertos de medicamentos registrados"
(`DADOS_ABERTOS_MEDICAMENTOS.csv`, que este documento indicava antes): aquele
arquivo tem mais registros (43.443, sendo 17.039 ativos), mas só nome do produto,
princípio ativo, empresa e classe terapêutica — **sem EAN, sem apresentação e sem
tarja**. A CMED publica **por apresentação** e traz os três, que é o que o médico
precisa para escolher a caixa que está prescrevendo.

### 8.1 Carga

```bash
bin/rails medications:import                    # baixa a lista da Anvisa e importa
bin/rails medications:import FILE=/tmp/cmed.csv # usa um CSV local (offline/staging)
bin/rails medications:import URL=...            # troca a fonte
```

O CSV **não** é versionado no repo (17 MB, republicado todo mês): a task baixa
para `tmp/`. A carga (`Medications::CmedCatalogImport`) é **idempotente** — a
chave é o **registro Anvisa**, com o **EAN** como chave alternativa, que casa
cadastro feito à mão no back-office em vez de duplicar.

Dois detalhes operacionais:

- `dados.anvisa.gov.br` serve só o certificado folha, sem a intermediária. O
  OpenSSL do Ruby não busca a cadeia faltante e recusa a conexão, então o
  download cai automaticamente para o `curl` (que busca). Sem os dois, baixar à
  mão e usar `FILE=`.
- `bin/rails db:seed` **trunca todas as tabelas** (`reset_seed_data!`), catálogo
  incluído. Em dev, rodar `medications:import` depois do seed.

| Coluna da CMED | Campo | Observação |
| --- | --- | --- |
| PRODUTO | `name` | como publicado (caixa alta) |
| SUBSTÂNCIA | `active_ingredient` | associação vem num campo só, separada por `;` |
| APRESENTAÇÃO | `presentation` | íntegra |
| (prefixo da apresentação) | `strength` | "500 MG", "10 MG/G + 0,443 MG/G"; nulo sem dose reconhecível (2.532) |
| (abreviação da apresentação) | `pharmaceutical_form` | COM, CAP, SOL INJ, XPE…; nulo quando não reconhece (433) |
| TARJA | `control_class` | Vermelha → `tarja_vermelha`; "sob restrição" → `tarja_vermelha_retencao`; Preta → `tarja_preta`; "Sem Tarja" → `comum`; **"- (*)" → nulo** (a fonte não informa; dizer "comum" seria afirmar o que ela não afirma) |
| REGISTRO, EAN 1, LABORATÓRIO | `anvisa_registration`, `ean`, `manufacturer` | EAN repetido em dois registros fica com o produto em comercialização (índice único) |
| COMERCIALIZAÇÃO | `active` | **só na criação** |

O que a carga **não** faz, de propósito: não reverte `active` de quem já existe
(desativação no back-office manda), não mexe em `default_posology` e não apaga
vínculo produto↔substância criado à mão.

### 8.2 Casamento produto → substância

`Medications::SubstanceMatcher` casa **exato sobre formas normalizadas**, nunca
por semelhança. Desfaz só variação de forma do mesmo princípio ativo:

- sal/éster no prefixo — "cloridrato de tramadol", "dimesilato de lisdexanfetamina";
- contraíon — "valproato de sódio" → `valproato sódico`;
- grau de hidratação — "amoxicilina tri-hidratada", "ceftriaxona dissódica hemieptaidratada";
- sufixo de sal/éster — "bacitracina zíncica", "sulbactam pivoxila";
- gênero da DCB — "ciprofloxacino" (CMED) × `ciprofloxacina` (IN 360);
- os sinônimos que o próprio nome da substância guarda entre parênteses ou com
  "ou" (§7) — "talidomida" casa `ftalimidoglutarimida (talidomida)`.

Resultado: **7.523 apresentações** com substância controlada (7.801 vínculos) —
RCE 4.390 · RET 1.858 · NRB 618 · NRA 506 · NRR 71 · NRT 69 · NRB2 25. O tipo da
receita continua saindo de `Medication#effective_sncr_type`.

### 8.3 Fila de revisão

Princípio ativo que não casa **não vira vínculo** — errar o casamento classifica
receita controlada errado. Cada carga escreve `tmp/medications_import_review.csv`
com os dois grupos que merecem olho humano: (a) princípio ativo **parecido** com
substância da base e (b) produto com **tarja preta/retenção sem nenhum vínculo**.
São 86 entradas hoje; as que pedem decisão de curadoria:

- `benzilpenicilina benzatina` e `fenoximetilpenicilina potássica` — a base traz
  `penicilina g` e `penicilina v` (nomes da IN 360). São sinônimos: decidir se o
  CSV ganha o sinônimo entre parênteses, como nos casos do §7.
- `benzoilmetronidazol`, `metronidazol benzoil`, `rifamicina sv sódica`,
  `delamanide` — variações de nome de substância controlada que o casamento
  exato não alcança.
- `sulfadiazina de prata` — tópico; a base controla `sulfadiazina` (sistêmica).
  Provavelmente **não** deve casar, mas é decisão de curadoria.

O resto do grupo (b) é ruído da tarja da CMED em eletrólitos, glicose,
enoxaparina, montelucaste, fluconazol: não constam da 344/98 nem da IN 360.

### 8.4 Refresh

Rodar `bin/rails medications:import` de novo quando a CMED republicar (mensal) ou
depois de mexer em `db/data/substances.csv` — a reexecução só grava o que mudou e
cria os vínculos novos.

## 9. Riscos e pontos a confirmar

- **Revisão humana da curadoria** (§7) — o maior item aberto.
- **Granularidade por apresentação**: o modelo classifica por substância; os
  adendos de dose/via ficam de fora e produzem excesso de restrição (§7).
- **Acurácia do matching** produto→substância (§8.2). A fila de revisão (§8.3)
  mitiga, mas ela **erra para menos**: produto sem casamento entra como comum, e
  os 86 casos abertos ainda não passaram por revisão.
- **Cobertura da CMED**: a lista de preços não traz produto sem preço regulado
  (manipulado, alguns hospitalares). Produto fora dela precisa de cadastro manual
  no back-office.
- **Manutenção perpétua**: cada RDC nova exige revisão — é o custo do "build"
  (ver `SNCR_INTEGRATION.md` §2.2).
- **Peso regulatório de `SNCR_TYPE_PRECEDENCE`** ainda não confirmado
  (`SNCR_INTEGRATION.md` §2.3).

## 10. Referências

- `db/data/substances.csv`, `db/seeds/14_substances.rb`, `lib/tasks/substances.rake`.
- `app/services/medications/cmed_catalog_import.rb`,
  `app/services/medications/substance_matcher.rb`, `lib/tasks/medications.rake`.
- `app/models/substance.rb`, `app/models/medication.rb`,
  `app/models/medication_substance.rb`.
- `SNCR_INTEGRATION.md` §2.1–2.3 (modelo implementado), §9 (pendências).
- Portaria SVS/MS 344/1998, RDC nº 1.036/2026 (Atualização nº 101),
  RDC nº 471/2021, RDC nº 973/2025 e IN nº 360/2025.
