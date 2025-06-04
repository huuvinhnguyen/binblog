
document.addEventListener("turbo:load", () => {

  // Handle switch toggle (turn ON/OFF relay)
  document.querySelectorAll('[id^="toggle-switch-"]').forEach((toggle) => {
    const relayIndex = toggle.id.split('-').pop();

    toggle.addEventListener('change', (e) => {
      const chipId = e.target.getAttribute('data-chip-id');
      const switchValue = e.target.checked ? 1 : 0;

      gtag("event", "switchon", {
        chip_id: chipId,
        relay_index: relayIndex,
        switch_value: switchValue
      });

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

      gtag("event", "set_reminders_active", {
        chip_id: chipId,
        relay_index: relayIndex,
        is_reminders_active: switchValue
      });

      fetch('/api/devices/set_reminders_active', { // 🔥 sửa lại path đúng
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
        // alert('Reminder toggled successfully!');
      })
      .catch(error => {
        console.error('Error:', error);
      });
    });
  });

  document.querySelectorAll('[id^="longlast-input-"]').forEach((relay) => {
    const relayIndex = relay.id.split('-').pop();

    relay.addEventListener('change', (e) => {
      const chipId = e.target.getAttribute('data-chip-id');
      const value = parseInt(e.target.value, 10);
      const unit = document.querySelector(`#longlast-unit-${relayIndex}`)?.value;


      gtag("event", "relay_longlast_input", {
        chip_id: chipId,
        relay_index: relayIndex,
        duration: value,
        unit: unit
      });
    });
  });


});

