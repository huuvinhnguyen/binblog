# app/services/slack_notification_service.rb
class SlackNotificationService
    def initialize(webhook_url, message, channel: 'farming#', username: 'khuonvien')
      @notifier = Slack::Notifier.new(webhook_url) do
        defaults channel: channel, username: username
      end
      @message = message
    end
  
    def send_notification
      @notifier.ping(@message)
    rescue StandardError => e
      Rails.logger.error "Failed to send Slack notification: #{e.message}"
      nil
    end
end

  