# watch-agent-pet

手表健康数据上报与 PC 桌宠展示系统：手表负责采集上报健康数据，PC 提供桌宠形象、健康看板与本地数据落盘。设备、通信通道与 PC 系统适配均可通过配置替换。

当前为 **M1a / pre-alpha**。已实现 Electron PC 客户端、静态插件运行时、配置加载、两种模拟手表、内存/本机 WebSocket 通道与健康数据本地采集（目录可配置）。OPPO 目前仍为探针阶段，BLE 与真实手表通信待接入。

## 核心功能（当前）

- **手表上报**：手表端只做健康数据采集上报（心率/血氧/腕温），不再接收 Agent 状态下发。

- **桌宠展示**：PC 端桌宠展示健康摘要与连接状态，健康看板显示心率/血氧/腕温及数据质量。

- **本地采集**：健康数据持续写入本机 JSONL 文件（按天分文件），**数据目录可配置、可运行中切换**，磁盘错误不中断采集；数据不上云。

- **可插拔**：设备、通信通道（Session/Codec/Transport 分离）、PC 系统适配按配置选择。

## 后期扩展（未实现，仅设计预留）

- **Agent 状态接入**：把 Claude Code、Codex、豆包、Qoder 等客户端的状态结果接入 PC 端展示（协议已预留 agent-state 通道；不下发手表）。

- **自定义模型分析**：配置自己的模型（本地或云），对采集的健康数据做分析。

## 整体设计

- **设备可替换**：机型代码、配套资料、探针和教程放在 packages/device-access/<机型>/，权限、传感器和屏幕差异由设备适配器处理。

- **通信可替换**：会话、协议编解码、字节传输分离，BLE/WebSocket 与 JSON 等编码独立选择。

- **PC 可扩展**：展示与桥接分离，Windows/macOS/Linux 差异通过平台接口处理。

详见[整体架构](docs/research/architecture.md)、[接口契约](packages/contracts/ports.md)、[配置样例](packages/runtime/config/runtime.example.json)。可运行配置见 [demo.json](packages/runtime/config/demo.json)；原真机配置仍是未实现方案示例。

## 目录导航

| 目录 | 职责 |
|---|---|
| [packages/device-access](packages/device-access/README.md) | 接入层：各手表的采集工程、插件与配套资料 |
| [packages/runtime](packages/runtime/README.md) | 运行层：生命周期、通信、服务、配置、本地存储 |
| [packages/contracts](packages/contracts/ports.md) | 公共消息和接口契约 |
| [apps/desktop](apps/desktop/README.md) | 展示层：Electron、UI、PC 平台适配、桌面打包 |
| [apps/bridge](apps/bridge/README.md) | 独立无窗口运行入口 |
| [docs](docs/research/architecture.md) | 架构与开发说明 |
| [AGENT.md](AGENT.md) | 开发、测试规范 |

这是一个多包 workspace：各包分别声明依赖，根目录的 `package.json` 只做统一命令与 workspace 编排，`package-lock.json` 保证整个仓库安装一致；根 `node_modules` 是 npm 统一安装的结果。

## 启动 PC 客户端

需要 Node.js 22.12+，在根目录执行：

```sh

npm ci

npm start

```

支持模拟健康看板、本地采集目录查看与切换、设备与通道切换、导入配置、窗口置顶和复制文本。默认使用模拟设备，不访问真实手表。

验证：`npm test`、`npm run test:desktop`；打包：`npm run pack` 或 `npm run dist`。详见[开发与插件指南](docs/development/desktop-runtime.md)。

## OPPO 探针

先阅读[设备说明](packages/device-access/oppo-watch-4-pro/README.md)，在仓库根目录执行：

```powershell

# 只读基线探针（需 adb，真机操作由用户执行）

powershell -NoProfile -ExecutionPolicy Bypass -File packages/device-access/oppo-watch-4-pro/tools/verify-watch.ps1

# 构建探针 APK（需 JDK 与 Android SDK）

powershell -NoProfile -ExecutionPolicy Bypass -File packages/device-access/oppo-watch-4-pro/collector/build.ps1

# 真机测试：安装 APK、授权传感器并采集日志

powershell -NoProfile -ExecutionPolicy Bypass -File packages/device-access/oppo-watch-4-pro/tools/device-test.ps1

```

adb 放在 tools/platform-tools/ 或 PATH；SDK 可放在根目录 android-sdk/，或用构建参数指定。Windows 双击入口位于设备 tools 目录。

下一步接入真实手表通信与可靠链路，完成配对与 BLE 验证；之后再评估 Agent 状态接入与自定义模型分析。Windows/macOS/Linux 已配置独立 CI 构建，其他系统的实际运行结果以对应验证为准。

项目与当前工作区名称为 watch-agent-pet；Git 远程地址未自动改名。

健康数据非医疗器械、不用于诊断，异常请就医。项目不 root、不刷机、不修改系统分区，不隶属任何手表厂商。

[贡献指南](CONTRIBUTING.md) · [MIT License](LICENSE)

> AI生成
