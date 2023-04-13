App.mqtt = App.cable.subscriptions.create "MqttChannel",
  received: (data) ->
    $("#mqtt-messages").append("<p>#{data.message}</p>")

