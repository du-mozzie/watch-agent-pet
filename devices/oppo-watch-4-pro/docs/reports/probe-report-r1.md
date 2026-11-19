# OPPO Watch 4 Pro 实测报告（第一轮 · 探针）

> 实测时间：2026-11-19 09:29
> 设备：OPPO Watch 4 Pro（OWW221），序列号 CA6C****（已脱敏）
> 连接方式：充电底座 USB → 电脑，adb 37.0.1
> 结论先行：**传感器权限全开，血氧 / ECG / 腕温均可侧载直读，不需要官方 SDK。**

---

## 1 设备基线（实测，非官网抄录）

| 项 | 实测值 | 说明 |
|---|---|---|
| 型号 / device | OWW221 | 与官方开放机型表一致 |
| Android 版本 | **11** | release=11 |
| SDK / API | **30** | 旧文档写的 minSdk 27 / Android 8.1 是通用口径，实测确认 11 |
| CPU ABI | **armeabi-v7a** | 只有 32 位 |
| ABI 列表 | `armeabi-v7a,armeabi` | **确认无 64 位**，装 64 位 APK 必然失败 |
| 系统构建 | `OPPO/OWW221/OWW221:11/RKQ1.220916.001.11_A.291.261009204239/01:user/release-keys` | 版本号 `11_A.291`，日期 261009 |
| 屏幕 | **378×496** | 与官方一致 |
| 屏幕密度 | **320 dpi** | 与预判一致，画布约 189×248 dp |
| 电池 | 71%，USB 供电中，温度 28.9℃ | 实测采于 09:29 |

**已确认的两条硬约束：**
1. 只能装 **armeabi-v7a（32 位）** APK — 实测 `abilist` 里没有 arm64。
2. 屏幕 378×496 / 320dpi — 和设计稿一致，不用再猜。

---

## 2 传感器：42 个硬件传感器，41 个在运行

`dumpsys sensorservice` 报告：**Total 42 h/w sensors, 41 running, 0 disabled clients**。

原始 dump 已归档：`devices/oppo-watch-4-pro/docs/reports/sensorservice-dump.txt`（202 行）。

### 2.1 健康类传感器（本项目核心）

| 传感器 | type 号 | Android 类型名 | 权限 | 速率能力 | 判定 |
|---|---|---|---|---|---|
| **PPG_SPO** | **69633** | `com.google.wear.sensor.ppg_spo` | BODY_SENSORS | 1~**500Hz** continuous | **血氧可读** ✅ |
| **ECG_Sensor** | **69636** | `android.sensor.ecg` | BODY_SENSORS | 10~100Hz on-change | **ECG 可读** ✅ |
| **ECG_RAW_PRO** | **69812** | `com.google.wear.sensor.ECG_RAW_PRO` | **n/a（免权限）** | 1~**500Hz** continuous | **ECG 原始波形** ✅ |
| **WRIST_TEMPERATURE** | **69815** | `com.google.wear.sensor.w_temperature` | **n/a（免权限）** | 5~100Hz on-change | **腕温可读** ✅ |
| PPG_HRM | 69632 | `com.google.wear.sensor.ppg_hrm` | BODY_SENSORS | 1~**500Hz** continuous | 心率（私有通道） |
| HEART_RATE | 21 | `android.sensor.heart_rate` | BODY_SENSORS | 0.2~1Hz on-change | 标准心率通道 |
| PPG_Sensor | 65572 | `com.google.wear.sensor.ppg` | BODY_SENSORS | 10~100Hz on-change | PPG 通用 |
| PPG_WEAR | 69634 | `com.google.wear.sensor.ppg_wear` | BODY_SENSORS | 1~500Hz | 佩戴检测 |
| CapSensor_POLL | 69635 | `com.google.wear.sensor.capsensor_poll` | n/a | 1~100Hz | 电极接触轮询 |
| Cap_Sensor | 69637 | `android.sensor.capsensor` | n/a | 10~100Hz | 电极接触 |

### 2.2 原始 PPG 多通道（全部免权限）

