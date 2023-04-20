
class DevicesController < ApplicationController

  def index
    # MqttWorker.perform_async('topic1')

    Thread.new do
      client = MQTT::Client.connect(
        host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
        port: 8883,
        ssl: true,
        cert_file: path_to('cert.crt'),
        key_file: path_to('private.key'),
        ca_file: path_to('rootCA.pem'),
        client_id: 'myClientID',
        keep_alive: 30
      )

      client.get('topic', timeout: 2) do |topic, message|

        # json_parse = JSON.parse(message)
        # puts "#{topic}: #{json_parse}"
        json_message = JSON.generate(message)
        ActionCable.server.broadcast('mqtt_channel', json_message)

      end
      client.disconnect()
    end
  end

  def publish

    topic = params[:topic]
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

    client.publish(topic, "{\"message\": \"#{message}\"}") if topic.present?
    client.disconnect()
    redirect_to devices_index_path
  end

  def latest_data message
    puts "message: #{message}"
    render json: { abc: message} if message.present?
  end

  def mqtt_data
    render json: { mqtt_data: @queue.pop }
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

  def path_to(filename)
    Rails.root.join('config', filename).to_s
  end
end
