// Real DOM behavior against mocked management API responses.
// Run: node spec/javascript/pir_trigger_actions_test.mjs (CHROME_BIN may override Chrome).
import { readFile, mkdtemp, rm } from 'node:fs/promises'
import { createServer } from 'node:http'
import { spawn } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import assert from 'node:assert/strict'
import * as sass from 'sass'

const css = sass.compile('app/assets/stylesheets/devices/_pir_device.scss').css
const partial = (await readFile('app/views/devices/_pir_trigger_actions.html.erb', 'utf8'))
  .replace('<%= @device.chip_id %>', 'pir-42')
const browserTests = `
import '/pir_trigger_actions.js'
const root = document.querySelector('[data-pir-trigger-actions]')
const q = name => root.querySelector('[data-actions-' + name + ']')
const check = (value, message) => { if (!value) throw new Error(message) }
const wait = async condition => {
  for (let i=0; i<150; i++) { if (condition()) return; await new Promise(resolve => setTimeout(resolve, 10)) }
  throw new Error('Timed out waiting for UI')
}
const settled = () => wait(() => !q('refresh').disabled)
let calls = [], nextId = 3, mode = 'none', fail = null, confirmations = []
let targets = [
  {id: 10, chip_id:'switch-10', name:'Công tắc phòng', device_type:'switch', relay_indexes:[0,1], duration_ms:{minimum:100,maximum:86400000}},
  {id: 20, chip_id:'buzzer-20', name:'Chuông cửa', device_type:'buzzer', relay_indexes:[0], duration_ms:{minimum:100,maximum:10000}}
]
let actions = []
window.confirm = text => { confirmations.push(text); return true }
const result = body => ({ok:true,status:200,json:async()=>structuredClone(body)})
window.fetch = async (url, options) => {
  calls.push({url,...options})
  check(url.startsWith('/api/devices/pir-42/trigger_actions'), 'Unexpected API: ' + url)
  check(options.credentials==='same-origin', 'Missing session credentials')
  check(options.headers['X-CSRF-Token']==='csrf-test', 'Missing CSRF')
  check(!url.includes('mqtt'), 'Browser attempted MQTT')
  if (fail) { const item=fail; fail=null; return {ok:false,status:item.status,json:async()=>({status:'error',code:item.code})} }
  if (url.endsWith('/targets')) return result({status:'success',targets})
  if (url.endsWith('/migrate_legacy') && options.method==='POST') {
    mode='actions'; actions=[{...actions[0],id:nextId++,origin:'persisted'}]
    return result({status:'success',migrated:true,mode:'actions',action:actions[0]})
  }
  if (url.endsWith('/order') && options.method==='PUT') {
    const ids=JSON.parse(options.body).action_ids
    actions=ids.map((id,index)=>({...actions.find(a=>a.id===id),position:index}))
    return result({status:'success',actions})
  }
  const match=url.match(/trigger_actions\\/(\\d+)$/)
  if (match && options.method==='DELETE') { actions=actions.filter(a=>a.id!==Number(match[1])); mode=actions.length?'actions':'none'; return result({status:'success'}) }
  if (match && options.method==='PUT') {
    const body=JSON.parse(options.body); actions=actions.map(a=>a.id===Number(match[1])?{...a,...body,target:body.target_device_id?targets.find(t=>t.id===body.target_device_id):a.target}:a)
    return result({status:'success',action:actions.find(a=>a.id===Number(match[1]))})
  }
  if (options.method==='POST') {
    const body=JSON.parse(options.body), target=targets.find(t=>t.id===body.target_device_id)
    const action={id:nextId++,origin:'persisted',position:actions.length,target,...body}; actions.push(action); mode='actions'
    return {ok:true,status:201,json:async()=>({status:'success',action})}
  }
  return result({status:'success',configuration_mode:mode,source_device:{id:42},actions})
}
const load = async () => { document.dispatchEvent(new Event('turbo:load')); await settled() }
const writes = () => calls.filter(c => ['POST','PUT','DELETE'].includes(c.method))
const refreshedAfter = from => {
  const recent=calls.slice(from)
  check(recent.some(c=>c.method==='GET' && c.url.endsWith('trigger_actions')), 'Configuration not authoritatively refreshed')
  check(recent.some(c=>c.method==='GET' && c.url.endsWith('/targets')), 'Targets not authoritatively refreshed')
}
const openWith = id => { q('add').click(); q('target').value=String(id); q('target').dispatchEvent(new Event('change')) }
const submit = () => q('form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))
const action = (id, target, values={}) => ({id,origin:'persisted',action_type:'relay_pulse',target,relay_index:0,duration_ms:1000,delay_ms:0,enabled:true,position:id,...values})
let passed=[]
try {
  document.dispatchEvent(new Event('turbo:load'))
  check(q('status').textContent.includes('Đang tải'), 'Loading state missing')
  await settled()
  check(!q('empty').hidden && q('list').children.length===0, 'None empty state missing')
  passed.push('none and loading')

  openWith(10)
  check(q('relay').options.length===3, 'Switch relay constraints missing')
  check(q('duration').max==='86400000', 'Switch duration constraints missing')
  q('relay').value='1'; q('duration').value='5000'; q('delay').value='250'
  let from=calls.length; submit(); await settled(); refreshedAfter(from)
  check(q('list').textContent.includes('Công tắc phòng') && q('list').textContent.includes('Công tắc'), 'Switch action missing')
  passed.push('add and authoritative refresh')

  openWith(20)
  check(q('relay').options.length===2 && q('duration').max==='10000', 'Buzzer constraints missing')
  q('duration').value='1000'; submit(); await settled()
  check(q('list').children.length===2 && q('list').textContent.includes('Buzzer'), 'Multiple target types missing')
  passed.push('multiple switch and buzzer rendering')

  let edit=root.querySelector('[data-action-id="3"] [data-action-operation="edit"]'); edit.click()
  q('target').value='10'; q('target').dispatchEvent(new Event('change')); q('relay').value='0'; q('duration').value='8000'; q('delay').value='500'; q('enabled').checked=false
  from=calls.length; submit(); await settled(); refreshedAfter(from)
  check(q('list').textContent.includes('8000 ms') && q('list').textContent.includes('trễ 500 ms') && q('list').textContent.includes('Đã tắt'), 'Edit fields not reflected')
  passed.push('edit all mutable fields')

  from=calls.length; root.querySelector('[data-action-id="3"] [data-action-operation="toggle"]').click(); await settled(); refreshedAfter(from)
  check(q('list').textContent.includes('Đang bật'), 'Toggle not reflected')
  from=calls.length; root.querySelector('[data-action-id="4"] [data-action-operation="up"]').click(); await settled(); refreshedAfter(from)
  check(q('list').firstElementChild.dataset.actionId==='4', 'Backend order not reflected')
  passed.push('toggle and reorder')

  from=calls.length; root.querySelector('[data-action-id="3"] [data-action-operation="delete"]').click()
  check(q('list').querySelector('[data-action-id="3"]'), 'Delete removed optimistically')
  await settled(); refreshedAfter(from); check(!q('list').querySelector('[data-action-id="3"]'), 'Delete refresh not reflected')
  passed.push('backend-confirmed delete')

  openWith(10); q('relay').value='999'; from=writes().length; submit()
  check(writes().length===from && q('error').textContent.includes('Kiểm tra'), 'Invalid relay sent')
  q('relay').value='0'; q('duration').value='99'; submit(); check(writes().length===from, 'Invalid duration sent')
  q('duration').value='100'; q('delay').value='300001'; submit(); check(writes().length===from, 'Invalid delay sent')
  q('cancel').click()
  passed.push('client constraints')

  for (const [code,text] of [['duplicate_action','đã được cấu hình'],['invalid_relay_index','không còn hợp lệ'],['invalid_duration','ngoài giới hạn'],['invalid_delay','Độ trễ']]) {
    openWith(10); q('relay').value='0'; q('duration').value='100'; q('delay').value='0'; fail={status:code==='duplicate_action'?409:422,code}; submit(); await settled()
    check(q('error').textContent.includes(text), 'Safe error missing: '+code)
    q('refresh').click(); await settled(); q('cancel').click()
  }
  fail={status:404,code:'target_not_found'}; q('refresh').click(); await settled()
  check(q('error').textContent.includes('Không thể sử dụng') && !q('error').textContent.includes('switch-10'), '404 leaked target details')
  q('refresh').click(); await settled()
  passed.push('safe API errors and inaccessible target')

  mode='legacy'; actions=[{id:null,origin:'legacy',target:targets[1],action_type:'relay_pulse',relay_index:0,duration_ms:1000,delay_ms:0,enabled:true,position:0}]
  q('refresh').click(); await settled(); check(!q('legacy').hidden && q('list').textContent.includes('Chuông cửa') && q('add').disabled, 'Legacy read state missing')
  from=calls.length; q('migrate').click(); await settled(); refreshedAfter(from); check(mode==='actions' && q('legacy').hidden, 'Legacy migration failed')
  mode='invalid_legacy'; actions=[]; q('refresh').click(); await settled()
  check(!q('invalid-legacy').hidden && q('add').disabled && !q('invalid-legacy').textContent.includes('migrate'), 'Invalid legacy safety missing')
  passed.push('legacy migration and invalid legacy')

  fail={status:401}; q('refresh').click(); await settled(); check(q('error').textContent.includes('đăng nhập'), '401 guidance missing')
  check(calls.every(c=>!c.url.includes('mqtt')), 'MQTT call detected')
  document.dispatchEvent(new Event('turbo:before-cache')); from=calls.length; q('refresh').click(); check(calls.length===from, 'Turbo teardown failed')
  passed.push('session, no MQTT, Turbo cleanup')
  document.querySelector('#result').textContent='PASS: '+passed.join(' | ')
} catch(error) { document.querySelector('#result').textContent='FAIL: '+error.stack }
`

