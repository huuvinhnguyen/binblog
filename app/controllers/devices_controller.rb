require 'slack-notifier'
class DevicesController < ApplicationController
  before_action :initialize_mqtt_client
  def initialize_mqtt_client
    @client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
      # ssl: true,
      # cert_file: path_to('cert.crt'),
      # key_file: path_to('private.key'),
      # ca_file: path_to('rootCA.pem'),
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
      host: '103.9.77.155',
      port: 1883,
      # ssl: true,
      # cert_file: path_to('cert.crt'),
      # key_file: path_to('private.key'),
      # ca_file: path_to('rootCA.pem'),
      # client_id: 'myClientID'
    )
    puts "#topic: #{topic}"
    puts "#publish mess: #{message}"

    client.publish(topic, message, retain: true) if topic.present?
    client.disconnect()

    subscribe_topic topic

  end

  def connect_dht

    topic = session[:device_id] + "/dht"
    subscribe_topic topic
    puts "#topic: #{topic}"
  end

  def disconnect_mqtt

  end

  def switchon

    topic = session[:device_id] + "/switchon"
    message = "{ \"longlast\" : #{params[:value].to_i} }"

    client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
      # ssl: true,
      # cert_file: path_to('cert.crt'),
      # key_file: path_to('private.key'),
      # ca_file: path_to('rootCA.pem'),
      # client_id: 'myClientID'
    )

    client.publish(topic, message, retain: true) if topic.present?
    client.disconnect()

    mainTopic = session[:device_id]
    subscribe_topic mainTopic
  end

  def switchon_ab
    notifier = Slack::Notifier.new "https://hooks.slack.com/services/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" do
      defaults channel: "nongtrai",
               username: "khuonvien"
    end
    
    notifier.ping "Hello default"
  end

  def notify
    notifier = Slack::Notifier.new "https://hooks.slack.com/services/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" do
      defaults channel: "#nongtrai",
               username: "khuonvien"
    end
    
    # Gửi thông báo đến Slack và lưu phản hồi
    response = notifier.ping "Hello default"

    # In ra phản hồi để kiểm tra
    Rails.logger.info "Response: #{response.inspect}"

    # Kiểm tra trạng thái phản hồi từ Slack
    status = response.all? { |r| r.is_a?(Net::HTTPSuccess) } ? "success" : "failure"

    # Trả về phản hồi dưới dạng JSON
    render json: { message: "Notification sent to Slack", status: status }
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

    json_message = nil

    Thread.new do
      @client.subscribe(topic)
      @client.get(topic, timeout: 2) do |rs_topic, message|
        current_message = JSON.generate(message)
        if json_message.to_s != current_message.to_s
          ActionCable.server.broadcast('mqtt_channel', current_message)
          json_message = current_message
        end
      end
      @client.disconnect()
    end
  end

  def path_to(filename)
    Rails.root.join('config', filename).to_s
  end
end
