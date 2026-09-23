# Configuration only: this service must never invoke MQTT or BuzzerTestService.
class BuzzerLinks
  NotFoundError = Class.new(StandardError)
  ValidationError = Class.new(StandardError)
  COMMAND_FIELDS = %w[chip_id relay_index longlast switch_value sent_time].freeze

  def initialize(buzzer:, user:)
    @buzzer = buzzer
    @devices = user.devices_for_current_user
  end

  def available_pirs
    buzzers = @devices.where(device_type: 'buzzer').index_by(&:chip_id)
    @devices.where(device_type: 'pir').order(:id).map do |pir|
      trigger = parsed_trigger(pir)
      target = buzzers[trigger['chip_id']]
      {
        id: pir.id, name: pir.name, chip_id: pir.chip_id,
        linked_buzzer: target && { id: target.id, name: target.name },
        requires_confirmation: configured?(pir) && trigger['chip_id'] != @buzzer.chip_id
      }
    end
  end

  def link(pir_id:, relay_index:, longlast:)
    unless pir_id.is_a?(Integer) && pir_id.positive?
      raise ValidationError, 'pir_id must be a positive integer.'
    end
    pir = accessible_pir(pir_id)
    unless relay_index.is_a?(Integer) && relay_index >= 0
      raise ValidationError, 'relay_index must be an integer greater than or equal to 0.'
    end
    unless longlast.is_a?(Integer) && longlast.between?(100, 10_000)
      raise ValidationError, 'longlast must be an integer between 100 and 10000 ms.'
    end

    trigger = { chip_id: @buzzer.chip_id, relay_index: relay_index, longlast: longlast }
    pir.with_lock { pir.update!(trigger: trigger.to_json) }
    { id: pir.id, name: pir.name, chip_id: pir.chip_id, relay_index: relay_index, longlast: longlast }
  end

  def unlink(pir_id:)
    # Path IDs are strings. Reject partial numeric IDs rather than letting AR coerce them.
    raise NotFoundError, 'PIR device not found' unless pir_id.to_s.match?(/\A[1-9]\d*\z/)

    pir = accessible_pir(pir_id)
    pir.with_lock do
      trigger = parsed_trigger(pir)
      if trigger['chip_id'] == @buzzer.chip_id
        pir.update!(trigger: trigger.except(*COMMAND_FIELDS).to_json)
      end
    end
    pir.id
  end

  private

  def accessible_pir(id)
    @devices.find_by(id: id, device_type: 'pir') || raise(NotFoundError, 'PIR device not found')
  end

  def configured?(pir)
    JSON.parse(pir.trigger.presence || '{}').present?
  rescue JSON::ParserError, TypeError
    true
  end

  def parsed_trigger(pir)
    value = JSON.parse(pir.trigger.presence || '{}')
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError, TypeError
    {}
  end
end
