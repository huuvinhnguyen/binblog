// Real DOM behavior tests with mocked API responses; no npm/browser-driver dependency.
// Run: node spec/javascript/buzzer_links_test.mjs (CHROME_BIN may override Chrome).
import { readFile, mkdtemp, rm } from 'node:fs/promises'
import { createServer } from 'node:http'
import { spawn } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import assert from 'node:assert/strict'
import * as sass from 'sass'

const css = sass.compile('app/assets/stylesheets/devices/_buzzer_device.scss').css

const partial = await readFile('app/views/devices/_buzzer_links.html.erb', 'utf8')
const browserTests = `
import '/buzzer_links.js'
import '/buzzer_test.js'
const root = document.querySelector('[data-buzzer-links]')
const q = (name) => root.querySelector('[data-links-' + name + ']')
const check = (condition, message) => { if (!condition) throw new Error(message) }
const wait = async (condition) => {
  for (let i = 0; i < 100; i++) { if (condition()) return; await new Promise(r => setTimeout(r, 10)) }
  throw new Error('Timed out waiting for UI')
}
let calls = [], confirmations = [], consent = true, fail = 0, failRefresh = false
let linked = []
let candidates = [
  {id: 7, name: 'PIR cửa', chip_id: 'pir7', linked_buzzer: null, requires_confirmation: false},
  {id: 8, name: 'PIR sân', chip_id: 'pir8', linked_buzzer: {id: 99, name: 'Buzzer sân'}, requires_confirmation: true},
  {id: 9, name: 'PIR riêng', chip_id: 'pir9', linked_buzzer: null, requires_confirmation: true}
]
window.confirm = (text) => { confirmations.push(text); return consent }
window.fetch = async (url, options) => {
  calls.push({url, ...options})
  check(/^\\/api\\/devices\\/42\\/buzzer\\/(available_pirs|linked_pirs)(\\/\\d+)?$/.test(url), 'Unexpected API / Test Buzzer call: ' + url)
  check(options.credentials === 'same-origin', 'Session credentials missing')
  check(options.headers['X-CSRF-Token'] === 'test-csrf', 'CSRF header missing')
  if (options.signal.aborted) throw new DOMException('Aborted', 'AbortError')
  if (fail || (failRefresh && options.method === 'GET')) {
    const status = fail || 503; fail = 0
    return {ok: false, status, json: async () => ({status:'error', message:'API unavailable'})}
  }
  if (options.method === 'POST') {
    const body = JSON.parse(options.body)
    check(Object.values(body).every(Number.isInteger), 'POST requires JSON integers')
    const candidate = candidates.find(p => p.id === body.pir_id)
    linked = linked.filter(p => p.id !== body.pir_id)
    linked.push({id: candidate.id, name: candidate.name, chip_id: candidate.chip_id, relay_index: body.relay_index, longlast: body.longlast})
    candidate.linked_buzzer = {id:42,name:'Current'}; candidate.requires_confirmation = false
    return {ok:true, status:200, json:async()=>({status:'success',linked_pir:linked.at(-1)})}
  }
  if (options.method === 'DELETE') {
    const id = Number(url.split('/').at(-1))
    linked = linked.filter(p => p.id !== id)
    const candidate = candidates.find(p => p.id === id)
    candidate.linked_buzzer = null; candidate.requires_confirmation = false
    return {ok:true,status:200,json:async()=>({status:'success',pir_id:id})}
  }
  return {ok:true,status:200,json:async()=>JSON.parse(JSON.stringify(url.endsWith('available_pirs') ? {status:'success',available_pirs:candidates} : {status:'success',linked_pirs:linked}))}
}
const reload = async () => { document.dispatchEvent(new Event('turbo:load')); await wait(()=>!q('refresh').disabled) }
const choose = (id) => {
  q('open').click(); q('pir').value = String(id); q('pir').dispatchEvent(new Event('change'))
}
const submit = () => q('form').dispatchEvent(new Event('submit', {bubbles:true,cancelable:true}))
const settled = () => wait(()=>!q('refresh').disabled)
const writes = () => calls.filter(c=>['POST','DELETE'].includes(c.method))
const refreshed = (from) => {
  const recent = calls.slice(from)
  check(recent.some(c=>c.method==='GET' && c.url.endsWith('/linked_pirs')), 'Linked list not refreshed')
  check(recent.some(c=>c.method==='GET' && c.url.endsWith('/available_pirs')), 'Available list not refreshed')
}
let passed = []
try {
  document.dispatchEvent(new Event('turbo:load'))
  check(q('status').textContent.includes('Đang tải'), 'Missing loading state')
  check(q('open').disabled, 'Mutation enabled during load')
  await settled()
  check(!q('empty').hidden, 'Missing linked empty state')
  check(q('pir').options.length===4, 'Available candidates not rendered')
  passed.push('loading, empty, available rendering')

  choose(7)
  for (const [relay, duration] of [['-1','1000'],['0.5','1000'],['0','99'],['0','10001'],['0','100.5'],['','1000']]) {
    q('relay').value=relay; q('duration').value=duration
    const before=writes().length; submit()
    check(writes().length===before && !q('error').hidden, 'Invalid input sent to API')
  }
  passed.push('relay and duration validation')
  for (const duration of [100,10000]) {
    choose(7); q('relay').value='2'; q('duration').value=String(duration)
    const from=calls.length; submit(); await settled()
    check(q('form').hidden, 'Form did not close after success')
    check(q('list').textContent.includes('Kênh 2 · ' + duration + ' ms'), 'Linked response not rendered')
    refreshed(from)
  }
  check(confirmations.length===0, 'Normal link prompted unexpectedly')
  check(document.querySelector('[data-buzzer-linked-count]').textContent==='1', 'Count stale')
  passed.push('normal link, same-target edit, both duration boundaries, refresh')

  choose(8); q('cancel').click(); q('open').click()
  check(q('pir').value === '' && q('warning').textContent === '' && q('submit').disabled, 'Cancel did not reset selection and warning')
  choose(8); consent=false
  let from=calls.length; submit()
  check(calls.length===from, 'Cancelled move sent request')
  check(confirmations.at(-1).includes('Buzzer sân') && confirmations.at(-1).includes('ngừng kích hoạt'), 'Move explanation missing')
  consent=true; submit(); await settled(); refreshed(from)
  check(linked.some(p=>p.id===8), 'Move failed')
  passed.push('Move & Link confirmation/cancel/success/refresh')

  choose(9)
  check(q('submit').textContent==='Thay thế & liên kết', 'Wrong replacement label')
  check(!q('warning').textContent.includes('99') && !q('warning').textContent.includes('Buzzer sân'), 'Hidden target inferred')
  consent=false; from=calls.length; submit(); check(calls.length===from, 'Cancelled replacement sent')
  check(confirmations.at(-1).includes('Cấu hình hiện có'), 'Generic confirmation missing')
  consent=true; submit(); await settled(); refreshed(from)
  passed.push('generic replacement, privacy, cancellation, refresh')
  choose(7)
  check(root.getBoundingClientRect().width <= 350 && root.getBoundingClientRect().right <= innerWidth, 'Panel overflows narrow viewport')
  check(q('duration').getBoundingClientRect().right <= root.getBoundingClientRect().right, 'Input overflows panel')
  q('cancel').click()
  passed.push('narrow-screen layout')

  let unlink=root.querySelector('[data-links-unlink="7"]')
  consent=false; from=calls.length; unlink.click(); check(calls.length===from, 'Cancelled unlink sent')
  check(confirmations.at(-1).includes('không phát âm') && confirmations.at(-1).includes('ngừng kích hoạt'), 'Unlink explanation missing')
  consent=true; unlink.click(); await settled(); refreshed(from)
  check(!root.querySelector('[data-links-unlink="7"]'), 'Unlinked row remains')
  passed.push('unlink confirmation/cancel/success/refresh')

  choose(7); fail=422; submit(); await settled()
  check(!q('error').hidden && q('error').textContent.includes('API unavailable'), 'Mutation API failure missing')
  check(q('submit').disabled, 'Uncertain mutation allows blind retry')
  q('refresh').click(); await settled(); check(!q('open').disabled, 'Retry did not recover')
  for (const status of [401,404,503]) {
    fail=status; q('refresh').click(); await settled()
    check(!q('error').hidden && q('open').disabled, 'Load failure not safe')
    if(status===401) check(q('error').textContent.includes('đăng nhập'), '401 guidance missing')
    q('refresh').click(); await settled()
  }
  passed.push('API failure, auth failure, retry')

  choose(7); failRefresh=true; submit(); await settled()
  check(q('status').textContent.includes('Đã lưu'), 'Committed success misreported')
  check(q('error').textContent.includes('chưa được cập nhật'), 'Refresh failure not distinguished')
  failRefresh=false; q('refresh').click(); await settled()
  passed.push('mutation success followed by refresh failure')

  candidates.push({id:10,name:'<img src=x onerror=alert(1)>',chip_id:'pir10',linked_buzzer:null,requires_confirmation:false})
  linked.push({id:10,name:candidates.at(-1).name,chip_id:'pir10',relay_index:null,longlast:null})
  q('refresh').click(); await settled()
  check(!q('list').querySelector('img') && q('list').textContent.includes('<img'), 'Untrusted name treated as HTML')
  check(q('list').textContent.includes('Kênh — · — ms'), 'Null fields not handled')
  passed.push('safe rendering and nullable fields')

  from=calls.length; await reload(); check(calls.length-from===2, 'Duplicate Turbo listeners')
  document.dispatchEvent(new Event('turbo:before-cache'))
  from=calls.length; q('refresh').click(); check(calls.length===from, 'Listener survived teardown')
  await reload()
  passed.push('Turbo remount and cleanup')

  candidates=[]; linked=[]; q('refresh').click(); await settled(); q('open').click()
  check(!q('no-candidates').hidden && q('submit').disabled, 'Empty candidates not handled')
  check(writes().every(c=>c.url.includes('/linked_pirs')), 'Management invoked another endpoint')
  const testForm=document.querySelector('[data-buzzer-test-form]')
  testForm.dispatchEvent(new Event('turbo:submit-start',{bubbles:true}))
  check(testForm.querySelector('button').disabled, 'Existing Test Buzzer loading behavior broken')
  testForm.dispatchEvent(new CustomEvent('turbo:submit-end',{bubbles:true,detail:{success:false}}))
  check(!testForm.querySelector('button').disabled, 'Test Buzzer retry behavior broken')
  passed.push('empty candidates, no Test Buzzer calls, existing Test Buzzer behavior')
  document.querySelector('#result').textContent='PASS: ' + passed.join(' | ')
} catch(error) { document.querySelector('#result').textContent='FAIL: ' + error.stack }
`
const server = createServer(async (req, res) => {
  if (req.url === '/style.css') { res.setHeader('Content-Type', 'text/css'); return res.end(css) }
  if (req.url === '/test.js') { res.setHeader('Content-Type', 'text/javascript'); return res.end(browserTests) }
  if (['/buzzer_links.js', '/buzzer_test.js'].includes(req.url)) {
    res.setHeader('Content-Type', 'text/javascript')
    return res.end(await readFile(`app/javascript${req.url}`, 'utf8'))
  }
  res.setHeader('Content-Type', 'text/html; charset=utf-8')
  res.end(`<!doctype html><meta charset="utf-8"><meta name="csrf-token" content="test-csrf"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/style.css"><style>*{box-sizing:border-box}body{margin:20px}.buzzer-device{width:350px;max-width:100%}</style>
    <section class="buzzer-device"><span data-buzzer-linked-count>0</span>
    <form data-buzzer-test-form><button data-buzzer-test-button>Test Buzzer</button></form>
    <div class="buzzer-device__card" data-buzzer-links data-buzzer-id="42"><div data-links-fallback>Server fallback</div>${partial}</div></section>
    <pre id="result">RUNNING</pre><script type="module" src="/test.js"></script>`)
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const profile = await mkdtemp(join(tmpdir(), 'buzzer-links-browser-'))
try {
  const chrome = process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  const child = spawn(chrome, ['--headless', '--disable-gpu', '--no-first-run', '--disable-background-networking',
    `--user-data-dir=${profile}`, '--dump-dom', '--window-size=390,950', '--virtual-time-budget=15000', `http://127.0.0.1:${server.address().port}`])
  let output = '', errors = ''
  child.stdout.on('data', data => { output += data })
  child.stderr.on('data', data => { errors += data })
  const timer = setTimeout(() => child.kill(), 30000)
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve) })
  clearTimeout(timer)
  const result = output.match(/<pre id="result">([\s\S]*?)<\/pre>/)?.[1]
  assert.equal(code, 0, errors.slice(-1000))
  assert.ok(result?.startsWith('PASS:'), result || errors.slice(-1000))
  console.log(result)
} finally {
  server.close()
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 })
}
