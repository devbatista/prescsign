module V1
  class PatientsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :set_patient, only: %i[show update destroy]

    def index
      authorize Patient

      patients = apply_search(policy_scope(Patient))
      page = normalize_page(params[:page])
      per_page = normalize_per_page(params[:per_page])
      total = patients.count
      records = patients.order(:full_name).offset((page - 1) * per_page).limit(per_page)

      render json: {
        data: records.map { |patient| patient_payload(patient) },
        meta: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: (total.to_f / per_page).ceil
        }
      }, status: :ok
    end

    def show
      authorize @patient
      render json: patient_payload(@patient), status: :ok
    end

    def create
      patient = current_doctor.patients.new(patient_params)
      authorize patient

      if patient.save
        render json: patient_payload(patient), status: :created
      else
        render json: { errors: patient.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      authorize @patient

      if @patient.update(patient_params)
        render json: patient_payload(@patient), status: :ok
      else
        render json: { errors: @patient.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @patient
      @patient.update!(active: false)
      head :no_content
    end

    private

    def set_patient
      @patient = policy_scope(Patient).find(params[:id])
    end

    def patient_params
      params.require(:patient).permit(:full_name, :cpf, :birth_date, :email, :phone, :active)
    end

    def apply_search(scope)
      query = params[:q].to_s.strip
      return scope if query.blank?

      normalized_cpf = query.gsub(/\D/, "")
      by_name = "lower(full_name) LIKE lower(:term)"
      values = { term: "%#{query}%" }
      return scope.where(by_name, values) if normalized_cpf.blank?

      scope.where(
        "#{by_name} OR cpf LIKE :cpf",
        values.merge(cpf: "%#{normalized_cpf}%")
      )
    end

    def normalize_page(value)
      parsed = value.to_i
      parsed.positive? ? parsed : 1
    end

    def normalize_per_page(value)
      parsed = value.to_i
      return 20 if parsed <= 0

      [parsed, 100].min
    end

    def patient_payload(patient)
      patient.slice(
        :id,
        :doctor_id,
        :full_name,
        :cpf,
        :birth_date,
        :email,
        :phone,
        :active,
        :created_at,
        :updated_at
      )
    end
  end
end
