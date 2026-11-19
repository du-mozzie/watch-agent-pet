# 业务核心

registry.js 提供可信静态插件注册与接口版本检查；desktop-service.js 管理 Agent/健康状态、数据新鲜度与变化订阅；errors.js 提供标准错误。

核心不导入 Android、Electron、厂商 SDK、BLE/WebSocket；应用装配器决定使用哪些实现。当前按职责拆为文件，规模扩大后再拆 domain/application/ports 子包。
