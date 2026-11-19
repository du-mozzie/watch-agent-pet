# PC 系统适配

electron-host.js 利用 Electron 封装 Windows/macOS/Linux 的剪贴板、窗口置顶、系统通知和平台能力描述。UI 不调用 OS API。

自动输入注入、蓝牙、麦克风当前明确为 unsupported；文本可通过复制入口使用。三个系统配置独立 CI，实际验证不能以 Windows 结果替代。凭据库、托盘、自动启动按后续真实接入需求实现。
