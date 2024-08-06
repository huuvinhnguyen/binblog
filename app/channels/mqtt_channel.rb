# app/channels/mqtt_channel.rb
class MqttChannel < ApplicationCable::Channel
  def subscribed
    @subscription = stream_from 'mqtt_channel'
  end

  def unsubscribed
    # hủy kết nối với MQTT tại đây
    puts "Disconnected from MQTT"

  end
end

