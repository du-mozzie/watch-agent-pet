import { app,BrowserWindow,ipcMain,dialog,clipboard,Notification,session } from 'electron';
import { readFile,writeFile,mkdir,rename } from 'node:fs/promises';
import { join,dirname } from 'node:path';
import { fileURLToPath,pathToFileURL } from 'node:url';
import { createRegistry } from './bootstrap.js';
import { PluginRuntime } from './runtime.js';
import { loadConfig,validateConfig } from '../../config/load.js';
import { createHost } from '../../platforms/electron-host.js';

const here=dirname(fileURLToPath(import.meta.url));
const registry=createRegistry(), runtime=new PluginRuntime(registry,{dataDirBase:app.getPath('userData')});
let window,host,config,quitting=false;
const viewUrl=pathToFileURL(join(here,'presentation/index.html')).href;
const testing=process.env.WATCH_AGENT_PET_TEST==='1';
if (testing) app.setPath('userData',process.env.WATCH_AGENT_PET_TEST_DATA);
const settingsPath=()=>join(app.getPath('userData'),'runtime.json');
async function persist(value) {
  await mkdir(app.getPath('userData'),{recursive:true});
  const target=settingsPath();
  await writeFile(target+'.tmp',JSON.stringify(value,null,2),'utf8');
  await rename(target+'.tmp',target);
}
let commands=Promise.resolve();
function register(name,fn) {
  ipcMain.handle(`pet:${name}`,(event,...args)=>{
    if (event.sender!==window?.webContents || event.senderFrame!==window.webContents.mainFrame || event.senderFrame.url.split('#')[0]!==viewUrl) throw new Error('拒绝未知调用者');
    const run=commands.then(()=>fn(...args)).then(value=>({ok:true,value}),error=>({ok:false,error:error.message}));
    commands=run.then(()=>{});
    return run;
  });
}
async function applyAndSave(next) {
  validateConfig(next,registry);
  const previous=config;
  try {await runtime.apply(next);}
  catch(error) {
    if(previous) await runtime.apply(previous).catch(()=>{});
    throw error;
  }
  config=structuredClone(next);
  await persist(config);
  return snapshot();
}
function snapshot() {return {...runtime.service.snapshot(),host:host.describe(),config,plugins:registry.list()};}
function makeWindow() {
  window=new BrowserWindow({width:1180,height:830,minWidth:920,minHeight:680,title:'Watch Agent Pet',backgroundColor:'#f5f4ef',
    webPreferences:{preload:join(here,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
  host=createHost({app,clipboard,Notification,window});
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  window.webContents.on('will-navigate',event=>event.preventDefault());
  window.loadFile(join(here,'presentation/index.html'));
}
app.whenReady().then(async()=>{
session.defaultSession.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
session.defaultSession.setPermissionCheckHandler(()=>false);
  register('snapshot',()=>snapshot());
  register('connect',()=>runtime.apply(config));
  register('disconnect',()=>runtime.stop());
  register('storage',async dataDir=>{
    if (typeof dataDir !== 'string' || dataDir.length === 0) throw new Error('请选择数据目录');
    validateConfig({...config,storage:{dataDir}},registry);
    const next=structuredClone(config);
    next.storage={dataDir};
    const previous=runtime.service.snapshot().storage;
    try {await runtime.setDataDir(dataDir);}
    catch(error) {
      await runtime.setDataDir(previous.dir ?? config.storage?.dataDir ?? 'data').catch(()=>{});
      throw error;
    }
    config=structuredClone(next);
    await persist(config);
    return snapshot();
  });
  register('pickDataDir',async()=>{
    const result=await dialog.showOpenDialog(window,{properties:['openDirectory','createDirectory']});
    return result.canceled?null:result.filePaths[0];
  });
register('configure',async selection=>{
  if (!selection || typeof selection.profile!=='string' || typeof selection.transport!=='string') throw new Error('请选择设备和通道');
  const next=structuredClone(config), d=next.devices.find(d=>d.enabled);
  d.profile=selection.profile; d.connection.transportPriority=[selection.transport];
  return applyAndSave(next);
});
register('import',async()=>{
  const result=await dialog.showOpenDialog(window,{properties:['openFile'],filters:[{name:'运行配置',extensions:['json']}]});
  if (result.canceled) return null;
  const next=await loadConfig(result.filePaths[0],registry);
  return applyAndSave(next);
});
register('copy',text=>host.copy(text));
register('pin',enabled=>host.alwaysOnTop(enabled));
makeWindow();
try {
  try {config=await loadConfig(settingsPath(),registry);}
  catch(error) {
    if(error.code!=='ENOENT') throw error;
    config=await loadConfig(join(app.getAppPath(),'config/demo.json'),registry);
  }
  await runtime.apply(config);
} catch(error) {
  // Keep configuration errors visible; never silently substitute a real device.
  config??=JSON.parse(await readFile(join(app.getAppPath(),'config/demo.json'),'utf8'));
  runtime.service.update({status:'error',error:`启动配置失败：${error.message}`});
}
runtime.service.subscribe(()=>{if(window&&!window.isDestroyed()) window.webContents.send('pet:changed');});
app.on('activate',()=>{if(BrowserWindow.getAllWindows().length===0) makeWindow();});
app.on('window-all-closed',()=>app.quit());
app.on('before-quit',event=>{
  if(quitting) return;
  event.preventDefault(); quitting=true;
  runtime.stop().finally(()=>app.quit());
});
}).catch(error=>{console.error(error);app.exit(1);});
