class DeviceTriggerActionExecution < ActiveRecord::Base
  STATUSES = %w[pending_enqueue queued publish_attempted publish_returned failed skipped].freeze
  TERMINAL_STATUSES = %w[publish_returned failed skipped].freeze
  SNAPSHOT_FIELDS = %w[
    device_event_id device_trigger_action_id target_device_id action_key target_chip_id
    action_type relay_index duration_ms delay_ms configured_position command_payload scheduled_for
  ].freeze

  belongs_to :device_event, inverse_of: :trigger_action_executions
  belongs_to :device_trigger_action, optional: true, inverse_of: :executions
  belongs_to :target_device, class_name: 'Device', optional: true, inverse_of: :incoming_trigger_executions

  serialize :command_payload, JSON

  validates :action_key, :target_chip_id, :action_type, :status, :scheduled_for, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :action_key, uniqueness: { scope: :device_event_id }
  validates :delay_ms, :configured_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :snapshot_is_immutable, on: :update
  validate :status_transition_is_forward_only, on: :update

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  private

  def snapshot_is_immutable
    changed_snapshot_fields = SNAPSHOT_FIELDS.select { |field| will_save_change_to_attribute?(field) }
    errors.add(:base, 'execution snapshot is immutable') if changed_snapshot_fields.any?
  end

  def status_transition_is_forward_only
    return unless will_save_change_to_status?

    allowed = {
      'pending_enqueue' => %w[queued publish_attempted failed skipped],
      'queued' => %w[publish_attempted failed skipped],
      'publish_attempted' => %w[publish_returned failed],
      'publish_returned' => [],
      'failed' => [],
      'skipped' => []
    }
    previous, current = status_change_to_be_saved
    errors.add(:status, 'transition is not allowed') unless allowed.fetch(previous, []).include?(current)
  end
end
