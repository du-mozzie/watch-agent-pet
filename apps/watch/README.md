# 手表应用（待实现）

计划拆分 bootstrap（装配）、presentation（状态与交互）、application（调用用例）。手表端职责为**健康采集与上报**（不再接收 Agent 状态下发，2026-11-19 决策）。设备特性来自 DeviceAdapter，通信经 Session；UI 根据能力而非机型名称决策。

首个宿主面向 Android，非 Android 手表需另建宿主，复用消息语义和测试向量。现有 [OPPO 探针](../../devices/oppo-watch-4-pro/probe)仅用于 M0 验证。

> AI生成
