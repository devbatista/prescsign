module App
  class PagesController < ApplicationController
    # Shown when the signed-in user has no active organization context.
    def organization_context_required
    end

    # Institutional/architecture page. Visibility mirrors the Vue ABOUT_ACCESS
    # (admins, excluding manager-only), enforced here via AccessContext.
    def about
      render_forbidden unless access_context.can?(:about)
    end
  end
end
