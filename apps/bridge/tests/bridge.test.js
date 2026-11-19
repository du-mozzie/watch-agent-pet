import test from 'node:test';
import assert from 'node:assert/strict';
import {fork} from 'node:child_process';
import {once} from 'node:events';
import {fileURLToPath} from 'node:url';

test('bridge boots and shuts down independently of desktop',async()=>{
  const child=fork(fileURLToPath(new URL('../main.js',import.meta.url)),[],{stdio:['ignore','pipe','pipe','ipc']});
  let errors='';child.stderr.on('data',data=>{errors+=data;});
  const exit=once(child,'exit');
  try {
    const [message]=await once(child,'message',{signal:AbortSignal.timeout(10000)});
    assert.equal(message.status,'connected');child.send('stop');
    const [code]=await exit;assert.equal(code,0,errors);
  }finally{if(child.exitCode===null)child.kill();}
});
