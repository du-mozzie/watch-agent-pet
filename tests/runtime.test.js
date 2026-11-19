import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRegistry } from '../apps/desktop/bootstrap.js';
import { PluginRuntime } from '../apps/desktop/runtime.js';
import { validateConfig } from '../config/load.js';
import { PluginRegistry } from '../core/registry.js';
import { jsonCodec } from '../connectivity/json-codec.js';
import { Session } from '../connectivity/session.js';
import { memoryPair } from '../connectivity/transports/memory.js';
import { DesktopService } from '../core/desktop-service.js';
import { createHealthStore } from '../apps/desktop/health-store.js';

const base=JSON.parse(await readFile(new URL('../config/demo.json',import.meta.url),'utf8'));
const config=()=>structuredClone(base);
async function until(fn) {
  const end=Date.now()+3000;
  while(Date.now()<end){if(fn())return;await new Promise(r=>setTimeout(r,10));}
  assert.fail('condition did not become true');
}
const frame=(overrides={})=>({v:1,sender:'watch',epoch:'boot',ch:'health',seq:1,ts:Date.now(),payload:{metric:'heart-rate',value:72,unit:'bpm',sampledAt:Date.now(),quality:'valid'},...overrides});
const tmpBase=()=>mkdtemp(join(tmpdir(),'watch-agent-pet-test-'));

