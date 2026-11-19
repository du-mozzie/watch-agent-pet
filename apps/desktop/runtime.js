import { DesktopService } from '../../core/desktop-service.js';
import { validateConfig } from '../../config/load.js';
import { Session } from '../../connectivity/session.js';
import { createHealthStore, resolveDataDir } from './health-store.js';

export class PluginRuntime {
  constructor(registry, { dataDirBase = process.cwd() } = {}) {
    this.registry=registry; this.service=new DesktopService(); this.queue=Promise.resolve(); this.generation=0; this.resources=null;
    this.dataDirBase=dataDirBase;
  }
  serialize(fn) {const result=this.queue.then(fn); this.queue=result.catch(()=>{}); return result;}
  apply(value) {
    // Validate before retiring a working configuration.
    const config=validateConfig(value,this.registry);
    return this.serialize(()=>this.activate(config));
  }
  async release() {
    this.generation++;
    const r=this.resources; this.resources=null;
    if (!r) return;
    r.unsubscribe?.();
    try {await r.adapter.stop();} finally {try {await r.session?.close();} finally {try {await r.pair.close();} finally {await r.store?.close();}}}
  }
  async activate(config) {
    await this.release();
    this.config=structuredClone(config);
    const d=config.devices.find(d=>d.enabled), conn=d.connection;
    const generation=this.generation;
    this.service.update({status:'connecting',health:{},device:null,transport:null,error:null});
    const attempts=conn.allowFallback?conn.transportPriority:conn.transportPriority.slice(0,1);
    let lastError;
    for (const transport of attempts) {
      let pair,adapter,session,unsubscribe,store;
      try {
        pair=await this.registry.get('transport',transport).create().open(conn.options?.[transport]??{});
        adapter=this.registry.get('device',d.profile).create({instanceId:d.instanceId});
        const codec=this.registry.get('codec',conn.codec).create();
        const onError=error=>{if (generation===this.generation) this.service.update({error:error.message});};
        // 本地采集：健康帧写入可配置目录（磁盘错误不中断链路）。
        const dataDir=resolveDataDir(config.storage?.dataDir ?? 'data', this.dataDirBase);
        store=createHealthStore({dataDir,onError});
        session=new Session({connection:pair.desktop,codec,sender:'desktop',peer:d.instanceId,
          onMessage: async frame=>{
            if(generation!==this.generation) return;
            // 动态取当前 store：setDataDir 换目录后闭包不持有旧实例。
            // await append 完成后再读取 info()，避免把过时的 records=0 快照推给 UI。
            if (frame.ch==='health') await this.resources?.store?.append({...frame.payload,deviceId:frame.sender});
            this.service.accept(frame);
            if (frame.ch==='health' && this.resources?.store) this.service.update({storage:this.resources.store.info()});
          },onError});
        unsubscribe=pair.desktop.subscribeStatus(()=>{
          if (generation!==this.generation) return;
          this.service.update({status:'offline',error:'连接中断，请重新连接'});
          // Retire timers and callbacks, even when the peer closes unexpectedly.
          this.serialize(async()=>{if(generation===this.generation) await this.release();}).catch(onError);
        });
        this.resources={pair,adapter,session,unsubscribe,store};
        this.service.update({status:'connected',device:adapter.describe(),transport,storage:store.info(),error:null});
        await adapter.start({connection:pair.device,codec,onError});
        return this.service.snapshot();
      } catch(error) {
        lastError=error;
        // A broken plugin cleanup must not prevent the remaining resources closing.
        for (const dispose of [unsubscribe,()=>adapter?.stop(),()=>session?.close(),()=>pair?.close(),()=>store?.close()]) {
          try {await dispose?.();} catch { /* Preserve the original connection error. */ }
        }
        this.resources=null;
      }
    }
    this.service.update({status:'error',device:null,transport:null,error:lastError?.message??'连接失败'});
    throw lastError;
  }
  async setDataDir(value) {
    return this.serialize(async()=>{
      const dataDir=resolveDataDir(value,this.dataDirBase);
      const r=this.resources;
      if (r?.store) await r.store.close();
      // 换目录不重建连接：仅替换存储实例；无连接时直接更新展示。
      const store=createHealthStore({dataDir,onError:error=>{this.service.update({error:error.message});}});
      if (r) {r.store=store; this.service.update({storage:store.info(),error:null});}
      else {this.service.update({storage:{dir:dataDir,records:0,files:0,lastError:null},error:null});}
      return this.service.snapshot();
    });
  }
  stop() {return this.serialize(async()=>{await this.release(); this.service.update({status:'offline',error:null});});}
}
