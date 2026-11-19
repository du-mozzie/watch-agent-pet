# OPPO Watch 4 Pro 接入包

首个验证设备：OWW221，实测 Android 11 / API 30、armeabi-v7a、378×496 屏幕。这些限制只适用于本机型，不应进入公共核心。

| 位置 | 内容 |
|---|---|
| [device.json](device.json) | 机型元数据与验证状态，尚无运行时加载器 |
| [collector](collector) | 纯 Java 最小传感器探针，现有包名 com.owapet.sensorprobe |
| [tools](tools) | 基线探针、真机会话、Wi-Fi adb 和 Windows 双击入口 |
| [官方资料](docs/official/oppo-wear-dev-notes.md) | OPPO 文档摘录与历史判读 |
| [报告 r1](docs/reports/probe-report-r1.md)、[r2](docs/reports/probe-report-r2.md) | 传感器枚举、亮屏回调、输入事件 |
| [教程 1](docs/tutorials/01-getting-started.md)、[2](docs/tutorials/02-sensor-probe.md)、[3](docs/tutorials/03-minimal-sensor-apk.md) | 连接、判读和构建 |

需用户准备手表、可传数据的 USB 线和充电底座，并启用调试授权。构建需要 JDK 与 Android SDK，见根目录 [AGENT.md](../../../AGENT.md)。脚本仍从仓库根目录调用；通用 adb 位于 tools/platform-tools 或 PATH。

已验证亮屏下部分原始传感器回调；血氧/心率成品有效值、后台常驻和 BLE GATT 仍待验证。底座遮挡表背时不能把零值当真实健康数据。正式 DeviceAdapter 尚未实现，collector 中的探针不实现公共插件接口。

健康数据非医疗器械、不用于诊断，异常请就医。
