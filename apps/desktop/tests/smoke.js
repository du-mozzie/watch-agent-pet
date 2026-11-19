import { _electron as electron } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir,mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const appDir=resolve(fileURLToPath(new URL('..',import.meta.url)));
const resultDir=resolve(appDir,'../../test-results');
await mkdir(resultDir,{recursive:true});
const userData=await mkdtemp(join(tmpdir(),'watch-agent-pet-test-'));
const env={...process.env,WATCH_AGENT_PET_TEST:'1',WATCH_AGENT_PET_TEST_DATA:userData};
delete env.ELECTRON_RUN_AS_NODE;
const executablePath=process.env.WATCH_AGENT_PET_EXECUTABLE;
const launch=()=>electron.launch({...(executablePath?{executablePath}:{}),args:executablePath?[]:[appDir],env,timeout:30000});
let app=await launch();
try {
  const page=await app.firstWindow(), errors=[];
  assert.equal(await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].isVisible()),false,'Smoke tests must not show desktop windows');
  page.on('pageerror',error=>errors.push(error.message));
  await page.locator('#connection-status').filter({hasText:'已连接'}).waitFor();
  await page.waitForFunction(()=>document.getElementById('heart-rate').textContent!=='—');
  // 本地采集：目录与记录数持续增长。
  await page.waitForFunction(()=>document.getElementById('storage-records').textContent!=='0 条记录');
  await page.waitForFunction(()=>document.getElementById('data-dir').value.length>0);
  await page.locator('#transport-select').selectOption('loopback-websocket');
  await page.locator('#device-select').selectOption('simulator-minimal');
  await page.locator('#apply').click();
  await page.waitForFunction(()=>document.getElementById('transport-label').textContent.includes('loopback-websocket'));
  await page.waitForFunction(()=>document.getElementById('spo2-quality').textContent==='当前设备不支持');
  assert.equal(await page.evaluate(()=>typeof window.require),'undefined');
  assert.equal(await page.evaluate(()=>typeof window.process),'undefined');
  await page.locator('#disconnect').click();
  await page.waitForFunction(()=>document.getElementById('connection-status').textContent==='已断开');
  await page.waitForFunction(()=>document.getElementById('heart-rate').textContent==='—');
  await page.locator('#device-select').selectOption('simulator-full');
  await page.locator('#apply').click();
  await page.waitForFunction(()=>document.getElementById('spo2').textContent==='98');
  await page.locator('a[href="#plugins"]').click();
  assert.equal((await page.evaluate(()=>window.pet.snapshot())).status,'connected');
  const rejection=await page.evaluate(async()=>{
    try {await window.pet.configure({profile:'untrusted-module',transport:'memory'});return false;} catch {return true;}
  });
  assert.equal(rejection,true);
  assert.equal((await page.evaluate(()=>window.pet.snapshot())).transport,'loopback-websocket');
  await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({path:join(resultDir,'desktop.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  await app.close(); app=await launch();
  const reopened=await app.firstWindow();
  await reopened.waitForFunction(()=>document.getElementById('connection-status').textContent==='已连接');
  await reopened.waitForFunction(()=>document.getElementById('transport-select').value==='loopback-websocket');
  console.log('Desktop smoke: health capture, switching, disconnect, isolation, rejected config and persistence PASS');
} finally {await app.close();}
