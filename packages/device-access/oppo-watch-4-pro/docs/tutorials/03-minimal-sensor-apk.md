# 教程 3：最小验证 APK —— 确认私有传感器真给第三方数据

> 目的：一次性回答两个 `dumpsys` 无法回答的问题：
> ① 私有 sensor（69633 血氧 / 69636 ECG / 69815 腕温 / 69812 ECG 原始波）注册后**是否真的吐数据**
> ② 实际**上报频率**是多少（声明的 500Hz 可能只是硬件上限）
>
> 产出：`adb logcat` 里一份「每个 sensor：10 秒回调 N 次、values=[...]」的实测清单。

## 环境准备

| 工具 | 版本要求 | 说明 |
|---|---|---|
| JDK | 17 | 编译用 |
| Android SDK | build-tools 34.x + platform android-30 | targetSdk 按 API 30（Android 11） |
| Gradle | 8.x | AGP 8.x 需要 JDK 17 |

> 手表侧需要的前置：已按[教程 1](01-getting-started.md) 完成 ADB 连接与授权。

## 工程配置（三条硬约束）

```groovy
// app/build.gradle
android {
    compileSdk 30                 // 实测 API level 30（Android 11）
    defaultConfig {
        minSdk 27                 // 官方文档口径 minSdk 27，向下兼容
        targetSdk 30
        ndk {
            abiFilters "armeabi-v7a"   // 【硬约束】Watch 4 Pro 只有 32 位 ABI
        }
    }
    buildFeatures { viewBinding true }
}
```

```xml
<!-- app/src/main/AndroidManifest.xml -->
<uses-feature android:name="android.hardware.type.watch" />

<uses-permission android:name="android.permission.BODY_SENSORS" />

<application ...>
    <activity
        android:name=".MainActivity"
        android:launchMode="singleTask"
        android:theme="@android:style/Theme.DeviceDefault">
        <!-- 右滑返回（ColorOS Watch 全局手势要求） -->
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent-filter>
    </activity>
</application>
```

三条不能省：**armeabi-v7a 过滤**（64 位包装不上）、**watch feature**、**Theme.DeviceDefault**（否则右滑重绘闪烁）。

## 核心代码

私有 sensor 没有 compile 期常量，正确姿势是**遍历全部传感器按 type 号匹配**：

```kotlin
class MainActivity : AppCompatActivity() {

    private lateinit var sm: SensorManager

    // 要验证的私有 type 号（来自教程 2 的 dump 判读）
    private val targets = mapOf(
        69633 to "PPG_SPO(血氧)",
        69636 to "ECG_Sensor(心电)",
        69812 to "ECG_RAW_PRO(心电原始波)",
        69815 to "WRIST_TEMPERATURE(腕温)",
        69632 to "PPG_HRM(心率私有)",
        21    to "HEART_RATE(心率标准)"
    )

    private val hitCount = mutableMapOf<String, Int>()   // 统计 10 秒回调次数

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sm = getSystemService(SensorManager::class.java)

        // BODY_SENSORS 是 runtime 权限，先请用户授权
        if (checkSelfPermission(android.Manifest.permission.BODY_SENSORS)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.BODY_SENSORS), 1)
        }
        startProbe()
    }

    private fun startProbe() {
        val all = sm.getSensorList(Sensor.TYPE_ALL)
        Log.i("PROBE", "共 ${all.size} 个传感器，开始匹配 ${targets.keys}")

        val listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val key = e.sensor.type.toString()
                val name = targets[e.sensor.type] ?: e.sensor.name
                val n = (hitCount[name] ?: 0) + 1
                hitCount[name] = n
                if (n == 1 || n % 50 == 0) {          // 第 1 次与每 50 次打一条，防刷屏
                    Log.i("PROBE", "$name #$n values=${e.values.contentToString()} acc=${e.accuracy}")
                }
            }
            override fun onAccuracyChanged(s: Sensor, acc: Int) {}
        }

        var matched = 0
        for (s in all) {
            if (targets.containsKey(s.type)) {
                sm.registerListener(listener, s, SensorManager.SENSOR_DELAY_FASTEST)
                Log.i("PROBE", "已注册: ${s.name} type=${s.type} 权限将按需申请")
                matched++
            }
        }
        Log.i("PROBE", "匹配到 $matched 个目标传感器")

        // 10 秒后输出统计（每个 sensor 的实际回调次数 = 实际 Hz × 10）
        Handler(Looper.getMainLooper()).postDelayed({
            hitCount.forEach { (name, n) ->
                Log.w("STATS", "$name => 10 秒 $n 次 ≈ ${n / 10.0} Hz")
            }
            Log.w("STATS", "零回调的 sensor = HAL 对第三方空转")
        }, 10_000)
    }
}
```

## 安装与观察

```bash
gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.example.sensorprobe/.MainActivity

# 表上授予 BODY_SENSORS 后，实时看结果：
adb logcat -s PROBE STATS
```

## 结果判读表

| 现象（10 秒观察窗） | 结论 | 下一步 |
|---|---|---|
| 有回调且 values 变化 | ✅ **可用**，拿到的 Hz 即真实采样能力 | 直接进开发 |
| 有回调但 values 恒 0 | ⚠️ HAL 对第三方吐空值 | 该项回退走官方 SDK（Wear Engine） |
| 有回调但频率远低于声明（如声明 500Hz 实际 1Hz） | ⚠️ 厂商限频 | 按实际 Hz 设计采样策略 |
| 完全无回调 | ❌ 被系统拦截 | 检查 `sensor_privacy`，仍不行则回退官方 SDK |

> **免权限**的四项（腕温 / ECG_RAW_PRO / 12 路 PPG_RAW）理论上连授权都不用弹——如果它们反而拿不到数据，去手表「设置 → 其他设置 → 应用权限」确认应用没被全局禁用传感器。

## 通过之后的下一关

确认能读之后，真正决定产品形态的是**功耗**：官方条款（后台 sensor 每次持有 ≤1s、非健康类最多 1 分钟 1 次、非 IM 禁后台联网）是 ROM 层事实。做连续曲线必须论证成「健康类」或进运动模式，详见[设计调研 §7 风险表](../../../../../docs/research/design-research.md)。

---

*本教程产出即设计调研 PoC 清单中「私有 sensor 出数验证」一项，跑完请把 logcat 结果整理成 issue 或 PR——不同固件版本的行为差异正是本项目最需要的社区数据。*

> AI生成
