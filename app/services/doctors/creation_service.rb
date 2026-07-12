module Doctors
  # Direct doctor onboarding by the organization responsible. Creates the user
  # (unconfirmed, with a random password), the doctor profile with its
  # specialties, an active doctor membership + role, and emails the doctor a link
  # to set their own password (which also confirms the account).
  class CreationService
    Result = Struct.new(:ok, :profile, :user, keyword_init: true) do
      def success? = ok
    end

    def initialize(organization:, email:, profile_attributes:, invited_by: nil)
      @organization = organization
      @email = email.to_s.strip.downcase
      @profile_attributes = (profile_attributes || {}).to_h
      @invited_by = invited_by
    end

    def call
      user = build_user
      profile = user.build_doctor_profile(@profile_attributes.merge(email: @email, active: true))

      copy_user_errors_into(profile, user) unless user.valid?
      return Result.new(ok: false, profile: profile, user: user) unless user.valid? && profile.valid?

      ActiveRecord::Base.transaction do
        user.save!
        profile.save!
        activate_doctor_role!(user)
        OrganizationMembership.create!(user: user, organization: @organization, role: "doctor", status: "active")
        send_account_setup_email(user)
      end

      Result.new(ok: true, profile: profile, user: user)
    rescue ActiveRecord::RecordInvalid
      Result.new(ok: false, profile: profile, user: user)
    end

    private

    def build_user
      password = SecureRandom.hex(24)
      user = User.new(email: @email, password: password, password_confirmation: password, status: "active")
      # We send our own "set your password" email instead of Devise's confirmation.
      user.skip_confirmation_notification!
      user
    end

    # Surface user-level errors (e.g. duplicate email) on the profile so the form
    # can re-render them next to the shared email field.
    def copy_user_errors_into(profile, user)
      user.errors.each { |error| profile.errors.add(:base, error.full_message) }
    end

    def activate_doctor_role!(user)
      role = user.user_roles.find_or_initialize_by(role: "doctor")
      role.status = "active"
      role.save! if role.new_record? || role.changed?
    end

    def send_account_setup_email(user)
      raw_token = user.send(:set_reset_password_token)
      DoctorAccountMailer.with(user: user, token: raw_token, organization: @organization)
                         .account_setup.deliver_later
    end
  end
end