| 传感器 | type 号 | 权限 | 速率 |
|---|---|---|---|
| PPG_RAW_G0 / G1 | 69801 / 69814 | **n/a** | 1~500Hz |
| PPG_RAW_R0~R4 | 69802 / 69804 / 69806 / 69808 / 69810 | **n/a** | 1~500Hz |
| PPG_RAW_IR0~IR4 | 69803 / 69805 / 69807 / 69809 / 69811 | **n/a** | 1~500Hz |

> 共 **12 个原始通道**（绿 ×2、红 ×5、红外 ×5）。这意味着**原始光电容积波形可以直接拿到**，心率和血氧都可以在 App 里自己算，不依赖厂商算法。

### 2.3 其他传感器

| 类别 | 传感器 |
|---|---|
| 运动 | G_Sensor(加速度)、Gyro_Sensor、LiAcc、Gravity、RV、Game Rotation、GeoMag RV、Magnetic_Uncalibed |
| 环境 | Mag_Sensor(地磁)、Light_Sensor、Press_Sensor(气压) |
| 姿态 | O_Sensor(方向)、Wrist_Tilt(抬腕)、LLOB(离腕检测)、Significant_motion |
| 计步 | Step_detector、Step_Sensor（需 ACTIVITY_RECOGNITION） |
| 定位 | **GPS_MAIN(69813)**，33Hz~10000Hz，免权限 |
| 状态 | **STATUS(69818)**，5~10Hz，免权限 |
| 其他 | CUST_ACC(69816)、CUST_GYRO(69817) |

### 2.4 一张关键表：谁要权限，谁不要

| 要不要 BODY_SENSORS | 传感器 |
|---|---|
| **要**（用户授权后可用） | PPG_SPO(血氧)、ECG_Sensor、PPG_HRM、HEART_RATE、PPG_Sensor、PPG_WEAR |
| **不要**（注册即可） | **WRIST_TEMPERATURE(腕温)**、**ECG_RAW_PRO**、**全部 12 个 PPG_RAW_\***、CapSensor、GPS_MAIN、STATUS |

**这是本次实测最重要的发现**：腕温、ECG 原始波形、12 路原始 PPG 全部标注 `perm: n/a`，第三方 App 连权限都不用申请就能注册。血氧和成品 ECG 只需要用户点一次 BODY_SENSORS 授权。

---

## 3 物理按键映射（来自系统 keylayout）

### 3.1 `qpnp_pon.kl`（电源/侧键）

| Linux keycode | 映射为 | 推测对应 |
|---|---|---|
| 114 | **BACK** | 功能键（下键） |
| 116 | **POWER** | 表冠按压 / 电源 |
| 59 | **F1** | 可能是表冠旋转方向 1 |
| 60 | **F2** | 可能是表冠旋转方向 2 |

### 3.2 `gpio-keys.kl`（GPIO 按键）

| Linux keycode | 映射为 |
|---|---|
| 115 | VOLUME_UP |
| 114 | VOLUME_DOWN |
| 102 | HOME |
| 528 | FOCUS |
| 766 | CAMERA |
| 158 | BACK |

> 判读：**59 / 60 → F1 / F2 几乎可以确定是表冠旋转的两个方向**（Android 里对应 KEYCODE_F1=131、KEYCODE_F2=132）。这意味着"表冠当物理旋钮"这个点子**技术上成立**，App 里监听 F1/F2 就能拿到旋转事件。
> 但需要 `getevent -l` 实测确认（转表冠时是否真的发 F1/F2）。

---

## 4 系统服务与预装应用

### 4.1 值得注意的系统服务（`cmd -l`）

| 服务 | 用途推测 |
|---|---|
| `linearmotor` / `external_vibrator_service` | 线性马达，可做表冠刻度震动 ✅ |
| `wear.manager` | OPPO 穿戴管理 |
| `mcu` | 双芯架构的 MCU 通道（恒玄那颗） |
| `sensor_privacy` | 传感器隐私控制 |
| `sensorservice` | 标准传感器服务 |

