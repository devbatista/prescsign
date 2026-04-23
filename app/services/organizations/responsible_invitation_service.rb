module Organizations
  class ResponsibleInvitationService
    def initialize(organization:, invited_email:, invited_by_user: nil)
      @organization = organization
      @invited_email = invited_email
      @invited_by_user = invited_by_user
    end

    def call
      invitation, raw_token = OrganizationRegistrationInvitation.issue!(
        organization: organization,
        invited_email: invited_email,
        invited_by_user: invited_by_user
      )

      OrganizationResponsibleMailer.with(
        organization: organization,
        invited_email: invited_email,
        invitation_token: raw_token,
        invitation: invitation
      ).signup_invitation.deliver_now

      invitation
    end

    private

    attr_reader :organization, :invited_email, :invited_by_user
  end
end
