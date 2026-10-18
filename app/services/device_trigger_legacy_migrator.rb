class DeviceTriggerLegacyMigrator
  ConflictError = Class.new(StandardError)
  InvalidConfiguration = Class.new(StandardError)
  NotFoundError = Class.new(StandardError)

  Result = Struct.new(:action, :migrated, keyword_init: true)

  def initialize(source_device:, target_scope:)
    @source_device = source_device
    @target_scope = target_scope
  end

  def call
    @source_device.with_lock do
      resolver = DeviceTriggerConfigurationResolver.new(source_device: @source_device)
      payload = resolver.legacy_payload
      raise InvalidConfiguration, 'Legacy trigger configuration is invalid' unless payload

      target = DeviceTriggerAction.eligible_target_scope(
        source_device: @source_device,
        scope: @target_scope
      ).find_by(chip_id: payload['chip_id'])
      raise NotFoundError, 'Target device not found' unless target

      attributes = {
        target_device: target,
        action_type: 'relay_pulse',
        relay_index: strict_integer(payload['relay_index'], 'relay_index'),
        duration_ms: strict_integer(payload['longlast'], 'longlast'),
        delay_ms: 0,
        enabled: true,
        position: 0
      }
      existing = @source_device.trigger_actions.to_a
      if existing.any?
        matching = existing.one? && matches?(existing.first, attributes)
        raise ConflictError, 'Trigger actions already exist' unless matching

        return Result.new(action: existing.first, migrated: false)
      end

      Result.new(action: @source_device.trigger_actions.create!(attributes), migrated: true)
    end
  end

  private

  def strict_integer(value, field)
    return value if value.is_a?(Integer)

    raise InvalidConfiguration, "Legacy #{field} must be an integer"
  end

  def matches?(action, attributes)
    attributes.all? { |key, value| action.public_send(key) == value }
  end
end
