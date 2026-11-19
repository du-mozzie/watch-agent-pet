import { requireValue } from '../core/errors.js';

export const STATES = Object.freeze(['idle','thinking','running','waiting','done','error']);
export const METRICS = Object.freeze({'heart-rate':'bpm','spo2':'%','temperature':'°C'});
const text = (v, max=200) => typeof v === 'string' && v.length > 0 && v.length <= max;
export function validateFrame(f) {
  const valid = (v,m) => requireValue(v,m,'invalid-message');
  valid(f && f.v === 1 && text(f.sender) && text(f.epoch), '消息身份或协议版本无效');
  valid(Number.isSafeInteger(f.seq) && f.seq > 0 && Number.isSafeInteger(f.ts) && f.ts >= 0, '消息序号或时间无效');
  const p = f.payload;
  valid(p && typeof p === 'object' && !Array.isArray(p), '消息载荷无效');
  if (f.ch === 'agent-state') {
    valid(text(p.source) && text(p.sessionId) && text(p.eventId) && STATES.includes(p.state), 'Agent 状态无效');
    valid(p.text === undefined || (typeof p.text === 'string' && p.text.length <= 1000), 'Agent 文本过长');
  } else if (f.ch === 'health') {
    valid(Object.hasOwn(METRICS,p.metric) && p.unit === METRICS[p.metric], '健康指标或单位无效');
    valid(['valid','no-contact','unavailable'].includes(p.quality), '健康质量无效');
    valid(Number.isSafeInteger(p.sampledAt) && p.sampledAt >= 0, '采样时间无效');
    valid(p.quality !== 'valid' || (typeof p.value === 'number' && Number.isFinite(p.value)), '有效采样必须有数值');
  } else {
    valid(false, `当前运行时未支持消息类型：${f.ch}`);
  }
  return f;
}
