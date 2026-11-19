# watch-agent-pet

> 让手表成为健康数据的采集入口，让水豚噜噜在电脑上陪伴你 —— 一个支持替换设备与通信方案的桌宠与健康看板项目。

当前处于**早期开发阶段**：桌面客户端、插件运行时与模拟采集链路已可运行；OPPO Watch 4 Pro 已完成部分真机探针验证，真实手表到电脑的通信链路尚未接入。现在启动客户端，看到的是明确标注的模拟数据。

## 这是什么项目

项目最初从 OPPO Watch 4 Pro 的真机调研出发，目前按**接入层、运行层、展示层**拆分，目标是逐步支持不同手表、可替换的通信协议，以及 Windows、macOS、Linux 电脑。

手表侧负责健康数据采集与上报，电脑侧负责桌宠展示、健康看板和本地数据保存。机型差异留在设备接入包中，运行层统一管理采集与通信，展示层订阅健康状态。

当前已经实现：

1. **水豚噜噜桌宠**：默认使用噜噜精灵图，连接时播放待机动画，断开时进入休息状态；支持系统减少动态效果设置。
2. **健康数据看板**：显示模拟心率、血氧、腕温，以及设备能力、数据质量和连接状态；缺失或过期的数据不会被显示为数值零。
3. **本地数据采集**：按天保存为 JSONL 文件，目录可在界面中选择并在运行中切换；写入异常会显示出来，不中断采集链路。
4. **设备与通信切换**：提供完整指标、仅心率两种模拟手表，以及内存和本机 WebSocket 两种通道，可通过配置选择和切换。
5. **独立运行入口**：既可启动 Electron 桌面客户端，也可启动不带窗口的桥接程序，两者复用运行层。
6. **桌面设置**：支持窗口置顶、配置导入、配置持久化及已注册插件查看。

**尚未实现**：真实手表上报、蓝牙接入、局域网配对、完整可靠传输、语音对话、宠物包导入和组件中心。Agent 状态接入电脑展示、自定义模型分析属于后期扩展；当前不向手表下发 Agent 状态。

## 整体架构

```text
watch-agent-pet/
├─ packages/
│  ├─ device-access/          接入层：硬件采集、设备插件与配套资料
│  │  ├─ simulator/           模拟手表插件
│  │  └─ oppo-watch-4-pro/
│  │     ├─ collector/        Android 传感器探针
│  │     ├─ tools/            机型测试脚本
│  │     └─ docs/             官方资料、实测报告与教程
│  ├─ runtime/                运行层：插件、通信、配置、健康服务与存储
│  └─ contracts/              公共消息、接口与协议契约
├─ apps/
│  ├─ desktop/                展示层：桌宠、看板、系统适配与桌面打包
│  └─ bridge/                 独立无窗口运行入口
├─ docs/                      架构、开发说明与历史调研
└─ tools/                     仓库级语法与依赖边界检查
```

- **硬件可扩展**：每个机型的采集实现、权限处理、测试脚本和资料集中放置；应用入口注册设备插件，运行层不依赖具体品牌。
- **通信可替换**：会话、消息编解码、字节传输分别管理。当前只实现本机模拟链路，蓝牙与远程连接仍需各自实现和验证。
- **展示可独立演进**：Electron 与系统能力适配放在桌面包，采集、通信和存储放在运行层；无窗口桥接不依赖桌面包。

仓库使用 npm 多包工作区，各包独立声明依赖。根目录的 `package.json` 负责工作区编排与统一命令，`package-lock.json` 统一锁定依赖；Electron 配置位于 `apps/desktop/package.json`。原生 Android 探针使用自身构建工具，不依赖 npm。

详细边界见[总体架构](docs/research/architecture.md)和[开发指南](docs/development/desktop-runtime.md)。

## 已被真机验证的核心发现

以下结论来自 **2026-11-19 的 OPPO Watch 4 Pro 实测**，仅适用于当时的机型、系统和测试条件，不代表其他手表的能力。

