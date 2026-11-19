# 教程 2：传感器探针判读 —— 这块表到底开放了什么

> 一条命令，回答「血氧 / ECG / 腕温 能不能绕过官方 SDK 直接读」。
> 本教程所有数据来自 OPPO Watch 4 Pro（OWW221）真机实测。

## 一条命令看全部传感器

```bash
adb shell dumpsys sensorservice
```

完整原始输出示例见 [docs/device-probe/sensorservice-dump.txt](../device-probe/sensorservice-dump.txt)（42 个硬件传感器、41 个运行中）。

## dump 结构怎么读

`Sensor List:` 段里每个传感器占两行：

```
0x00011001) PPG_SPO     | OPPO | ver: 1 | type: com.google.wear.sensor.ppg_spo(69633) | perm: android.permission.BODY_SENSORS | flags: 0x00000000
	continuous | minRate=1.00Hz | maxRate=500.00Hz | FIFO (max,reserved) = (40960, 0) events | non-wakeUp |
```

| 字段 | 含义 | 对我们的意义 |
|---|---|---|
| `PPG_SPO` | 传感器名 | 搜索关键词 |
| `type: xxx(69633)` | Android type 号 | **私有能力识别的核心**：括号里的数字 |
| `perm:` | 需要的权限 | `n/a` = 免权限；`BODY_SENSORS` = 要用户点一次授权 |
| `continuous / on-change` | 上报模式 | continuous 可高频采样 |
| `minRate / maxRate` | 频率能力 | 声明值≠实际给到第三方的值（见文末警告） |

## 健康类传感器速查表（Watch 4 Pro 实测）

| 能力 | 传感器 | type 号 | 权限 | 声明频率 | 判定 |
|---|---|---|---|---|---|
| **血氧** | `PPG_SPO` | **69633** | BODY_SENSORS | 1~500Hz continuous | ✅ 可侧载直读 |
| **心电（成品）** | `ECG_Sensor` | **69636** | BODY_SENSORS | 10~100Hz on-change | ✅ |
| **心电（原始波形）** | `ECG_RAW_PRO` | **69812** | **n/a 免权限** | 1~500Hz continuous | ✅ |
| **腕温** | `WRIST_TEMPERATURE` | **69815** | **n/a 免权限** | 5~100Hz on-change | ✅ |
| 心率（私有） | `PPG_HRM` | 69632 | BODY_SENSORS | 1~500Hz continuous | ✅ |
| 心率（标准） | `HEART_RATE` | 21 | BODY_SENSORS | 0.2~1Hz on-change | ✅ 标准 API |
| 佩戴检测 | `PPG_WEAR` | 69634 | BODY_SENSORS | 1~500Hz | 辅助 |
| 电极接触 | `Cap_Sensor` | 69637 | n/a | 10~100Hz | 辅助 |

### 原始 PPG 多通道（全部免权限，共 12 路）

| 通道 | type 号 |
|---|---|
| `PPG_RAW_G0` / `G1`（绿光 ×2） | 69801 / 69814 |
| `PPG_RAW_R0`~`R4`（红光 ×5） | 69802 / 69804 / 69806 / 69808 / 69810 |
| `PPG_RAW_IR0`~`IR4`（红外 ×5） | 69803 / 69805 / 69807 / 69809 / 69811 |

> 意味着**原始光电容积波形可直接拿到**，心率和血氧可以自研算法计算，不依赖厂商算法与 SDK。

### 其余免权限传感器

`GPS_MAIN`(69813)、`STATUS`(69818)、`CapSensor_POLL`、`Cap_Sensor`、抬腕 `Wrist_Tilt`、离腕 `LLOB`、加速度 / 陀螺 / 地磁 / 气压 / 环境光等全部 `n/a`。

## 为什么要看权限列——这张表是整个项目的分水岭

| 类别 | 传感器 | 开发含义 |
|---|---|---|
| `perm: n/a` | 腕温、ECG_RAW_PRO、12 路 PPG_RAW、GPS_MAIN、STATUS | **注册即用**：不需要 OPPO 开发者账号、不需要 SDK、不需要用户授权弹窗 |
| `BODY_SENSORS` | 血氧、成品 ECG、心率 | 需用户点一次授权（Android 标准 runtime 权限），**依然不需要 OPPO SDK** |

结论：**侧载直读路径成立，完全不用注册 OPPO 开发者、不用包名签名鉴权、不用手机中转。** 走官方 Wear Engine / 健康服务 SDK 才需要走那些流程。

## 附赠：物理按键的 keylayout 判读

从系统 keylayout 文件看物理输入映射（侧面说明了「表冠当物理旋钮」是否有戏）：

```bash
adb shell cat /system/usr/keylayout/qpnp_pon.kl
```

实测发现 59/60 两个 Linux keycode 被映射为 **F1 / F2** —— 推测对应**表冠旋转的两个方向**。这意味着 App 里监听 `KEYCODE_F1/F2` 就可能拿到旋转事件。但 keylayout 只是定义，还需 `getevent -l` 实测确认转表冠时真的发出这两个键：

```bash
adb shell getevent -l    # 然后转动表冠、按功能键，观察输出
```

> 该项是设计调研里的 PoC **P1**，实测通过则「表冠调电脑音量 / 切歌 / 翻页」成立。

## ⚠️ 最重要的警告：注册 ≠ 出数

`dumpsys` 里有条目，只说明传感器向**系统**注册了，不代表 HAL 会把数据交给**非系统应用**：

- 有些厂商在 HAL 层对第三方返回空值或恒 0
- 有些限制实际频率（声明 500Hz，实际可能只给 1Hz）
- 免权限（`perm: n/a`）不等于不被 `sensor_privacy` 拦截

**唯一可靠的验证方法**是装一个最小 APK 真实注册监听这些 type，数回调次数、看数值变化 —— 这正是[教程 3：最小验证 APK](03-minimal-sensor-apk.md) 的内容。

> AI生成
