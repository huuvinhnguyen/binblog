module SwitchApi
  class Configuration
    MAX_RELAYS = 32
    MIN_DURATION_MS = 1_000
    MAX_DURATION_MS = 86_400_000
    attr_reader :relays

    def initialize(device)
      info = JSON.parse(device.device_info.to_s)
      @relays = info['relays'] if info.is_a?(Hash)
      unless @relays.is_a?(Array) && @relays.length <= MAX_RELAYS && @relays.all? { |relay| relay.is_a?(Hash) }
        raise Error.new('invalid_configuration')
      end
    rescue JSON::ParserError, TypeError
      raise Error.new('invalid_configuration')
    end

    def relay!(value)
      index = if value.is_a?(String) && /\A(?:0|[1-9][0-9]{0,2})\z/.match?(value)
                value.to_i
              elsif value.is_a?(Integer)
                value
              end
      raise Error.new('invalid_relay_index') unless index && index >= 0 && index < relays.length

      index
    end

    def self.duration?(value)
      value.is_a?(Integer) && value.between?(MIN_DURATION_MS, MAX_DURATION_MS) && (value % 1000).zero?
    end
  end
end
