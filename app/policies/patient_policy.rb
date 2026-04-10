class PatientPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    linked_to_doctor? || admin?
  end

  def create?
    user.present?
  end

  def update?
    linked_to_doctor? || admin?
  end

  def destroy?
    linked_to_doctor? || admin?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      scope
        .left_joins(:prescriptions, :medical_certificates, :documents)
        .where(
          "prescriptions.doctor_id = :doctor_id OR medical_certificates.doctor_id = :doctor_id OR documents.doctor_id = :doctor_id",
          doctor_id: user.id
        )
        .distinct
    end
  end

  private

  def linked_to_doctor?
    return false unless user.present?

    record.prescriptions.where(doctor_id: user.id).exists? ||
      record.medical_certificates.where(doctor_id: user.id).exists? ||
      record.documents.where(doctor_id: user.id).exists?
  end
end
