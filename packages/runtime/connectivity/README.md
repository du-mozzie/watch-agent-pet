# 通信模块

- session.js：连接内身份绑定、epoch/序号去重与生命周期，重连使用快照。
- json-codec.js：UTF-8 JSON v1 编解码、大小和字段验证。
- transports/memory.js：异步有界队列。
- transports/loopback-websocket.js：本机真实 socket，随机端口与一次性令牌，不接受局域网手表。

当前仅支持本机模拟 profile；ACK 补传、自动重连、BLE、TLS 配对与远程握手仍为[协议目标](../../contracts/protocol.md)。两个通道均执行双向传输，不以 UI 假数据绕过通信模块。
