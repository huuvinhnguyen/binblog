class DevicesController < ApplicationController
  before_action :initialize_mqtt_client
  skip_before_action :verify_authenticity_token, only: [:notify]

  def initialize_mqtt_client  
    @client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
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
    )

    client.publish(topic, message, retain: true) if topic.present?
    client.disconnect()

    subscribe_topic topic

  end

  def connect_dht

    topic = session[:device_id] + "/dht"
    subscribe_topic topic
  end

  def switchon

    topic = session[:device_id] + "/switchon"
    message = "{ \"longlast\" : #{params[:value].to_i} }"

    client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883
    )

    client.publish(topic, message, retain: true) if topic.present?
    client.disconnect()

    mainTopic = session[:device_id]
    subscribe_topic mainTopic
  end

  def switchon_ab
    notifier = Slack::Notifier.new "https://abc.com" do
      defaults channel: "general",
               username: "khuonvien"
    end
    
    notifier.ping "Hello default"
  end

  def notify
    begin
      json_data = JSON.parse(request.body.read)
      handle_device_init(request.body.read)
      chip_id = json_data['id']
      message = json_data['message']
      time = Time.at(json_data['time'])
      model = json_data['model']

      # Cấu hình Slack Notifier
      notifier = Slack::Notifier.new "https://abc.com" do
        defaults channel: "general",
                 username: "khuonvien"
      end

      # Tạo thông báo
      slack_message = "Received data from ESP32:\n" +
                      "Chip ID: #{chip_id}\n" +
                      "Message: #{message}\n" +
                      "Time: #{time}\n" +
                      "Model: #{model}"

      # Gửi thông báo đến Slack và lưu phản hồi
      response = notifier.ping slack_message

      # Kiểm tra trạng thái phản hồi từ Slack
      # status = response.is_a?(Net::HTTPSuccess) ? "success" : "failure"
      status = response.all? { |r| r.is_a?(Net::HTTPSuccess) } ? "success" : "failure"

      # Trả về phản hồi dưới dạng JSON
      render json: { message: "Notification sent to Slack", status: status }
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse JSON: #{e.message}")
      render json: { message: "Invalid JSON", status: "failure" }, status: :bad_request
    end
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
          puts "#handle device"
          handle_device_init(JSON.parse(json_message))

        end
      end
      @client.disconnect()
    end
  end

  def handle_device_init(message)
    begin
      parsed_data = message.is_a?(String) ? JSON.parse(message) : message

      chip_id = parsed_data['id']
      is_payment = parsed_data['is_payment']
      name = parsed_data['name']
      return if chip_id.nil? || chip_id.empty?
      device = Device.find_or_create_by(chip_id: chip_id) do |device|
        device.name = name
      end

      # Rails.logger.info "Device #{device.chip_id} stored in the database."
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse init message: #{e.message}"
    end
  end

  def path_to(filename)
    Rails.root.join('config', filename).to_s
  end
end
