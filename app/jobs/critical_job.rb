class CriticalJob < ApplicationJob
  queue_as :critical
end
