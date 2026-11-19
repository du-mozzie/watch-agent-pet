import { requireValue } from '@watch-agent-pet/contracts/errors';

/** Explicit trusted registration; configuration never imports executable paths. */
export class PluginRegistry {
  #entries = new Map();
  register(kind, plugin) {
    requireValue(plugin?.apiVersion === 1 && typeof plugin.id === 'string' && typeof plugin.create === 'function', '插件接口版本或工厂无效');
    const key = `${kind}:${plugin.id}`;
    requireValue(!this.#entries.has(key), `插件重复注册：${key}`);
    this.#entries.set(key, Object.freeze({...plugin}));
    return this;
  }
  get(kind, id) {
    const plugin = this.#entries.get(`${kind}:${id}`);
    requireValue(plugin, `未注册插件：${kind}/${id}`, 'unsupported');
    return plugin;
  }
  list() {
    return [...this.#entries].map(([key, p]) => ({kind: key.split(':')[0], id:p.id, name:p.name, apiVersion:p.apiVersion}));
  }
}
