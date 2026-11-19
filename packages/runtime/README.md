# 运行层

独立 npm workspace：`@watch-agent-pet/runtime`。不依赖 Electron、桌面源码或具体设备的生产实现。

- `index.js`：公开装配 API。
- `runtime.js`：配置应用、采集生命周期、会话装配、切换与资源释放。
- `plugins/`：注册表与内置通信插件装配；设备由应用宿主注入。
- `services/`：健康快照、数据新鲜度和订阅。
- `connectivity/`：Session、Codec、Transport。
- `storage/`：本地 JSONL 存储和目录热切换。
- `config/`：配置校验、默认模拟配置及未来真机配置草案。
- `integrations/`：后期 Agent 来源接入说明，当前未启用。
- `tests/`：运行时验证；模拟器只作为开发依赖。

桌面与无窗口桥接分别消费本包。可通过 `createRegistry({devices,transports})` 注入设备与传输插件，通过注册表添加 codec。配置只选择受信任的注册 ID。
