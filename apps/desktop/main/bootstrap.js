import { createRegistry as createRuntimeRegistry } from '@watch-agent-pet/runtime';
import { simulatorPlugins } from '@watch-agent-pet/device-simulator';

// Agent 来源（integrations/）为后期扩展：当前不注册任何 agent 插件。
export function createRegistry() {
  return createRuntimeRegistry({devices:simulatorPlugins});
}
