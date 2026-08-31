# Como adicionar uma tela

Guia prático para criar uma nova tela no painel (`app.` subdomínio). O app é um
monolito Rails server-rendered: **rota → controller fino → view ERB → policy**.
Nada de JavaScript de framework; os _services_ carregam a regra de negócio.

Use a tela de **Pacientes** como referência viva:
[`App::PatientsController`](../app/controllers/app/patients_controller.rb),
[`app/views/app/patients/`](../app/views/app/patients/),
[`PatientPolicy`](../app/policies/patient_policy.rb).

---

## 1. Rota

Adicione dentro do bloco `constraints subdomain: "app"` em
[`config/routes.rb`](../config/routes.rb). Paths em inglês; controllers no
namespace `app/`:

```ruby
constraints subdomain: "app" do
  resources :widgets, controller: "app/widgets"
  # ...
end
```

Para telas de outro subdomínio (auth), use o bloco `login.`/`register.`.

## 2. Controller (`App::`, fino)

Fica em `app/controllers/app/widgets_controller.rb`, herda de
`ApplicationController` e **chama services** — sem regra de negócio no controller:

```ruby
module App
  class WidgetsController < ApplicationController
    before_action :ensure_active_organization!   # se a tela exige tenant ativo

    def index
      authorize Widget                            # Pundit: sempre autorize
      scope = policy_scope(Widget).order(:name)   # Pundit scope por tenant
      @widgets, @page, @total_pages, @total = paginate(scope)
    end

    def create
      @widget = current_user.widgets.new(widget_params.merge(organization: current_organization))
      authorize @widget
      if @widget.save
        redirect_to widget_path(@widget), notice: "Widget criado."
      else
        flash.now[:alert] = @widget.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content   # 422 re-renderiza com erros
      end
    end

    private

    def widget_params
      params.require(:widget).permit(:name, :description)
    end
  end
end
```

Helpers disponíveis na base ([`ApplicationController`](../app/controllers/application_controller.rb)):
`current_organization`, `current_membership`, `current_persona`,
`available_organizations`, `access_context`, `paginate(scope)`,
`ensure_active_organization!`, `render_forbidden`.

## 3. Policy (Pundit)

`app/policies/widget_policy.rb`. **A autorização real é aqui**, não na view:

```ruby
class WidgetPolicy < ApplicationPolicy
  def index?  = user.present?
  def show?   = (same_organization_record? && (owner_record? || organization_admin? || support?)) || admin?
  def create? = user.present? && !support?

  class Scope < Scope
    def resolve
      return scope.all if user&.admin?
      scope.where(organization_id: Current.organization&.id)
    end
  end
end
```

## 4. Views (ERB + Tailwind)

Em `app/views/app/widgets/` (`index`, `show`, `new`, `edit`, `_form`). Use
`form_with` **sem Turbo**; o mesmo formulário serve create/update:

```erb
<%= form_with model: widget,
      url: (widget.persisted? ? widget_path(widget) : widgets_path),
      method: (widget.persisted? ? :patch : :post), class: "space-y-5" do |f| %>
  <% if widget.errors.any? %>
    <div class="rounded-lg border border-ps-error-border bg-ps-error-bg px-3 py-2 text-sm text-ps-error-fg">
      <%= widget.errors.full_messages.to_sentence %>
    </div>
  <% end %>
  <%= f.text_field :name, class: "..." %>
  <%= f.submit (widget.persisted? ? "Salvar" : "Criar"), class: "ps-btn-primary ..." %>
<% end %>
```

Padrões de UI: paleta `ps-*` (tokens Tailwind em
[`app/assets/tailwind/application.css`](../app/assets/tailwind/application.css)),
botão primário `.ps-btn-primary`, paginação via `render "shared/pagination"`,
estado proibido via `render_forbidden` (→ `shared/forbidden`).

## 5. Menu

Se a tela vai no menu lateral, adicione um `NavItem` em
[`NavigationHelper#nav_items`](../app/helpers/navigation_helper.rb) com a `section`
e ajuste [`AccessContext#can?`](../app/models/access_context.rb) para a persona.

## 6. Request spec (obrigatório)

Em `spec/requests/app/widgets_spec.rb`, com **happy path + autorização negada**.
Use o helper [`spec/support/web_spec_helpers.rb`](../spec/support/web_spec_helpers.rb)
(login por sessão + host de subdomínio):

```ruby
require "rails_helper"

RSpec.describe "App::Widgets", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }

  before { sign_in_web(user); use_app_host! }

  it "lista widgets" do
    get "/widgets"
    expect(response).to have_http_status(:ok)
  end

  it "nega acesso cross-tenant (404)" do
    other = create_organization
    foreign = Widget.create!(organization: other, name: "x")
    get "/widgets/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
  end
end
```

Rode: `docker compose exec web bundle exec rspec spec/requests/app/widgets_spec.rb`.

---

### Definition of Done por tela
- [ ] Rota nomeada sob o subdomínio correto
- [ ] Controller fino chamando **service existente** (nada de regra no controller/view)
- [ ] Autorização via **Pundit** (`authorize` + `policy_scope`)
- [ ] View ERB, partials, **sem JS de framework**; `form_with` sem Turbo; 422 re-renderiza
- [ ] Flash de sucesso/erro
- [ ] Request spec: happy path + autorização negada
