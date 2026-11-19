const {contextBridge,ipcRenderer}=require('electron');
const invoke=async(name,...args)=>{
  const result=await ipcRenderer.invoke(`pet:${name}`,...args);
  if(!result.ok) throw new Error(result.error);
  return result.value;
};
contextBridge.exposeInMainWorld('pet',{
  snapshot:()=>invoke('snapshot'),
  connect:()=>invoke('connect'),disconnect:()=>invoke('disconnect'),
  configure:selection=>invoke('configure',selection),
  importConfig:()=>invoke('import'),copy:text=>invoke('copy',text),pin:enabled=>invoke('pin',enabled),
  setDataDir:dataDir=>invoke('storage',dataDir),pickDataDir:()=>invoke('pickDataDir'),
  subscribe:callback=>{const listener=()=>callback(); ipcRenderer.on('pet:changed',listener); return ()=>ipcRenderer.removeListener('pet:changed',listener);}
});
