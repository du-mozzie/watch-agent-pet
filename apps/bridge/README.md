# 无窗口桥接宿主

独立 npm workspace：`@watch-agent-pet/bridge`。仅依赖运行层与设备插件，不依赖 Electron 或桌面包。

根目录运行 `npm run bridge`。指定配置可运行 `node apps/bridge/main.js packages/runtime/config/demo.json`；相对配置路径按启动工作目录解析。Ctrl+C 关闭采集与连接。当前为本机模拟链路，日志只输出状态与指标名，不输出健康数值。

该入口不是向桌面提供远程 API 的守护进程；桌面目前在主进程内独立装配运行层。
