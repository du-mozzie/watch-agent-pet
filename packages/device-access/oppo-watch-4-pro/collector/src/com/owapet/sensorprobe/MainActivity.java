package com.owapet.sensorprobe;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * M0 最小传感器验证 APK（watch-agent-pet）
 *
 * 目的：回答「注册 ≠ 出数」——私有 sensor 注册后是否真的向第三方 App 吐数据、实际频率多少。
 * 用法：adb install 后 am start；观察 adb logcat -s PROBE STATS，或直接看表上滚动日志。
 * 判读：对照 devices/oppo-watch-4-pro/docs/tutorials/03-minimal-sensor-apk.md 的结果判读表。
 *
 * 设计要点：
 * - 纯 Java + 系统 UI（ScrollView/TextView），零第三方依赖，无需 Gradle。
 * - 私有 sensor 无 compile 常量：遍历 Sensor.TYPE_ALL 按 type 号匹配（表见 devices/oppo-watch-4-pro/docs/tutorials/02-sensor-probe.md）。
 * - 每个 sensor：第 1 次回调打「首发」带 values，之后每 500 次打「心跳」；15 秒后打统计。
 * - BODY_SENSORS 未授权时免权限传感器照常注册，授权后自动补注册被拒项。
 */
public class MainActivity extends Activity {

    private static final String TAG = "PROBE";
    private static final String TAGS = "STATS";
    private static final long WINDOW_MS = 15000;   // 统计窗口
    private static final int LOG_EVERY = 500;     // 每 N 次回调打 1 条心跳日志

    /** 目标 sensor：Android type 号 -> 人读名（全部来自真机 dumpsys 实测） */
    private static final Map<Integer, String> TARGETS = new HashMap<>();
    static {
        TARGETS.put(21,     "HEART_RATE 标准心率");
        TARGETS.put(69632,  "PPG_HRM 心率私有");
        TARGETS.put(69633,  "PPG_SPO 血氧");
        TARGETS.put(69634,  "PPG_WEAR 佩戴检测");
        TARGETS.put(69636,  "ECG_Sensor 心电成品");
        TARGETS.put(69812,  "ECG_RAW_PRO 心电原始波");
        TARGETS.put(69815,  "WRIST_TEMPERATURE 腕温");
        TARGETS.put(69801,  "PPG_RAW_G0 绿光");
        TARGETS.put(69814,  "PPG_RAW_G1 绿光");
        TARGETS.put(69802,  "PPG_RAW_R0 红光");
        TARGETS.put(69804,  "PPG_RAW_R1 红光");
        TARGETS.put(69806,  "PPG_RAW_R2 红光");
        TARGETS.put(69808,  "PPG_RAW_R3 红光");
        TARGETS.put(69810,  "PPG_RAW_R4 红光");
        TARGETS.put(69803,  "PPG_RAW_IR0 红外");
        TARGETS.put(69805,  "PPG_RAW_IR1 红外");
        TARGETS.put(69807,  "PPG_RAW_IR2 红外");
        TARGETS.put(69809,  "PPG_RAW_IR3 红外");
        TARGETS.put(69811,  "PPG_RAW_IR4 红外");
    }

    private SensorManager sm;
    private TextView tv;
    private final Map<String, Integer> hit = new HashMap<>();      // sensor -> 回调次数
    private final Set<String> registered = new HashSet<>();       // 已成功注册的 sensor
    private boolean statsScheduled = false;

