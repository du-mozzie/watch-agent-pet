import { createRegistry } from './bootstrap.js';
import { PluginRuntime } from './runtime.js';
import { loadConfig } from '../../config/load.js';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const registry=createRegistry(), runtime=new PluginRuntime(registry,{dataDirBase:join(tmpdir(),'watch-agent-pet-bridge')});
const config=await loadConfig(process.argv[2]??fileURLToPath(new URL('../../config/demo.json',import.meta.url)),registry);
await runtime.apply(config);
console.log('Bridge connected:',runtime.service.snapshot().transport,'(simulated data)');
runtime.service.subscribe(s=>console.log(JSON.stringify({status:s.status,storage:s.storage?.records??0,metrics:Object.keys(s.health)})));
for(const signal of ['SIGINT','SIGTERM']) process.on(signal,async()=>{await runtime.stop();process.exit(0);});
