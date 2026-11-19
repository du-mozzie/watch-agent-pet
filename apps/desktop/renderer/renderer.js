const $=id=>document.getElementById(id);
let revision=-1, initialized=false, busy=false;
function error(message) {$('error').textContent=message??''; $('error').hidden=!message;}
async function action(fn) {
  if(busy) return;
  busy=true; document.querySelectorAll('button').forEach(b=>b.disabled=true);
  try {await fn(); error(null); await refresh();} catch(e){error(e.message);}
  finally {busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);}
}
function render(s) {
  if(s.revision<revision) return; revision=s.revision;
  const connected=s.status==='connected';
  $('connection-status').textContent=({connected:'已连接',offline:'已断开',connecting:'连接中',error:'连接失败'})[s.status];
  $('connection-detail').textContent=connected?'配置已生效':'连接后开始同步';
  // 桌宠展示健康摘要（Agent 状态不下发手表，六态展示已移除）。
  const hr=s.health['heart-rate'], live=hr&&!hr.stale&&hr.quality==='valid';
  $('pet').dataset.state=connected?'calm':'idle';
  $('pet-state').textContent=connected?(live?'守护中':'等待采样'):'休息中';
  $('pet-message').textContent=connected?(live?`心率 ${hr.value} bpm，一切都在记录里。`:'手表连接好了，等第一份健康数据。'):'噜噜休息了，重新连接即可唤醒。';
  $('device-label').textContent=s.device?.name??'尚未连接设备';
  $('transport-label').textContent=s.transport?`· ${s.transport}`:'';
  $('platform').textContent=`${s.host.id} · 自动输入暂不支持`;
  for(const key of ['heart-rate','spo2','temperature']) {
    const sample=s.health[key], supported=s.device?.capabilities[key];
    $(key).textContent=sample&&!sample.stale&&sample.quality==='valid'?String(sample.value):'—';
    $(`${key}-quality`).textContent=supported==='unsupported'?'当前设备不支持':!sample?'等待采样':sample.stale?'数据已过期':sample.quality==='valid'?'模拟采样 · 刚刚更新':'暂无有效数据';
  }
  // 本地采集状态
  const storage=s.storage;
  if (storage) {
    $('data-dir').value=storage.dir??'';
    $('storage-records').textContent=`${storage.records} 条记录`;
    $('storage-files').textContent=`${storage.files} 个文件`;
    $('storage-error').textContent=storage.lastError?`写入异常：${storage.lastError}`:'';
  }
  $('freshness').textContent=connected?'每 1.5 秒更新 · 本地模拟':'已停止同步';
  if(s.error) error(s.error);
  if(!initialized && s.config) {
    for(const [kind,id] of [['device','device-select'],['transport','transport-select']]) {
      for(const plugin of s.plugins.filter(p=>p.kind===kind)) {const o=document.createElement('option');o.value=plugin.id;o.textContent=plugin.name;$(id).append(o);}
    }
    for(const plugin of s.plugins) {const el=document.createElement('span');el.textContent=`${plugin.kind} / ${plugin.id}`;$('plugin-list').append(el);}
    const d=s.config?.devices.find(d=>d.enabled);
    if(d){$('device-select').value=d.profile;$('transport-select').value=d.connection.transportPriority[0];}
    initialized=true;
  }
}
async function refresh(){try{render(await window.pet.snapshot());}catch(e){error(e.message);}}
$('apply').addEventListener('click',()=>action(()=>window.pet.configure({profile:$('device-select').value,transport:$('transport-select').value})));
$('disconnect').addEventListener('click',()=>action(()=>window.pet.disconnect()));
$('pin').addEventListener('change',()=>action(()=>window.pet.pin($('pin').checked)));
$('pick-dir').addEventListener('click',()=>action(async()=>{
  const dir=await window.pet.pickDataDir();
  if(dir) await window.pet.setDataDir(dir);
}));
$('import').addEventListener('click',()=>action(async()=>{const s=await window.pet.importConfig();if(s){const d=s.config.devices.find(d=>d.enabled);$('device-select').value=d.profile;$('transport-select').value=d.connection.transportPriority[0];}}));
window.pet.subscribe(refresh);
setInterval(refresh,2000);
refresh();
