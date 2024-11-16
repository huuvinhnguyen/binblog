
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

    // Toggle switch functionality for each relay
    document.querySelectorAll('[id^="toggle-switch-"]').forEach((toggleSwitch) => {
      const relayIndex = toggleSwitch.id.split('-').pop(); // Get relay index from toggle switch ID
      const toggleStateField = document.getElementById(`toggle_state_field-${relayIndex}`);
      const toggleForm = document.getElementById(`toggle-form-${relayIndex}`);

      toggleSwitch.addEventListener('change', (event) => {
        // Update the value of the hidden field based on toggle state
        toggleStateField.value = toggleSwitch.checked ? '1' : '0';

        // Prevent default form submission and submit manually
        event.preventDefault();
        toggleForm.submit();
      });
    });

    document.querySelectorAll('.form-check-input').forEach((toggleSwitch) => {
      toggleSwitch.addEventListener('change', (e) => {
        const relayIndex = e.target.id.split('-').pop(); // Lấy relay index từ id
        const stateField = document.getElementById(`toggle_state_field-${relayIndex}`);
        stateField.value = e.target.checked ? '1' : '0'; // Cập nhật giá trị
      });
    });
});
