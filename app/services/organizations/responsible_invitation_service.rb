module Organizations
  class ResponsibleInvitationService
    def initialize(organization:, user:)
      @organization = organization
      @user = user
    end

    def call
      if user.confirmed?
        OrganizationResponsibleMailer.with(organization: organization, user: user).existing_account_invitation.deliver_now
      else
        raw_token = refresh_confirmation_token!
        OrganizationResponsibleMailer.with(
          organization: organization,
          user: user,
          confirmation_token: raw_token
        ).signup_invitation.deliver_now
      end
    end

    private

    attr_reader :organization, :user

    def refresh_confirmation_token!
      raw_token, enc_token = Devise.token_generator.generate(User, :confirmation_token)
      user.update_columns(
        confirmation_token: enc_token,
        confirmation_sent_at: Time.current,
        updated_at: Time.current
      )
      raw_token
    end
  end
end
