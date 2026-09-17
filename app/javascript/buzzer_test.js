document.addEventListener("turbo:submit-start", (event) => {
  const form = event.target
  if (!form.matches("form[data-buzzer-test-form]")) return

  const button = form.querySelector("[data-buzzer-test-button]")
  if (!button) return

  button.dataset.originalLabel = button.value || button.textContent
  button.disabled = true

  if ("value" in button) {
    button.value = "Đang gửi…"
  } else {
    button.textContent = "Đang gửi…"
  }
})

document.addEventListener("turbo:submit-end", (event) => {
  const form = event.target
  if (!form.matches("form[data-buzzer-test-form]") || event.detail.success) return

  const button = form.querySelector("[data-buzzer-test-button]")
  if (!button) return

  button.disabled = false
  if ("value" in button) {
    button.value = button.dataset.originalLabel
  } else {
    button.textContent = button.dataset.originalLabel
  }
})