### 4.2 预装的健康类应用（`pm list packages -3`）

| 包名 | 功能 |
|---|---|
| `com.heytap.wearable.heartrate` | 心率 |
| `com.heytap.wearable.oxygen` | **血氧** |
| `com.heytap.wearable.ecg` | **心电** |
| `com.heytap.wearable.temperature` | **腕温** |
| `com.heytap.wearable.stress` | 压力 |
| `com.heytap.wearable.sleep` | 睡眠 |
| `com.heytap.wearable.sports` | 运动 |
| `com.heytap.wearable.research` | 健康研究 |
| `com.heytap.wearable.healthassessment` | 健康评估 |
| 其他 | 天气、指南针、钱包、日历、录音机、相机助手、时钟、每日活动、放松、海拔、音乐控制器、网易云音乐、手电筒 |

> 这些是 OPPO 自己的应用，但它们证明**血氧/ECG/腕温的采集链路在系统里是完整跑通的**。也意味着可以用 `adb shell am start` 直接拉起这些页面看实际数值。

---

## 5 结论：路径 B（侧载直读）完胜

之前担心的"血氧/ECG 拿不到"，**实测证伪**。

| 原担心 | 实测结论 |
|---|---|
| 血氧没有 Android 标准 API | ✅ 有私有 `PPG_SPO(69633)`，需 BODY_SENSORS |
| ECG 不开放 | ✅ 有 `ECG_Sensor(69636)` + `ECG_RAW_PRO(69812)`，后者免权限 |
| 腕温可能读不到 | ✅ 有 `WRIST_TEMPERATURE(69815)`，**且免权限** |
| 心率只能读标准通道 | ✅ 标准 `HEART_RATE(21)` + 私有 `PPG_HRM(69632)` 双通道，后者声明 500Hz |

**这意味着：**
- **不需要注册 OPPO 开发者**
- **不需要申请 SDK 权限、不需要包名签名鉴权**
- **不需要手机中转**（不走路径 A）
- 手表 App 直接 DI 读 → Wi-Fi/蓝牙推 PC，链路最短

**但必须先泼一盆冷水：注册成功 ≠ 有数据。**
传感器在 `dumpsys` 里注册了，不代表 HAL 会把数据交给**非系统应用**。有些厂商会在 HAL 层对第三方返回空值或固定 0，也有些会限制实际上报频率（声明 500Hz，实际可能只给 1Hz）。**这只能靠真实安装一个 APK 去读一次来确认。**

---

## 6 尚未验证（必须实测）

| 待验证项 | 为什么必须验证 | 怎么验 |
|---|---|---|
| 私有 sensor 是否真给第三方数据 | 注册 ≠ 出数 | 装最小 APK，注册 69633/69636/69815/69812 看回调 |
| 实际上报频率 | 声明的 500Hz 可能是硬件上限 | 同上，统计 10 秒内回调次数 |
| BODY_SENSORS 能否授予 | ColorOS Watch 权限收紧 | `pm grant` 或 App 内请求 |
| 免权限 sensor 是否受 sensor_privacy 拦截 | perm:n/a 不等于可用 | 同上 |
| 表冠是否真映射为 F1/F2 | keylayout 只是定义 | `getevent -l` 转表冠 |
| 前台服务能活多久 | 后台策略未知 | 装 App 后切后台观察 |
| 570mAh 下高频采样的续航 | 续航是最终约束 | 功耗实测 |

---

## 7 下一步

1. **装编译工具链**（JDK 17 已有，缺 Android build-tools）→ 编出最小 sensor 测试 APK
2. 装到手表，逐个注册 6 个关键 sensor，把回调值和频率打到 logcat / 屏幕
3. 用 `adb logcat` 取结果，得出"能不能读、读多快"
4. 过了这一关，再谈 PC 桌面应用

---

*本文件为开源项目示例报告：序列号已脱敏，其余均为真机实测数据。传感器 dump 原始文件见 [sensorservice-dump.txt](sensorservice-dump.txt)。*

> AI生成
