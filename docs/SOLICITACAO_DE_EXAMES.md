# Solicitação de exames — modelagem

Desenho do terceiro tipo de documento do PrescSign, para ser implementado sobre
a infraestrutura genérica de `Document` (versionamento, assinatura, PDF,
entrega, validação pública, revogação e auditoria).

Escrito em **15/09/2026**, a partir do código da branch `main` (commit
`c7de7ae`). É um desenho, não um retrato do que existe: nada descrito aqui está
implementado ainda. Cada seção aponta os arquivos existentes que servem de
modelo, para que a implementação copie convenções em vez de inventar.

---

## 1. Por que entra, e por que agora

O `Document` é polimórfico sobre `documentable` e não sabe o que é o documento.
Tudo o que é caro — assinar com ICP-Brasil, versionar, gerar PDF, entregar por
e-mail/WhatsApp, validar publicamente, revogar, auditar — já é genérico. Um novo
tipo custa o que o atestado custou: um model, uma controller, uma policy, um
formulário e um template de PDF.

Solicitação de exames **não passa pelo SNCR**. Os dois serviços de numeração
já ignoram o que não é receita:

- `app/services/sncr/numbering_assignment.rb:12` — `return unless documentable.is_a?(::Prescription)`
- `app/services/sncr/numbering_revocation.rb:34` — `return nil unless @documentable.is_a?(::Prescription)`

Logo, o novo tipo passa por `Documents::SigningService#sign!` e por
`Documents::LifecycleService#revoke!` sem alteração nesses serviços e sem risco
para a numeração de receitas controladas.

O que **não** entra neste desenho, deliberadamente: prontuário. A decisão e os
motivos (regime de guarda de 20 anos da Lei 13.787/2018, certificação SBIS/CFM
da Resolução CFM 1.821/2007, mudança de posicionamento do produto) estão fora do
escopo deste documento. O degrau intermediário barato — vincular documentos à
consulta — é independente disto e pode vir antes ou depois.

---

## 2. Tabelas

### 2.1 `exam_requests`

Espelha `medical_certificates` nas convenções (uuid, checks, índices).

| Coluna | Tipo | Restrições | Observação |
| --- | --- | --- | --- |
| `code` | string | not null, único, `char_length(trim) >= 8`, não vazio | Gerado como nos outros tipos |
| `user_id` | uuid | not null, FK `users` (restrict) | Prescritor |
| `patient_id` | uuid | not null, FK `patients` (restrict) | |
| `organization_id` | uuid | not null, FK `organizations` (restrict) | |
| `issued_on` | date | not null | |
| `status` | string | not null, default `draft`, check em (`draft`, `signed`, `cancelled`) | Mesmo ciclo dos outros documentables |
| `content` | text | not null, não vazio | **Sintetizado dos itens** — ver seção 3.1 |
| `clinical_indication` | text | nulo | Hipótese diagnóstica / indicação clínica |
| `icd_code` | string | nulo | Normaliza upcase, como no atestado |
| `notes` | text | nulo | Orientações ao paciente (jejum, preparo) |
| `created_at`, `updated_at` | datetime | not null | |

Índices, iguais aos de `medical_certificates`: `code` (único), `issued_on`,
`[organization_id, status]`, `[organization_id, user_id]`,
`[patient_id, status]` e os individuais de cada FK.

### 2.2 `exam_request_items`

Espelha `prescription_items` sem a parte de classificação de controle
(`medication_id`, `substance_id`, `sncr_type`, `uncontrolled_confirmed_at`).

| Coluna | Tipo | Restrições | Observação |
| --- | --- | --- | --- |
| `exam_request_id` | uuid | not null, FK `exam_requests` | |
| `position` | integer | not null, `>= 1`, único em `(exam_request_id, position)` | |
| `name` | string | not null, não vazio | Nome do exame |
| `observation` | text | nulo | "com contraste", "lado direito", "em jejum" |
| `created_at`, `updated_at` | datetime | not null | |

