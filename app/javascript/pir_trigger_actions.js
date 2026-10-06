const ERROR_MESSAGES = {
  duplicate_action: 'Thiết bị và loại hành động này đã được cấu hình.',
  action_limit_reached: 'Đã đạt giới hạn số hành động cho PIR này.',
  configuration_mode_conflict: 'Cấu hình đã thay đổi. Danh sách sẽ được tải lại.',
  legacy_configuration_requires_reconciliation: 'Cấu hình cũ cần được chuyển đổi trước khi chỉnh sửa.',
  trigger_actions_managed: 'Cấu hình này được quản lý bằng danh sách hành động mới.',
  invalid_action_type: 'Loại hành động không hợp lệ.',
  invalid_relay_index: 'Kênh relay không còn hợp lệ. Danh sách thiết bị sẽ được tải lại.',
  invalid_duration: 'Thời lượng nằm ngoài giới hạn của thiết bị.',
  invalid_delay: 'Thực thi đồng bộ hiện chỉ hỗ trợ độ trễ 0 ms.',
  invalid_order: 'Thứ tự hành động không hợp lệ. Danh sách sẽ được tải lại.',
  invalid_enabled: 'Trạng thái hành động không hợp lệ.',
  target_not_found: 'Không thể sử dụng thiết bị đích. Danh sách sẽ được tải lại.',
  feature_disabled: 'Tính năng hành động PIR hiện chưa khả dụng.'
}

class PirTriggerActionsPanel {
  constructor(root) {
    this.root = root
    this.base = `/api/devices/${encodeURIComponent(root.dataset.chipId)}/trigger_actions`
    this.abort = new AbortController()
    this.find = (name) => root.querySelector(`[data-actions-${name}]`)
    this.actions = []
    this.targets = []
    this.mode = 'none'
    this.editingId = null
    this.ready = false
    this.busy = false
    root.addEventListener('click', (event) => this.click(event), { signal: this.abort.signal })
    this.find('form').addEventListener('submit', (event) => this.submit(event), { signal: this.abort.signal })
    this.find('target').addEventListener('change', () => this.targetChanged(), { signal: this.abort.signal })
    this.refresh()
  }

  controls() {
    const locked = this.busy || !this.ready
    this.root.querySelectorAll('button, input, select').forEach((control) => {
      control.disabled = locked || control.dataset.actionBoundary === 'true'
    })
    this.find('refresh').disabled = this.busy
    const editable = this.ready && ['none', 'actions'].includes(this.mode)
    this.find('add').disabled = this.busy || !editable
    this.find('submit').disabled = this.busy || !editable || !this.find('target').value
    this.root.setAttribute('aria-busy', String(this.busy))
  }

  showError(message = '') {
    this.find('error').textContent = message
    this.find('error').hidden = !message
  }

