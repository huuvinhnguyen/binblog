class DeviceEvent < ActiveRecord::Base
  belongs_to :device

  EVENT_TYPES = %w[
    motion_detected
    buzzer_started
    buzzer_finished
    device_online
    device_offline
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  serialize :payload, JSON

  scope :recent, -> { order(occurred_at: :desc) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :today, -> { where('occurred_at >= ?', Time.current.beginning_of_day) }

  def parsed_payload
    @parsed_payload ||= JSON.parse(payload || '{}')
  rescue JSON::ParserError
    {}
  end
end
