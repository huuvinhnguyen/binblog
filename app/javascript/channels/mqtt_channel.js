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

  received(message_hash) {

    const currentDeviceId = document.getElementById('switch-div').getAttribute('data-chip-id');
    console.log(currentDeviceId);
    if (message_hash.device_id === currentDeviceId) {

    } else {
      return;
    }

    let relayIndex = getCurrentRelayIndex();

    document.querySelectorAll('[id^="relay-tab-"]').forEach(tab => {
      tab.addEventListener("shown.bs.tab", function() {
        relayIndex = getCurrentRelayIndex();
      });
    });
   
    document.querySelectorAll('[id^="toggle-switch-"]').forEach((toggleSwitch) => {
      if (message_hash.relays[relayIndex].switch_value === 1) {
        toggleSwitch.checked = true;
      } else if (message_hash.relays[relayIndex].switch_value === 0) {
        toggleSwitch.checked = false;
      }
    });

    document.querySelectorAll('[id^="toggle-reminders-active"]').forEach((toggleSwitch) => {
      if (message_hash.relays[relayIndex].switch_value === 1) {
        toggleSwitch.checked = true;
      } else if (message_hash.relays[relayIndex].switch_value === 0) {
        toggleSwitch.checked = false;
      }
    });
    
    if (message_hash.device_type === "switch") {
      

      // const toggleSwitch = document.getElementById("toggle-switch");

      // // Update toggle switch based on switch_value
      // if (message_hash.switch_value === 1) {
      //   toggleSwitch.checked = true;
      // } else if (message_hash.switch_value === 0) {
      //   toggleSwitch.checked = false;
      // }

      // Cập nhật last active từ update_at
      const lastActiveElement = document.getElementById("last-active");
      if (lastActiveElement && message_hash.update_at) {
        const formattedDateTime = formatDateTime(message_hash.update_at);
        lastActiveElement.innerText = formattedDateTime; // Hiển thị thời gian ở dạng văn bản
      } else {
        console.error("last-active element or update_at not found");
      }

      if (message_hash.relays[relayIndex].reminders && Array.isArray(message_hash.relays[relayIndex].reminders)) {
        const remindersList = document.getElementById(`reminders-list-${relayIndex}`);
  
        if (remindersList) {
          // Clear the current reminders list
          remindersList.innerHTML = `
              <div style="display: flex; justify-content: space-between; align-items: center;">
              <h3>Danh sách Hẹn giờ</h3>
                <div class="form-check form-switch large-toggle">
                  <input 
                    type="checkbox" 
                    id="toggle-reminders-active-${relayIndex}" 
                    class="form-check-input" 
                    data-chip-id="${message_hash.device_id}" 
                    data-relay-index="${relayIndex}" 
                    ${message_hash.relays[relayIndex].is_reminders_active ? "checked" : ""}
                  >
                </div>
              </div>
                <table class="table">
                  <thead>
                    <tr>
                      <th>Ngày và giờ bắt đầu</th>
                      <th>Thời gian hoạt động (phút)</th>
                      <th>Kiểu lặp lại</th>
                      <th>Thao tác</th>
                    </tr>
                  </thead>
                  <tbody id="reminders-tbody-${relayIndex}"></tbody>
                </table>
          `;
  
          const remindersTbody = document.getElementById(`reminders-tbody-${relayIndex}`);
  
          // Populate the reminders table with each reminder
          message_hash.relays[relayIndex].reminders.forEach((reminder) => {
            const row = document.createElement("tr");
  
            // Start Time
            const startTimeCell = document.createElement("td");
            if (reminder.start_time) {
              const formattedStartTime = formatDateTime(new Date(reminder.start_time) / 1000); // Assuming timestamp is in ms
              startTimeCell.innerText = formattedStartTime;
            } else {
              startTimeCell.innerText = "Không có thời gian";
            }
            row.appendChild(startTimeCell);
  
            // Duration
            const durationCell = document.createElement("td");
            durationCell.innerText = `${reminder.duration / 60000} phút`; // Assuming duration is in ms
            row.appendChild(durationCell);
  
            // Repeat Type
            const repeatTypeCell = document.createElement("td");
            let repeatTypeText;
            switch (reminder.repeat_type) {
              case 'none':
                repeatTypeText = 'Không lặp lại';
                break;
              case 'daily':
                repeatTypeText = 'Hằng ngày';
                break;
              case 'weekly':
                repeatTypeText = 'Hằng tuần';
                break;
              case 'monthly':
                repeatTypeText = 'Hằng tháng';
                break;
              default:
                repeatTypeText = 'Không xác định';
            }
            repeatTypeCell.innerText = repeatTypeText;
            row.appendChild(repeatTypeCell);
  
            // Action - Delete Button
            const actionCell = document.createElement("td");
            const deleteButton = document.createElement("button");
            deleteButton.classList.add("btn", "btn-danger");
            deleteButton.innerText = "Xoá";
            deleteButton.onclick = function () {
              if (confirm("Bạn có chắc chắn muốn xoá?")) {
                fetch(`/devices/remove_reminder_message?chip_id=${message_hash.device_id}&start_time=${reminder.start_time}`, {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
                  }
                }).then(response => {
                  if (!response.ok) {
                    throw new Error('Failed to delete reminder');
                  }
                  console.log("Reminder deleted");
                }).catch(error => console.error("Error:", error));
              }
            };
            actionCell.appendChild(deleteButton);
            row.appendChild(actionCell);
  
            remindersTbody.appendChild(row);
          });
        } else {
          console.error("reminders-list element not found");
        }
      }


      message_hash.relays[relayIndex].reminders.forEach((reminder) => {
        const reminderStartTime = document.getElementById("reminder-start-time");
        const reminderDuration = document.getElementById("reminder-duration");
        const reminderRepeatType = document.getElementById("reminder-repeat-type");

    
        // Kiểm tra phần tử trước khi gán giá trị
        if (reminderStartTime) {
          
          const currentDate = new Date(reminder.start_time);
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
          console.log("Duration:", reminder.duration);
          reminderDuration.value = reminder.duration / 60000 || "";
        } else {
          console.error("reminder-duration element not found");
        }

        // Cập nhật reminderRepeatType
        if (reminderRepeatType) {
          const repeatTypeValue = reminder.repeat_type || 'none';
          reminderRepeatType.value = repeatTypeValue;
          console.log("Repeat Type:", repeatTypeValue);
        } else {
          console.error("reminder-repeat-type element not found");
        }
      });

    }
    

    if(message_hash.sen == "dht11") {

      var connectionDiv = document.getElementById("connection-div");
      connectionDiv.style.display = "none";

      console.log(typeof message_hash);
      console.log("message_hash:", message_hash)


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

function getCurrentRelayIndex() {
  const activeTabPane = document.querySelector(".tab-pane.show.active"); // Select the active tab content
  if (activeTabPane) {
    const relayIndex = activeTabPane.id.split("-")[1]; // Assumes ID format "relay-<%= index %>"
    console.log(`Current Relay Index: ${relayIndex}`);
    return relayIndex;
  }
  return null; // Return null if no active tab is found
}