    private final SensorEventListener listener = new SensorEventListener() {
        @Override
        public void onSensorChanged(SensorEvent e) {
            String key = TARGETS.get(Integer.valueOf(e.sensor.getType()));
            if (key == null) key = e.sensor.getName();
            Integer n = hit.get(key);
            n = (n == null) ? Integer.valueOf(1) : Integer.valueOf(n.intValue() + 1);
            hit.put(key, n);
            int c = n.intValue();
            if (c == 1) {
                log("首发 " + key + " values=" + fmt(e.values) + " acc=" + e.accuracy);
            } else if (c % LOG_EVERY == 0) {
                log("心跳 " + key + " #" + c + " values=" + fmt(e.values));
            }
        }
        @Override
        public void onAccuracyChanged(Sensor s, int accuracy) {}
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ScrollView sv = new ScrollView(this);
        tv = new TextView(this);
        tv.setPadding(24, 40, 24, 40);
        tv.setText("== Sensor Probe v0.1 ==\n");
        sv.addView(tv);
        setContentView(sv);
        sm = (SensorManager) getSystemService(SENSOR_SERVICE);
        uiLine("目标传感器 " + TARGETS.size() + " 个（含 12 路原始 PPG）");
        if (!hasPerm()) {
            uiLine("未授权 BODY_SENSORS，请求中（免权限传感器会先注册）");
            requestPermissions(new String[]{android.Manifest.permission.BODY_SENSORS}, 1);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        attemptProbe();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            uiLine("BODY_SENSORS 已授权，补注册被拒项");
            attemptProbe();
        } else {
            uiLine("授权被拒：免权限传感器照常，血氧/成品ECG/心率通道注册将失败");
        }
    }

    private boolean hasPerm() {
        return checkSelfPermission(android.Manifest.permission.BODY_SENSORS)
                == PackageManager.PERMISSION_GRANTED;
    }

    /** 注册所有未注册的目标 sensor，逐个 try/catch，失败原因写日志 */
    private void attemptProbe() {
        List<Sensor> all = sm.getSensorList(Sensor.TYPE_ALL);
        log("系统传感器总数 " + all.size());
        int ok = 0;
        for (Map.Entry<Integer, String> en : TARGETS.entrySet()) {
            String key = en.getValue();
            if (registered.contains(key)) continue;
            Sensor found = null;
            for (Sensor s : all) {
                if (s.getType() == en.getKey().intValue()) { found = s; break; }
            }
            if (found == null) { log("未发现 " + key); continue; }
            try {
                sm.registerListener(listener, found, SensorManager.SENSOR_DELAY_FASTEST);
                registered.add(key);
                ok++;
                log("已注册 " + key + " (" + found.getName() + ")");
            } catch (SecurityException se) {
                log("注册被拒 " + key + "（需 BODY_SENSORS）");
            } catch (Exception ex) {
                log("注册异常 " + key + " " + ex);
            }
        }
        log("本轮新增 " + ok + "，累计注册 " + registered.size() + "/" + TARGETS.size()
                + "，" + (WINDOW_MS / 1000) + " 秒后出统计");
        scheduleStats();
    }

    private void scheduleStats() {
        if (statsScheduled) return;
        statsScheduled = true;
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override public void run() { dumpStats(); }
        }, WINDOW_MS);
    }

    /** 15 秒统计：每个 sensor 的回调次数 ≈ 实际 Hz × 10 */
    private void dumpStats() {
        StringBuilder sb = new StringBuilder();
        sb.append("===== ").append(WINDOW_MS / 1000).append(" 秒出数统计 =====");
        if (hit.isEmpty()) {
            sb.append("\n无任何回调 —— HAL 对第三方空转或权限被拒");
        } else {
            for (Map.Entry<String, Integer> en : hit.entrySet()) {
                int c = en.getValue().intValue();
                double hz = c / (WINDOW_MS / 1000.0);
                String verdict = hz >= 0.5 ? "活跃" : "低频";
                sb.append(String.format(Locale.US, "%n%s => %d 次 ≈ %.1f Hz [%s]",
                        en.getKey(), Integer.valueOf(c), Double.valueOf(hz), verdict));
            }
        }
        sb.append(String.format(Locale.US, "%n===== 统计结束（App 继续运行可再观察） ====="));
        String[] lines = sb.toString().split("\n");
        for (String line : lines) {
            Log.w(TAGS, line);
            uiLine(line);
        }
    }

    private void log(String msg) {
        Log.i(TAG, msg);
        uiLine(msg);
    }

    private void uiLine(final String s) {
        runOnUiThread(new Runnable() {
            @Override public void run() { tv.append(s + "\n"); }
        });
    }

    private static String fmt(float[] v) {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < v.length; i++) {
            if (i > 0) sb.append(',');
            sb.append(String.format(Locale.US, "%.2f", Float.valueOf(v[i])));
        }
        sb.append(']');
        return sb.toString();
    }
}
