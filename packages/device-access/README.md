# 硬件数据接入层

按设备组织采集实现与配套资料，品牌差异在这里消化，向运行层输出标准健康采样。

- [simulator](simulator/README.md)：可运行的 npm 设备插件，包含完整指标和仅心率两种配置。
- [oppo-watch-4-pro](oppo-watch-4-pro/README.md)：`collector/` 保存 Android 探针、`tools/` 保存测试脚本、`docs/` 保存官方资料/报告/教程、`device.json` 保存机型描述。真实通信适配尚未实现。

每个 JavaScript 设备插件独立声明 package.json，只依赖 contracts。Android 等原生采集工程使用自身工具链，不创建无意义的 npm 包。后续正式手表采集 App 也放在对应机型下；确有第二款设备共享实现时再抽公共包。

当前设备接口为 `describe()`、`start({onSample,onError})`、`stop()`。设备提供标准采样，Session/Codec/Transport 由运行层管理。真实设备接入仍需实现远端连接与协议握手，不能将模拟插件当作 BLE 实现。
