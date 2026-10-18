class ApplicationMailer < ActionMailer::Base
  default from: -> { Devise.mailer_sender }
  layout false
end
