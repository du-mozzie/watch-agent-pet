import { build } from 'electron-builder';
import electronPath from 'electron';
import { access,cp,mkdir,mkdtemp,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve,join,sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url);
const appDir=resolve(fileURLToPath(new URL('..',import.meta.url)));
const repoDir=resolve(appDir,'../..');

// Stage on the system temp volume: Electron's default_app.asar cleanup can fail
// on Windows workspace volumes. Copy only completed builds into the repository.
const tempRoot=resolve(tmpdir());
// Importing electron also installs the pinned binary on a fresh npm ci.
await access(electronPath);
const stage=await mkdtemp(join(tempRoot,'watch-agent-pet-package-'));
const output=resolve(repoDir,'release',`${process.platform}-${process.arch}-${Date.now()}`);
await build({projectDir:appDir,dir:process.argv.includes('--dir'),config:{
  directories:{output:stage},electronDist:resolve(require.resolve('electron/package.json'),'../dist')
}});
await mkdir(output,{recursive:true});
await cp(stage,output,{recursive:true});
// Delete only the unique temporary directory allocated above, after copying.
if(!resolve(stage).startsWith(tempRoot+sep) || !stage.startsWith(join(tempRoot,'watch-agent-pet-package-'))) throw new Error('Unexpected build staging path');
await rm(stage,{recursive:true,force:true});
console.log(`Build output: ${output}`);
