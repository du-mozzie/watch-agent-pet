import { createRegistry, PluginRuntime, loadDefaultConfig } from '@watch-agent-pet/runtime';
import { simulatorPlugins } from '@watch-agent-pet/device-simulator';
import { loadConfig } from '@watch-agent-pet/runtime/config';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const registry=createRegistry({devices:simulatorPlugins}), runtime=new PluginRuntime(registry,{dataDirBase:join(tmpdir(),'watch-agent-pet-bridge')});
const config=process.argv[2]?await loadConfig(process.argv[2],registry):await loadDefaultConfig(registry);
await runtime.apply(config);
console.log('Bridge connected:',runtime.service.snapshot().transport,'(simulated data)');
if(process.send) process.send({status:'connected'});
runtime.service.subscribe(s=>console.log(JSON.stringify({status:s.status,storage:s.storage?.records??0,metrics:Object.keys(s.health)})));
for(const signal of ['SIGINT','SIGTERM']) process.on(signal,async()=>{await runtime.stop();process.exit(0);});
// Allows embedding/automation to stop cleanly on Windows as well.
process.on('message',async message=>{if(message==='stop'){await runtime.stop();process.exit(0);}});
