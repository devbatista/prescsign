module Agenda
  class EventsQuery
    DEFAULT_DURATION = 30.minutes

    def initialize(user:, organization:, params: {})
      @user = user
      @organization = organization
      @params = params
    end

    def call
      consultations_scope.map { |consultation| consultation_event(consultation) }
    end

    private

    attr_reader :user, :organization, :params

    def consultations_scope
      scope = Consultation
              .where(organization: organization)
              .includes(:patient, user: :doctor_profile)
              .order(:scheduled_at, :created_at)

      scope = scope.where(user_id: visible_doctor_id)
      scope = scope.where(status: params[:status]) if params[:status].present?

      starts_at = parsed_time(params[:starts_at])
      ends_at = parsed_time(params[:ends_at])
      scope = scope.where("scheduled_at >= ?", starts_at) if starts_at.present?
      scope = scope.where("scheduled_at <= ?", ends_at) if ends_at.present?
      scope
    end

    def visible_doctor_id
      return params[:doctor_id] if can_view_organization_agenda? && params[:doctor_id].present?
      return nil if can_view_organization_agenda?

      user.id
    end

    def can_view_organization_agenda?
      user.admin? || user.support? || user.organization_admin?(organization.id)
    end

    def consultation_event(consultation)
      {
        id: consultation.id,
        type: "consultation",
        title: consultation_title(consultation),
        consultation_id: consultation.id,
        organization_id: consultation.organization_id,
        doctor_id: consultation.user_id,
        doctor_name: doctor_name(consultation.user),
        patient_id: consultation.patient_id,
        patient_name: consultation.patient.full_name,
        starts_at: consultation.scheduled_at,
        ends_at: consultation.finished_at || consultation.scheduled_at + DEFAULT_DURATION,
        status: consultation.status
      }
    end

    def consultation_title(consultation)
      "Consulta - #{consultation.patient.full_name}"
    end

    def doctor_name(doctor)
      doctor.doctor_profile&.full_name.presence || doctor.email
    end

    def parsed_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
