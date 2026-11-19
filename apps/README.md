# 应用宿主

- [desktop](desktop/README.md)：Electron PC 展示层，装配运行层与设备插件。
- [bridge](bridge/README.md)：无窗口 Node.js 宿主，可独立运行采集链路。

硬件采集工程与配套资料统一放在 [device-access](../packages/device-access/README.md)。应用之间不互相导入源码。
