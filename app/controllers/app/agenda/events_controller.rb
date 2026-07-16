module App
  module Agenda
    # Month calendar of consultations within the panel (app.prescsign.local).
    # Mirrors V1::Agenda::EventsController, reusing ::Agenda::EventsQuery for the
    # event list and doctor-visibility rules. The controller only turns the flat
    # event list into a month grid for the ERB calendar.
    class EventsController < ApplicationController
      before_action :ensure_active_organization!

      WEEKDAY_LABELS = %w[Dom Seg Ter Qua Qui Sex Sáb].freeze
      MONTH_NAMES = [nil, "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
                     "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"].freeze

      def index
        authorize Consultation, :index?

        @selected_day = resolve_day
        @month = resolve_month(@selected_day)
        @can_filter_doctor = can_filter_doctor?
        @doctor_id = params[:doctor_id].presence if @can_filter_doctor
        @status = params[:status].presence

        @events = ::Agenda::EventsQuery.new(
          user: current_user,
          organization: current_organization,
          params: query_params
        ).call

        @events_by_day = @events.group_by { |event| event[:starts_at]&.to_date }
        selected_events = @selected_day.present? ? (@events_by_day[@selected_day] || []) : []
        @selected_events, @selected_events_page, @selected_events_total_pages, @selected_events_total =
          paginate_array(selected_events, per_page: 10, page_param: :selected_events_page)
        @status_counts = @events.each_with_object(Hash.new(0)) { |event, acc| acc[event[:status]] += 1 }
        @calendar_days = calendar_days_for(@month)
        @weekday_labels = WEEKDAY_LABELS
        @month_label = "#{MONTH_NAMES[@month.month]} de #{@month.year}"
      end

      private

      # Parses ?month=YYYY-MM, falling back to the current month.
      def resolve_month(selected_day = nil)
        value = params[:month].to_s
        return selected_day.beginning_of_month if value.blank? && selected_day.present?

        Date.strptime(value, "%Y-%m").beginning_of_month
      rescue ArgumentError, TypeError
        Date.current.beginning_of_month
      end

      def resolve_day
        value = params[:day].to_s
        return nil if value.blank?

        Date.iso8601(value)
      rescue ArgumentError, TypeError
        nil
      end

      def query_params
        {
          status: @status,
          doctor_id: @doctor_id,
          starts_at: @month.beginning_of_month.beginning_of_day.iso8601,
          ends_at: @month.end_of_month.end_of_day.iso8601
        }
      end

      # Full weeks (Sunday-start) covering the month, so the grid is rectangular.
      def calendar_days_for(month)
        first = month.beginning_of_month.beginning_of_week(:sunday)
        last  = month.end_of_month.end_of_week(:sunday)
        (first..last).to_a
      end

      def can_filter_doctor?
        current_user.admin? || current_user.support? ||
          current_user.organization_admin?(current_organization.id)
      end
    end
  end
end