**Sem catálogo nesta versão.** Não há `category` (laboratorial/imagem) nem FK
para TUSS. Quando o catálogo vier, entra como `belongs_to :exam_catalog,
optional: true` com snapshot em `name` — o mesmo padrão de `medication_id` em
`PrescriptionItem`, que mantém o item íntegro se o catálogo mudar ou sumir.
Nada da tabela precisa mudar para isso.

### 2.3 `documents` — a única alteração em tabela existente

Dois check constraints precisam ser recriados para aceitar o novo tipo
(`db/schema.rb`, tabela `documents`):

- `chk_documents_kind_values` — incluir `'exam_request'`;
- `chk_documents_kind_matches_documentable_type` — incluir o par
  `kind = 'exam_request' AND documentable_type = 'ExamRequest'`.

É drop + add de constraint, sem reescrita de linha. A tabela é pequena, mas por
disciplina: adicionar com `NOT VALID` e validar em seguida
(`validate_check_constraint`), para não segurar lock enquanto varre.

---

## 3. Modelos

### 3.1 `ExamRequest`

Estrutura do `MedicalCertificate` (`app/models/medical_certificate.rb`) com a
parte de itens da `Prescription` (`app/models/prescription.rb`).

```ruby
class ExamRequest < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze

  belongs_to :user
  belongs_to :patient
  belongs_to :organization
  has_one :document, as: :documentable, dependent: :restrict_with_exception
  has_many :exam_request_items, -> { order(:position) },
           inverse_of: :exam_request, dependent: :destroy

  accepts_nested_attributes_for :exam_request_items, allow_destroy: true,
    reject_if: ->(attrs) { attrs[:name].blank? }

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :must_have_at_least_one_item
  validate :organization_must_match_relations

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
  normalizes :icd_code, with: ->(value) { value&.strip&.upcase.presence }

  before_validation :assign_default_organization
  before_validation :assign_default_user
  before_validation :sync_content_from_items
end
```

`assign_default_organization`, `assign_default_user` e
`organization_must_match_relations` são cópia literal do atestado.

**`content` é sintetizado, e é a fonte de verdade.** É o que
`Documents::SigningService#sign!` lê (`document.documentable.content`), o que
vira checksum e o que fica em `DocumentVersion.content`. Formato:

```
1. Hemograma completo — em jejum
2. TSH
3. Ultrassonografia de abdome total — com contraste

Indicação clínica: Investigação de fadiga crônica (CID R53)
```

A indicação clínica e o CID entram no `content` para que a versão do documento
seja autocontida — quem lê `DocumentVersion.content` sem abrir o PDF vê o pedido
inteiro. `notes` também entra, quando presente, como último bloco
("Orientações: …").

**Itens obrigatórios, sem texto livre.** Diferença deliberada em relação à
receita, que mantém `content` digitado por causa do legado. Aqui não há legado
a preservar, e texto livre é o que tornaria o catálogo doloroso depois.

### 3.2 `ExamRequestItem`

`PrescriptionItem` (`app/models/prescription_item.rb`) sem tudo o que é
classificação de controle.

```ruby
class ExamRequestItem < ApplicationRecord
  belongs_to :exam_request, inverse_of: :exam_request_items

  validates :name, presence: true
  validates :position,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            uniqueness: { scope: :exam_request_id }

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :observation, with: ->(value) { value&.strip.presence }

  before_validation :assign_position, on: :create

  # "Hemograma completo — em jejum"
  def to_content_line
    [ name, observation ].compact_blank.join(" — ")
  end
end
```

`assign_position` é a mesma lógica de `PrescriptionItem#assign_position`
(considera irmãos carregados, persistidos ou em memória). Com o terceiro uso,
vale extrair um concern pequeno — `PositionedWithinParent`, ~10 linhas,
parametrizado pela associação do pai — e aplicá-lo nos dois itens. A terceira
cópia é a "necessidade clara" que o `AGENTS.md` pede antes de abstrair.

