require "rails_helper"

RSpec.describe Observability::CriticalAlertService do
  it "captures exception in Sentry and logs structured critical alert once" do
    error = StandardError.new("boom")
    allow(Rails.logger).to receive(:error)
    allow(Sentry).to receive(:with_scope).and_yield(instance_double(Sentry::Scope, set_tags: nil, set_extras: nil))
    allow(Sentry).to receive(:capture_exception)

    first = described_class.notify!(
      category: "http_500",
      exception: error,
      context: { request_id: "req-1" }
    )
    second = described_class.notify!(
      category: "http_500",
      exception: error,
      context: { request_id: "req-1" }
    )

    expect(first).to eq(true)
    expect(second).to eq(false)
    expect(Rails.logger).to have_received(:error).once
    expect(Sentry).to have_received(:capture_exception).with(error).once
  end
end
