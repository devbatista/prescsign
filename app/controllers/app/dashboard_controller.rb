module App
  # Authenticated landing page (app.prescsign.local), routed by persona.
  class DashboardController < ApplicationController
    before_action :ensure_active_organization!

    def show
      @persona = current_persona

      return load_doctor_dashboard if @persona == :doctor

      load_organization_dashboard
    end

    private

    def load_organization_dashboard
      patients = policy_scope(Patient)
      @patients_total = patients.count
      @patients_active = patients.where(active: true).count
      @recent_patients = patients.order(created_at: :desc).limit(5)
      @recent_doctors = recent_doctors
    end

    def load_doctor_dashboard
      patients = policy_scope(Patient)
      consultations = doctor_consultations
      documents = policy_scope(Document).includes(:patient)

      @patients_total = patients.count
      @patients_active = patients.where(active: true).count
      @doctor_consultations_today = consultations.scheduled_between(Time.zone.today.beginning_of_day, Time.zone.today.end_of_day).count
      @doctor_upcoming_consultations_count = consultations.where(status: "scheduled").where("scheduled_at >= ?", Time.current).count
      @doctor_documents_month = documents.where(issued_on: Time.zone.today.all_month).count
      @doctor_upcoming_consultations = consultations.where(status: "scheduled")
                                                    .where("scheduled_at >= ?", Time.current)
                                                    .includes(:patient)
                                                    .order(:scheduled_at)
                                                    .limit(5)
      @doctor_recent_documents = documents.order(created_at: :desc).limit(5)
      @recent_patients = patients.order(updated_at: :desc).limit(5)
    end

    def doctor_consultations
      Consultation.where(organization_id: current_organization.id, user_id: current_user.id)
    end

    def recent_doctors
      return DoctorProfile.none unless current_organization

      user_ids = OrganizationMembership
                   .where(organization_id: current_organization.id, role: "doctor", status: "active")
                   .pluck(:user_id)
      DoctorProfile.where(user_id: user_ids).order(created_at: :desc).limit(5)
    rescue StandardError
      DoctorProfile.none
    end
  end
end
