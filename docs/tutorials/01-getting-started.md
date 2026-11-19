# 教程 1：从零把 OPPO Watch 4 Pro 连上电脑

> 目标：15 分钟内让电脑通过 ADB 看到你的手表，为后续所有探针/侧载操作打地基。
> 前提：**全程纯只读**，不改手表任何设置（开发者模式与 USB 调试都是官方提供的功能，关闭即还原）。

## 前置条件

| 物品 | 说明 |
|---|---|
| OPPO Watch 4 Pro | 其他型号（Watch X / X3、Watch 3、一加手表 2 等）流程相同 |
| 磁吸充电底座 | 原装底座，顶针接触 |
| USB 数据线 | **必须是能传数据的线**——大量 Type-C 线只走充电不带数据引脚，这是连接失败的第一大原因 |
| 电脑 | Windows / macOS / Linux 均可 |

## 第 1 步：装 ADB 工具

下载 Google 官方 platform-tools（含 adb）：

```
https://developer.android.com/tools/releases/platform-tools
```

解压到本项目的 `tools/platform-tools/` 目录（脚本会自动找到它），或放到任何 PATH 里的位置。

验证：

```bash
adb version
# 正常输出类似：Android Debug Bridge version 1.0.41 ...
```

## 第 2 步：手表开启开发者模式

按官方口径操作（网上有说点 5 次的，**以 7 次为准，以表上出现提示为准**）：

1. 按一下**导航键（上键）**进入应用列表
2. **设置 → 其他设置 → 关于手表**
3. 找到**版本号，连续点击 7 次**
4. 表上提示「已进入开发者模式」
5. 返回「其他设置」，列表最底部出现**开发者选项**

> 若「开发者选项」里找不到「USB 调试」，说明开发者模式没开成功——回到关于手表对版本号再连点 7 次。

## 第 3 步：开 USB 调试

**开发者选项 → USB 调试**，打开开关。

## 第 4 步：底座连电脑

1. 手表吸上磁吸充电底座
2. 底座的 USB 线**插电脑**（建议主机**后置 USB 口**；前面板 / 扩展坞可能供电不足）
3. 手表屏幕弹出「允许 USB 调试吗」→ **勾选「一律允许」** → 确定

> 没弹授权窗的，把手表从底座拿起来再放一次。

## 第 5 步：验证连接

```bash
adb devices
```

正常输出：

```
List of devices attached
CA6CXXXX       device
```

> 状态列含义：`device`=正常 ｜ `unauthorized`=表上授权弹窗没点 ｜ `offline`=重启 adb（`adb kill-server`）后重插

顺手确认系统基线（应与 [实测报告 §1](../device-probe/probe-report-r1.md) 一致）：

```bash
adb shell getprop ro.build.version.release   # Android 版本（4 Pro 实测 11）
adb shell getprop ro.product.cpu.abi          # armeabi-v7a（只支持 32 位！）
adb shell getprop ro.build.version.sdk        # API level（实测 30）
adb shell wm size                             # 378x496
adb shell wm density                          # 320
```

## 第 6 步：跑一键探针

Windows 用户直接双击 `tools/run-verify.bat`；命令行用户：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify-watch.ps1
```

脚本会依次输出：设备连接状态 → 型号/系统/ABI/屏幕/电池基线 → **全部传感器清单与血氧/ECG/腕温关键词命中** → 侧载环境检查 → 前台窗口。同时生成 `watch-report-<时间戳>.md` 报告文件。

传感器怎么判读？继续看[教程 2：传感器探针判读](02-sensor-probe.md)。

## 常见故障排查

| 症状 | 原因 | 解法 |
|---|---|---|
| `adb devices` 空列表 | 线只充电不传数据 | 换一根确定能传文件的手机数据线 |
| 空列表且换线无效 | 插的是充电头不是电脑 / 供电不足 | 插电脑后置 USB 口 |
| 空列表，表上无任何反应 | USB 调试没开 | 回到第 3 步 |
| `unauthorized` | 表上授权弹窗没点 | 点「一律允许」；没弹窗就重新放一次底座 |
| `offline` | adb 服务状态异常 | `adb kill-server` 后重新插拔 |
| 设备管理器里有未知设备 | 缺 USB 驱动 | Windows 更新 / 厂商驱动 |

## 环境差异说明

- **PowerShell 5.1 用户**（Windows 自带）：直接用本教程命令即可，不需要 `pwsh`
- **macOS / Linux**：`verify-watch.ps1` 是 PowerShell 语法；核心命令 `adb shell dumpsys sensorservice` 跨平台通用，可手动执行

> AI生成