  async request(path = '', method = 'GET', body) {
    const response = await fetch(`${this.base}${path}`, {
      method,
      credentials: 'same-origin',
      signal: this.abort.signal,
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
      },
      ...(body ? { body: JSON.stringify(body) } : {})
    })
    if (response.status === 401 || response.redirected) {
      throw Object.assign(new Error('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi tải lại trang.'), { status: 401 })
    }
    const data = await response.json().catch(() => ({}))
    if (!response.ok || data.status !== 'success') {
      const message = ERROR_MESSAGES[data.code] || (response.status === 404
        ? 'Không tìm thấy thiết bị hoặc bạn không có quyền truy cập.'
        : 'Không thể thực hiện yêu cầu. Hãy thử lại.')
      throw Object.assign(new Error(message), { status: response.status, code: data.code })
    }
    return data
  }

  async refresh(success = '') {
    if (this.busy) return
    this.busy = true
    this.ready = false
    this.showError()
    this.find('status').textContent = success ? `${success} Đang tải lại cấu hình…` : 'Đang tải cấu hình…'
    this.controls()
    try {
      const [configuration, targets] = await Promise.all([this.request(), this.request('/targets')])
      if (!Array.isArray(configuration.actions) || !Array.isArray(targets.targets)) throw new Error('Phản hồi cấu hình không hợp lệ.')
      this.mode = configuration.configuration_mode
      this.actions = configuration.actions
      this.targets = targets.targets
      this.render()
      this.ready = true
      this.find('status').textContent = success || this.modeLabel()
    } catch (error) {
      if (this.abort.signal.aborted) return
      this.find('status').textContent = success
      this.showError(`${error.message} Cấu hình chưa được cập nhật; chọn “Làm mới”.`)
    } finally {
      if (!this.abort.signal.aborted) { this.busy = false; this.controls() }
    }
  }

  modeLabel() {
    return {
      none: 'Chưa có cấu hình hành động.',
      legacy: 'Đang dùng cấu hình cũ (chỉ đọc).',
      actions: `${this.actions.length} hành động đã cấu hình.`,
      invalid_legacy: 'Cấu hình cũ cần được kiểm tra.'
    }[this.mode] || 'Trạng thái cấu hình không xác định.'
  }

  targetName(target) { return target?.name || target?.chip_id || 'Thiết bị không còn khả dụng' }
  typeName(type) { return type === 'switch' ? 'Công tắc' : type === 'buzzer' ? 'Buzzer' : 'Thiết bị' }

  render() {
    this.find('legacy').hidden = this.mode !== 'legacy'
    this.find('invalid-legacy').hidden = this.mode !== 'invalid_legacy'
    this.find('empty').hidden = this.mode !== 'none' || this.actions.length !== 0
    const list = this.find('list')
    list.replaceChildren()
    this.actions.forEach((action, index) => list.append(this.actionRow(action, index)))
    this.closeForm(false)
  }

  actionRow(action, index) {
    const row = document.createElement('li')
    row.className = 'pir-device__action-row'
    row.dataset.actionId = action.id == null ? '' : String(action.id)
    if (!action.enabled) row.classList.add('pir-device__action-row--disabled')
    const info = document.createElement('div')
    info.className = 'pir-device__action-info'
    const heading = document.createElement('div')
    const name = document.createElement('strong')
    name.textContent = this.targetName(action.target)
    const badge = document.createElement('span')
    badge.className = `pir-device__action-type pir-device__action-type--${action.target?.device_type || 'unknown'}`
    badge.textContent = this.typeName(action.target?.device_type)
    heading.append(name, badge)
    const detail = document.createElement('small')
    detail.textContent = `Relay ${action.relay_index ?? '—'} · ${action.duration_ms ?? '—'} ms · trễ ${action.delay_ms ?? '—'} ms · ${action.enabled ? 'Đang bật' : 'Đã tắt'}`
    info.append(heading, detail)
    row.append(info)
    if (action.origin === 'persisted') {
      const buttons = document.createElement('div')
      buttons.className = 'pir-device__action-row-buttons'
      const specs = [
        ['up', '↑', 'Đưa lên', index === 0], ['down', '↓', 'Đưa xuống', index === this.actions.length - 1],
        ['toggle', action.enabled ? 'Tắt' : 'Bật', action.enabled ? 'Tắt hành động' : 'Bật hành động', false],
        ['edit', 'Sửa', 'Sửa hành động', false], ['delete', 'Xóa', 'Xóa hành động', false]
      ]
      specs.forEach(([operation, text, label, disabled]) => {
        const button = document.createElement('button')
        button.type = 'button'; button.dataset.actionOperation = operation; button.dataset.actionId = action.id
        button.textContent = text; button.title = label; button.setAttribute('aria-label', `${label}: ${this.targetName(action.target)}`)
        button.disabled = disabled
        if (disabled) button.dataset.actionBoundary = 'true'
        buttons.append(button)
      })
      row.append(buttons)
    }
    return row
  }

  openForm(action = null) {
    this.editingId = action?.id ?? null
    this.find('form-title').textContent = action ? 'Sửa hành động' : 'Thêm hành động'
    const select = this.find('target')
    select.replaceChildren(new Option('Chọn thiết bị', ''))
    this.targets.forEach((target) => select.add(new Option(`${this.typeName(target.device_type)} · ${this.targetName(target)}`, String(target.id))))
    select.value = action?.target?.id == null ? '' : String(action.target.id)
    this.find('delay').value = action?.delay_ms ?? 0
    this.find('enabled').checked = action?.enabled ?? true
    this.targetChanged(action)
    this.find('no-targets').hidden = this.targets.length !== 0
    this.find('form').hidden = false
    this.find('add').setAttribute('aria-expanded', 'true')
    select.focus()
    this.controls()
  }

  targetChanged(action = null) {
    const target = this.targets.find((item) => String(item.id) === this.find('target').value)
    const relay = this.find('relay')
    relay.replaceChildren(new Option('Chọn relay', ''))
    target?.relay_indexes?.forEach((index) => relay.add(new Option(`Relay ${index}`, String(index))))
    relay.value = action?.relay_index == null ? (target?.relay_indexes?.[0]?.toString() || '') : String(action.relay_index)
    const range = target?.duration_ms
    const duration = this.find('duration')
    duration.min = range?.minimum ?? ''
    duration.max = range?.maximum ?? ''
    duration.value = action?.duration_ms ?? range?.minimum ?? ''
    this.find('duration-help').textContent = range ? `${range.minimum.toLocaleString('vi-VN')}–${range.maximum.toLocaleString('vi-VN')} ms` : ''
    this.controls()
  }

  closeForm(focus = true) {
    this.editingId = null
    this.find('form').hidden = true
    this.find('form').reset()
    this.find('add').setAttribute('aria-expanded', 'false')
    if (focus) this.find('add').focus()
  }

  integer(name, minimum, maximum) {
    const input = this.find(name)
    const value = Number(input.value)
    return input.value.trim() && Number.isSafeInteger(value) && value >= minimum && value <= maximum ? value : null
  }

  submit(event) {
    event.preventDefault()
    const target = this.targets.find((item) => String(item.id) === this.find('target').value)
    const relay = this.integer('relay', 0, Number.MAX_SAFE_INTEGER)
    const duration = this.integer('duration', target?.duration_ms?.minimum ?? 1, target?.duration_ms?.maximum ?? 0)
    const delay = this.integer('delay', 0, 0)
    if (!target || !target.relay_indexes.includes(relay) || duration == null || delay == null) {
      this.showError('Kiểm tra thiết bị, relay, thời lượng và độ trễ theo giới hạn hiển thị.')
      return
    }
    const body = { target_device_id: target.id, action_type: 'relay_pulse', relay_index: relay,
      duration_ms: duration, delay_ms: delay, enabled: this.find('enabled').checked }
    const path = this.editingId == null ? '' : `/${encodeURIComponent(this.editingId)}`
    this.mutate(path, this.editingId == null ? 'POST' : 'PUT', body, 'Đã lưu hành động.')
  }

  click(event) {
    const button = event.target.closest('button')
    if (!button || !this.root.contains(button) || button.disabled) return
    if (button.matches('[data-actions-refresh]')) return this.refresh()
    if (button.matches('[data-actions-add]')) return this.openForm()
    if (button.matches('[data-actions-cancel]')) return this.closeForm()
    if (button.matches('[data-actions-migrate]')) {
      if (window.confirm('Chuyển cấu hình cũ sang danh sách hành động mới?')) this.mutate('/migrate_legacy', 'POST', undefined, 'Đã chuyển đổi cấu hình.')
      return
    }
    const operation = button.dataset.actionOperation
    const action = this.actions.find((item) => String(item.id) === button.dataset.actionId)
    if (!action) return
    if (operation === 'edit') return this.openForm(action)
    if (operation === 'toggle') return this.mutate(`/${action.id}`, 'PUT', { enabled: !action.enabled }, 'Đã cập nhật trạng thái.')
    if (operation === 'delete' && window.confirm(`Xóa hành động cho ${this.targetName(action.target)}?`)) {
      return this.mutate(`/${action.id}`, 'DELETE', undefined, 'Đã xóa hành động.')
    }
    if (operation === 'up' || operation === 'down') {
      const ids = this.actions.map((item) => item.id)
      const from = ids.indexOf(action.id)
      const to = from + (operation === 'up' ? -1 : 1)
      if (to >= 0 && to < ids.length) [ids[from], ids[to]] = [ids[to], ids[from]]
      return this.mutate('/order', 'PUT', { action_ids: ids }, 'Đã cập nhật thứ tự.')
    }
  }

  async mutate(path, method, body, success) {
    if (this.busy || !this.ready) return
    this.busy = true; this.showError(); this.find('status').textContent = 'Đang lưu cấu hình…'; this.controls()
    try {
      await this.request(path, method, body)
      if (this.abort.signal.aborted) return
      this.busy = false
      await this.refresh(success)
    } catch (error) {
      if (this.abort.signal.aborted) return
      this.busy = false
      const reconcile = ['configuration_mode_conflict', 'legacy_configuration_requires_reconciliation', 'invalid_relay_index',
        'invalid_duration', 'invalid_delay', 'invalid_order', 'target_not_found'].includes(error.code)
      if (reconcile) {
        await this.refresh()
        this.showError(error.message)
      } else {
        this.ready = false
        this.find('status').textContent = ''
        this.showError(`${error.message} Hãy làm mới cấu hình để kiểm tra trạng thái trước khi gửi lại.`)
      }
    } finally {
      if (!this.abort.signal.aborted) { this.busy = false; this.controls() }
    }
  }

  destroy() { this.abort.abort() }
}

let triggerActionPanels = []
const teardown = () => { triggerActionPanels.forEach((panel) => panel.destroy()); triggerActionPanels = [] }
document.addEventListener('turbo:before-cache', teardown)
document.addEventListener('turbo:before-render', teardown)
document.addEventListener('turbo:load', () => {
  teardown()
  triggerActionPanels = Array.from(document.querySelectorAll('[data-pir-trigger-actions]'), (root) => new PirTriggerActionsPanel(root))
})