| 发现 | 对开发的影响 |
|---|---|
| 设备为 Android 11 / API 30，仅支持 armeabi-v7a | 原生依赖需要适配 32 位环境 |
| 亮屏、探针在前台时，12 路原始 PPG 有回调，频率约 246.7 Hz | 已验证原始采样回调路径，尚不能直接等同于有效心率或血氧 |
| 心电原始波约 52.7 Hz、腕温约 98.5 Hz，探针测试中无需传感器权限即可收到回调 | 可继续验证采样质量、佩戴条件与处理流程 |
| 本轮灭屏后出现零回调，并观察到探针进程被终止 | 后台保活、功耗和长期采集必须单独验证 |
| 侧边功能键为 KEY_F1，表冠旋转为 REL_WHEEL 相对轴事件 | 表冠旋转不是早期推测的 F1/F2 按键事件 |
| 血氧、心率及成品心电在停靠测试中未收到回调 | 需要离座、接触皮肤条件下复测，不能宣称已经可用 |

**有回调不等于有效健康测量。** 停靠时充电底座遮挡表背，原始光学信号可能是反射噪声，腕温也可能受充电器温度影响。

详见[第一轮传感器清单](packages/device-access/oppo-watch-4-pro/docs/reports/probe-report-r1.md)和[第二轮回调与按键实测](packages/device-access/oppo-watch-4-pro/docs/reports/probe-report-r2.md)。

## 快速开始

### 体验桌面客户端

准备 Node.js 22.12 或更高版本及 npm，在仓库根目录执行：

```sh
npm ci
npm start
```

首次安装需要下载 Electron。启动后即可体验噜噜桌宠、模拟健康看板、数据保存和设备切换，无需连接真实手表。

桌面配置保存在系统用户数据目录，默认采集目录为该目录下的 `data/`，可在界面中修改。配置和健康数据不写回源码目录，当前应用不上传健康数据。

不需要界面时，可启动无窗口桥接：

```sh
npm run bridge
```

指定配置文件时，在仓库根目录执行：

```sh
node apps/bridge/main.js packages/runtime/config/demo.json
```

桥接默认数据目录位于系统临时目录中的 `watch-agent-pet-bridge/data/`；需要长期保存时应在配置中指定绝对目录。按 Ctrl+C 关闭采集和连接。本机 WebSocket 仅绑定回环地址，不能据此连接局域网中的手表。

### 构建与验证

```sh
npm run check          # 语法与包依赖边界检查
npm test               # 运行层与独立桥接测试
npm run test:desktop   # 桌面冒烟测试，窗口默认隐藏
npm run pack           # 生成当前系统的应用目录
npm run dist           # 生成当前系统的分发包
```

打包产物位于 `release/` 下按平台、架构和时间戳区分的目录。Windows 配置为便携程序、macOS 为压缩包、Linux 为 AppImage；发行产物尚未签名或公证。

本地已验证 Windows 桌面启动、目录打包及打包后冒烟测试。仓库已配置三个系统的自动化检查，**不代表 macOS 和 Linux 已完成实际运行验证**。

### 验证 OPPO 手表

准备手表、磁吸底座、可传数据的 USB 线，并按[连接教程](packages/device-access/oppo-watch-4-pro/docs/tutorials/01-getting-started.md)开启调试。adb 可放在 `tools/platform-tools/` 或加入系统命令搜索路径；构建探针另需 JDK 与 Android SDK，具体版本见[开发规范](AGENT.md)。

以下真机操作由使用者执行，命令均从仓库根目录运行：

```powershell
# 读取设备基线信息，不安装应用
powershell -NoProfile -ExecutionPolicy Bypass -File packages/device-access/oppo-watch-4-pro/tools/verify-watch.ps1

# 本地构建探针，无需连接设备
powershell -NoProfile -ExecutionPolicy Bypass -File packages/device-access/oppo-watch-4-pro/collector/build.ps1

# 真机测试：安装探针、授予传感器权限并采集日志
powershell -NoProfile -ExecutionPolicy Bypass -File packages/device-access/oppo-watch-4-pro/tools/device-test.ps1
```

