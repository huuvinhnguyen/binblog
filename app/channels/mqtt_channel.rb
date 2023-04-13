# app/channels/mqtt_channel.rb
class MqttChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'mqtt_channel'
  end
end

