import { randomUUID } from 'node:crypto';

/** Ordered, connection-scoped session. Snapshot resync replaces replay in M1a. */
export class Session {
  constructor({connection,codec,sender,peer,onMessage,onError=()=>{}}) {
    this.connection=connection; this.codec=codec; this.sender=sender; this.peer=peer;
    this.epoch=randomUUID(); this.seq=new Map(); this.received=new Map(); this.peerEpoch=null;
    this.closed=false;
    this.unsubscribe=connection.subscribeMessages(bytes=>{
      if (this.closed) return;
      try {
        const frame=codec.decode(bytes);
        if (frame.sender !== peer) throw new Error('消息来源与绑定设备不符');
        if (this.peerEpoch && frame.epoch !== this.peerEpoch) throw new Error('会话 epoch 变化，需要重新连接');
        this.peerEpoch=frame.epoch;
        if (frame.seq <= (this.received.get(frame.ch) ?? 0)) return;
        onMessage(frame);
        this.received.set(frame.ch,frame.seq);
      } catch(error) {onError(error);}
    });
  }
  send(ch,payload) {
    if (this.closed) throw new Error('会话已关闭');
    const seq=(this.seq.get(ch)??0)+1;
    this.connection.send(this.codec.encode({v:1,sender:this.sender,epoch:this.epoch,ch,seq,ts:Date.now(),payload}));
    this.seq.set(ch,seq);
  }
  close() {if (this.closed) return; this.closed=true; this.unsubscribe(); this.connection.close();}
}
