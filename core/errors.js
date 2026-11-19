export class PluginError extends Error {
  constructor(code, message) { super(message); this.name = 'PluginError'; this.code = code; }
}
export function requireValue(condition, message, code = 'invalid-config') {
  if (!condition) throw new PluginError(code, message);
}
