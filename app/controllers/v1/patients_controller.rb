module V1
  class PatientsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!
    before_action :set_patient, only: %i[show update destroy]

    def index
      authorize Patient

      patients = apply_search(policy_scope(Patient))
      ordered_patients, sort_meta = apply_standard_order(
        patients,
        allowed_sorts: {
          "full_name" => :full_name,
          "created_at" => :created_at,
          "updated_at" => :updated_at
        },
        default_sort: :full_name
      )
      records, total, page, per_page = paginate_scope(ordered_patients)

      render_success(
        data: records.map { |patient| patient_payload(patient) },
        meta: build_pagination_meta(total: total, page: page, per_page: per_page, extra: sort_meta)
      )
    end

    def show
      authorize @patient
      render_success(data: patient_payload(@patient))
    end

    def create
      patient = current_user.patients.new(
        patient_params.merge(
          organization: current_organization
        )
      )
      authorize patient

      if patient.save
        render_success(data: patient_payload(patient), status: :created)
      else
        render_error(patient.errors.full_messages, status: :unprocessable_content)
      end
    end

    def update
      authorize @patient

      if @patient.update(patient_params)
        render_success(data: patient_payload(@patient))
      else
        render_error(@patient.errors.full_messages, status: :unprocessable_content)
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

    def patient_payload(patient)
      patient.slice(
        :id,
        :organization_id,
        :user_id,
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
