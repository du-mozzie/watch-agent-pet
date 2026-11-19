import { readFile } from 'node:fs/promises';
import { requireValue } from '../core/errors.js';

export function validateConfig(value, registry, platform = process.platform) {
  const c = structuredClone(value);
  requireValue(c?.schemaVersion === 1, '配置 schemaVersion 必须为 1');
  const host = {win32:'windows',darwin:'macos',linux:'linux'}[platform];
  requireValue(host && ['auto',host].includes(c.host?.platform), 'PC 平台配置与当前系统不匹配');
  requireValue(Array.isArray(c.devices) && c.devices.length > 0 && c.devices.length <= 16, '需要设备配置');
  // 可选：本地采集目录（相对路径相对应用数据目录解析；缺省 data）。
  if (c.storage !== undefined) {
    requireValue(c.storage && typeof c.storage.dataDir === 'string' && c.storage.dataDir.length > 0 && c.storage.dataDir.length <= 260, '采集目录配置无效');
  }
  // Agent 来源为后期扩展：当前配置不接受 agent 段（注册表无 agent 插件）。
  requireValue(c.agent === undefined, 'Agent 状态接入为后期扩展，当前配置不含 agent 段');
  const ids = new Set();
  for (const d of c.devices) {
    requireValue(d && typeof d.instanceId==='string' && /^[a-zA-Z0-9_-]{1,64}$/.test(d.instanceId) && !ids.has(d.instanceId), '设备 ID 无效或重复');
    ids.add(d.instanceId);
    requireValue(typeof d.enabled === 'boolean', 'enabled 必须是布尔值');
    if (!d.enabled) continue;
    const device = registry.get('device', d.profile);
    const conn = d.connection;
    requireValue(conn && typeof conn.allowFallback === 'boolean', '连接配置无效');
    registry.get('codec', conn.codec);
    requireValue(Array.isArray(conn.transportPriority) && conn.transportPriority.length > 0 && conn.transportPriority.length <= 8, '通道列表不能为空');
    requireValue(new Set(conn.transportPriority).size === conn.transportPriority.length, '通道不能重复');
    for (const id of conn.transportPriority) {
      registry.get('transport', id);
      requireValue(device.transports.includes(id), `设备 ${d.profile} 不支持通道 ${id}`);
    }
  }
  requireValue(c.devices.filter(d=>d.enabled).length === 1, '首版必须且只能启用一台设备');
  return c;
}
export async function loadConfig(path, registry) {
  const raw = await readFile(path,'utf8');
  requireValue(Buffer.byteLength(raw) <= 65536, '配置文件过大');
  return validateConfig(JSON.parse(raw.replace(/^\uFEFF/,'')),registry);
}
