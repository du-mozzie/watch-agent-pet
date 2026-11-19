# Wire 协议 v1（手表 ↔ PC 通道无关帧协议）

> 两端 transport 实现共同遵守的唯一规范。版本：v1（2026-11-19）。
> 设计约束：帧 <4KB、通道无关（BLE GATT 与 Wi-Fi WS 同帧编码）、断线可补传、可扩展通道。

## 1 帧公共头（所有通道通用）

```jsonc
{
  "v":   1,                     // 协议版本（uint）
  "ch":  "health",              // 通道名（见 §2）
  "seq": 412,                    // 发送侧帧序号（uint，每 ch 独立自增）
  "ack": 411,                    // 已确认收到对端最大 seq（可选）
  "ts":  1732020123.456          // 发送时刻 Unix 秒（小数=ms 精度）
}
```

- 分片：帧超 4KB 必须先聚合/压缩/降采样，**不允许网络层分片**
- 字节序/编码：UTF-8 JSON；BLE 上再叠加 CBOR/二进制头（保留，v1 先 JSON）

## 2 通道（ch）与载荷

| ch | 方向 | 载荷示例 | 频率 |
|---|---|---|---|
| `health` | 手表→PC | `{"hr":72,"spo2":98,"temp":36.4,"wear":true}` | 分钟级聚合 |
| `agent-state` | PC→手表 | `{"session":"cc-1","agent":"claude-code","state":"thinking","text":"重构 transport","tool":"Edit"}` | 事件驱动 |
| `control` | 双向 | `{"op":"voice.start"}` / `{"op":"pet.wake"}` / `{"op":"ping"}` | 事件驱动 |
| `audio` | 手表→PC | `{"codec":"opus-16k","chunk":"<base64>"}` | 会话中 |
| `config` | 双向 | `{"set":{"brightness":0.8}}` / `{"get":"all"}` | 低频 |

六态取值：`idle | thinking | running | waiting | done | error`。

## 3 可靠性

- **seq/ACK 补传**：接收方在下一帧 `ack` 回执；发送方缓存已发帧，重连后重发 `seq>ack` 的帧，窗口上限 256 帧（约 = 一小时健康帧）
- **心跳**：`control:{"op":"ping"}` 每 30s，3 次未回判定断连 → 触发降级策略
- **幂等**：`agent-state` 按 `(session, state)` 去重；`health` 按 `ts` 新鲜度取舍

## 4 通道能力约定（transport 实现契约）

| 约束 | BLE GATT | Wi-Fi WS |
|---|---|---|
| MTU/分帧 | 单 notify ≤ MTU-3 字节，长帧拆子帧 + 结尾标记 | 单消息 ≤4KB 直接发 |
| 背压 | 发送队列满即丢最旧 health（非关键帧） | WebSocket 自带缓冲 |
| 服务端/客户端 | 手表 = GATT server（P9 待验证）；PC = central | 手表 = WS client；PC = WS server（局域网） |

## 5 版本与兼容

- `v` 不匹配：接收方回 `config:{"err":"version"}` 并忽略载荷
- 新增 ch = 兼容；改名/改语义 = 升 v2
- 本文件是唯一权威；两端 transport/协议测试帧以本文为准

> AI生成
