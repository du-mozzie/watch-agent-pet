# 插件与应用服务契约（设计草案）

以下是目标契约。PC 已实现其中的本机模拟子集，当前接口以代码和[开发指南](../docs/development/desktop-runtime.md)为准：静态 PluginRegistry、Device.describe/start/stop、成对 Transport.open、Connection、Codec、Session、DesktopService。完整目标中的采集权限、远程配对及系统凭据尚未实现。

| 接口 | 操作 | 责任 |
|---|---|---|
| DeviceAdapter | describe / probeCapabilities / start / stop / subscribeInput / collect | 设备身份、能力、标准输入和健康采样，隔离厂商 API |
| AgentSource（后期扩展，未注册实现） | start / subscribe / stop | 标准 AgentEvent，保留来源与 sessionId；接入 PC 端展示，不下发手表 |
| HostPlatform | capabilities / notify / setWindowMode / insertText / credentialStore | 返回能力与授权结果，不向业务暴露 OS 句柄 |
| Codec | id / version / encode / decode | 消息与字节互转，验证字段与长度 |
| TransportFactory | id / capabilities / connect | 异步返回 Connection，可取消、可超时 |
| Connection | send(bytes) / subscribeMessages / subscribeStatus / close | 完整消息交付、物理分片重组、背压 |
| Session | connect / publish(message, policy) / subscribe / close | 配对、协商、恢复与可靠性 |
| DesktopService | snapshot / subscribe / dispatch(command) | UI 唯一入口，可用进程内或未来 IPC 实现 |

订阅返回取消句柄；stop/close 幂等并释放资源；异步操作支持超时与取消；旧会话回调不能影响新会话。

- AgentEvent（后期扩展）：source、sessionId、eventId、occurredAt、state、可选 text；state 为 idle/thinking/running/waiting/done/error。Agent 状态不下发手表（2026-11-19 决策）；该事件供 PC 端展示与后续分析用，协议保留 agent-state 通道作扩展位。
- HealthSample：deviceId、metric、可选 value、unit、sampledAt、quality；质量区分有效、无接触、过期、不可用，不能伪造 0。
- InputEvent：deviceId、kind、可选 value、occurredAt；设备实现将物理输入转为逻辑输入。
- Capability：name、status、可选 reason/limits；区分静态候选与运行时探测结果。
- PluginError：code、message、retryable；至少覆盖 unsupported、permission-denied、disconnected、timeout、backpressure、incompatible-version、invalid-config。

配置只能引用注册表插件 ID。实现时须提供运行时限制、支持版本与测试夹具，覆盖断线、权限拒绝、无数据与能力缺失。

> AI生成