test('registry rejects incompatible versions and duplicate plugins',()=>{
  const r=new PluginRegistry();
  assert.throws(()=>r.register('device',{id:'x',apiVersion:2,create(){}}));
  r.register('device',{id:'x',apiVersion:1,create(){}});
  assert.throws(()=>r.register('device',{id:'x',apiVersion:1,create(){}}));
});
test('config rejects unknown plugins, duplicate devices, host mismatch and agent section',()=>{
  const r=createRegistry();let c=config();c.devices[0].profile='oppo-watch-4-pro';assert.throws(()=>validateConfig(c,r),/未注册/);
  c=config();c.devices.push(structuredClone(c.devices[0]));assert.throws(()=>validateConfig(c,r),/重复/);
  c=config();c.host.platform='macos';assert.throws(()=>validateConfig(c,r,'win32'),/不匹配/);
  c=config();c.devices[0].connection.transportPriority=['ble-gatt'];assert.throws(()=>validateConfig(c,r),/未注册/);
  c=config();delete c.devices[0].instanceId;assert.throws(()=>validateConfig(c,r),/ID/);
  c=config();c.agent={source:'manual'};assert.throws(()=>validateConfig(c,r),/后期扩展/);
  c=config();c.storage={dataDir:''};assert.throws(()=>validateConfig(c,r),/采集目录/);
});
test('codec rejects invalid state, malformed UTF-8, missing measurement and oversized frame',()=>{
  const codec=jsonCodec.create();
  assert.throws(()=>codec.decode(Buffer.from([0xff])));
  assert.throws(()=>codec.encode(frame({payload:{metric:'heart-rate',unit:'bpm',sampledAt:1,quality:'valid'}})));
  assert.throws(()=>codec.encode(frame({ch:'agent-state',payload:{state:'unknown'}})));
  assert.throws(()=>codec.decode(Buffer.alloc(4097)));
  assert.deepEqual(codec.decode(codec.encode(frame({seq:15}))).seq,15);
});
for (const transport of ['memory','loopback-websocket']) {
  test(`${transport}: health uplink reaches service and is captured to the configured local dir`,async()=>{
    const dir=await tmpBase();
    const r=new PluginRuntime(createRegistry(),{dataDirBase:dir});const c=config();c.devices[0].connection.transportPriority=[transport];
    try {
      await r.apply(c);await until(()=>r.service.snapshot().health['heart-rate']);
      assert.equal(r.service.snapshot().device.simulated,true);
      await until(()=>r.service.snapshot().storage.records>0);
      const day=new Date().toISOString().slice(0,10);
      const files=await readdir(join(dir,'data'));
      assert.equal(files.includes(`health-${day}.jsonl`),true);
      const lines=(await readFile(join(dir,'data',`health-${day}.jsonl`),'utf8')).trim().split('\n');
      // 追加为并发异步，行序不保证；校验存在合法 heart-rate 记录且字段完整。
      const rows=lines.map(l=>JSON.parse(l));
      const hr=rows.find(r=>r.metric==='heart-rate');
      assert.ok(hr,'heart-rate record should be captured');
      assert.equal(typeof hr.value,'number');
      assert.equal(hr.deviceId,'demo-watch');assert.equal(hr.quality,'valid');assert.equal(hr.unit,'bpm');
    } finally {await r.stop();}
    assert.equal(r.resources,null);
  });
}
test('switching profiles clears unsupported samples and retires previous adapter',async()=>{
  const r=new PluginRuntime(createRegistry(),{dataDirBase:await tmpBase()});
  try {
    await r.apply(config());await until(()=>r.service.snapshot().health.spo2);
    const old=r.resources;
    const c=config();c.devices[0].profile='simulator-minimal';c.devices[0].connection.transportPriority=['loopback-websocket'];
    await r.apply(c);await until(()=>r.service.snapshot().health['heart-rate']);
    assert.equal(r.service.snapshot().health.spo2,undefined);
    assert.equal(r.service.snapshot().device.capabilities.spo2,'unsupported');
    assert.throws(()=>old.pair.desktop.send(Buffer.from('{}')),/关闭/);
  } finally {await r.stop();}
});
test('invalid config leaves running connection intact',async()=>{
  const r=new PluginRuntime(createRegistry(),{dataDirBase:await tmpBase()});
  try {
    await r.apply(config());const current=r.resources;const c=config();c.devices[0].profile='missing';
    assert.throws(()=>r.apply(c));assert.equal(r.resources,current);assert.equal(r.service.snapshot().status,'connected');
  } finally {await r.stop();}
});
test('fallback is explicit and failed attempts do not leave resources',async()=>{
  const registry=createRegistry();
  registry.register('transport',{id:'broken',name:'Broken',apiVersion:1,create:()=>({open:async()=>{throw new Error('test offline');}})});
  const original=registry.get('device','simulator-full');
  registry.register('device',{...original,id:'fallback-watch',transports:['broken','memory']});
  const r=new PluginRuntime(registry,{dataDirBase:await tmpBase()}),c=config();c.devices[0].profile='fallback-watch';
  c.devices[0].connection.transportPriority=['broken','memory'];
  await assert.rejects(r.apply(c),/offline/);assert.equal(r.resources,null);
  c.devices[0].connection.allowFallback=true;
  try {await r.apply(c);assert.equal(r.service.snapshot().transport,'memory');}finally{await r.stop();}
});
test('concurrent reconfiguration and stop are serialized, with no surviving connection',async()=>{
  const r=new PluginRuntime(createRegistry(),{dataDirBase:await tmpBase()}),c=config();c.devices[0].connection.transportPriority=['loopback-websocket'];
  await Promise.all([r.apply(c),r.apply(config()),r.stop()]);
  assert.equal(r.resources,null);assert.equal(r.service.snapshot().status,'offline');
});
test('session rejects spoofed sender, ignores duplicate sequence, keeps same-state updates',async()=>{
  const pair=memoryPair(),codec=jsonCodec.create(),seen=[],errors=[];
  const session=new Session({connection:pair.desktop,codec,sender:'desktop',peer:'watch',onMessage:f=>seen.push(f),onError:e=>errors.push(e)});
  try {
    pair.device.send(codec.encode(frame({sender:'stranger'})));
    const health=frame({payload:{metric:'heart-rate',value:72,unit:'bpm',sampledAt:Date.now(),quality:'valid'}});
    pair.device.send(codec.encode(health));
    pair.device.send(codec.encode(health));
    pair.device.send(codec.encode(frame({seq:2,payload:{metric:'heart-rate',value:73,unit:'bpm',sampledAt:Date.now(),quality:'valid'}})));
    await until(()=>seen.length===2);
    assert.equal(errors.length,1);assert.equal(seen[1].payload.value,73);
  } finally {session.close();pair.close();}
});
test('old callbacks are ignored after close, queue is bounded',async()=>{
  const pair=memoryPair(),codec=jsonCodec.create();let calls=0;
  const s=new Session({connection:pair.desktop,codec,sender:'desktop',peer:'watch',onMessage:()=>calls++});
  pair.device.send(codec.encode(frame()));s.close();
  await new Promise(r=>setImmediate(r));assert.equal(calls,0);
  const other=memoryPair();try {for(let i=0;i<256;i++)other.desktop.send(Buffer.from('{}'));assert.throws(()=>other.desktop.send(Buffer.from('{}')),/队列/);}finally{other.close();}
});
test('health freshness and sampling order do not fabricate zero values',()=>{
  const service=new DesktopService();service.update({status:'connected'});
  service.accept(frame({payload:{metric:'heart-rate',value:75,unit:'bpm',sampledAt:1000,quality:'valid'}}));
  service.accept(frame({payload:{metric:'heart-rate',value:30,unit:'bpm',sampledAt:900,quality:'valid'}}));
  assert.equal(service.snapshot(1001).health['heart-rate'].value,75);
  assert.equal(service.snapshot(12000).health['heart-rate'].stale,true);
  service.update({status:'offline'});assert.equal(service.snapshot(1001).health['heart-rate'].stale,true);
});
test('health store writes jsonl per day and disk errors do not throw',async()=>{
  const dir=await tmpBase();
  const store=createHealthStore({dataDir:join(dir,'captures'),onError:()=>{}});
  await store.append({metric:'heart-rate',value:72,unit:'bpm',quality:'valid',sampledAt:1,deviceId:'w'});
  await store.append({metric:'spo2',value:98,unit:'%',quality:'valid',sampledAt:2,deviceId:'w'});
  const info=store.info();
  assert.equal(info.records,2);assert.equal(info.files,1);
  // 目录改为一个无效路径（占用一个已存在的文件作为目录）验证错误被吞掉。
  const file=join(dir,'occupied');
  const { writeFile } = await import('node:fs/promises');
  await writeFile(file,'x');
  const broken=createHealthStore({dataDir:file,onError:()=>{}});
  await broken.append({metric:'heart-rate',value:1,unit:'bpm',quality:'valid',sampledAt:3,deviceId:'w'});
  assert.ok(broken.info().lastError,'disk error should be recorded');
  assert.equal(broken.info().records,0);
});
test('unexpected disconnect releases the device and reconnect restores capture',async()=>{
  const base=await tmpBase();
  const r=new PluginRuntime(createRegistry(),{dataDirBase:base});
  try {
    await r.apply(config());await until(()=>r.service.snapshot().storage.records>0);
    const before=r.service.snapshot().storage.records;
    r.resources.pair.close();
    await until(()=>r.resources===null);
    assert.equal(r.service.snapshot().status,'offline');
    await r.apply(config());await until(()=>r.resources.adapter);
    await until(()=>r.service.snapshot().storage.records>0);
    assert.equal(r.service.snapshot().storage.dir,join(base,'data'));
  }finally{await r.stop();}
});
test('setDataDir switches the capture directory without rebuilding the connection',async()=>{
  const base=await tmpBase();
  const r=new PluginRuntime(createRegistry(),{dataDirBase:base});
  try {
    await r.apply(config());const conn=r.resources.session;
    const next=join(base,'moved');
    await r.setDataDir('moved');
    assert.equal(r.service.snapshot().storage.dir,next);
    assert.equal(r.resources.session,conn);
    await until(()=>r.service.snapshot().storage.records>0);
    const files=await readdir(next);
    assert.equal(files.some(f=>f.startsWith('health-')),true);
  }finally{await r.stop();}
});
