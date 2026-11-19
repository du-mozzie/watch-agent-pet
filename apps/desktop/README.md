# PC 客户端（M1a）

已实现 Electron 桌面窗口、桌宠健康摘要展示、模拟健康看板、本地采集（JSONL 按天、数据目录可配置可热切换）、设备/通道选择、配置导入与持久化。Node.js 22.12+，根目录运行 npm ci、npm start。

- main.js / preload.cjs：安全桌面宿主与受限 IPC。
- bootstrap.js：可信插件装配入口（不注册 agent 插件）。
- runtime.js：配置校验、生命周期、连接切换与采集存储装配。
- health-store.js：本地采集存储（JSONL、目录切换、磁盘错误不中断）。
- presentation/：UI，仅调用 DesktopService，经 preload 访问，不直接导入 Node/设备 API。
- bridge-cli.js：独立无窗口桥接入口（输出采集与指标名，不输出健康数值）。

Agent 状态展示已移除（2026-11-19 决策，后期扩展）。运行方式、实现范围与扩展步骤见[开发指南](../../docs/development/desktop-runtime.md)。真实 OPPO、BLE 仍待接入。

> AI生成
