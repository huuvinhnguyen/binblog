
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

  // Handle switch toggle (turn ON/OFF relay)
  document.querySelectorAll('[id^="toggle-switch-"]').forEach((toggle) => {
    const relayIndex = toggle.id.split('-').pop();

    toggle.addEventListener('change', (e) => {
      const chipId = e.target.getAttribute('data-chip-id');
      const switchValue = e.target.checked ? 1 : 0;

      fetch('/api/devices/switchon', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        },
        body: JSON.stringify({ device_id: chipId, relay_index: relayIndex, switch_value: switchValue })
      })
      .then(response => {
        if (!response.ok) throw new Error('Network error');
        return response.json();
      })
      .then(data => {
        // alert('Switch toggled successfully!');
      })
      .catch(error => {
        console.error('Error:', error);
      });
    });
  });

  // Handle reminder active/inactive toggle
  document.querySelectorAll('[id^="toggle-reminders-active-"]').forEach((toggle) => {
    const relayIndex = toggle.id.split('-').pop();

    toggle.addEventListener('change', (e) => {
      const chipId = e.target.getAttribute('data-chip-id');
      const toggleValue = e.target.checked ? 1 : 0;

      fetch('/api/devices/switchon', { // 🔥 sửa lại path đúng
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        },
        body: JSON.stringify({ device_id: chipId, relay_index: relayIndex, is_reminders_active: toggleValue })
      })
      .then(response => {
        console.log('Raw response:', response);
        if (!response.ok) throw new Error('Network error');
        return response.json();
      })
      .then(data => {
        alert('Reminder toggled successfully!');
      })
      .catch(error => {
        console.error('Error:', error);
      });
    });
  });
});

