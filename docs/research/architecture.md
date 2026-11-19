# 总体架构与目录规范（v2，2026-11-19）

> 本文是仓库结构的**唯一权威**（取代散落在各文档的结构描述）。设计目标：**通信渠道可插拔**（BLE/Wi-Fi/其他快速切换）、**PC 展示层预留**、**可读性优先**（新人 3 分钟能看懂目录在干什么）。
> 配套阅读：[design-research.md](design-research.md)（为什么做）｜[transport-selection.md](transport-selection.md)（为什么 BLE 优先）

---

## 1 分层总架构（v2）

```
┌────────────── 手表端 app-watch ──────────────┐      ┌──────────── PC 桥接/展示 bridge-pc ────────────┐
│ ui/        宠物页·气泡·对话·设置                 │      │ adapter/   Claude Code·Qoder·Codex·WorkBuddy·豆包  │
│ core/      六态状态机·会话聚合·事件模型            │      │ core/      事件总线·状态聚合·会话管理               │
│ sensor/    SensorManager 采集·聚合·上报           │      │ ui/        桌宠悬浮窗·看板大屏·托盘设置         │
│ transport/ ┌──────────────┐                    │      │ transport/ ┌──────────────┐                   │
│  (可插拔)   │ BLE GATT      │ ←── 同一协议 ──→   │      │  (可插拔)   │ BLE Central   │                   │
│            │ Wi-Fi WS      │                    │      │            │ Wi-Fi WS      │                   │
│            │ (未来新通道)   │                    │      │            │ (未来新通道)   │                   │
│            └──────────────┘                    │      │            └──────────────┘                   │
│ input/     表冠·功能键·触摸·麦克风               │      │ service/   STT·TTS·注入·组件工厂              │
└─────────────────────────────────────────────┘      └───────────────────────────────────────────────┘
              两端 transport 层实现同一「Wire 协议」：
              帧格式 JSON <4KB · seq 序号 · ACK · 六态事件模型
              —— 换通道 = 换 transport 实现，协议与业务零改动
```

## 2 可插拔通信设计（核心）

### 2.1 抽象（两端一致）

```java
// 手表端（Java）与 PC 端（Rust/Tauri）各有一份等价接口
interface Transport {                 // 通道生命周期
    String  name();                  // "ble" | "wifi-ws" | ...
    void    start(Callbacks cb);     // 异步起通道，onStarted/onError
    void    stop();
    boolean isReady();
}
interface Channel {                  // 建立后的数据面
    void    send(Frame f);           // 帧已按 Wire 协议编码
    void    onFrame(Consumer<Frame>);
    Stats   stats();                 // rtt/丢包/重连次数 → 状态页展示
}
```

### 2.2 Wire 协议（通道无关，版本化）

```jsonc
// 所有帧的公共头
{ "v": 1, "ch": "health" | "agent-state" | "control" | "audio" | "config",
  "seq": 412, "ts": 1732020123.456, "ack": 411 }        // seq+ack = 断线补传
// ch=health:   { "hr": 72, "spo2": 98, "temp": 36.4, "ecg": [...] }
// ch=agent-state: { "session": "cc-1", "agent": "claude-code",
//                   "state": "thinking", "text": "重构 transport 模块" }
// ch=control:  { "op": "voice.start" | "voice.stop" | "pet.wake" | ... }
```

### 2.3 切换成本（设计验收标准）

| 动作 | 允许改动范围 |
|---|---|
| 新增一个通道（如未来 USB/局域网 mDNS） | **只加一个 Transport/Channel 实现 + 注册表登记一行** |
| BLE→Wi-Fi 主备切换 | 两个实现 + 一行优先级配置，core/sensor/ui **零改动** |
| 协议升级（v1→v2 帧） | 只改 Wire 编解码层，两端 transport 实现不动 |

### 2.4 自动降级

BLE 断 → 健康帧带 seq 缓存 → 重连后按 ACK 补传；工位场景用户手动切 Wi-Fi；全部失败 → 本地 SQLite 缓存，同步恢复。**业务层永远不感知通道细节。**

## 3 目录结构（v2 规范）

