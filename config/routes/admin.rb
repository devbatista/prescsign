# admin.prescsign.com.br — platform back-office (cross-org, super_admin/support)
constraints subdomain: "admin" do
  delete "sign-out", to: "sessions#destroy"

  # Módulos do back-office. `scope module: "admin", as: :admin` mantém os
  # controllers em Admin:: e prefixa os helpers com `admin_` (evita colisão com
  # os helpers `organizations` do subdomínio app.).
  scope module: "admin", as: :admin do
    resources :organizations, only: %i[index show new create] do
      member do
        patch :activate
        patch :deactivate
      end

      # Membros da organização (aninhado): /organizations/:id/users. Controller
      # em Admin::Organizations::UsersController (module: :organizations) para não
      # colidir com o módulo de usuários de plataforma (Admin::UsersController).
      resources :users, only: %i[index], module: :organizations do
        member do
          patch :update_role
          patch :activate
          patch :deactivate
          delete :remove
        end
      end
    end

    resources :invitations, only: %i[index] do
      member do
        post :resend
        patch :revoke
      end
    end

    # Catálogo global de medicamentos (cross-org). Escrita restrita a admin.
    resources :medications, only: %i[index show new create edit update] do
      member do
        patch :activate
        patch :deactivate
      end
    end

    # Substâncias ativas + classificação de controle (fonte da exigência SNCR).
    # Escrita restrita a admin.
    resources :substances, only: %i[index show new create edit update] do
      member do
        patch :activate
        patch :deactivate
      end
    end

    resources :users, only: %i[index show] do
      member do
        post :grant_role
        delete :revoke_role
        patch :block
        patch :activate
      end
    end
  end

  root "admin/dashboard#show", as: :admin_root
end
