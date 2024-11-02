// app/javascript/channels/mqtt_channel.js
import consumer from "./consumer"
// import { createConsumer } from "@rails/actioncable";
import { createVerGauge, getTempColor, createRadGauge, getHumColor  }  from "gauges";


consumer.subscriptions.create("MqttChannel", {
  connected() {
    console.log("Connected to MQTT channel")
  },

  disconnected() {
    console.log("Disconnected from MQTT channel")
    this.unsubscribe();
  },

  received(data) {
   
    const string_data = JSON.parse(data.replace(/(?:\\[rn])+/g, ''));
    const message_hash = JSON.parse(string_data.replace(/(?:\\[rn])+/g, ''));
    
    if (message_hash.device_type === "switch") {

      const toggleSwitch = document.getElementById("toggle-switch");

      // Update toggle switch based on switch_value
      if (message_hash.switch_value === 1) {
        toggleSwitch.checked = true;
      } else if (message_hash.switch_value === 0) {
        toggleSwitch.checked = false;
      }

      // Cập nhật last active từ update_at
      const lastActiveElement = document.getElementById("last-active");
      if (lastActiveElement && message_hash.update_at) {
        const formattedDateTime = formatDateTime(message_hash.update_at);
        lastActiveElement.innerText = formattedDateTime; // Hiển thị thời gian ở dạng văn bản
      } else {
        console.error("last-active element or update_at not found");
      }

      if (message_hash.reminder) {
        const reminderStartTime = document.getElementById("reminder-start-time");
        const reminderDuration = document.getElementById("reminder-duration");
        const reminderRepeatType = document.getElementById("reminder-repeat-type");

    
        // Kiểm tra phần tử trước khi gán giá trị
        if (reminderStartTime) {
          
          const currentDate = new Date(message_hash.reminder.start_time);
          const year = currentDate.getFullYear();
          const month = String(currentDate.getMonth() + 1).padStart(2, '0');
          const day = String(currentDate.getDate()).padStart(2, '0');
          const hours = String(currentDate.getHours()).padStart(2, '0');
          const minutes = String(currentDate.getMinutes()).padStart(2, '0');
          reminderStartTime.value = `${year}-${month}-${day}T${hours}:${minutes}`; 

        } else {
          console.error("reminder-start-time element not found");
        }
    
        if (reminderDuration) {
          console.log("Duration:", message_hash.reminder.duration);
          reminderDuration.value = message_hash.reminder.duration / 60 || "";
        } else {
          console.error("reminder-duration element not found");
        }

        // Cập nhật reminderRepeatType
        if (reminderRepeatType) {
          const repeatTypeValue = message_hash.reminder.repeat_type || 'none';
          reminderRepeatType.value = repeatTypeValue;
          console.log("Repeat Type:", repeatTypeValue);
        } else {
          console.error("reminder-repeat-type element not found");
        }
      }

    }

    var connectionDiv = document.getElementById("connection-div");
    connectionDiv.style.display = "none";

    console.log(typeof message_hash);
    console.log("message_hash:", message_hash)


    if(message_hash.sen == "dht11") {
      var tempGauge = createVerGauge('temp', -20, 60, ' °C').setVal(0).setColor(getTempColor(0));
      tempGauge.setVal(message_hash.tem).setColor(getTempColor(message_hash.tem));

      var humGauge = createRadGauge('hum', 0, 100, '%').setVal(80).setColor(getHumColor(80));
      humGauge.setVal(message_hash.hum).setColor(getHumColor(message_hash.hum));

    } else {

      var switchDiv = document.getElementById("switch-div");
      switchDiv.style.display = "block";

      if (message_hash.update_at) {
        const timestamp = message_hash.update_at;
        const formattedDateTime = formatDateTime(timestamp);
        console.log(formattedDateTime);

        const lastActiveMessageDiv = document.getElementById('last-active-message-div');
        lastActiveMessageDiv.value = formattedDateTime;
      }
    }
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
