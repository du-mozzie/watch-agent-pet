import { PluginRegistry } from './registry.js';
import { jsonCodec } from '../connectivity/json-codec.js';
import { memoryTransport } from '../connectivity/transports/memory.js';
import { loopbackWebsocket } from '../connectivity/transports/loopback-websocket.js';

/** Hosts supply device plugins; the runtime never imports a hardware implementation. */
export function createRegistry({devices = [], transports = []} = {}) {
  const registry = new PluginRegistry();
  for (const plugin of devices) registry.register('device', plugin);
  registry.register('codec', jsonCodec);
  for (const plugin of [memoryTransport, loopbackWebsocket, ...transports]) registry.register('transport', plugin);
  return registry;
}
