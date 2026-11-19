# Agent 来源适配（后期扩展）

Agent 状态跟随功能已于 2026-11-19 从当前运行时移除：手表端不再接收六态下发。本目录是**后期扩展预留位**——把 Claude Code、Codex、豆包、Qoder 等客户端的状态结果接入 **PC 端**展示与分析（不下发手表）。

扩展时的接入方式：

- 实现 AgentSource 端口（见 [contracts/ports.md](../../contracts/ports.md)）：产生标准 AgentEvent（source/sessionId/eventId/state/text）。
- 在 bootstrap 显式注册 agent 插件；配置届时新增 agent 段（当前配置含 agent 段会被拒绝，避免半成品路径）。
- 各客户端实际接口需接入时核验（Claude Code HTTP hooks、Qoder IDE hooks、豆包粗粒度等，历史调研见 [docs/research/design-research.md](../../../docs/research/design-research.md) 的适配器矩阵）。
- 自定义模型分析（配置用户自己的模型对健康数据做分析）为同一阶段的另一个扩展项。

此层不负责手表连接、PC 窗口或渲染。

> AI生成
