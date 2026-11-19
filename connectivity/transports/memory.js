import { EventEmitter } from 'node:events';
import { PluginError } from '../../core/errors.js';

export function memoryPair() {
  const events = [new EventEmitter(),new EventEmitter()];
  let closed = false, pending = 0;
  const ends = events.map((own,i)=>({
    send(bytes) {
      if (closed) throw new PluginError('disconnected','连接已关闭');
      if (pending >= 256) throw new PluginError('backpressure','发送队列已满');
      if (bytes.byteLength > 4096) throw new PluginError('invalid-message','消息过大');
      const copy = Buffer.from(bytes); pending++;
      queueMicrotask(()=>{pending--; if (!closed) events[1-i].emit('message',copy);});
    },
    subscribeMessages(fn) {own.on('message',fn); return ()=>own.off('message',fn);},
    subscribeStatus(fn) {own.on('status',fn); return ()=>own.off('status',fn);},
    close() {
      if (closed) return;
      closed = true;
      for (const e of events) {e.emit('status','closed'); e.removeAllListeners();}
    }
  }));
  return {desktop:ends[0],device:ends[1],close:()=>ends[0].close()};
}
export const memoryTransport = {id:'memory',name:'内存通道',apiVersion:1,create:()=>({open:async()=>memoryPair()})};
