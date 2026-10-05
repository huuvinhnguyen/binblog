class DeviceEvent < ActiveRecord::Base
  belongs_to :device
  has_many :trigger_action_executions,
           class_name: 'DeviceTriggerActionExecution',
           inverse_of: :device_event,
           dependent: :destroy

  EVENT_TYPES = %w[
    motion_detected
    buzzer_started
    buzzer_finished
    buzzer_test_requested
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
    @parsed_payload ||= payload.is_a?(Hash) ? payload : JSON.parse(payload || '{}')
  rescue JSON::ParserError, TypeError
    {}
  end
end
