# 运行配置

[demo.json](demo.json) 是可直接运行的模拟配置；[load.js](load.js) 提供读取和校验。PC 首次使用它，之后读取 Electron userData/runtime.json；UI 切换设备/通道后持久化，导入 JSON 也会校验后应用。

- schemaVersion 必须为 1；host.platform 可为 auto 或当前平台 windows/macos/linux。
- devices 仅允许一个 enabled 项，instanceId 唯一；profile 必须注册，通道必须与设备兼容。
- connection.codec 为注册的编码器；transportPriority 不允许为空或重复；allowFallback=false 仅尝试第一项。
- **storage.dataDir**（可选）：本地健康采集目录。相对路径相对 Electron userData 解析，绝对路径直接使用；缺省为 data。UI 内可运行中切换（不重建连接），并持久化到配置。
- **agent 段不允许**：Agent 状态跟随已移除（2026-11-19），配置含 agent 段会被拒绝；Agent 来源为后期扩展，届时再开放。
- 支持热切换，关闭旧设备/连接/订阅后建立新会话；失败显示错误，不静默启用未知实现。

[runtime.example.json](runtime.example.json) 保留为未来 OPPO 真机配置草案，**当前导入会因未注册插件而被拒绝**。其中 credentialRef、peerRef 为未来配对记录引用，尚无密钥存储实现。请勿把它当作可运行 demo。

> AI生成
