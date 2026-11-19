# Wire JSON v1（目标草案，M1a 已实现本机子集）

本文件规定消息语义；[架构](../docs/research/architecture.md)规定会话、codec、transport 职责。M1a 已实现 health 的编码验证、身份绑定、连接内序号去重；ACK、control/config/audio、握手和跨连接补传尚未实现。以下可靠性与配对部分仍是目标，不能当作已部署协议。

## 帧结构

```json
{
  "v": 1,
  "sender": "watch-01",
  "epoch": "boot-unique-id",
  "ch": "health",
  "seq": 412,
  "ts": 1795046400000,
  "payload": {
    "metric": "heart-rate",
    "value": 72,
    "unit": "bpm",
    "sampledAt": 1795046400000,
    "quality": "valid"
  }
}
```

UTF-8 JSON，完整编码消息最多 4096 字节（含头）。时间使用 Unix 毫秒；seq 为每 sender/epoch/ch 从 1 自增的安全整数；丢失序列状态时更新 epoch。sender 必须绑定认证身份。BLE 可在 transport 内按 MTU 分片，重组完整消息后才交给 codec；重组须有长度上限与超时。

| ch | 方向 | 载荷 |
|---|---|---|
| agent-state（后期扩展，不下发手表） | Agent 来源 → PC | source、sessionId、eventId、state、可选 text；供 PC 端展示与分析 |
| health | 手表 → PC | metric、可选 value、unit、sampledAt、quality |
| control | 双向 | commandId、op、expiresAt、参数；返回执行结果 |
| config | 双向 | requestId、op、参数；仅开放白名单设置 |
| audio | 按能力协商 | streamId、index、codec、chunk；未协商则拒绝 |
| ack | 双向 | sender、epoch、ch、through，标识被确认的目标流 |

Agent 状态六态（idle/thinking/running/waiting/done/error）保留为协议取值；当前运行时不注册 agent 插件（2026-11-19 决策）。无效健康值使用 quality 表达。

## 可靠性

- ACK 的 through 为连续收到并接受的最大序号，不能越过缺口；ACK 不需要 ACK，避免回执循环。无业务回包也主动发 ACK。
- 去重键为 sender/epoch/ch/seq；不能按 sessionId/state 去重，否则丢失同态更新和再次进入同一状态。
- 恢复时交换 epoch 与确认点；发送缓存每流最多 256 条/1 MiB/1 小时，全局最多 8 MiB。缺口超出缓存时返回 resync-required，以新 epoch 和快照恢复，不无限重发。
- Agent 状态可合并为最新快照；health 有限补发并保留采样时间；音频断连丢弃，不跨会话补发。
- control 不自动重试执行；commandId 和执行结果用于去重，结果未知时先查询或要求用户重发。网络 ACK 不等于执行成功，不承诺恰好一次。
- 队列有界：健康消息可按策略合并/丢弃并计数，控制队列满则明确拒绝。WebSocket 缓冲不代替背压。
- 默认心跳 30 秒，三次无响应判定断连，具体周期在握手协商并实测功耗。

## 协商与安全

配对认证后先用固定 JSON v1 握手交换版本、codec、功能、最大帧、设备身份，再传业务消息；无共同版本则终止并报告 UI。未知消息类型返回 unsupported，不执行任意 op。

局域网仍需认证。生产 WebSocket 要求 TLS 或经验证的等效加密；BLE 须明确配对与对端身份校验。具体密钥交换、证书信任和 BLE 分片头为实现前待定项，未完成验证前不开放控制/配置入口。

> AI生成
