class ApplicationMailer < ActionMailer::Base
  default from: -> { Mailers::SenderAddress.default }
  layout "mailer"
end
