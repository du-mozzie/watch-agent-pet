# AGENT.md — 开发与测试流程

> 本文件面向在本仓库工作的 AI 编码代理与人类贡献者，开工前必读。

> 配套：[README.md](README.md)（项目定位）｜[docs/research/design-research.md](docs/research/design-research.md)（总体计划）｜[packages/device-access/oppo-watch-4-pro/docs/tutorials/](packages/device-access/oppo-watch-4-pro/docs/tutorials)（操作细节）

> 任何 Agent 拿到本仓库的会话，第一步是读本文件，第二步是查「§12 计划指针」确认当前进度，再动手。

---

## 0. 角色与总原则

- 仓库主线：手表上报健康数据，PC 桌宠展示并采集到本地（数据目录可配置）；**当前阶段 M1a（桌面与模拟链路），真机仍为 M0**。

- **Agent 状态跟随已移除（2026-11-19 决策）**：手表端不再接收六态下发；Agent 状态接入（Claude Code/Codex/豆包/Qoder → PC 端展示）与自定义模型分析为后期扩展。协议保留 agent-state 通道作扩展位；当前运行时不注册任何 agent 插件，配置含 agent 段会被拒绝。

- 所有结论以**真机实测**为准；文档推断必须标注「待实测」。

- 设备操作三红线：**不 root、不刷机、不换表盘**。脚本除「安装被测 App / 采集日志」这类测试动作外，对设备一律只读。

- **真机测试永远请用户执行**：Agent 不自行要求连接设备；需要真机时，明确告知用户要做什么（放底座、开调试、跑哪个脚本），等用户完成并拿回结果。

- **测试通过才 push**：对应功能的真机测试未通过前，只 commit 到本地，不 push 远程。

## 1. OPPO Watch 4 Pro 约束（不适用于其他设备）

| 约束 | 值 | 来源 |
|---|---|---|
| ABI | **仅 armeabi-v7a（32 位）**，无 arm64 | 真机 `ro.product.cpu.abilist` 实测 |
| API | target 30 / min 27（Android 11 实测） | 真机 getprop |
| 表单 | 必须声明 `android.hardware.type.watch`，主题用 `Theme.DeviceDefault` | 官方文档 |
| 后台 | ROM 层事实：后台 sensor 持有 ≤1s、非健康类 ≤1 次/分钟、非 IM 禁后台联网 | 官方审核条款＝系统事实 |
| 蓝牙带宽 | ~80KB/s，不传图片/音视频 | 官方文档 |
| 安装权限 | 无 `INSTALL_PACKAGES`，组件中心不能自动装 APK | Android 权限模型 |
| 屏幕 | 378×496 @320dpi（≈189×248 dp，安全区约 180×235） | 实测 |

## 2. 环境要求与安装

| 依赖 | 要求 | 说明 |
|---|---|---|
| JDK | 17（javac 8+ 即可编译，d8.bat 经 JAVA_HOME 找 java，需 JDK 11+） | |
| Android SDK | `platforms;android-30` + `build-tools;34.0.0` | |
| platform-tools | adb（解压到 `tools/platform-tools/` 或 PATH） | 官方下载 |

SDK 安装（一次性，约 110MB）：

```powershell

# sdkmanager 在 cmdline-tools\latest\bin；SDK 根建议放在仓库根目录下 android-sdk（.gitignore 已忽略）

$env:JAVA_HOME = '<jdk17 目录>'

("y`n" * 10) | & <sdkmanager.bat> --licenses

& <sdkmanager.bat> 'platforms;android-30' 'build-tools;34.0.0'

