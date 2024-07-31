// app/javascript/channels/mqtt_channel.js
import consumer from "./consumer"

consumer.subscriptions.create("MqttChannel", {
  connected() {
    console.log("Connected to MQTT channel")
  },

  disconnected() {
    console.log("Disconnected from MQTT channel")
    this.unsubscribe();
  },

  received(data) {

    var connectionDiv = document.getElementById("connection-div");
    connectionDiv.style.display = "none";

    const string_data = JSON.parse(data.replace(/(?:\\[rn])+/g, ''));
    const message_hash = JSON.parse(string_data.replace(/(?:\\[rn])+/g, ''));

    console.log(typeof message_hash);
    console.log("message_hash:", message_hash)

    var switchDiv = document.getElementById("switch-div");
    switchDiv.style.display = "block";

    if (message_hash.update_at) {
      const timestamp = message_hash.update_at;
      const formattedDateTime = formatDateTime(timestamp);
      console.log(formattedDateTime);

      const lastActiveMessageDiv = document.getElementById('last-active-message-div');
      lastActiveMessageDiv.value = formattedDateTime;
    }

    var temperatureDiv = document.getElementById("dht-value-temperature");
    temperatureDiv.textContent = message_hash.tem;
    var humidityDiv = document.getElementById("dht-value-humidity");
    humidityDiv.textContent = message_hash.hum;

  }
})

function formatDateTime(timestamp) {
  const date = new Date(timestamp * 1000);

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  const seconds = String(date.getSeconds()).padStart(2, '0');

  const formattedDateTime = `${day}/${month}/${year} ${hours}:${minutes}:${seconds}`;
  return formattedDateTime;
}
