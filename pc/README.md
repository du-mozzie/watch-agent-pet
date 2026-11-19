# pc/ — PC 桥接与展示层（M1 起开发）

> 技术栈：Tauri 2（Rust 内核 + WebView UI）。职责：汇聚手表上行数据 + 对接五个 Agent 客户端 + 桌面展示。
> 状态：**结构预留**（2026-11-19 v2 架构落地），首个工程 M1 阶段开建。架构与选型见 [docs/research/architecture.md](../docs/research/architecture.md)。

## 计划结构

```
pc/
├── adapter/     五 Agent 适配器：Claude Code(HTTP hooks)·Qoder·Codex·WorkBuddy(tail 日志)·豆包(粗粒度)
├── core/        事件总线·六态聚合·会话管理（单设备聚焦最近活跃会话）
├── transport/   可插拔通道（与 watch 端对称）：ble-central/ · wifi-ws/ ·（注册表登记新通道）
└── ui/          桌宠悬浮窗·健康看板大屏·托盘设置
```

## 与手表端的契约

- 帧协议：[shared/protocol.md](../shared/protocol.md)（Wire v1，唯一权威）
- 通道契约：每新增通道只加一个 `transport/` 实现 + 注册表一行（[architecture.md §2.3](../docs/research/architecture.md) 的切换成本验收标准）
- 联调顺序：假数据端到端跑通六态 → BLE/Wi-Fi 真通道（依 P9 结论）→ 稳定性实测（P2~P4）

> AI生成
