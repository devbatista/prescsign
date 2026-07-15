module Doctors
  # Direct doctor onboarding by the organization responsible. If the doctor
  # already exists, links the existing user to the organization; otherwise
  # creates the user, profile, active doctor membership + role, and emails the
  # doctor a link to set their own password.
  class CreationService
    Result = Struct.new(:ok, :profile, :user, :action, keyword_init: true) do
      def success? = ok

      def linked? = action == :linked
    end

    def initialize(organization:, email:, profile_attributes:, invited_by: nil)
      @organization = organization
      @email = email.to_s.strip.downcase
      @profile_attributes = (profile_attributes || {}).to_h
      @invited_by = invited_by
    end

    def call
      existing_result = link_existing_doctor
      return existing_result if existing_result

      user = build_user
      profile = user.build_doctor_profile(@profile_attributes.merge(email: @email, active: true))
      profile.license_organization_id = @organization.id

      copy_user_errors_into(profile, user) unless user.valid?
      return Result.new(ok: false, profile: profile, user: user) unless user.valid? && profile.valid?

      ActiveRecord::Base.transaction do
        user.save!
        profile.save!
        activate_doctor_role!(user)
        OrganizationMembership.create!(user: user, organization: @organization, role: "doctor", status: "active")
        send_account_setup_email(user)
      end

      Result.new(ok: true, profile: profile, user: user, action: :created)
    rescue ActiveRecord::RecordInvalid
      Result.new(ok: false, profile: profile, user: user)
    end

    private

    def link_existing_doctor
      profile_by_email = User.find_by(email: @email)&.doctor_profile
      profile_by_cpf = DoctorProfile.find_by(cpf: normalized_cpf)

      if profile_by_email && profile_by_cpf && profile_by_email.id != profile_by_cpf.id
        profile_by_email.errors.add(:base, "E-mail e CPF pertencem a médicos diferentes.")
        return Result.new(ok: false, profile: profile_by_email, user: profile_by_email.user)
      end

      profile = profile_by_email || profile_by_cpf
      return nil if profile.blank?

      profile.license_organization_id = @organization.id
      return Result.new(ok: false, profile: profile, user: profile.user) unless profile.valid?

      if profile.user.membership_for(@organization.id).present?
        profile.errors.add(:base, "Médico já está vinculado a esta clínica.")
        return Result.new(ok: false, profile: profile, user: profile.user)
      end

      ActiveRecord::Base.transaction do
        activate_doctor_role!(profile.user)
        OrganizationMembership.create!(user: profile.user, organization: @organization, role: "doctor", status: "active")
      end

      Result.new(ok: true, profile: profile, user: profile.user, action: :linked)
    end

    def normalized_cpf
      (@profile_attributes[:cpf] || @profile_attributes["cpf"]).to_s.gsub(/\D/, "")
    end

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
