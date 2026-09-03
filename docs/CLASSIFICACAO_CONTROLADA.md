# Classificação de controle do item de receita

Como o PrescSign decide se uma receita é comum ou controlada, e o que acontece
quando o medicamento não veio do catálogo.

Escrito em **01/09/2026**, junto da correção que fechou a falha descrita abaixo.

## 1. O problema que isto corrige

Até 31/08/2026, o `medication_id` era opcional no item e o nome do medicamento
era texto livre. Quando o médico digitava em vez de escolher no catálogo:

```
medication_id nulo
  → PrescriptionItem#snapshot_sncr_type não tem de onde derivar
  → Prescription#sync_sncr_type_from_items não encontra tipo
  → sncr_type fica nulo
  → controlled? responde false
  → receita comum, sem numeração SNCR
```

Uma substância da Portaria 344/98 saía num receituário comum. E o formulário
exibia "Receita comum (sem numeração SNCR)" — **sem aviso nenhum**.

O modo de falha é o que torna isto grave: não é uma funcionalidade ausente, cuja
falta é visível. É um documento inválido que parece correto no momento da
emissão, e cuja falha só aparece na farmácia ou numa fiscalização.

E não era caso raro. Os antimicrobianos da IN 360/2025 estão na base e exigem
`RET`:

| Substância | Lista | Tipo |
| --- | --- | --- |
| amoxicilina | IN 360/2025 art. 1º | RET |
| azitromicina | IN 360/2025 art. 1º | RET |
| cefalexina | IN 360/2025 art. 1º | RET |

Um clínico que digita "Amoxicilina 500mg" à mão emitia receita comum onde a lei
pede retenção.

## 2. O princípio que não muda

**O médico nunca escolhe o tipo de receituário.** A decisão de 27/08/2026
continua valendo, e devolver um select seria trocar uma falha silenciosa por uma
falha atribuída ao médico.

O que mudou foi o default. Era *"não reconheci, logo é comum"*. Passou a ser
*"não reconheci, logo não sei"* — e não saber impede emitir.

## 3. Por que a pergunta ao médico é sobre substância, não sobre tipo

A base `Substance` tem 612 registros e **todos** têm `sncr_type` preenchido: ela
é exclusivamente a lista controlada (Anexos A1–C5 da 344/98, mais os
antimicrobianos e os GLP-1 da IN 360/2025). Não há substância não controlada ali.

Disso decorre a propriedade que sustenta todo o desenho:

> **Não estar na lista já é a resposta "não é controlado".**

Então o médico nunca precisa classificar nada. Ele identifica o princípio ativo —
ato clínico, que ele sabe fazer — e o tipo sai de `Substance#sncr_type`. A fonte
de verdade regulatória continua sendo a substância.

É também o que faz o **manipulado controlado** passar a funcionar: um manipulado
é uma formulação de substâncias conhecidas, então identificá-las basta para a
receita sair com o receituário e a numeração certos, sem depender de alguém
cadastrar o produto no back-office.

## 4. As camadas, na ordem em que agem

Para cada item **sem `medication_id`** (texto livre):

| # | Camada | Onde | Cobre |
| --- | --- | --- | --- |
| 1 | Casamento automático | `PrescriptionItem#match_substance_from_text` | nome genérico ("clonazepam", "cloridrato de tramadol") |
| 2 | Nome que existe no catálogo | `PrescriptionItem#catalog_match_for_typed_name` | nome comercial ("Rivotril") |
| 3 | Identificação assistida | busca em `App::SubstancesController` | o que escapou das duas |
| 4 | Bloqueio | `Prescription#items_must_have_resolved_control` | tudo que ficou sem resposta |

A camada 1 usa `Medications::SubstanceMatcher`, que casa de forma **exata sobre
forma normalizada** — desfaz sal, hidratação e gênero, mas nunca aproxima. Casar
por semelhança classificaria receita controlada errado, que é a falha que se
quer evitar, não uma a se aceitar.

A camada 2 não classifica: manda selecionar. Quem digitou o nome de um produto
que está no catálogo deve clicar na sugestão, porque o produto pode associar mais
de uma controlada e `Medication#effective_sncr_type` já resolve a mais restritiva.

## 5. Quem vence quem

Duas regras de precedência, e as duas existem por segurança:

- **Catálogo vence substância avulsa.** `medication&.effective_sncr_type ||
  substance&.sncr_type` — o produto pode ter mais de uma substância e já resolveu
  a mais restritiva.
- **Casamento automático vence a afirmação do médico.** Se o sistema reconhece a
  substância, não há como declarar que ela não é controlada: marcar "nenhuma se
  aplica" para um item que casa com `clonazepam` não desliga a classificação.

## 6. O que fica gravado

Duas colunas em `prescription_items`, mutuamente exclusivas por check constraint:

- `substance_id` — a substância que classifica o item, casada ou identificada;
- `uncontrolled_confirmed_at` — quando o médico afirmou que nenhuma controlada se
  aplica. É o **único** caminho para item de texto livre sair como receita comum.

Guarda-se o instante, não um booleano: a auditoria precisa distinguir afirmação
de omissão, e saber quando ela foi feita.

Trocar o nome ou o princípio ativo do item **descarta as duas** e refaz a
pergunta — a resposta dada sobre um texto não vale para outro.

## 7. Limitação conhecida: a qualidade da lista

Todo o desenho apoia-se em *"não está nas 612, logo não é controlado"*. A
curadoria dessas 612 **ainda não passou por revisão humana** (ver
[sncr/SUBSTANCES_DATA_SOURCING.md](sncr/SUBSTANCES_DATA_SOURCING.md) §7 e a
seção 2.3 de [PENDENCIAS.md](PENDENCIAS.md)).

Se a lista tiver furo, a falha silenciosa volta por outra porta: uma controlada
ausente da base não casa, não aparece na busca assistida, e o médico confirma de
boa-fé que nada se aplica.

**Por isso a revisão da curadoria deixou de ser higiene de dados e passou a ser
pré-requisito de conformidade desta correção.**

## 8. O que isto não faz

- Não fala com o SNCR na revogação (pendência separada, seção 2.2).
- Não cobre nome comercial que **não** esteja no catálogo — cai na camada 3, que
  depende do médico responder.
- Não reclassifica receitas já emitidas. Não havia passivo em 31/08/2026:
  verificado antes de implementar.
