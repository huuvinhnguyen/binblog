
class DevicesController < ApplicationController

  def index
    MqttWorker.perform_async('topic1')

    # @message = ""
    # client = MQTT::Client.new
    # client.host = 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com'
    # client.ssl = true
    # client.cert_file = path_to('cert.crt')
    # client.key_file  = path_to('private.key')
    # client.ca_file   = path_to('rootCA.pem')
    # client.connect()
    # # client.subscribe('topic1')
    # # client.get do |topic,message|
    # #   # Block is executed for every message received
    # #   @message = message
    # # end
    # # client.disconnect()
    #
    # # @queue = Queue.new
    # #
    # # conn_opts = {
    #   host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
    #   port: 8883,
    #   ssl: true,
    #   cert_file: path_to('cert.crt'),
    #   key_file: path_to('private.key'),
    #   ca_file: path_to('rootCA.pem'),
    #   # client_id: 'myClientID'
    # }
    #
    # Thread.new do
    #   MQTT::Client.connect(conn_opts) do |c|
    #     c.get("topic1") do |t, message|
    #       puts "#{t}: #{message}"
    #       @queue << message
    #     end
    #   end
    # end

     # message = @queue.pop
    # @message = "abc"
    # conn_opts = {
    #   host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
    #   port: 8883,
    #   ssl: true,
    #   cert_file: path_to('cert.crt'),
    #   key_file: path_to('private.key'),
    #   ca_file: path_to('rootCA.pem'),
    #   # client_id: 'myClientID'
    # }
    #
    # thread = Thread.new do
    #    MQTT::Client.connect(conn_opts) do |c|
    #     # The block will be called when you messages arrive to the topic
    #     c.get("topic1") do |t, message|
    #       puts "#{t}: #{message}"
    #       @message = message
    #       # render :index
    #     end
    #   end
    # end

    # thread.join

    # client = MQTT::Client.connect(
    #   host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
    #   port: 8883,
    #   ssl: true,
    #   cert_file: path_to('cert.crt'),
    #   key_file: path_to('private.key'),
    #   ca_file: path_to('rootCA.pem'),
    #   # client_id: 'myClientID'
    # )

    # client.publish('both_directions', '{"message": "helloFromRailsApp - from ruby"}')
    # client.subscribe('topic1')
    # Thread.new do
    #   topic, message = client.get
    # end

    # topic, message = client.get
    # client.get do |topic, message|
    #   @message = message
    #   # render :index
    # end
    # client.disconnect

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

    client.publish(topic, "{\"message\": \"#{message}\"}")
    client.disconnect()



    redirect_to devices_index_path


  end

  def mqtt_data
    render json: { mqtt_data: @queue.pop }
  end


  # app/controllers/devices_controller.rb
  # def mqtt_data
  #   topic = "example_topic"
  #   conn_opts = {
  #     host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
  #     port: 8883,
  #     ssl: true,
  #     cert_file: path_to('cert.crt'),
  #     key_file: path_to('private.key'),
  #     ca_file: path_to('rootCA.pem'),
  #     # client_id: 'myClientID'
  #   }
  #
  #
  #
  #   Thread.new do
  #     MQTT::Client.connect(conn_opts) do |c|
  #       c.get("topic1") do |t, message|
  #         puts "#{t}: #{message}"
  #         @mqtt_data = message
  #       end
  #     end
  #   end
  #
  #   render json: {mqtt_data: @mqtt_data}
  # end


  def show
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
