import { Session } from '../../connectivity/session.js';

function createSimulator({instanceId,variant}) {
  let session, timer, tick=0;
  return {
    describe:()=>({id:instanceId,name:variant==='minimal'?'轻量模拟手表':'完整模拟手表',simulated:true,
      capabilities:{'heart-rate':'supported',spo2:variant==='minimal'?'unsupported':'supported',temperature:variant==='minimal'?'unsupported':'supported'}}),
    start({connection,codec,onError}) {
      // 手表端只上报健康数据；Agent 状态不下发手表（协议保留 agent-state 通道，供 PC 端接入 Agent 来源的后期扩展）。
      session=new Session({connection,codec,sender:instanceId,peer:'desktop',onError,onMessage:()=>{}});
      const sample=()=>{
        tick++;
        const sampledAt=Date.now();
        const values=[['heart-rate',72+Math.round(Math.sin(tick/3)*5),'bpm']];
        if (variant!=='minimal') values.push(['spo2',98,'%'],['temperature',36.4,'°C']);
        for (const [metric,value,unit] of values) {
          try {session.send('health',{metric,value,unit,sampledAt,quality:'valid'});} catch(e) {onError(e);}
        }
      };
      timer=setInterval(sample,1500); sample();
    },
    stop() {clearInterval(timer); timer=undefined; session?.close(); session=undefined;}
  };
}
export const simulatorPlugins = ['full','minimal'].map(variant=>({
  id:`simulator-${variant}`,name:variant==='full'?'完整模拟手表':'轻量模拟手表',apiVersion:1,
  transports:['memory','loopback-websocket'],create:options=>createSimulator({...options,variant})
}));
