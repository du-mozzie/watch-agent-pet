# 贡献指南

谢谢你想贡献这个项目！这是一个以真机实测为根基的调研型项目，最有价值的贡献是**新的实测数据**。

## 最欢迎的三类贡献

### 1. 新机型的探针报告

你手里是其他 OPPO / 一加手表（Watch X / X2 / X3、Watch 3、一加手表 2、Watch SE……）？跑一遍探针把报告发来：

1. 照 [devices/oppo-watch-4-pro/docs/tutorials/01-getting-started.md](devices/oppo-watch-4-pro/docs/tutorials/01-getting-started.md) 连上手表
2. 运行 `devices/oppo-watch-4-pro/tools/verify-watch.ps1`（Windows 双击 `run-verify.bat` 即可）
3. 把生成的 `watch-report-<时间戳>.md` 附在 issue 里

贡献前请把报告里的**序列号脱敏**（换成 `XXXX****`）。

### 2. 判读修正

「表冠旋转 = F1/F2」「某私有 sensor 出数频率」这类结论都是基于有限实测的推断，拿新证据推翻它们是非常受欢迎的贡献。

### 3. 文档与教程

- 翻译（英文版 README / 教程）
- 新教程选题：最小 APK 的 Gradle 配置、Wi-Fi 直连通道实测、前台服务保活实测……

## 流程

1. Fork → 分支改动 → Pull Request
2. PR 请写清楚：验证了什么、设备型号 / 系统版本、实测命令与输出
3. 涉及健康数据的截图请自行脱敏

## 代码风格

现有脚本为 PowerShell 5.1 兼容语法，保持 UTF-8 BOM。基线探针保持只读；安装被测 App、传感器授权、Wi-Fi adb 等测试动作须明确说明，由用户执行，不得修改系统分区。

新增机型在 `devices/<机型>/` 提交适配、元数据、测试和配套资料；公共核心不得引入厂商 API。通信、PC 系统和 Agent 来源适配分别遵守 connectivity、platforms、integrations 的边界，见[总体架构](docs/research/architecture.md)。

## 行为边界

- 不讨论 / 不提供 root、刷机、改系统分区的方法
- 不提交需要 OPPO 开发者账号凭据的内容
- 健康数据结论始终附「非医疗器械、不用于诊断」声明

> AI生成
