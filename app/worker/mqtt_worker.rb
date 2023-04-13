# app/workers/mqtt_worker.rb
class MqttWorker
  include Sidekiq::Worker

  def perform(topic)

    conn_opts = {
      host: 'a2eoz3l3pmara3-ats.iot.ap-southeast-1.amazonaws.com',
      port: 8883,
      ssl: true,
      cert_file: path_to('cert.crt'),
      key_file: path_to('private.key'),
      ca_file: path_to('rootCA.pem'),
      # client_id: 'myClientID'
    }

    Thread.new do
      MQTT::Client.connect(conn_opts) do |c|
        c.get(topic) do |t, message|
          # Gửi tin nhắn đến client qua Websocket
          # ActionCable.server.broadcast 'mqtt_channel', message: message

          ActionCable.server.broadcast \
  "mqtt_channel", { topic: topic, body: message }
          puts "#{t}: #{message}"

        end
      end
    end
  end
  private

  def path_to(filename)
    Rails.root.join('config', filename).to_s
  end
end

