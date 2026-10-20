export const RELEASES_URL = 'https://api.github.com/repos/abner-forever/night_sleep/releases?per_page=30'
export const RELEASES_PAGE = 'https://github.com/abner-forever/night_sleep/releases'
const REPOSITORY = '/abner-forever/night_sleep'
const CACHE_KEY = 'yeshen-github-release-v1'
const FRESH_FOR = 5 * 60 * 1000
const OFFLINE_FOR = 24 * 60 * 60 * 1000

function versionParts(tag) {
  const match = /^v?(\d+)\.(\d+)\.(\d+)(?:-(preview|beta|rc)\.([1-9]\d*))?$/.exec(tag)
  if (!match) return null
  return [Number(match[1]), Number(match[2]), Number(match[3]),
    { preview: 0, beta: 1, rc: 2 }[match[4]] ?? 3, Number(match[5] ?? 0)]
}

function releaseDownload(release) {
  if (!release || release.draft !== false || !Number.isFinite(Date.parse(release.published_at)) || !versionParts(release.tag_name)) return null
  const version = release.tag_name.replace(/^v/, '')
  const filename = `night-sleep-${version}-android.apk`
  // 已发布的首个 preview 包保留兼容；后续 APK 必须按版本命名。
  const asset = Array.isArray(release.assets) && release.assets.find((item) => item && (item.name === filename ||
    (version === '0.49.0-preview.1' && item.name === 'night-sleep-preview.apk')))
  if (!asset || asset.state !== 'uploaded' || !Number.isSafeInteger(asset.size) || asset.size <= 0) return null
  if (!/^sha256:[a-f0-9]{64}$/i.test(asset.digest)) return null
  try {
    const url = new URL(asset.browser_download_url)
    if (url.origin !== 'https://github.com' || url.search || url.hash ||
      decodeURIComponent(url.pathname) !== `${REPOSITORY}/releases/download/${release.tag_name}/${asset.name}`) return null
    return {
      url: url.href,
      version,
      channel: version.includes('-') ? 'beta' : 'stable',
      sha256: asset.digest.slice(7).toLowerCase(),
      size: asset.size,
    }
  } catch {
    return null
  }
}

export function selectLatestDownload(releases) {
  if (!Array.isArray(releases)) return null
  return releases.map(releaseDownload).filter(Boolean).sort((a, b) => {
    const left = versionParts(a.version), right = versionParts(b.version)
    for (let i = 0; i < left.length; i++) {
      if (left[i] !== right[i]) return right[i] - left[i]
    }
    return 0
  })[0] ?? null
}

// 短缓存减轻匿名 API 限流；网络异常时仅保留一天内已成功验证的数据。
export function createDownloadClient({ fetcher = globalThis.fetch, storage, now = Date.now } = {}) {
  let memory = null
  let pending = null
  try { memory = JSON.parse(storage?.getItem(CACHE_KEY) ?? 'null') } catch { /* 禁用存储时仍可下载 */ }

  function cached(maxAge) {
    const age = now() - memory?.time
    const download = selectLatestDownload(memory?.releases)
    return age >= 0 && age < maxAge && download ? download : null
  }

  async function request() {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 12000)
    try {
      const response = await fetcher(RELEASES_URL, {
        signal: controller.signal,
        cache: 'no-cache',
        headers: { Accept: 'application/vnd.github+json' },
      })
      if (!response.ok) throw new Error(`GitHub ${response.status}`)
      const releases = await response.json()
      if (!Array.isArray(releases)) throw new Error('Invalid releases response')
      const download = selectLatestDownload(releases)
      memory = { time: now(), releases }
      try { storage?.setItem(CACHE_KEY, JSON.stringify(memory)) } catch { /* 存储容量或隐私模式 */ }
      return { download, stale: false, failed: false }
    } catch {
      return { download: cached(OFFLINE_FOR), stale: true, failed: true }
    } finally {
      clearTimeout(timeout)
    }
  }

  return {
    load({ refresh = false } = {}) {
      const download = cached(FRESH_FOR)
      if (!refresh && download) return Promise.resolve({ download, stale: false, failed: false })
      if (!pending) pending = request().finally(() => { pending = null })
      return pending
    },
  }
}

let browserClient
export function loadDownload(options) {
  if (!browserClient) {
    let storage
    try { storage = globalThis.localStorage } catch { /* 存储可被浏览器禁用 */ }
    browserClient = createDownloadClient({ storage })
  }
  return browserClient.load(options)
}
