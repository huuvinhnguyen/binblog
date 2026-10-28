require 'uri'
require 'mqtt'

# Load before Rails and all verification commands, including schema tasks.
module SwitchVerificationNoMqtt
  def connect(*)
    raise 'Live MQTT connections are disabled during Switch verification'
  end
end

MQTT::Client.prepend(SwitchVerificationNoMqtt)
