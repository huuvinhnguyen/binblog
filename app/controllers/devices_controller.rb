class DevicesController < ApplicationController
  before_action :authenticate_user!, except: [:notify]
  # before_action :initialize_mqtt_client
  skip_before_action :verify_authenticity_token, only: [:notify]
  before_action :set_device, only: [:show]

  def initialize_mqtt_client  
    @client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
    )

  end

  def index
    @devices = Device.all

  end

  def connect
    # session[:device_id] = params[:deviceid]
    # topic = params[:deviceid]
    # subscribe_topic topic

    @device = Device.find_by(chip_id: params[:deviceid])
    if @device
      # Perform connection logic here
      redirect_to device_path(@device), notice: "Connected successfully."

      
    else
      flash[:alert] = "Device not found."
      render :connect # Re-render the form
    end

  end

  def publish

    topic = session[:device_id] + "/switch"
    message = params[:message]

    client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
    )

    client.publish(topic, message, retain: false) if topic.present?
    client.disconnect()

    subscribe_topic topic

  end

  def connect_dht

    topic = session[:device_id] + "/dht"
    subscribe_topic topic
  end

  def switchon
    # initialize_mqtt_client

    # Đường dẫn đến mã nguồn gốc
    # https://github.com/huuvinhnguyen/kvxduino/pull/4/files#diff-72403d98b2706b2110d12c0b98c93d5febf832c7ca1b2ab17fc2935f88943b45
  
    topic = "#{params[:chip_id]}/switchon"
    message_hash = {}
    message_hash["reminder"] = {} if params[:start_time].present?
  
    # Kiểm tra và thêm các tham số vào hash
    message_hash["reminder"]["start_time"] = params[:start_time].to_s if params[:start_time].present?
    message_hash["reminder"]["duration"] = params[:duration].to_i * 60000 if params[:duration].present?
    message_hash["reminder"]["repeat_type"] = params[:repeat_type].to_s if params[:repeat_type].present?
    message_hash["longlast"] = params[:longlast].to_i * 1000 if params[:longlast].present?
    message_hash["switch_value"] = params[:switch_value].to_i if params[:switch_value].present?
    # Chuyển đổi hash thành JSON
    message = message_hash.to_json
  
    client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883
    )
  
    client.publish(topic, message, retain: false) if topic.present?
    client.disconnect()
  
  end

  def switchon_ab
    notifier = Slack::Notifier.new "https://abc.com" do
      defaults channel: "general",
               username: "khuonvien"
    end
    
    notifier.ping "Hello default"
  end

  def notify 
    # Parse JSON từ request body
    json_data = JSON.parse(request.body.read)
    handle_device_init(request.body.read) 

    chip_id = json_data['id']
    message = json_data['message']
    # time = Time.at(json_data['time'])
    time = Time.current
    model = json_data['model']
    device = Device.find_by(chip_id: chip_id)

    slack_message = "Received data from ESP32:\n" \
                      "Chip ID: #{chip_id}\n" \
                      "Message: #{message}\n" \
                      "Time: #{time}\n" \
                      "Model: #{model}"

    users = device.users
    notify_users(users, slack_message) 

  end
  
  def show

    initialize_mqtt_client
    topic = @device.chip_id.to_s
    subscribe_topic topic
    message = { "action": "ping" }.to_json
    pingTopic = topic + "/ping"
    @client.publish(pingTopic, message, retain: false) if pingTopic.present?
    # mosquitto_pub -h 103.9.77.155 -p 1883 -t "3197470/switchon" -m '{ "switch_value": 1 }' 
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

  def notify_users(users, message)
    if users.present?
      responses = users.map do |user|
        SlackNotificationService.new(user.webhook_url, message).send_notification
      end

      status = responses.all? ? "success" : "failure"
    else
      Rails.logger.error "No managers found for this notification"
      status = "failure"
    end

    render json: { message: "Notification sent to Slack", status: status }
  end

  def subscribe_topic topic

    json_message = nil
    @client.unsubscribed unless @client.connected?
    @client.subscribe(topic) unless @client.connected?

    Thread.new do
      @client.get(topic, timeout: 2) do |rs_topic, message|
        current_message = JSON.generate(message)
        if json_message.to_s != current_message.to_s
          ActionCable.server.broadcast('mqtt_channel', current_message)
          puts "$$$$$$$$$$$$$$$$$"
          json_message = current_message
          handle_device_init(JSON.parse(json_message))
        end
      end
      # client.disconnect()

    end
  end

  def handle_device_init(message)
    begin
      parsed_data = message.is_a?(String) ? JSON.parse(message) : message

      chip_id = parsed_data['id']
      is_payment = parsed_data['is_payment']
      name = parsed_data['name']
      return if chip_id.nil? || chip_id.to_s.empty?
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

  def set_device
    @device = Device.find(params[:id])
  end
end