```

## 3. 仓库结构（v4，workspace 分层）

结构权威：[总体架构](docs/research/architecture.md)。

- `packages/device-access/<机型>/`：硬件采集与插件、测试工具、配套资料；OPPO 原生探针在 `collector/`。
- `packages/runtime/`：插件运行时、服务、通信、配置与本地存储。
- `packages/contracts/`：公共消息、错误和跨语言协议契约。
- `apps/desktop/`：Electron 展示层及 PC 平台适配，拥有独立依赖与打包配置。
- `apps/bridge/`：独立无窗口运行入口，不依赖桌面包。
- `docs/`：设计与开发文档；`tools/`：仓库级检查及本地 adb。

根 package.json 仅编排 npm workspaces 与统一命令；依赖声明在各包，锁文件统一保留根目录。禁止跨包相对路径导入。运行层生产代码不依赖具体设备或 Electron，接入插件只依赖契约。

真实 OPPO 通信与 BLE 尚未实现。PC 开发要求 Node.js 22.12+；提交前运行 npm run check、npm test、npm run test:desktop，打包用 npm run pack。真机操作仍由用户执行。

## 4. 构建流程

```powershell

cd packages\device-access\oppo-watch-4-pro\collector

powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1

# 可选参数：-SdkPath <sdk目录> -JavaHome <jdk目录>（不传则自动探测）

```

- 产物：`packages/device-access/oppo-watch-4-pro/collector/build/sensor-probe-debug.apk`（当前 ~12KB）

- 构建在 `%TEMP%` 的 ASCII 暂存目录内进行，规避中文路径与原生工具的兼容问题

- **为什么不用 Gradle**：探针级 APK 零依赖，Gradle 拉取（发行版+AGP+依赖）远重于产出；正式宠物 App（M1 起）再上 Gradle

**本地静态校验（无需设备，Agent 可独立完成）**：

```powershell

& <build-tools>\aapt2.exe dump badging build\sensor-probe-debug.apk   # package/sdkVersion/uses-feature 正确性

# apksigner verify 已在 build.ps1 内置；检查 minSdk=27/target=30/watch feature

# 脚本编码防回归（§10 坑 1）：所有 .ps1 必须带 BOM 的 UTF-8，改完必跑两项校验：

#   ① PS 5.1 解析 0 错误；② 前 3 字节为 UTF-8 BOM（EF BB BF）

$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('<脚本路径>',[ref]$null,[ref]$e); $e.Count

([System.IO.File]::ReadAllBytes('<脚本路径>')[0..2] | ForEach-Object { $_.ToString('X2') }) -join ' '   # 应为 EF BB BF

```

## 5. 测试分层

| 层 | 谁执行 | 触发时机 |
|---|---|---|
| L1 本地静态 | Agent | 每次构建后（§4 校验清单） |
| L2 真机会话 | **用户** | 新 APK / 新探针脚本就绪时（§6 剧本） |
| L3 结果判读 | Agent | 用户交回 results/ 目录后（§7） |

## 6. 真机测试会话剧本（请用户执行时照此说明）

前置：手表放磁吸底座 → 底座 USB 接电脑 → USB 调试已开 → 表上授权「一律允许」。

### 两种测试位（物理约束决定，2026-11-19 实测发现）

| 位 | adb 通道 | 能验证什么 | 局限 |
|---|---|---|---|
| **停靠位**（默认） | 底座 USB | ✅ 核心问题「HAL 是否向第三方喂回调」＋P1 按键 | 表背贴充电器，PPG/ECG 值为零/噪声（无效值）；腕温读到的是充电器表面温度 |
| **手持/佩戴位** | Wi-Fi adb（`packages/device-access/oppo-watch-4-pro/tools/adb-wifi.ps1` 开启，拔线后手持/戴腕） | ✅ 全部：回调＋真实数值（PPG 见活体、ECG 表背贴掌＋指按表冠） | 手表需与 PC 同局域网；不支持 Portal 认证网络 |

**停靠位零回调的歧义警告**：表上有离腕检测（LLOB/PPG_WEAR），检测到未佩戴时 HAL 可能暂停 PPG 类传感器——停靠模式下「无回调」分不清是「HAL 拦第三方」还是「没戴暂停」。停靠测出零回调时，必须用 Wi-Fi 模式手持复测才能下结论。

用户只需一条命令（或双击 `packages/device-access/oppo-watch-4-pro/tools/device-test.bat`）：

```powershell

