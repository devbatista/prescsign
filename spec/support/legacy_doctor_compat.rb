module LegacyDoctorCompat
  module_function

  def create_doctor_with_profile!(attributes = {})
    attrs = attributes.to_h.symbolize_keys

    user = User.new(
      email: attrs.fetch(:email),
      password: attrs.fetch(:password, "password123"),
      password_confirmation: attrs.fetch(:password_confirmation, attrs.fetch(:password, "password123")),
      status: attrs.fetch(:status, "active")
    )
    user.save!

    profile = user.build_doctor_profile(
      full_name: attrs.fetch(:full_name),
      email: attrs.fetch(:email),
      cpf: attrs[:cpf],
      license_number: attrs.fetch(:license_number),
      license_state: attrs.fetch(:license_state),
      specialty: attrs[:specialty],
      active: attrs.fetch(:active, true)
    )
    profile.save!

    role = user.user_roles.find_or_initialize_by(role: "doctor")
    role.status = "active"
    role.save! if role.new_record? || role.changed?

    organization = Organization.create!(name: "Autônomo - #{profile.full_name}", kind: "autonomo", active: true)
    OrganizationMembership.create!(user: user, organization: organization, role: "owner", status: "active")
    user.update!(current_organization_id: organization.id)

    user.update!(confirmed_at: attrs[:confirmed_at]) if attrs[:confirmed_at].present?
    user
  end
end

unless defined?(Doctor)
  class Doctor
    class << self
      def create!(attributes = {})
        LegacyDoctorCompat.create_doctor_with_profile!(attributes)
      end

      def find_by(*args)
        User.find_by(*args)
      end

      def count
        User.joins(:user_roles).where(user_roles: { role: "doctor", status: "active" }).distinct.count
      end
    end
  end
end

module Auth
  class UserIdentityResolver
    class << self
      def resolve_for_doctor(doctor)
        doctor
      end
    end
  end
end

DoctorPolicy = DoctorProfilePolicy unless defined?(DoctorPolicy)

module Auth
  class RefreshTokenService
    class << self
      alias_method :issue_for_without_legacy_doctor, :issue_for unless method_defined?(:issue_for_without_legacy_doctor)

      def issue_for(user:, **_legacy_kwargs)
        issue_for_without_legacy_doctor(user: user)
      end
    end
  end
end

[
  OrganizationMembership,
  OrganizationResponsible,
  Patient,
  Prescription,
  MedicalCertificate,
  Document,
  DeliveryLog
].each do |klass|
  next if klass.reflect_on_association(:doctor)

  klass.belongs_to :doctor, class_name: "User", foreign_key: :user_id, optional: true
end

unless User.method_defined?(:masked_cpf)
  User.class_eval do
    def user
      self
    end

    def confirm
      update!(confirmed_at: Time.current)
    end

    def doctor_id
      id
    end

    def current_organization
      super || Organization.find_by(id: current_organization_id)
    end

    def active_organization_memberships
      organization_memberships.active
    end

    def full_name
      doctor_profile&.full_name
    end

    def cpf
      doctor_profile&.cpf
    end

    def license_number
      doctor_profile&.license_number
    end

    def license_state
      doctor_profile&.license_state
    end

    def specialty
      doctor_profile&.specialty
    end

    def active
      doctor_profile&.active
    end

    def masked_cpf
      digits = doctor_profile&.cpf.to_s.gsub(/\D/, "")
      return nil if digits.length < 11

      "***.***.***-#{digits[-2, 2]}"
    end
  end
end
