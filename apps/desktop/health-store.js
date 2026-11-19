import { appendFile, mkdir } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';

/**
 * 本地健康采集存储（M1a）。
 * - 按天写 JSONL：dataDir/health-YYYY-MM-DD.jsonl，每行一个采样。
 * - 写入失败仅记录错误，不中断采集链路（服务层继续运行）。
 * - 不读取、不上传；数据目录由配置指定，可运行中切换。
 */
export function resolveDataDir(value, baseDir) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 260) {
    throw new Error('数据目录配置无效');
  }
  return isAbsolute(value) ? value : join(baseDir, value);
}

export function createHealthStore({ dataDir, onError = () => {} }) {
  let records = 0;
  const days = new Set();
  let lastError = null;
  let closed = false;
  let ready = null;
  const ensureDir = () => (ready ??= mkdir(dataDir, { recursive: true }));

  return {
    info() {
      return { dir: dataDir, records, files: days.size, lastError };
    },
    async append(sample) {
      if (closed) return;
      const date = new Date();
      const day = date.toISOString().slice(0, 10);
      try {
        await ensureDir();
        const line = JSON.stringify({
          ts: date.toISOString(),
          deviceId: sample.deviceId,
          metric: sample.metric,
          value: sample.value ?? null,
          unit: sample.unit,
          quality: sample.quality,
          sampledAt: sample.sampledAt,
        }) + '\n';
        await appendFile(join(dataDir, `health-${day}.jsonl`), line, 'utf8');
        records++;
        days.add(day);
        lastError = null;
      } catch (error) {
        // 磁盘错误不中断采集：记录后继续，等待用户更换目录。
        lastError = error.message;
        onError(error);
      }
    },
    async close() {
      closed = true;
      await ready?.catch(() => {});
    },
  };
}
