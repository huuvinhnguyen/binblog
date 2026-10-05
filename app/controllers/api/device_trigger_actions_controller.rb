module Api
  class DeviceTriggerActionsController < ApplicationController
    include Api::DeviceApiAuthentication

    TargetNotFound = Class.new(StandardError)

    before_action :authenticate_device_api_user!
    before_action :require_feature
    before_action :load_source
    before_action :load_action, only: %i[update destroy]

    def index
      resolver = DeviceTriggerConfigurationResolver.new(source_device: @source)
      actions = if resolver.mode == 'legacy'
                  [serialize_legacy_action(resolver)]
                elsif resolver.mode == 'actions'
                  @source.trigger_actions.runtime_order.includes(:target_device).map { |action| serialize_action(action) }
                else
                  []
                end
      render json: {
        status: 'success',
        configuration_mode: resolver.mode,
        source_device: serialize_source,
        actions: actions
      }
    end

    def targets
      render json: {
        status: 'success',
        targets: eligible_targets.order(:id).map do |target|
          duration_range = DeviceTriggerAction::DURATION_RANGES.fetch(target.device_type)
          {
            id: target.id,
            chip_id: target.chip_id,
            name: target.name,
            device_type: target.device_type,
            relay_indexes: relay_indexes(target),
            duration_ms: { minimum: duration_range.begin, maximum: duration_range.end }
          }
        end
      }
    end

    def create
      result = nil
      @source.with_lock do
        resolver = DeviceTriggerConfigurationResolver.new(source_device: @source)
        if %w[legacy invalid_legacy].include?(resolver.mode)
          return render_conflict('legacy_configuration_requires_reconciliation')
        end

        attributes = action_attributes
        attributes[:position] = (@source.trigger_actions.maximum(:position) || -1) + 1
        result = @source.trigger_actions.create!(attributes)
      end
      render json: { status: 'success', action: serialize_action(result) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render_model_error(e.record)
    rescue ActiveRecord::RecordNotUnique
      render_conflict('duplicate_action')
    rescue TargetNotFound
      render_not_found('target_not_found', 'Target device not found')
    end

    def update
      @source.with_lock { @action.update!(action_attributes.except(:position)) }
      render json: { status: 'success', action: serialize_action(@action.reload) }
    rescue ActiveRecord::RecordInvalid => e
      render_model_error(e.record)
    rescue ActiveRecord::RecordNotUnique
      render_conflict('duplicate_action')
    rescue TargetNotFound
      render_not_found('target_not_found', 'Target device not found')
    end

    def destroy
      @source.with_lock { @action.destroy! }
      render json: { status: 'success', action_id: @action.id }
    end

    def order
      ids = params[:action_ids]
      return render_validation('invalid_order', 'action_ids must be an array of action IDs') unless ids.is_a?(Array)

      @source.with_lock do
        actions = @source.trigger_actions.lock.to_a
        normalized_ids = ids.map { |id| strict_positive_id(id) }
        unless normalized_ids.all? && normalized_ids.sort == actions.map(&:id).sort && normalized_ids.uniq.length == normalized_ids.length
          return render_validation('invalid_order', 'action_ids must contain every action exactly once')
        end

        normalized_ids.each_with_index do |id, index|
          @source.trigger_actions.where(id: id).update_all(position: index, updated_at: Time.current)
        end
      end
      render json: {
        status: 'success',
        actions: @source.trigger_actions.runtime_order.map { |action| serialize_action(action) }
      }
    end

    def migrate_legacy
      result = DeviceTriggerLegacyMigrator.new(source_device: @source, target_scope: accessible_devices).call
      render json: {
        status: 'success',
        migrated: result.migrated,
        mode: 'actions',
        action: serialize_action(result.action)
      }
    rescue DeviceTriggerLegacyMigrator::NotFoundError
      render_not_found('target_not_found', 'Target device not found')
    rescue DeviceTriggerLegacyMigrator::InvalidConfiguration => e
      render_conflict('legacy_configuration_requires_reconciliation', e.message)
    rescue DeviceTriggerLegacyMigrator::ConflictError
      render_conflict('configuration_mode_conflict')
    rescue ActiveRecord::RecordInvalid => e
      render_model_error(e.record)
    rescue ActiveRecord::RecordNotUnique
      render_conflict('duplicate_action')
    end

    private

    def require_feature
      return if DeviceTriggerFeature.enabled?

      render json: { status: 'error', code: 'feature_disabled', message: 'Trigger actions are disabled' },
             status: :service_unavailable
    end

    def load_source
      return if performed?

      @source = accessible_devices.find_by(chip_id: params[:chip_id], device_type: 'pir')
      render_not_found('source_not_found', 'PIR device not found') unless @source
    end

    def load_action
      return if performed?

      @action = @source.trigger_actions.find_by(id: params[:id])
      render_not_found('action_not_found', 'Trigger action not found') unless @action
    end

    def accessible_devices
      current_user.devices_for_current_user
    end

    def action_attributes
      permitted = params.permit(:target_device_id, :action_type, :relay_index, :duration_ms, :delay_ms, :enabled)
      creating = @action.nil?
      attributes = {}

      if permitted.key?(:target_device_id) || creating
        target_id = strict_positive_id(permitted[:target_device_id])
        target = eligible_targets.find_by(id: target_id)
        raise TargetNotFound unless target
        attributes[:target_device] = target
      end
      attributes[:action_type] = permitted.key?(:action_type) ? permitted[:action_type] : 'relay_pulse' if permitted.key?(:action_type) || creating
      attributes[:relay_index] = strict_integer(permitted[:relay_index]) if permitted.key?(:relay_index) || creating
      attributes[:duration_ms] = strict_integer(permitted[:duration_ms]) if permitted.key?(:duration_ms) || creating
      attributes[:delay_ms] = permitted.key?(:delay_ms) ? strict_integer(permitted[:delay_ms]) : 0 if permitted.key?(:delay_ms) || creating
      attributes[:enabled] = permitted.key?(:enabled) ? strict_boolean(permitted[:enabled]) : true if permitted.key?(:enabled) || creating
      attributes
    end

    def strict_integer(value)
      return value if value.is_a?(Integer)

      nil
    end

    def strict_positive_id(value)
      result = value.is_a?(String) && value.match?(/\A\d+\z/) ? value.to_i : strict_integer(value)
      result if result&.positive?
    end

    def strict_boolean(value)
      value if value == true || value == false
    end

    def relay_indexes(device)
      DeviceTriggerAction.new(target_device: device).available_relay_indexes
    end

    def serialize_source
      { id: @source.id, name: @source.name, chip_id: @source.chip_id }
    end

    def serialize_action(action)
      target = action.target_device if eligible_target_ids.include?(action.target_device_id)
      {
        id: action.id,
        origin: 'persisted',
        action_type: action.action_type,
        target: serialize_target(target),
        relay_index: action.relay_index,
        duration_ms: action.duration_ms,
        delay_ms: action.delay_ms,
        enabled: action.enabled,
        position: action.position
      }
    end

    def eligible_targets
      @eligible_targets ||= DeviceTriggerAction.eligible_target_scope(
        source_device: @source,
        scope: accessible_devices
      )
    end

    def eligible_target_ids
      @eligible_target_ids ||= eligible_targets.pluck(:id)
    end

    def serialize_target(target)
      return nil unless target

      {
        id: target.id,
        name: target.name,
        chip_id: target.chip_id,
        device_type: target.device_type
      }
    end

    def serialize_legacy_action(resolver)
      payload = resolver.legacy_payload
      target = eligible_targets.find_by(chip_id: payload['chip_id'])

      {
        id: nil,
        origin: 'legacy',
        action_type: 'relay_pulse',
        target: serialize_target(target),
        relay_index: strict_integer(payload['relay_index']),
        duration_ms: strict_integer(payload['longlast']),
        delay_ms: 0,
        enabled: true,
        position: 0
      }
    end

    def render_model_error(record)
      messages = record.errors.full_messages
      if record.errors.details[:target_device_id].any? { |detail| detail[:error] == :taken }
        return render_conflict('duplicate_action')
      end

      if record.errors[:base].any? { |message| message.include?('maximum') }
        return render_conflict('action_limit_reached')
      end
      return render_not_found('target_not_found', 'Target device not found') if record.errors[:target_device].any?

      code = if record.errors[:action_type].any?
               'invalid_action_type'
             elsif record.errors[:relay_index].any?
               'invalid_relay_index'
             elsif record.errors[:duration_ms].any?
               'invalid_duration'
             elsif record.errors[:delay_ms].any?
               'invalid_delay'
             elsif record.errors[:enabled].any?
               'invalid_enabled'
             else
               'invalid_action'
             end
      render_validation(code, messages.to_sentence)
    end

    def render_validation(code, message)
      render json: { status: 'error', code: code, message: message }, status: :unprocessable_entity
    end

    def render_conflict(code, message = code.humanize)
      render json: { status: 'error', code: code, message: message }, status: :conflict
    end

    def render_not_found(code, message)
      render json: { status: 'error', code: code, message: message }, status: :not_found
    end
  end
end
