// 只有已发布、可公开访问的 APK 才能开启下载。拒绝占位地址和不完整元数据。
export function parseDownload(value) {
  if (!value || value.available !== true) return null
  try {
    const url = new URL(value.url)
    if (url.protocol !== 'https:' || !url.pathname.endsWith('.apk')) return null
    if (!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(value.version)) return null
    if (!/^[a-f0-9]{64}$/i.test(value.sha256)) return null
    if (!Number.isSafeInteger(value.size) || value.size <= 0) return null
    return {
      url: url.href,
      version: value.version,
      sha256: value.sha256,
      size: value.size,
    }
  } catch {
    return null
  }
}