```
oppo-watch-agent-pet/
├── README.md                  # 入口：项目是什么·怎么跑起来
├── AGENT.md                   # 工程规范（开发/测试/推送全流程，Agent 与人共用）
├── LICENSE / CONTRIBUTING.md
│
├── docs/                      # ── 知识层：为什么这么设计 ──
│   ├── research/              # 调研与决策
│   │   ├── design-research.md       # 项目缘起·六能力·五 Agent 矩阵·PoC P1~P9
│   │   ├── transport-selection.md   # 通信选型：BLE 优先+Wi-Fi 备选（2026-11-19）
│   │   └── architecture.md          # ←本文：分层架构·目录规范·可插拔设计
│   ├── official-docs/         # OPPO 开放平台资料汇编（外部事实）
│   ├── device-probe/          # 真机实测报告 r1/r2/…（含 dump 原文）
│   └── tutorials/             # 操作教程 ①连接 ②探针判读 ③验证 APK
│
├── tools/                     # ── 工具层：对着真机用的脚本 ──
│   ├── verify-watch.ps1       # 基线探针（只读）
│   ├── device-test.ps1        # M0 真机测试会话（P1 按键+传感器出数）
│   ├── adb-wifi.ps1           # Wi-Fi adb 开关（离座手持测试）
│   ├── run-verify.bat / device-test.bat   # 双击入口
│   └── platform-tools/        # adb（gitignored）
│
├── watch/                     # ── 手表端（Android APK，armeabi-v7a）──
│   └── sensor-probe/          # M0 探针 App（现唯一成员）
│       ├── AndroidManifest.xml
│       ├── src/…/MainActivity.java
│       ├── build.ps1           # 无 Gradle 一键构建
│       └── build/              # 产物（gitignored）
│
├── pc/                        # ── PC 桥接/展示层（Tauri 2，M1 起开发）──
│   ├── README.md              # 子项目说明（M1 建）
│   ├── adapter/               # 五 Agent 适配器（hooks/日志解析）
│   ├── core/                  # 事件总线·六态聚合·会话管理
│   ├── transport/             # BLE Central / Wi-Fi WS（与 watch 侧对称）
│   └── ui/                    # 悬浮窗·看板大屏·托盘
│
├── shared/                    # ── 跨端共享（协议与文档）──
│   ├── protocol.md            # Wire 协议 v1 规范（两端实现共同遵守）
│   └── （未来）schema 校验与测试帧
│
└── results/                   # 真机测试原始输出（gitignored）
```

**目录语义一句话版**：`docs` 为什么 · `tools` 怎么测 · `watch` 手表上跑什么 · `pc` 电脑上跑什么 · `shared` 两端说什么话。

## 4 迁移说明（v1 → v2）

| v1 位置 | v2 位置 | 理由 |
|---|---|---|
| `android/sensor-probe/` | `watch/sensor-probe/` | android 是技术词，watch 是产品视角；为 watch 端多 App 预留兄弟目录 |
| （无） | `pc/` | PC 展示层预留：M1 Tauri 工程落位，adapter/core/transport/ui 子结构先行声明 |
| （无） | `shared/protocol.md` | Wire 协议单点权威，两端对齐有唯一参照物 |
| docs 内散落的架构描述 | `docs/research/architecture.md` | 结构决策集中一处，冲突时以本文为准 |

**命名规约**（新增目录/文件必须遵守）：小写连字符；包名 `com.owapet.<端>.<模块>`（如 `com.owapet.watch.sensorprobe`、未来 `com.owapet.watch.pet`、`com.owapet.pc.bridge`）；脚本中文提示 + BOM UTF-8（AGENT.md §10）；文档互相引用一律相对路径。

## 5 与既有事实的关系

- r2 实测的亮屏门控/灭屏杀 App → `transport/` 的 Wi-Fi 实现必须设计「亮屏驱动采集窗口」；BLE 实现须设计后台广播保活（前台服务，P2）
- 停靠即致盲 → 健康看板产品文案定位为「白天佩戴」，pc/ui 看板默认显示「数据新鲜度」而非实时曲线
- 表冠 REL_WHEEL → watch/input 用输入设备读取方案，不走按键
- P9（BLE GATT server 可行性）→ 通过则 BLE 实现进 `watch/…/transport/ble` 与 `pc/transport/ble`，不通过则 Wi-Fi 升主

## 6 下一步（结构落地后）

1. `git mv` 迁移 + 全文档引用更新（本次执行）
2. `shared/protocol.md` 写 Wire 协议 v1 正式规范（下一步）
3. M1 第一个工程：`pc/` Tauri 骨架 + 假数据端到端跑通六态（P9 并行）

> AI生成
