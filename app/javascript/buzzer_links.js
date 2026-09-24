// Only the #105 configuration endpoints belong here. Test Buzzer is independent.
class BuzzerLinksPanel {
  constructor(root) {
    this.root = root
    this.base = `/api/devices/${encodeURIComponent(root.dataset.buzzerId)}/buzzer`
    this.abort = new AbortController()
    this.find = (name) => root.querySelector(`[data-links-${name}]`)
    this.ui = this.find('ui')
    this.form = this.find('form')
    this.select = this.find('pir')
    this.ready = false
    this.busy = false
    this.candidates = []
    this.linked = []
    this.ui.hidden = false
    this.find('fallback').hidden = true
    root.addEventListener('click', (event) => this.click(event), { signal: this.abort.signal })
    this.form.addEventListener('submit', (event) => this.submit(event), { signal: this.abort.signal })
    this.select.addEventListener('change', () => this.selection(), { signal: this.abort.signal })
    this.refresh()
  }

  controls() {
    this.ui.querySelectorAll('button, input, select').forEach((control) => {
      control.disabled = this.busy || !this.ready
    })
    this.find('refresh').disabled = this.busy
    this.find('submit').disabled = this.busy || !this.ready || !this.select.value
    this.root.setAttribute('aria-busy', String(this.busy))
  }

  error(message = '') {
    this.find('error').textContent = message
    this.find('error').hidden = !message
  }

  async request(path, method = 'GET', body) {
    const response = await fetch(`${this.base}/${path}`, {
      method, credentials: 'same-origin', signal: this.abort.signal,
      headers: {
        Accept: 'application/json', 'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
      },
      ...(body ? { body: JSON.stringify(body) } : {})
    })
    if (response.status === 401 || response.redirected) throw new Error('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi tải lại trang.')
    if (response.status === 404) throw new Error('Không tìm thấy thiết bị hoặc bạn không có quyền truy cập. Hãy làm mới danh sách.')
    const data = await response.json().catch(() => { throw new Error('Không thể đọc phản hồi. Hãy làm mới danh sách trước khi thử lại.') })
    if (!response.ok || data.status !== 'success') throw new Error(data.message || 'Không thể thực hiện yêu cầu. Hãy thử lại.')
    return data
  }

  async refresh(success = '') {
    if (this.busy) return
    this.busy = true
    this.ready = false
    this.error()
    this.find('status').textContent = success ? `${success} Đang tải lại danh sách…` : 'Đang tải danh sách PIR…'
    this.controls()
    try {
      const [linked, available] = await Promise.all([
        this.request('linked_pirs'), this.request('available_pirs')
      ])
      if (this.abort.signal.aborted) return
      if (!Array.isArray(linked.linked_pirs) || !Array.isArray(available.available_pirs)) throw new Error('Danh sách PIR không hợp lệ.')
      this.linked = linked.linked_pirs
      this.candidates = available.available_pirs
      this.render()
      this.ready = true
      this.find('status').textContent = success || 'Danh sách PIR đã cập nhật.'
    } catch (error) {
      if (this.abort.signal.aborted) return
      this.find('status').textContent = success
      this.error(`${error.message} Danh sách chưa được cập nhật; chọn “Làm mới danh sách”.`)
    } finally {
      if (!this.abort.signal.aborted) { this.busy = false; this.controls() }
    }
  }

  name(pir) { return pir.name || pir.chip_id || `PIR #${pir.id}` }

  render() {
    const list = this.find('list')
    list.replaceChildren()
    this.linked.forEach((pir) => {
      const row = document.createElement('li')
      const info = document.createElement('span')
      info.className = 'buzzer-device__link-info'
      const name = document.createElement('strong')
      name.textContent = this.name(pir)
      const detail = document.createElement('small')
      const scalar = (value) => ['string', 'number'].includes(typeof value) ? value : '—'
      detail.textContent = `Kênh ${scalar(pir.relay_index)} · ${scalar(pir.longlast)} ms`
      info.append(name, detail)
      const button = document.createElement('button')
      button.type = 'button'
      button.className = 'buzzer-device__link-secondary'
      button.dataset.linksUnlink = String(pir.id)
      button.textContent = 'Hủy liên kết'
      button.setAttribute('aria-label', `Hủy liên kết ${this.name(pir)}`)
      row.append(info, button)
      list.append(row)
    })
    this.find('empty').hidden = this.linked.length !== 0
    this.root.closest('.buzzer-device')?.querySelectorAll('[data-buzzer-linked-count]').forEach((count) => {
      count.textContent = String(this.linked.length)
    })
    const selected = this.select.value
    this.select.replaceChildren(new Option('Chọn PIR', ''))
    this.candidates.forEach((pir) => this.select.add(new Option(this.name(pir), String(pir.id))))
    if (this.candidates.some((pir) => String(pir.id) === selected)) this.select.value = selected
    this.find('no-candidates').hidden = this.candidates.length !== 0
    this.selection()
  }

