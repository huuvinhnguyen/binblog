class DeviceTriggerAction < ActiveRecord::Base
  ACTION_TYPES = %w[relay_pulse].freeze
  SUPPORTED_TARGET_TYPES = %w[switch buzzer].freeze
  MAX_ACTIONS_PER_SOURCE = 20
  MAX_DELAY_MS = 300_000
  DURATION_RANGES = {
    'buzzer' => (100..10_000),
    'switch' => (100..86_400_000)
  }.freeze

  belongs_to :source_device, class_name: 'Device', inverse_of: :trigger_actions
  belongs_to :target_device, class_name: 'Device', inverse_of: :incoming_trigger_actions
  has_many :executions, class_name: 'DeviceTriggerActionExecution', dependent: :nullify

  validates :action_type, presence: true, inclusion: { in: ACTION_TYPES }
  validates :relay_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :delay_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_DELAY_MS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :enabled, inclusion: { in: [true, false] }
  validates :target_device_id, uniqueness: { scope: %i[source_device_id action_type] }
  validate :source_must_be_pir
  validate :target_must_be_supported
  validate :source_and_target_must_differ
  validate :relay_index_must_exist
  validate :duration_must_match_target
  validate :source_and_target_must_share_owner
  validate :source_action_limit, on: :create

  scope :runtime_order, -> { order(:position, :id) }
  scope :usable, -> { where(enabled: true) }

  def self.eligible_target_scope(source_device:, scope: Device.all)
    owner_ids = source_device.users.select(:id)
    scope.where(device_type: SUPPORTED_TARGET_TYPES)
         .where.not(id: source_device.id)
         .joins(:users)
         .where(users: { id: owner_ids })
         .distinct
  end

  def available_relay_indexes
    parsed = target_device_info
    relays = parsed['relays']
    return (0...relays.length).to_a if relays.is_a?(Array)

    indexes = parsed['relay_indexes']
    return indexes.select { |value| value.is_a?(Integer) && value >= 0 }.uniq if indexes.is_a?(Array)

    []
  end

  def runtime_error_code
    return 'source_not_pir' unless source_device&.device_type == 'pir'
    return 'target_missing' unless target_device
    return 'unsupported_target' unless SUPPORTED_TARGET_TYPES.include?(target_device.device_type)
    return 'same_device' if source_device_id == target_device_id
    return 'ownership_changed' unless shared_owner?
    return 'invalid_relay_index' unless available_relay_indexes.include?(relay_index)
    return 'invalid_duration' unless valid_duration?

    nil
  end

  def shared_owner?
    return false unless source_device && target_device

    source_device.users.where(id: target_device.users.select(:id)).exists?
  end

  private

  def source_must_be_pir
    errors.add(:source_device, 'must be a PIR device') unless source_device&.device_type == 'pir'
  end

  def target_must_be_supported
    return if target_device && SUPPORTED_TARGET_TYPES.include?(target_device.device_type)

    errors.add(:target_device, 'must be a switch or buzzer device')
  end

  def source_and_target_must_differ
    errors.add(:target_device, 'must differ from source device') if source_device_id.present? && source_device_id == target_device_id
  end

  def relay_index_must_exist
    return unless target_device && SUPPORTED_TARGET_TYPES.include?(target_device.device_type)
    return if available_relay_indexes.include?(relay_index)

    errors.add(:relay_index, 'does not exist on target device')
  end

  def duration_must_match_target
    return unless target_device && DURATION_RANGES.key?(target_device.device_type)
    return if valid_duration?

    range = DURATION_RANGES.fetch(target_device.device_type)
    errors.add(:duration_ms, "must be between #{range.begin} and #{range.end}")
  end

  def valid_duration?
    range = DURATION_RANGES[target_device&.device_type]
    duration_ms.is_a?(Integer) && range&.cover?(duration_ms)
  end

  def source_and_target_must_share_owner
    errors.add(:target_device, 'must share an owner with source device') unless shared_owner?
  end

  def source_action_limit
    return unless source_device_id
    return if self.class.where(source_device_id: source_device_id).count < MAX_ACTIONS_PER_SOURCE

    errors.add(:base, 'maximum number of trigger actions reached')
  end

  def target_device_info
    value = target_device&.device_info
    parsed = value.is_a?(Hash) ? value : JSON.parse(value.presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, TypeError
    {}
  end
end
