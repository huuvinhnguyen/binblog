
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
        console.log("chip id: ", chipId);
        console.log("relay index = ", relayIndex);
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
    
});