  selected() { return this.candidates.find((pir) => String(pir.id) === this.select.value) }

  confirmation(pir) {
    if (pir.linked_buzzer && String(pir.linked_buzzer.id) !== this.root.dataset.buzzerId) {
      return `PIR sẽ ngừng kích hoạt ${pir.linked_buzzer.name || 'Buzzer hiện tại'} và chuyển sang Buzzer này. Bạn muốn chuyển & liên kết?`
    }
    if (pir.requires_confirmation) return 'Cấu hình hiện có của PIR sẽ bị thay thế bằng liên kết với Buzzer này. Bạn muốn thay thế & liên kết?'
    return ''
  }

  selection() {
    const pir = this.selected()
    const warning = pir ? this.confirmation(pir) : ''
    this.find('warning').textContent = warning || (pir?.linked_buzzer ? 'PIR đã liên kết với Buzzer này. Bạn có thể cập nhật kênh và thời lượng.' : '')
    this.find('submit').textContent = !warning ? 'Liên kết' : pir.linked_buzzer ? 'Chuyển & liên kết' : 'Thay thế & liên kết'
    const existing = this.linked.find((item) => item.id === pir?.id)
    this.find('relay').value = existing?.relay_index ?? 0
    this.find('duration').value = existing?.longlast ?? 1000
    this.controls()
  }

  click(event) {
    const button = event.target.closest('button')
    if (!button || !this.root.contains(button) || button.disabled) return
    if (button.matches('[data-links-refresh]')) return this.refresh()
    if (button.matches('[data-links-open]')) {
      this.form.hidden = false
      button.setAttribute('aria-expanded', 'true')
      this.select.focus()
    }
    if (button.matches('[data-links-cancel]')) this.close()
    if (button.matches('[data-links-unlink]')) {
      const pir = this.linked.find((item) => String(item.id) === button.dataset.linksUnlink)
      if (pir && window.confirm(`${this.name(pir)} sẽ ngừng kích hoạt Buzzer này. Hủy liên kết chỉ thay đổi cấu hình, không phát âm hoặc chạy Test Buzzer. Tiếp tục?`)) {
        this.mutate(`linked_pirs/${encodeURIComponent(pir.id)}`, 'DELETE', undefined, 'Đã hủy liên kết PIR.')
      }
    }
  }

  close() {
    this.form.hidden = true
    this.form.reset()
    this.selection()
    this.find('open').setAttribute('aria-expanded', 'false')
    this.find('open').focus()
  }

  submit(event) {
    event.preventDefault()
    if (this.busy || !this.ready) return
    const pir = this.selected()
    const relayText = this.find('relay').value
    const durationText = this.find('duration').value
    const relay = Number(relayText)
    const duration = Number(durationText)
    if (!pir || !relayText.trim() || !Number.isSafeInteger(relay) || relay < 0 ||
        !durationText.trim() || !Number.isSafeInteger(duration) || duration < 100 || duration > 10000) {
      this.error('Chọn PIR, kênh relay là số nguyên từ 0 và thời lượng là số nguyên từ 100 đến 10000 ms.')
      return
    }
    const warning = this.confirmation(pir)
    if (warning && !window.confirm(warning)) return
    this.mutate('linked_pirs', 'POST', { pir_id: pir.id, relay_index: relay, longlast: duration }, 'Đã lưu liên kết PIR.')
  }

  async mutate(path, method, body, success) {
    if (this.busy || !this.ready) return
    this.busy = true
    this.error()
    this.find('status').textContent = 'Đang lưu cấu hình…'
    this.controls()
    try {
      await this.request(path, method, body)
      if (this.abort.signal.aborted) return
      this.busy = false
      this.close()
      await this.refresh(success)
    } catch (error) {
      if (this.abort.signal.aborted) return
      // A transport error may follow a committed write. Reload before allowing retry.
      this.ready = false
      this.find('status').textContent = ''
      this.error(`${error.message} Hãy làm mới danh sách để kiểm tra trạng thái trước khi gửi lại.`)
    } finally {
      if (!this.abort.signal.aborted) { this.busy = false; this.controls() }
    }
  }

  destroy() { this.abort.abort() }
}

let panels = []
const teardown = () => { panels.forEach((panel) => panel.destroy()); panels = [] }
document.addEventListener('turbo:before-cache', teardown)
document.addEventListener('turbo:before-render', teardown)
document.addEventListener('turbo:load', () => {
  teardown()
  panels = Array.from(document.querySelectorAll('[data-buzzer-links]'), (root) => new BuzzerLinksPanel(root))
})
