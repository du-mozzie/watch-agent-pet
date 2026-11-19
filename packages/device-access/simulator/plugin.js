import { METRICS } from '@watch-agent-pet/contracts';

function createSimulator({instanceId,variant}) {
  let timer, tick=0;
  return {
    describe:()=>({id:instanceId,name:variant==='minimal'?'轻量模拟手表':'完整模拟手表',simulated:true,
      capabilities:{'heart-rate':'supported',spo2:variant==='minimal'?'unsupported':'supported',temperature:variant==='minimal'?'unsupported':'supported'}}),
    start({onSample,onError}) {
      clearInterval(timer);
      // Acquisition knows measurements only; the host owns sessions and encoding.
      const sample=()=>{
        tick++;
        const sampledAt=Date.now();
        const values=[['heart-rate',72+Math.round(Math.sin(tick/3)*5)]];
        if (variant!=='minimal') values.push(['spo2',98],['temperature',36.4]);
        for (const [metric,value] of values) {
          try {onSample({metric,value,unit:METRICS[metric],sampledAt,quality:'valid'});} catch(e) {onError(e);}
        }
      };
      timer=setInterval(sample,1500); sample();
    },
    stop() {clearInterval(timer); timer=undefined;}
  };
}
export const simulatorPlugins = ['full','minimal'].map(variant=>({
  id:`simulator-${variant}`,name:variant==='full'?'完整模拟手表':'轻量模拟手表',apiVersion:1,
  transports:['memory','loopback-websocket'],create:options=>createSimulator({...options,variant})
}));
