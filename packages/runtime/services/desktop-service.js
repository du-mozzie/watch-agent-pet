import { EventEmitter } from 'node:events';

export class DesktopService extends EventEmitter {
  constructor() {
    super();
    this.value={status:'offline',device:null,transport:null,storage:{dir:null,records:0,files:0,lastError:null},health:{},error:null,revision:0};
  }
  snapshot(now=Date.now()) {
    const result=structuredClone(this.value);
    for (const sample of Object.values(result.health)) {
      sample.stale=now-sample.sampledAt>10000 || result.status!=='connected';
    }
    return result;
  }
  update(patch) {Object.assign(this.value,patch); this.value.revision++; this.emit('change',this.snapshot());}
  accept(frame) {
    if (frame.ch!=='health') return;
    const p=frame.payload, previous=this.value.health[p.metric];
    if (p.sampledAt>Date.now()+60000 || (previous && p.sampledAt<previous.sampledAt)) return;
    this.update({health:{...this.value.health,[p.metric]:{...p,deviceId:frame.sender}}});
  }
  subscribe(fn) {this.on('change',fn); return ()=>this.off('change',fn);}
}
