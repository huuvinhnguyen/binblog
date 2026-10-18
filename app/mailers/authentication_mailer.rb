class AuthenticationMailer < ApplicationMailer
  def social_recovery_instructions(user, token)
    @user = user
    @recovery_url = Rails.application.routes.url_helpers.edit_user_password_url(
      social_recovery_token: token,
      host: ENV.fetch('APP_HOST', 'khuonvien.vn'),
      protocol: 'https'
    )
    mail(to: user.email, subject: 'Binblog account recovery')
  end
end