### 3.3 Associações nos agregados

`has_many :exam_requests, dependent: :restrict_with_exception` em `User`,
`Patient` e `Organization`, ao lado das duas associações que já existem em cada
um.

---

## 4. Registro de tipos de documento

Hoje o `kind` está espalhado:

| Onde | O quê |
| --- | --- |
| `app/models/document.rb:2-4` | `KINDS`, `KIND_LABELS`, mapa kind → classe em `documentable_type_matches_kind` |
| `app/services/documents/pdf_renderer.rb:38-66` | dois `case document.kind` (template e chave de `locals`) |
| `app/helpers/documents_helper.rb:17-18` | cópia de `KIND_LABELS` |
| `app/helpers/documents_helper.rb:107-115` | três ternários `is_a?(Prescription) ? … : …` para rotas |
| `app/services/deliveries/adapters/whatsapp_adapter.rb:71-72` | texto da mensagem por kind |
| `app/controllers/app/documents_controller.rb:19-21` | uma aba por kind |

Com dois tipos, funciona. Com três, cada novo tipo exige editar seis lugares e
esquecer um deles quebra em produção, não em compilação. A proposta é uma fonte
só, em `Document`:

```ruby
KIND_REGISTRY = {
  "prescription"        => { documentable_type: "Prescription",       label: "Receita" },
  "medical_certificate" => { documentable_type: "MedicalCertificate", label: "Atestado" },
  "exam_request"        => { documentable_type: "ExamRequest",        label: "Solicitação de exames" }
}.freeze
KINDS = KIND_REGISTRY.keys.freeze
KIND_LABELS = KIND_REGISTRY.transform_values { |entry| entry[:label] }.freeze
```

E os pontos de ramificação deixam de ramificar:

- **`PdfRenderer`**: `"documents/pdf/#{document.kind}"` e `document.kind.to_sym`.
  É seguro interpolar porque `kind` é validado por inclusão no model **e** por
  check constraint no banco — o `case` de hoje só repete essa whitelist.
- **`DocumentsHelper`**: `edit_polymorphic_path(documentable)`,
  `polymorphic_path([:pdf, documentable])`,
  `polymorphic_path([:revoke, documentable])`. Funciona porque as rotas seguem o
  nome do model (`resources :exam_requests` → `pdf_exam_request_path`). A cópia
  de labels na linha 17 passa a apontar para `Document::KIND_LABELS`.
- **`WhatsappAdapter`**: ganha a terceira linha —
  `"exam_request" => { possessive: "sua", noun: "solicitação de exames", pronoun: "ela", signed: "assinada" }`.
  Fica no adapter de propósito: é texto de entrega com gênero gramatical, não
  estrutura de documento.

Depois disso, um quarto tipo (encaminhamento, relatório médico) toca: o
registro, o adapter, a aba do índice, a rota e os arquivos próprios dele. Nenhum
`case` novo.

---

## 5. Policy

`PrescriptionPolicy` e `MedicalCertificatePolicy` são idênticas — `diff` entre
os dois arquivos só acusa o nome da classe. `ExamRequestPolicy` seria a terceira
cópia.

Extrair `DocumentablePolicy < ApplicationPolicy` com o conteúdo atual (incluindo
a `Scope`) e fazer as três herdarem vazias:

```ruby
class ExamRequestPolicy < DocumentablePolicy; end
```

Pundit resolve a policy pelo nome do model, então as três classes precisam
existir — mas ficam com uma linha cada.

---

## 6. Controller, rotas e views

### 6.1 Rotas (`config/routes/app.rb`)

Ao lado de `prescriptions` e `medical_certificates`:

```ruby
resources :exam_requests, controller: "app/exam_requests", only: %i[new create edit update] do
  member do
    patch :revoke
    get :pdf
  end
end
```

### 6.2 `App::ExamRequestsController`

Cópia de `App::MedicalCertificatesController`
(`app/controllers/app/medical_certificates_controller.rb`), com:

