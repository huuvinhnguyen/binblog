Rails.application.config.action_mailer.default_url_options = {
  host: ENV.fetch('APP_HOST', 'khuonvien.vn'),
  protocol: ENV.fetch('APP_PROTOCOL', 'https')
}
