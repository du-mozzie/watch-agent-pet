# oppo-watch-agent-pet

> 把 OPPO Watch 4 Pro 变成 AI Coding 桌宠与健康数据桌面看板 —— 基于真机实测的开源调研项目。
>
> Turn an OPPO Watch 4 Pro into an AI-coding desk pet and health dashboard — an open research project backed by real-device probes.

**English overview**: This project investigates how to repurpose the OPPO Watch 4 Pro (ColorOS Watch 6.0 / Android 11) into a companion device for AI coding agents (Claude Code / Codex / Qoder / WorkBuddy / Doubao) and a desktop health-data dashboard, while keeping all original watch features intact. All conclusions are based on official OPPO open-platform documentation plus a first round of real-device probes via ADB. Current phase: **research + verification (pre-alpha)**. See the docs tree below; most content is written in Chinese.

---

## 这是什么项目

以一块**没有 root、不刷机、不换表盘**的 OPPO Watch 4 Pro 为硬件底座，复刻 [HachimoDock（哈基米机）](https://www.antutu.com/doc/138107) 式「AI Coding 陪伴设备」的六项能力，并顺带把它变成 PC 桌面上的健康数据看板：

1. **Agent 状态跟随** —— 手表实时显示 Claude Code / Codex / Qoder 等客户端的思考/执行/等待/完成/错误六态
2. **语音输入** —— 手表录音 → PC 转写 → 注入目标输入框（追加，非覆盖）
3. **实时对话** —— 对宠物长按说话，走用户自己配置的 STT / LLM / TTS 服务
4. **形象与音效** —— 内置水豚形象，支持导入 [Petdex](https://petdex.dev/zh/docs) 格式宠物包
5. **组件中心** —— 番茄钟 / 喝水提醒 / PC 状态等小组件（声明式 JSON + 轻量脚本）
6. **健康数据桌面看板** —— 血氧 / ECG / 腕温 / 心率推到 PC 悬浮小部件

## 已被真机验证的核心发现 🔍

2026-11-19 第一轮探针（OWW221，Android 11 / API 30 / armeabi-v7a）：

| 发现 | 意义 |
|---|---|
| 42 个硬件传感器、41 个在运行 | 传感器层完全向系统注册 |
| **血氧 `PPG_SPO`(69633)** 需 BODY_SENSORS 即可读 | 无需 OPPO 开发者账号 / SDK / 手机中转 |
| **ECG `ECG_Sensor`(69636) + `ECG_RAW_PRO`(69812)** | 前者需权限，**原始波形免权限** |
| **腕温 `WRIST_TEMPERATURE`(69815) 免权限** | 第三方 App 注册即用 |
| **12 路原始 PPG（绿/红/红外）全部免权限** | 心率/血氧可以自己算算法，不依赖厂商 |
| 表冠旋转疑似映射 F1/F2 keylayout | 「表冠当物理旋钮」玩法技术上有戏，待 `getevent` 确认 |

完整表格见 [docs/device-probe/probe-report-r1.md](docs/device-probe/probe-report-r1.md)。

> ⚠️ **注册 ≠ 出数**：`dumpsys` 里有条目不代表 HAL 会把数据交给第三方 App，实际可用性需按 [教程 3](docs/tutorials/03-minimal-sensor-apk.md) 装一个最小 APK 验证回调。

## 快速开始

只需一块 OPPO Watch 4 Pro、磁吸充电底座、一根**能传数据**的 USB 线：

```bash
# 1. 下载 Android platform-tools（含 adb）解压到 tools/platform-tools/
#    https://developer.android.com/tools/releases/platform-tools

# 2. 手表开启开发者模式 + USB 调试（照着教程第 1 篇做，2 分钟）
#    https://github.com/du-mozzie/oppo-watch-agent-pet/blob/main/docs/tutorials/01-getting-started.md

# 3. Windows 用户直接双击 tools/run-verify.bat
#    （或：powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify-watch.ps1）
```

脚本纯只读，不改手表任何内容，会生成 `watch-report-<时间戳>.md` 探针报告。

## 文档导航

| 目录 | 内容 |
|---|---|
| [docs/research/](docs/research/) | [设计调研](docs/research/design-research.md)：六项能力逐条落地判定、五 Agent 接入矩阵、总体架构、PoC 清单 P1~P8 |
| [docs/official-docs/](docs/official-docs/) | [OPPO 开放平台资料汇编](docs/official-docs/oppo-wear-dev-notes.md)：机型表、Wear Engine / 健康服务 SDK 字段、审核红线 vs 系统硬边界 |
| [docs/device-probe/](docs/device-probe/) | [真机实测报告](docs/device-probe/probe-report-r1.md) + [传感器 dump 原文](docs/device-probe/sensorservice-dump.txt) |
| [docs/tutorials/](docs/tutorials/) | 教程：[①上手连接](docs/tutorials/01-getting-started.md) · [②传感器探针判读](docs/tutorials/02-sensor-probe.md) · [③最小验证 APK](docs/tutorials/03-minimal-sensor-apk.md) |
| [android/sensor-probe/](android/sensor-probe/) | **M0 核心交付：最小传感器验证 APK**（纯 Java 零依赖，`build.ps1` 一键构建，无需 Gradle） |
| [AGENT.md](AGENT.md) | 开发 / 测试 / 推送全流程规范（Agent 与贡献者必读） |
| [tools/](tools/) | `verify-watch.ps1` 基线探针 · `device-test.ps1` 真机测试会话（+双击入口） |

## 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| **M0** PoC | P1~P8 探针（按键/保活/功耗/长连/录音/播放/runtime/快捷键），通知形态打通 Claude Code → PC → 手表 | 🔄 进行中：探针 APK 与真机测试脚本已就绪，待首轮真机验证 |
| **M1** 宠物页 | 手表宠物页（五态动画 + 任务气泡）+ Wi-Fi 长连 + Claude Code 适配器 | ⏸ 待启动 |
| **M2** 语音 | Qoder / Codex 适配器 + 语音输入 + 实时对话 | ⏸ |
| **M3** 组件中心 | 声明式组件 + 形象导入 + 音效 + 桌面端设置 | ⏸ |
| **M4** 稳定性 | WorkBuddy 日志适配 + 豆包兜底 + 功耗打磨 | ⏸ |

## 必须先泼的三盆冷水 💧

1. **宠物不能成为表盘。** OPPO 表盘是私有格式，第三方无法注册。产品叙事是「一键唤起的宠物 App / 充电底座桌宠」，不是「桌面变宠物」。
2. **只有 32 位。** `armeabi-v7a` 独占，无 64 位，重型 runtime（wasmtime/V8）全部排除，组件脚本只能上 wasm3 / wasmi / QuickJS。
3. **后台策略收紧。** ColorOS Watch 官方「不支持应用后台运行」，常驻只有前台服务一条路，且系统功耗条款（后台 sensor 持有 ≤1s、非 IM 禁后台联网）是 ROM 层事实，侧载也绕不过。

详见 [设计调研 §7](docs/research/design-research.md) 与 [官方资料汇编 §3 判读](docs/official-docs/oppo-wear-dev-notes.md)。

## 贡献

欢迎任何形态的贡献：其他 OPPO / 一加手表机型的探针报告、文档纠错、判读经验、组件创意。见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 免责声明

- 本项目为**个人自用的侧载调研**，不修改系统分区、不 root、不刷机，卸载 App 即完全还原手表。
- 健康数据相关内容**非医疗器械级**，不用于诊断，异常请就医，本项目不做异常报警承诺。
- 官方条款以 OPPO 开放平台最新页面为准；本项目不与 OPPO 存在隶属关系，"OPPO" 仅为设备描述用途。

## License

[MIT](LICENSE) © 2026 mozzie

> AI生成
