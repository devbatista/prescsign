module AuditLogs
  class Recorder
    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(
      action:,
      resource:,
      actor: nil,
      patient: nil,
      document: nil,
      organization: nil,
      before_data: {},
      after_data: {},
      occurred_at: Time.current,
      request_id: nil,
      request_origin: nil,
      ip_address: nil,
      user_agent: nil
    )
      @action = action
      @resource = resource
      @actor = actor
      @patient = patient
      @document = document
      @organization = organization
      @before_data = before_data
      @after_data = after_data
      @occurred_at = occurred_at
      @request_id = request_id
      @request_origin = request_origin
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      AuditLog.create!(
        actor: @actor,
        user: resolved_user,
        organization: resolved_organization,
        patient: resolved_patient,
        document: resolved_document,
        resource: @resource,
        action: @action,
        occurred_at: @occurred_at,
        before_data: @before_data || {},
        after_data: @after_data || {},
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    private

    def resolved_document
      return @resolved_document if defined?(@resolved_document)

      @resolved_document =
        @document ||
        (@resource if @resource.is_a?(Document)) ||
        @resource.try(:document)
    end

    def resolved_patient
      return @resolved_patient if defined?(@resolved_patient)

      @resolved_patient =
        @patient ||
        resolved_document&.patient ||
        @resource.try(:patient)
    end

    def resolved_organization
      return @organization if @organization.present?
      return resolved_document&.organization if resolved_document.present?
      return resolved_patient&.organization if resolved_patient.present?
      return @actor.current_organization if @actor.respond_to?(:current_organization)
      return Organization.find_by(id: @actor.current_organization_id) if @actor.respond_to?(:current_organization_id)

      nil
    end

    def resolved_user
      return @actor if @actor.is_a?(User)
      return @actor.user if @actor.is_a?(Doctor)
      return resolved_document&.user if resolved_document.present?
      return resolved_patient&.user if resolved_patient.present?

      nil
    end
  end
end
