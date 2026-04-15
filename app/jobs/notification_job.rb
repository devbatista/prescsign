class NotificationJob < ApplicationJob
  queue_as :notifications
end
