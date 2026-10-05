class DeviceTriggerConfigurationResolver
  Relationship = Struct.new(
    :source_device, :target_device, :relay_index, :duration_ms, :origin, :action, keyword_init: true
  )

  MODES = %w[none legacy actions invalid_legacy].freeze

  attr_reader :source_device

  def initialize(source_device:)
    @source_device = source_device
  end

  def mode
    return legacy_payload.present? ? 'legacy' : 'none' unless source_device.device_type == 'pir'
    return 'actions' if actions_present?
    return 'none' if raw_trigger.blank?
    return 'none' if parse_trigger == {}

    legacy_payload.present? ? 'legacy' : 'invalid_legacy'
  end

  def runtime_actions
    return DeviceTriggerAction.none unless mode == 'actions'

    source_device.trigger_actions.usable.runtime_order
  end

  def legacy_payload
    parsed = parse_trigger
    return nil unless parsed.is_a?(Hash) && parsed['chip_id'].present?

    parsed
  end

  def legacy_relationship(target_scope: Device.all)
    payload = legacy_payload
    return unless payload

    target = target_scope.find_by(chip_id: payload['chip_id'])
    Relationship.new(
      source_device: source_device,
      target_device: target,
      relay_index: payload['relay_index'],
      duration_ms: payload['longlast'],
      origin: 'legacy',
      action: nil
    )
  end

  def relationships
    if mode == 'actions'
      actions = if source_device.association(:trigger_actions).loaded?
                  source_device.trigger_actions.select(&:enabled?).sort_by { |action| [action.position, action.id] }
                else
                  source_device.trigger_actions.usable.runtime_order.includes(:target_device).to_a
                end
      actions.map do |action|
        Relationship.new(
          source_device: source_device,
          target_device: action.target_device,
          relay_index: action.relay_index,
          duration_ms: action.duration_ms,
          origin: 'actions',
          action: action
        )
      end
    else
      relationship = legacy_relationship
      relationship ? [relationship] : []
    end
  end

  def self.relationships_for_target(target_device:, source_scope:)
    source_scope.where(device_type: 'pir').includes(trigger_actions: :target_device).flat_map do |source|
      resolver = new(source_device: source)
      if resolver.mode == 'actions'
        resolver.relationships.select { |relationship| relationship.target_device&.id == target_device.id }
      elsif resolver.legacy_payload&.fetch('chip_id', nil) == target_device.chip_id
        [Relationship.new(
          source_device: source,
          target_device: target_device,
          relay_index: resolver.legacy_payload['relay_index'],
          duration_ms: resolver.legacy_payload['longlast'],
          origin: 'legacy',
          action: nil
        )]
      else
        []
      end
    end
  end

  private

  def raw_trigger
    source_device.trigger
  end

  def actions_present?
    association = source_device.association(:trigger_actions)
    association.loaded? ? source_device.trigger_actions.any? : source_device.trigger_actions.exists?
  end

  def parse_trigger
    value = raw_trigger
    return value if value.is_a?(Hash)

    parsed = JSON.parse(value.presence || '{}')
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError, TypeError
    nil
  end
end
