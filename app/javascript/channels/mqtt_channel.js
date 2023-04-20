// app/javascript/channels/mqtt_channel.js
import consumer from "./consumer"

consumer.subscriptions.create("MqttChannel", {
  connected() {
    console.log("Connected to MQTT channel")
  },

  disconnected() {
    console.log("Disconnected from MQTT channel")
  },

  received(data) {

    const mess1 = String(data);
    const dict = JSON.parse(mess1)
    console.log("Received MQTT data1111:", message)
    const mqttMessages = document.querySelector("#mqtt-messages")
    mqttMessages.insertAdjacentHTML("beforeend",`<p>${mess1}</p>`)
  }
})
