
class DevicesController < ApplicationController
  before_action :initialize_mqtt_client
  def initialize_mqtt_client
    @client = MQTT::Client.connect(
      host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
      port: 8883,
      ssl: true,
      cert_file: path_to('cert.crt'),
      key_file: path_to('private.key'),
      ca_file: path_to('rootCA.pem'),
      keep_alive: 30
    )

  end

  def index
  end

  def connect
    session[:device_id] = params[:deviceid]
    topic = params[:deviceid]
    subscribe_topic topic
  end

  def publish


    topic = session[:device_id] + "/switch"
    message = params[:message]


    client = MQTT::Client.connect(
      host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
      port: 8883,
      ssl: true,
      cert_file: path_to('cert.crt'),
      key_file: path_to('private.key'),
      ca_file: path_to('rootCA.pem'),
      # client_id: 'myClientID'
    )
    puts "#topic: #{topic}"
    puts "#publish mess: #{message}"


    client.publish(topic, message, retain: true) if topic.present?
    client.disconnect()

    subscribe_topic topic

  end

  def switchon

    topic = session[:device_id] + "/switchon"
    message = "{ \"longlast\" : #{params[:value].to_i} }"


    client = MQTT::Client.connect(
      host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
      port: 8883,
      ssl: true,
      cert_file: path_to('cert.crt'),
      key_file: path_to('private.key'),
      ca_file: path_to('rootCA.pem'),
      # client_id: 'myClientID'
    )
    puts "#topic: #{topic}"
    puts "#publish mess: #{message}"


    client.publish(topic, message, retain: true) if topic.present?
    client.disconnect()

    mainTopic = session[:device_id]
    subscribe_topic mainTopic
  end
 

  def new
  end

  def create
  end

  def edit
  end

  def update
  end

  def destroy
  end

  private

  def subscribe_topic topic
    Thread.new do
      @client.subscribe(topic)
      @client.get(topic, timeout: 2) do |rs_topic, message|

        json_message = JSON.generate(message)
        ActionCable.server.broadcast('mqtt_channel', json_message)
        @client.disconnect()
        # ActionCable.server.remote_connections.where(current_user: User.find(1)).disconnect

      end
      @client.disconnect()
      # ActionCable.server.remote_connections.where(current_user: User.find(1)).disconnect
    end

  end

  def path_to(filename)
    Rails.root.join('config', filename).to_s
  end
end
