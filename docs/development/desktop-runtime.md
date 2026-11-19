# 桌面客户端与插件运行时（M1a）

## 运行与构建

需要 **Node.js 22.12+**（推荐 22 LTS）与 npm。首次安装需要下载 Electron。所有命令在仓库根目录执行：

```sh
npm ci
npm start
npm run check
npm test
npm run test:desktop
npm run pack
npm run dist
```

`pack` 生成当前 OS 的未安装目录，`dist` 生成 Windows portable / macOS zip / Linux AppImage，通过系统临时目录打包后，复制到 release/<平台>-<架构>-<时间戳>/，避免 Windows 工作区卷上默认示例文件清理失败；不覆盖已有产物。发行产物尚未代码签名或公证。三个系统分别构建，不能用一次 Windows 构建宣称已验证其他系统。

不需要桌面窗口时：`npm run bridge`，也可 `npm run bridge -- config/demo.json` 指定配置。桥接仅输出状态与指标名称，不输出健康数值；Ctrl+C 释放设备定时器与连接。

## 可用功能

- Electron 客户端：桌宠展示健康摘要、模拟健康看板、本地采集状态（目录/记录数/写入异常）、采集目录选择与热切换、设备/通道切换、配置导入、窗口置顶、复制文本、插件列表。Agent 状态展示与下发已移除（2026-11-19 决策，后期扩展）。
- 可信插件注册表：API v1 校验、重复注册拒绝、设备与 transport 兼容校验、单活动设备限制；配置含 agent 段会被拒绝。
- 两种设备：simulator-full（心率/血氧/腕温）、simulator-minimal（仅心率）。数据明确标注模拟；无能力或断连时显示 —。
- 两种真实执行路径：memory（异步有界消息队列）、loopback-websocket（本机真实 socket，随机端口与一次性令牌）。WebSocket 仅绑定 127.0.0.1，不接入 LAN 手表。
- json-v1 编码：4096 字节限制、严格 UTF-8、帧字段验证、身份绑定、按流序号去重。
- 本地采集（health-store.js）：健康帧追加写入 dataDir/health-日期.jsonl（每行一条采样，含 deviceId/质量/采样时间）；目录可配置（相对路径相对 userData）与运行中切换（不重建连接）；磁盘错误记录到状态不中断链路。
- 生命周期串行化：热切换关闭旧订阅、设备、会话和通道；异常断连释放资源；手动重新连接恢复采集；配置允许时才按优先级尝试备用通道。
- 平台接口：windows/macos/linux 描述、剪贴板、置顶、系统通知能力；未实现的蓝牙/输入注入/麦克风明确报告 unsupported。

窗口内通过“应用并连接”重新连接。插件选择保存在 Electron userData/runtime.json（Windows 通常位于用户 AppData/Roaming；macOS/Linux 使用 Electron 对应用户目录）。首次使用加载 [demo.json](../../config/demo.json)。设置不写回仓库；采集数据只写入用户配置的目录，不写入仓库。

## 边界与尚未实现

当前实现是 **本机模拟链路 profile**，不是完整 Wire v1：未实现跨设备认证协商、ACK 补发、心跳、自动退避重连、BLE 分片、语音和控制命令。重连使用新会话与最新快照，不重放历史数据。不能用此状态展示客户端控制真实手表。

OPPO 仍仅有探针，不能选择为可运行设备。原 [runtime.example.json](../../config/runtime.example.json) 是未来真机配置草案，导入会明确拒绝未注册插件。Agent 状态接入（Claude Code/Codex/豆包/Qoder → PC 端展示）与自定义模型分析为后期扩展：协议保留 agent-state 通道，但当前不注册任何 agent 插件。

## 添加插件

1. 设备实现放到 devices/<id>，通信实现放到 connectivity/transports 或 codecs，Agent 来源放到 integrations。
2. 导出 `{id, name, apiVersion:1, create}`；设备还须列出支持的 transports。实现参考 [模拟设备](../../devices/simulator/plugin.js)与[内存通道](../../connectivity/transports/memory.js)。
3. 在 [bootstrap.js](../../apps/desktop/bootstrap.js)显式注册，禁止从配置动态 import 任意文件。
4. 配置选择注册 ID，核心与 UI 不加品牌条件。设备 describe 返回实际能力，stop 必须幂等释放资源。
5. 添加双向消息、权限拒绝、连接失败、stop 后无回调和组合兼容测试。

M1a 的 transport.open 返回 `{desktop, device, close}`，用于同进程托管模拟对端，两端各实现 Connection。未来真实网络传输应提供 accept/connect 单端连接，将模拟对端托管从运行时移出；不要在核心里加入 OPPO 判断，也不要把本机令牌当成真实设备配对协议。

## 安全与跨平台验证

渲染进程禁用 Node，启用 sandbox/contextIsolation，仅通过 preload 暴露具体方法；IPC 校验主窗口与主 frame；禁止新窗口、外部导航与默认权限；CSP 禁止远程资源。UI 文本使用 textContent，不能渲染设备传入 HTML。

Electron 安全方案依据[官方安全指南](https://www.electronjs.org/docs/latest/tutorial/security)和[上下文隔离说明](https://www.electronjs.org/docs/latest/tutorial/context-isolation)。

CI 为 Windows/macOS/Linux 分别执行语法检查、运行时测试、桌面冒烟和目录打包。CI 文件存在不等于远端已运行；本地验证结果见实际开发交付说明。Linux 无显示器时使用 xvfb-run。

桌面测试使用临时 userData，不覆盖日常配置，截图写入 test-results/desktop.png。依赖锁定在 package-lock.json；构建工具的 minimatch 覆盖到 11.0.1，以避开上游版本的已知拒绝服务漏洞，升级构建工具时应复核并移除不再需要的 override。

> AI生成
