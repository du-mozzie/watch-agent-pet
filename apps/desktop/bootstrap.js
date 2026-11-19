import { PluginRegistry } from '../../core/registry.js';
import { simulatorPlugins } from '../../devices/simulator/plugin.js';
import { jsonCodec } from '../../connectivity/json-codec.js';
import { memoryTransport } from '../../connectivity/transports/memory.js';
import { loopbackWebsocket } from '../../connectivity/transports/loopback-websocket.js';

// Agent 来源（integrations/）为后期扩展：当前不注册任何 agent 插件。
export function createRegistry() {
  const registry=new PluginRegistry();
  for (const plugin of simulatorPlugins) registry.register('device',plugin);
  registry.register('codec',jsonCodec).register('transport',memoryTransport).register('transport',loopbackWebsocket);
  return registry;
}