powershell -NoProfile -ExecutionPolicy Bypass -File packages\device-access\oppo-watch-4-pro\tools\device-test.ps1

# 升级到手持/佩戴位：先跑 packages\device-access\oppo-watch-4-pro\tools\adb-wifi.ps1（拔线拔座），再跑 device-test.ps1

```

脚本自动完成：等设备 → **P1 按键采集**（提示用户转表冠/按功能键/按表冠/抬腕，`getevent -l` 录 25 秒）→ 安装探针 APK → `pm grant` 授权 → 拉起 App → 录 `logcat -s PROBE STATS` 20 秒 → 抓 `dumpsys sensorservice` 中 owapet 的注册行 → 汇总。

产出：`results/device-test-<时间戳>/`（getevent.txt / logcat-probe.txt / sensorservice-dump.txt / summary.md）。

**用户须知**（脚本会按 adb 通道自动提示对应模式）：采集期间保持 App 在前台；手持模式手指贴表背、ECG 表背贴掌＋指按表冠。

## 7. 结果判读与处理回路

判读依据 [packages/device-access/oppo-watch-4-pro/docs/tutorials/03-minimal-sensor-apk.md](packages/device-access/oppo-watch-4-pro/docs/tutorials/03-minimal-sensor-apk.md) 与 [报告 r2 §3](packages/device-access/oppo-watch-4-pro/docs/reports/probe-report-r2.md)：

| logcat 现象 | 结论 | 动作 |
|---|---|---|
| `首发` + values 变化 + STATS `活跃` | ✅ 可用 | 直接进开发，结论写入 probe-report-rN |
| 全部零回调，但**灭屏/息屏状态** | ⚠️ **亮屏门控（不是 HAL 拦截）** | 先 `input keyevent KEYCODE_WAKEUP` 再重测（r2 实测：亮屏即恢复 246Hz 数据流） |
| 有回调但 values 恒 0（亮屏下） | ⚠️ HAL 空转 | 该项回退官方 SDK 路线 |
| STATS 显示 Hz 远低于 dumpsys 声明 | ⚠️ 厂商限频 | 按实际 Hz 设计采样 |
| 亮屏+接触皮肤下仍零回调 | ❌ 被拦截 | 查 sensor_privacy / 权限，仍不行回退 SDK |

**亮屏门控三步法**（r2 实证）：① 灭屏时零回调 ≠ 拦截，先亮屏；② 亮屏后 App 被杀则冷启动重装重测；③ 成品类传感器（血氧/心率/ECG 成品）停靠位零回调需 Wi-Fi 手持位+皮肤接触复测才能定论。

getevent 判读：`KEY_F1`（侧边功能键）与 `EV_REL REL_WHEEL`（表冠旋转，±1）均已被 App 监听路径覆盖（r2 §1：旋转走相对轴非按键，接表冠需读输入设备，工程量大于按键）。

- **通过**：整理 results/ → 脱敏 → 写 `packages/device-access/oppo-watch-4-pro/docs/reports/probe-report-rN.md` → git commit → **git push**（§8 纪律）

- **不通过**：原始结果交回 Agent 分析 → 定位（权限/HAL/频率）→ 修正代码或调整方案 → 重新构建 → 再约真机会话

## 8. Git 纪律

- 分支：单线开发，当前为 `master`（2026-11-19 仓库重建后从 main 切换，勿再建新分支）；小步提交；commit message 英文祈使句（沿用现有风格），正文可中文。

- **推送纪律：对应功能真机测试通过后才 push**；push 前跑敏感扫描：

  ```powershell

  git grep -n -i -E 'CA6C[0-9A-F]{4}|github_pat_|ghp_|E:\\资料' -- .

  ```

- 不提交：`results/` 原始输出、`build/`、`*.keystore`、`platform-tools`/`cmdline-tools`/`android-sdk`、任何 token/密钥（.gitignore 已列）。

- 报告入库前脱敏：序列号写 `CA6C****` 形式。

- push 认证：凭据不写入仓库与 remote URL；用会话内临时凭据或用户侧凭证管理器。

## 9. 安全与合规底线

- 健康数据内容必须带「非医疗器械、不用于诊断、异常请就医」声明。

- 数据不上云；PC 桥接仅局域网。

- 本仓库不与 OPPO 存在隶属关系；引用官方条款以最新页面为准。

- 不提供 root/刷机/改分区方法。

## 10. PowerShell 5.1 工程坑位表（本仓库实测踩过，必须遵守）

1. **.ps1 中文脚本必须带 BOM 的 UTF-8**：PS 5.1 把无 BOM 的 UTF-8 当 ANSI/GBK 解析，含中文的脚本会直接解析报错（字符串被切碎→MissingArrayIndexExpression 等假语法错）；`Get-Content`→改→`Set-Content` 的往返也可能毁文件（编码错配）。仓库规范：**所有 .ps1 保存为带 BOM 的 UTF-8，提示信息用中文**；每次改动后跑 §4 的 BOM+解析双校验。

2. **数组 splatting 传原生 exe 会坏参数**：`@args` 展开传给 javac/d8 会被切碎；只能用**字面量字符串参数**逐个传，多文件用 foreach 或先 `jar` 打包成单输入。

3. **d8.bat / apksigner.bat 经 JAVA_HOME 找 java**：构建前把 `$env:JAVA_HOME` 指到 JDK 11+（系统 JAVA_HOME 若指向 JDK8 会报 class version 55 错）。

4. **`$ErrorActionPreference='Stop'` + 原生命令 stderr**：javac 的警告会变成终止错误；构建脚本里用 `Continue` + 显式 `$LASTEXITCODE` 检查。

5. **中文报错读法**：原生工具 stderr 是 GBK；重定向到文件后用 `[System.Text.Encoding]::GetEncoding(936)` 解码。

6. adb 输出统一为 UTF-8：脚本开头 `[Console]::OutputEncoding = UTF8`。

## 11. OPPO 硬件事实与历史协议决策

- 私有 sensor type 号：血氧 69633 / 成品 ECG 69636 / ECG 原始波 69812 / 腕温 69815 / 心率私有 69632 / 标准心率 21 / 12 路 PPG_RAW 69801~69814；免权限项见 [教程②速查表](packages/device-access/oppo-watch-4-pro/docs/tutorials/02-sensor-probe.md)。

- 最新通信契约以 [contracts/protocol.md](packages/contracts/protocol.md) 为准，以下选型是 OPPO 历史方案，尚非运行时能力。

- 事件模型六态：`idle|thinking|running|waiting|done|error`（JSON、<4KB/帧）——**协议扩展位**，Agent 状态不再下发手表，供后期 PC 端接入 Agent 来源用。

- 适配器优先级（后期扩展参考）：Claude Code（HTTP hooks）> Qoder > Codex > WorkBuddy（tail 日志）> 豆包（粗粒度兜底）。

- 产品叙事：宠物是「一键唤起的 App / 充电底座桌宠」，不是表盘。

- **停靠即致盲（2026-11-19 实测发现）**：表吸底座时背面（PPG/ECG 电极/腕温）贴着充电器——「底座桌宠」模式下健康测量物理不可行，夜间心率/睡眠数据拿不到（宠物状态显示不受影响，它不走传感器）。健康数据看板是「白天佩戴」功能，不是「夜间桌宠」功能。

- **通信选型（2026-11-19 决策）**：主场景是白天佩戴——**BLE GATT 优先（P9 待验证）+ Wi-Fi 局域网备选**，上层统一健康帧协议（JSON、<4KB/帧、可插拔 transport）。调研与决策详见 [transport-selection.md](docs/research/transport-selection.md)。

- **表冠输入路径（r2 实测）**：旋转走 `EV_REL REL_WHEEL` 相对轴（非按键，接它需读输入设备，工程量大于按键）；侧边功能键走 `KEY_F1`。

- **亮屏门控（2026-11-19 r2 实测）**：灭屏时 HAL 对第三方全部零回调（非拦截），亮屏即恢复——实测 246.7 Hz PPG / 52.7 Hz ECG / 98.5 Hz 腕温；采健康数据必须亮屏。灭屏也会杀后台 App 进程（前台服务是常驻唯一路径）。

- **离腕门控混淆**：LLOB/PPG_WEAR 检测未佩戴时 HAL 可能暂停 PPG 类传感器——停靠位零回调 ≠ HAL 拦截第三方，需 Wi-Fi 手持位复测区分。

## 12. 计划指针（M0 ✅ → M1b 手表数据采集 → M1c 稳定性与数据价值）

### 12.0 里程碑总览

| 阶段 | 目标 | 状态 |
|---|---|---|
| M0 探针验证 | 传感器/按键边界实证 | ✅ 完成（见 12.1） |
| M1a 桌面与模拟链路 | 插件运行时 + 桌宠展示 + 本地采集（模拟数据端到端） | ✅ 完成 |
| **M1b 手表数据采集** | **真机 OPPO → PC 端到端真实数据**（本阶段，见 12.2） | 🔄 计划已定 |
| M1c 稳定性与数据价值 | 断线恢复、看板趋势、功耗（见 12.3） | ⏸ |
| M2 后期扩展 | Agent 状态接入 PC / 自定义模型分析 / 第二机型 | ⏸ 评估位 |

### 12.1 M0 PoC 结论（已完成，实测依据）

| # | 验证项 | 结论 | 载体 |
|---|---|---|---|
| P1 | 按键事件能否被 App 截获 | ✅ 功能键=KEY_F1；表冠旋转=REL_WHEEL 相对轴 ±1 | [报告 r2 §1](packages/device-access/oppo-watch-4-pro/docs/reports/probe-report-r2.md) |
| P0+ | 私有 sensor 出数与频率 | ✅ 12路 PPG_RAW 246.7Hz + ECG_RAW 52.7Hz + 腕温 98.5Hz 全部免权限直读；亮屏门控实证（灭屏零回调+杀进程）；血氧/心率/ECG 成品停靠位零回调→悬案 H1 | [报告 r2 §2-3](packages/device-access/oppo-watch-4-pro/docs/reports/probe-report-r2.md) |
| P5/P6/P7/P8 | 录音/播放/32位runtime/自定义按键 | ⏸ 后期评估（定位反转后优先级降） | — |

**M0 遗留悬案**：H1 成品通道（血氧/心率/ECG 成品）手持位是否出数——归入 M1b T5 收口。

### 12.2 M1b：手表数据采集（当前阶段，2026-11-19 定稿）

**目标**：真机 OPPO 亮屏采集健康数据 → Wi-Fi 上报 → PC 桌宠/看板展示 + JSONL 落盘，端到端真实数据。

| # | 任务 | 内容 | 真机依赖 | 验收标准 |
|---|---|---|---|---|
| **T1** | 手表采集 App 骨架 | 正式 Gradle 工程（替代探针的临时 build.ps1 流程）：亮屏采集窗口 + 前台服务（indicator 常驻）+ 免权限 RAW 传感器（PPG_RAW×12 / ECG_RAW_PRO / 腕温）直读；**端上聚合**（滑窗均值）把 246Hz 原始流降为 ~1Hz 健康帧 | 构建无需真机；验证需 | 亮屏下 logcat 可见聚合健康帧（数值合理）；灭屏自动暂停、亮屏恢复；前台服务 8h 孜活（=P2）；**后台采集实证**（前台服务+灭屏下 sensor 是否继续出数——r2 只测过普通 Activity，未测前台服务；结论写报告，若灭屏可采则升级为后台连续采集） |
| **T2** | 手表 Wi-Fi 上报 | App 作 WebSocket client 连 PC。PC 侧新增**真网络 transport**（单端 connect/accept 分离，替换成对 open 模拟接口——架构预留的演进点）；先绑局域网、令牌握手 | 需真机 | bridge/desktop 收到真机帧并落盘 JSONL |
| **T3** | PC 真机适配器 | `device-access/oppo-watch-4-pro` 实现 JS DeviceAdapter（注册 oppo profile）+ 真机配置样例更新 | 需真机 | UI 切到真机 profile：看板显示真机数值、采集目录正常写盘、断连恢复 |
| **T4** | 稳定性实测 | P2（前台服务 8h 断流 ≤1 次）、P4（Wi-Fi 24h 断连 <3 次 + 断线自动恢复）、P3（功耗：日耗电可接受） | **需用户** | 按各准出标准；报告写 probe-report-r3 |
| **T5** | 悬案收口 + 通道决策 | H1 手持位复测（血氧/心率/ECG 成品是否出数→决定采集通道清单）；P9 BLE GATT server PoC→通道决策更新 transport-selection.md | **需用户** | 两个明确结论入库 |

**执行顺序与并行**：T1 纯本地开发可立即开工；T2 的 PC 侧 transport 可先用 simulator 联调（不需要真机）；T3 依赖 T1/T2 就绪；T4/T5 需约用户真机会话（§6 剧本）。

**风险与对策**（基于 M0 实测事实）：
- 亮屏门控 → 采集设计为「亮屏采集、灭屏暂停」，**不对抗 ROM 省电策略**；数据新鲜度在 UI 如实展示。**后台采集可行性未排除**：官方条款明说前台服务是后台运行的正解、健康类有后台例外——r2 只测过普通 Activity（灭屏被杀+零回调），**没测过前台服务**；T1 验收含此实证，若灭屏可采则升级为后台连续采集
- 官方健康路线兜底：Wear Engine / 健康服务 SDK 是官方设计的灭屏健康通道（事件级推送），当前免权限侧载路线失败时再启用（需注册开发者+鉴权）
- 停靠即致盲 → 产品口径「白天佩戴采集」；桌宠在停靠位只展示不采集
- P9 BLE 失败 → 回退 Wi-Fi 为主（工位场景可用）；通道可插拔设计保证切换成本仅 transport 层
- 前台服务被杀 → 崩溃自动重启重连（JobScheduler/ScheduledWork 兜底）+ 断线补传（协议 ACK 扩展位）
- Wi-Fi 不支持 Portal 认证网络（官方限制）→ 文档明示

### 12.3 M1c：稳定性与数据价值（后续）

- 断线恢复与补传：协议 ACK/重放落地（contracts/protocol.md 目标）；断连期间手表本地缓存（有界）、恢复后补传
- 看板趋势：读 JSONL 历史画当日/近 7 天曲线；数据导出（CSV/JSON）
- 功耗打磨：采样窗口调度（抬腕优先）、聚合频率分级
- 第二通道落地：依 T5 决策（BLE 或 Wi-Fi 优化）
- 稳定性准入：连续 7 天采集不中断、日耗电可接受

### 12.4 M2：后期扩展（评估位，未排期）

- **Agent 状态接入 PC**：Claude Code（HTTP hooks）/ Qoder / Codex / WorkBuddy / 豆包 → PC 端展示（agent-state 协议扩展位已预留）
- **自定义模型分析**：配置用户自己的模型（本地/云）分析采集数据
- 第二机型 / 第二 PC OS：验证 v4 可替换边界（新增 device-access/<机型> 或 platforms 适配）
- 组件中心（原 M3 设想）：定位反转后降为低优先级评估项

**当前活动任务**：M1b T1 手表采集 App 骨架（无真机依赖，可直接开工）。

---

*本文件随流程演进持续更新；与现状冲突时以最新实测报告为准。*

> AI生成
