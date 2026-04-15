require "rails_helper"

RSpec.describe "Job queue configuration" do
  it "configures default and mailer queues" do
    expect(Rails.application.config.active_job.default_queue_name.to_s).to eq("default")
    expect(Rails.application.config.action_mailer.deliver_later_queue_name.to_s).to eq("mailers")
  end

  it "exposes dedicated base jobs for critical and notifications queues" do
    expect(ApplicationJob.queue_name).to eq("default")
    expect(CriticalJob.queue_name).to eq("critical")
    expect(NotificationJob.queue_name).to eq("notifications")
  end
end
