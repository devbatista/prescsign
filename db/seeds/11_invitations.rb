# frozen_string_literal: true

def seed_invitations!(context)
  clinic = context.fetch(:clinic)
  admin = context.fetch(:admin)

  create_once_by(
    OrganizationRegistrationInvitation,
    {
      organization: clinic,
      invited_email: "novo.medico@prescsign.test"
    },
    {
      invited_by_user: admin,
      token_digest: OrganizationRegistrationInvitation.digest_token("seed-invitation-token"),
      expires_at: 7.days.from_now
    }
  )
end
