# PC 展示层

独立 npm workspace：`@watch-agent-pet/desktop`。Electron 依赖、启动和打包配置由本包管理。根目录 `npm ci` 后运行 `npm start`；也可在此目录运行 `npm start`。

- `main/`：窗口、IPC、配置持久化与插件装配。
- `preload/`：向渲染进程提供受限接口。
- `renderer/`：桌宠、健康看板与配置界面。
- `platforms/`：Windows/macOS/Linux 能力适配。
- `tools/`、`tests/`：桌面打包与冒烟验证。

采集生命周期、通信和本地存储归 [runtime](../../packages/runtime/README.md)，不放在展示层。详见[开发指南](../../docs/development/desktop-runtime.md)。