- params aninhados:
  `exam_request_items_attributes: %i[id name observation position _destroy]`;
- `create` chamando
  `lifecycle_service.create_with_initial_version!(kind: "exam_request", content: @exam_request.content, …)`
  — o serviço não muda;
- `update` registrando em `before_data`/`after_data` os campos
  `content`, `issued_on`, `clinical_indication`, `icd_code`, `notes`;
- nome do PDF `solicitacao-exames-#{code}-v#{version}.pdf`;
- mensagens: "Solicitação de exames emitida com sucesso.", "Solicitação de
  exames atualizada.", "Solicitação de exames revogada.", "A solicitação só
  pode ser editada antes da assinatura."

`generate_code` e `lifecycle_service` são cópias literais. Se o refactor da
seção 4 for feito, vale também subir `generate_code` para um lugar comum às
três controllers — hoje já está duplicado.

### 6.3 Formulário

`app/views/app/exam_requests/_form.html.erb`, `new.html.erb`, `edit.html.erb`.
O padrão de linhas dinâmicas já existe em
`app/views/app/prescriptions/_form.html.erb:87-93` (`fields_for` sobre os itens
existentes + template com `child_index: "NEW_RECORD"`). Reaproveitar o mecanismo
com dois campos por linha (`name`, `observation`) e os campos de cabeçalho
(`patient_id`, `issued_on`, `clinical_indication`, `icd_code`, `notes`).

### 6.4 PDF

`app/views/documents/pdf/exam_request.html.erb`. Cabeçalho de clínica/médico e
rodapé de assinatura + QR de validação iguais aos de
`documents/pdf/medical_certificate.html.erb`; corpo com paciente, data, lista
numerada dos itens, indicação clínica, CID e orientações.

### 6.5 Pontos de entrada

- terceira aba em `app/controllers/app/documents_controller.rb:19-21` e na view
  `app/views/app/documents/index.html.erb`;
- botão "Solicitar exames" em `app/views/app/consultations/show.html.erb`, ao
  lado de receita e atestado;
- botão em `app/views/app/patients/show.html.erb`;
- contador em `app/views/app/dashboard/show.html.erb`;
- item em `app/helpers/navigation_helper.rb:58-60`.

---

## 7. Sequência de entrega

Quatro PRs pequenos, cada um com a suíte verde
(`docker compose exec -T web bundle exec rspec`):

1. **Registro de tipos + `DocumentablePolicy`** (seções 4 e 5). Refactor puro,
   sem mudança de comportamento. Spec de paridade: helpers e renderer produzem o
   mesmo resultado de antes para os dois tipos existentes. Entra antes de
   qualquer coisa nova — se der problema, reverte sozinho.
2. **Migrations + `ExamRequest` + `ExamRequestItem`** (seções 2 e 3), com specs
   de model: síntese de `content`, item obrigatório, posição, contexto de
   organização, check constraints de `documents`.
3. **Controller + policy + formulário + PDF + entrega** (seção 6), com specs de
   request espelhando `spec/requests/app/documents_spec.rb` e os do atestado,
   incluindo assinar e revogar.
4. **Pontos de entrada** (seção 6.5).

---

## 8. Decisões em aberto

- **`notes` (orientações ao paciente).** Incluído no desenho porque "jejum de
  12h" é a observação mais comum que não pertence a um exame específico. Se a
  preferência for enxuto, remover a coluna e o bloco do `content`.
- **Nome do tipo na interface.** "Solicitação de exames" (adotado aqui) ou
  "Pedido de exames". Afeta `KIND_LABELS`, mensagens, texto do WhatsApp e nome
  do arquivo PDF.
- **Um pedido por categoria?** Muito médico emite um pedido para laboratório e
  outro para imagem. Sem `category`, isso se resolve criando dois pedidos — o
  comportamento mais simples e que não exige decisão de modelagem agora. Se o
  uso mostrar que é atrito, `category` entra no item como string com check
  constraint, e o PDF agrupa por ela.
