import { readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
let count=0;
async function check(dir) {
  for(const item of await readdir(dir,{withFileTypes:true})) {
    const path=join(dir,item.name);
    if(item.isDirectory()) {if(!['build','node_modules'].includes(item.name))await check(path);}
    else if(/\.(js|cjs)$/.test(path)) {
      const result=spawnSync(process.execPath,['--check',path],{encoding:'utf8'});
      if(result.status!==0)throw new Error(result.stderr);count++;
    }
  }
}
for(const dir of ['apps','packages','tools'])await check(dir);
console.log(`Syntax checked: ${count} files`);
await import('./check-boundaries.js');