const server=createServer(async (req,res)=>{
  if(req.url==='/style.css'){res.setHeader('Content-Type','text/css');return res.end(css)}
  if(req.url==='/test.js'){res.setHeader('Content-Type','text/javascript');return res.end(browserTests)}
  if(req.url==='/pir_trigger_actions.js'){res.setHeader('Content-Type','text/javascript');return res.end(await readFile('app/javascript/pir_trigger_actions.js','utf8'))}
  res.setHeader('Content-Type','text/html; charset=utf-8')
  res.end(`<!doctype html><meta name="csrf-token" content="csrf-test"><meta name="viewport" content="width=device-width"><link rel="stylesheet" href="/style.css"><div class="pir-device">${partial}</div><pre id="result">RUNNING</pre><script type="module" src="/test.js"></script>`)
})
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
const profile=await mkdtemp(join(tmpdir(),'pir-actions-browser-'))
try {
  const chrome=process.env.CHROME_BIN||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  const child=spawn(chrome,['--headless','--disable-gpu','--no-first-run','--disable-background-networking','--enable-logging=stderr',`--user-data-dir=${profile}`,'--dump-dom','--window-size=390,1000','--virtual-time-budget=20000',`http://127.0.0.1:${server.address().port}`])
  let output='',errors='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>errors+=d)
  const timer=setTimeout(()=>child.kill(),35000)
  const code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',resolve)});clearTimeout(timer)
  const result=output.match(/<pre id="result">([\s\S]*?)<\/pre>/)?.[1]
  assert.equal(code,0,errors.slice(-2000));assert.ok(result?.startsWith('PASS:'),`${result}\n${errors.slice(-4000)}`);console.log(result)
} finally {server.close();await rm(profile,{recursive:true,force:true,maxRetries:5,retryDelay:200})}
