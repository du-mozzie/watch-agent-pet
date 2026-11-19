import { validateFrame } from '../contracts/messages.js';
import { requireValue } from '../core/errors.js';

export const jsonCodec = { id:'json-v1', name:'JSON v1', apiVersion:1, create:()=>({
  encode(frame) {
    validateFrame(frame);
    const bytes = Buffer.from(JSON.stringify(frame));
    requireValue(bytes.length <= 4096,'消息超过 4096 字节','invalid-message');
    return bytes;
  },
  decode(bytes) {
    requireValue(bytes.byteLength <= 4096,'消息超过 4096 字节','invalid-message');
    return validateFrame(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)));
  }
})};
