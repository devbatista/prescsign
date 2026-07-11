module App
  class PagesController < WebBaseController
    # Shown when the signed-in user has no active organization context.
    def organization_context_required
    end
  end
end
