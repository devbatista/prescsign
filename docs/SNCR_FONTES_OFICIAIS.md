# SNCR — Fontes oficiais da Anvisa

Este documento reúne os links e materiais **oficiais** da Anvisa sobre o SNCR
(Sistema Nacional de Controle de Receituários) e a integração de serviços de
prescrição eletrônica. Serve de ponto de partida para resolver os "Pontos
pendentes" do [SNCR_INTEGRATION.md](SNCR_INTEGRATION.md).

> Conteúdo compilado a partir das páginas do portal gov.br/anvisa em
> **21/07/2026**. Os manuais técnicos (PDF) devem ser baixados e lidos
> diretamente na fonte — este arquivo não substitui a documentação oficial.

## Documentação técnica (o que o desenvolvedor precisa)

O material técnico de integração fica na página **"Documentos do SNCR"**:

- **Documentos do SNCR** (hub):
  https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/documentos-do-sncr

Documentos disponíveis nessa página:

| Documento | Tipo | Link | Última modificação |
| --- | --- | --- | --- |
| **Manual API SNCR - 1ed** | Arquivo | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/documentos-do-sncr/manual-api-sncr-1ed/view | 24/06/2026 |
| **Manual do SNCR** | Link | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/documentos-do-sncr/manual-do-sncr | 24/06/2026 |

O **Manual API SNCR** é a especificação técnica da API (autenticação,
comunicação com o SNCR, instruções de acesso ao ambiente de treinamento e
modelos de receituário eletrônico). É a fonte que confirma os endpoints reais e
o contrato — hoje ainda marcado como pendente no `SNCR_INTEGRATION.md`.

## Páginas oficiais do SNCR

| Recurso | URL |
| --- | --- |
| Página principal do SNCR | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr |
| Documentos do SNCR (manuais/API) | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/documentos-do-sncr |
| Perguntas e Respostas | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/perguntas-e-respostas |
| Receituário Eletrônico | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/receituario-eletronico/receituario-eletronico |
| Modelos de Receituários Eletrônicos | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/modelos-de-receituarios/modelos-de-receituarios-eletronicos |
| Receituário Físico | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/receituario-fisico/receituario-fisico |
| Notícias do SNCR | https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/noticias |
| Sistema SNCR (aplicação) | https://sncr.anvisa.gov.br |

## Notícias-chave (contexto e prazos)

- **Anvisa publica documentação técnica para integração ao SNCR** (30/06/2026):
  https://www.gov.br/anvisa/pt-br/assuntos/noticias-anvisa/anvisa-publica-documentacao-tecnica-para-integracao-de-sistemas-de-prescricao-eletronica-ao-sncr
- **SNCR: Anvisa inicia etapa de integração e amplia prazo** (03/06/2026):
  https://www.gov.br/anvisa/pt-br/assuntos/noticias-anvisa/2026/sncr-anvisa-inicia-etapa-de-integracao-com-sistemas-de-prescricao-eletronica-e-amplia-prazo-para-implementacao
- **SNCR: o que muda para farmácias e drogarias**:
  https://www.gov.br/anvisa/pt-br/assuntos/noticias-anvisa/2026/SNCR-o-que-muda-para-farmacias-e-drogarias-com-o-novo-sistema-de-controle-de-receitas

## Base regulatória

| Norma | Assunto | Referência |
| --- | --- | --- |
| **RDC 873/2024** | Institui o SNCR (em vigor desde 18/07/2024) | anvisalegis.datalegis.net |
| **RDC 1.000/2025** | Prescrição eletrônica de controlados integrada ao SNCR (publicada 11–15/12/2025, em vigor desde 15/02/2026) | https://anvisalegis.datalegis.net/action/ActionDatalegis.php?acao=abrirTextoAto&tipo=RDC&numeroAto=00001000&seqAto=000&valorAno=2025&orgao=RDC%2FDC%2FANVISA%2FMS |
| **RDC 1.028/2026** | Prorroga o prazo de adequação de 01/06/2026 para **30/09/2026** | anvisalegis.datalegis.net |

## Fatos técnicos já confirmados nas páginas oficiais

Pontos concretos extraídos das páginas (úteis para a implementação):

- **Numeração nacional** no formato `0000.0-00.0000000` (padrão exibido nos
  modelos de Notificação de Receita eletrônica).
- **QR Code obrigatório** na receita eletrônica aponta para:
  `https://sncr.anvisa.gov.br/receita/consultar?numero={numero}`
  (substituindo `{numero}` pela numeração no formato acima). Atenção: hoje o
  PrescSign gera QR para `/validate/{code}` interno — para controlados o QR deve
  seguir o padrão do SNCR.
- **Modelos não customizáveis**: "não é permitida a customização dos modelos de
  Notificações de Receita e de Receitas de Controle Especial em formato
  eletrônico" — devem ser usados integralmente conforme a Anvisa. Impacta o
  `Documents::PdfRenderer` / templates de PDF, que hoje são próprios do PrescSign.
- **Escopo dos modelos eletrônicos** disponibilizados: Notificações de Receita e
  Receitas de Controle Especial. (À época, ainda sem modelo específico para
  substâncias sujeitas a prescrição e retenção listadas em IN própria —
  confirmar evolução no Manual API.)
- **A API permite** requisitar a numeração e emitir Notificações de Receita,
  Receitas de Controle Especial e receitas sujeitas à retenção em meio
  eletrônico.
- **Ambiente de treinamento/homologação** para desenvolvedores é
  disponibilizado pela Anvisa; instruções de acesso estão no Manual API SNCR.
- **Estado atual**: os modelos eletrônicos "não podem ser utilizados até que a
  Anvisa disponibilize a integração", com disponibilização prevista até
  **30/09/2026**.

## Aviso: não confundir com o SNCR do INCRA

Existe outro "SNCR" — o **Sistema Nacional de Cadastro Rural** (INCRA) — que
também publica um "Manual de Integração SNCR-API" no portal gov.br/conecta.
**Não é o mesmo sistema.** Para receituários controlados, usar exclusivamente as
páginas em `gov.br/anvisa/.../medicamentos/controlados/sncr` e o domínio
`sncr.anvisa.gov.br`.

## Próximos passos sugeridos

1. Baixar e ler o **Manual API SNCR - 1ed** e o **Manual do SNCR**.
2. Preencher os "Pontos pendentes" do [SNCR_INTEGRATION.md](SNCR_INTEGRATION.md)
   com os dados reais (autenticação, endpoints, campos de numeração).
3. Solicitar acesso ao **ambiente de treinamento** e validar o fluxo
   requisitar numeração → emitir → assinar (CryptoCubo) em homologação.
4. Ajustar `Documents::PdfRenderer` para os **modelos padronizados** da Anvisa e
   o **QR Code** no padrão SNCR quando a receita for de controlado.