Windows 双击入口位于该机型的 `tools/` 目录。基础信息探针与安装测试的动作不同，完整操作和结果判读见[设备说明](packages/device-access/oppo-watch-4-pro/README.md)及[最小探针教程](packages/device-access/oppo-watch-4-pro/docs/tutorials/03-minimal-sensor-apk.md)。

## 文档导航

| 文档 | 内容 |
|---|---|
| [总体架构](docs/research/architecture.md) | 当前分层、依赖方向、可替换边界与迁移说明 |
| [桌面与插件开发指南](docs/development/desktop-runtime.md) | 启动、打包、插件扩展及当前限制 |
| [接口契约](packages/contracts/ports.md)与[协议草案](packages/contracts/protocol.md) | 当前接口与目标通信协议，未实现部分以文档标注为准 |
| [配置说明](packages/runtime/config/README.md) | 默认模拟配置与未来真机配置草案 |
| [OPPO 官方资料汇编](packages/device-access/oppo-watch-4-pro/docs/official/oppo-wear-dev-notes.md) | 机型、接口与平台限制的调研记录 |
| [实测报告目录](packages/device-access/oppo-watch-4-pro/docs/reports) | 传感器清单、回调与输入事件验证 |
| [设备接入教程](packages/device-access/oppo-watch-4-pro/docs/tutorials) | 连接、传感器判读与探针构建 |
| [通信选型](docs/research/transport-selection.md) | OPPO 蓝牙优先、局域网备选的待验证方案 |
| [早期设计调研](docs/research/design-research.md) | 历史方案与探索记录，不作为当前已实现功能清单 |
| [开发规范](AGENT.md) | 构建、真机测试、脚本编码与提交要求 |

## 路线图

| 阶段 | 目标 | 当前状态 |
|---|---|---|
| M0：硬件验证 | 探针、输入事件、传感器、保活、功耗与通信可行性 | 已完成部分输入与原始采样验证；成品指标、保活和蓝牙等仍待实测 |
| M1a：桌面与模拟链路 | 多包分层、插件运行时、桌宠、健康看板、本地存储 | 已实现；当前默认使用模拟设备 |
| M1b：真实设备接入 | 正式采集工程、接通一条实测可用链路、验证稳定性 | 待开发与真机验证 |
| M1c：扩展性验证 | 接入第二款手表，验证其他电脑系统与通信替换 | 待推进 |
| 后期扩展 | Agent 状态接入电脑、自定义模型分析，以及语音、组件等能力 | 设计预留，尚未实现 |

## 当前限制

- **OPPO 仍处于探针阶段**，不能在客户端中选择为已可运行的真实设备；不能将模拟健康数值当作手表测量结果。
- **长期采集尚未验证**。当前实测观察到了亮屏门控与灭屏终止进程，前台服务是否能满足持续采集要求，需要结合佩戴和功耗测试确认。
- **通信运行时只完成本机模拟子集**，远程鉴权、配对、确认补发、心跳、自动重连和蓝牙分片仍未完成。
- **插件采用静态注册**，配置只能选择已注册实现，暂不支持从任意文件动态加载第三方插件。

## 贡献

欢迎贡献新机型的接入实现与脱敏实测报告、通信适配、不同电脑系统的验证结果，以及文档纠错。新增设备的源码和配套资料请放在对应接入包下，遵守公共契约，避免在运行层或界面加入品牌判断。

参与前请阅读[贡献指南](CONTRIBUTING.md)与[开发规范](AGENT.md)。

## 免责声明

- 项目不 root、不刷机、不换表盘、不修改系统分区；真机验证包含明确说明的探针安装、授权和日志采集动作。
- 健康数据相关功能非医疗器械，不用于诊断，异常请就医；原始传感器回调不代表医疗级测量能力。
- 本项目不隶属于 OPPO 或其他手表厂商，品牌名称仅用于描述设备；调研记录不替代厂商最新文档。

## 开源许可

采用 [MIT 许可证](LICENSE)，版权所有 © 2026 mozzie。

> AI生成
