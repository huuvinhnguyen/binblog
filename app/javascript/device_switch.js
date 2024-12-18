
import { createVerGauge, getTempColor, createRadGauge, getHumColor  }  from "gauges";

  
  document.addEventListener("turbo:load", () => {
    // Slider functionality
    document.querySelectorAll('.slider').forEach((sliderInput) => {
      const relayIndex = sliderInput.id.split('-').pop(); // Get relay index from slider ID
      const messageField = document.getElementById(`switchon-message-field-${relayIndex}`);
  
      if (sliderInput && messageField) {
        sliderInput.addEventListener('input', () => {
          console.log(`Slider value for relay ${relayIndex} = `, sliderInput.value);
          messageField.value = sliderInput.value;
        });
      }
    });


    document.querySelectorAll('[id^="toggle-switch-"]').forEach((toggle) => {
      const relayIndex = toggle.id.split('-').pop();

      toggle.addEventListener('change', (e) => {
        const chipId = e.target.getAttribute('data-chip-id');
        const switchValue = e.target.checked ? 1 : 0;
    
        fetch('/devices/switchon', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
          },
          body: JSON.stringify({ chip_id: chipId, relay_index: relayIndex, switch_value: switchValue })
        })
        .then(response => {
          if (!response.ok) throw new Error('Network error');
          return response.json();
        })
        .then(data => {
          alert('Switch toggled successfully!');
        })
        .catch(error => {
          console.error('Error:', error);
        });
      });
    });

    document.querySelectorAll('[id^="toggle-reminders-active-"]').forEach((toggle) => {
      const relayIndex = toggle.id.split('-').pop();

      toggle.addEventListener('change', (e) => {
        const chipId = e.target.getAttribute('data-chip-id');
        const toggleValue = e.target.checked ? 1 : 0;
    
        fetch('/devices/switchon', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
          },
          body: JSON.stringify({ chip_id: chipId, relay_index: relayIndex, is_reminders_active: toggleValue })
        })
        .then(response => {
          console.log('Raw response:', response);
          if (!response.ok) throw new Error('Network error');
          return response.json();
        })
        .then(data => {
          alert('Switch toggled successfully!');
        })
        .catch(error => {
          console.error('Error:', error);
        });
      });
    });
    
});

document.addEventListener("turbo:load", function() {

  if ($('#dht-container').length) {
    function loadDHT() {

      var tempGauge = createVerGauge('temp', -20, 60, ' °C').setVal(0).setColor(getTempColor(0));
      tempGauge.setVal(50).setColor(getTempColor(60));
      var humGauge = createRadGauge('hum', 0, 100, '%').setVal(50).setColor(getHumColor(50));
      humGauge.setVal(50).setColor(getHumColor(50)); // Giá trị mặc định khi load trang
    }

    loadDHT();

  }

});

document.addEventListener("turbo:load", function() {
  if (document.querySelector('#dht-form-wrapper')) {

      function sendConnectDhtRequest() {
          $.ajax({
              url: "devices/connect_dht", // Ensure this matches the route in your Rails app
              type: "POST",
              dataType: "script", // Expect JavaScript response if needed
              success: function(response) {
                  console.log("Request successful");
                  // Handle the response if needed
              },
              error: function(xhr, status, error) {
                  console.error("Request failed:", error);
              }
          });
      }

      sendConnectDhtRequest();
  }
});



