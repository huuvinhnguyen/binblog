
document.addEventListener("turbo:load", () => {
    // Slider functionality
    const sliderInput = document.getElementById('switch-slider');
    const messageField = document.getElementById('switchon-message-field');

    if (sliderInput && messageField) {
      sliderInput.addEventListener('input', () => {
        console.log("sliderInput.value = ", sliderInput.value);
        messageField.value = sliderInput.value;
      });
    }

    const toggleSwitch = document.getElementById('toggle-switch');
    const toggleStateField = document.getElementById('toggle_state_field');
    const toggleForm = document.getElementById('toggle-form');

    toggleSwitch.addEventListener('change', (event) => {
      // Cập nhật giá trị cho trường ẩn
      toggleStateField.value = toggleSwitch.checked ? '1' : '0';

      // Ngăn chặn hành động gửi form mặc định
      event.preventDefault();

      // Gửi form ngay lập tức mà không cần xác nhận
      toggleForm.submit();
    });

});
