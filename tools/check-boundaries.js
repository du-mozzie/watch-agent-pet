import {readFile,readdir} from 'node:fs/promises';
import {resolve,dirname,relative,sep} from 'node:path';

const root=resolve('.');
const manifest=JSON.parse(await readFile('package.json','utf8'));
const packages=await Promise.all(manifest.workspaces.map(async path=>({path:resolve(path),...JSON.parse(await readFile(`${path}/package.json`,'utf8'))})));
const owner=path=>packages.find(p=>path.startsWith(p.path+sep));
const files=[];
async function walk(dir){for(const entry of await readdir(dir,{withFileTypes:true})){
  const path=resolve(dir,entry.name);
  if(entry.isDirectory()){if(!['node_modules','build'].includes(entry.name))await walk(path);}
  else if(/\.(js|cjs)$/.test(path))files.push(path);
}}
await walk('apps');await walk('packages');
for(const path of files){
  const pkg=owner(path);if(!pkg)continue;
  const source=await readFile(path,'utf8');
  for(const match of source.matchAll(/(?:from\s+|import\s*\(|require\s*\()\s*['"]([^'"]+)['"]/g)){
    const spec=match[1];
    if(spec.startsWith('node:'))continue;
    if(spec.startsWith('.')){
      if(owner(resolve(dirname(path),spec))!==pkg)throw new Error(`跨包相对路径：${relative(root,path)} → ${spec}`);
      continue;
    }
    const name=spec.startsWith('@')?spec.split('/').slice(0,2).join('/'):spec.split('/')[0];
    if(name===pkg.name)continue;
    if(!(pkg.dependencies?.[name]||pkg.devDependencies?.[name]))throw new Error(`未声明依赖：${pkg.name} → ${name}`);
    if(pkg.name!=='@watch-agent-pet/desktop' && ['electron','electron-builder','playwright'].includes(name))throw new Error(`桌面依赖泄漏：${pkg.name}`);
    if(pkg.name==='@watch-agent-pet/contracts' && name.startsWith('@watch-agent-pet/'))throw new Error('契约不能依赖其他业务包');
    if(pkg.name==='@watch-agent-pet/device-simulator' && name!=='@watch-agent-pet/contracts')throw new Error('采集插件只能依赖契约');
    if(pkg.name==='@watch-agent-pet/runtime' && name.startsWith('@watch-agent-pet/') && name!=='@watch-agent-pet/contracts' && !path.includes(`${sep}tests${sep}`))throw new Error('运行层不能依赖具体设备或应用宿主');
    if(pkg.name==='@watch-agent-pet/bridge' && name==='@watch-agent-pet/desktop')throw new Error('桥接不能依赖桌面');
  }
}
console.log(`Workspace boundaries checked: ${packages.length} packages`);
